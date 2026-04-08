#!/bin/bash
# shellcheck disable=SC1091,SC2153
set -e

source ./lib/common.sh

is_executable_file_path() {
  local path="$1"
  [[ -f "$path" && -x "$path" ]]
}

_extract_nginx_binary_from_systemd_unit_content() {
  local unit_content="$1"
  local line candidate

  while IFS= read -r line; do
    [[ "$line" == ExecStart=* ]] || continue

    candidate="${line#ExecStart=}"
    candidate="${candidate#-}"
    candidate="${candidate#"${candidate%%[![:space:]]*}"}"

    if [[ "$candidate" =~ ^\"([^\"]+)\" ]]; then
      candidate="${BASH_REMATCH[1]}"
    elif [[ "$candidate" =~ ^\'([^\']+)\' ]]; then
      candidate="${BASH_REMATCH[1]}"
    else
      candidate="${candidate%%[[:space:]]*}"
    fi

    [[ -n "$candidate" ]] && {
      echo "$candidate"
      return 0
    }
  done <<< "$unit_content"

  return 1
}

resolve_nginx_binary_path() {
  if command -v nginx >/dev/null 2>&1; then
    command -v nginx
    return 0
  fi

  local candidate
  for candidate in /usr/sbin/nginx /usr/bin/nginx /usr/local/sbin/nginx /usr/local/bin/nginx; do
    if is_executable_file_path "$candidate"; then
      echo "$candidate"
      return 0
    fi
  done

  local package_name package_file
  for package_name in nginx nginx-core nginx-full nginx-light nginx-extras; do
    while IFS= read -r package_file; do
      if [[ "${package_file##*/}" == "nginx" ]] && is_executable_file_path "$package_file"; then
        echo "$package_file"
        return 0
      fi
    done < <(dpkg -L "$package_name" 2>/dev/null || true)
  done

  if command -v systemctl >/dev/null 2>&1; then
    local unit_content
    unit_content=$(systemctl cat nginx.service 2>/dev/null || true)
    candidate=$(_extract_nginx_binary_from_systemd_unit_content "$unit_content" 2>/dev/null || true)
    if [[ -n "$candidate" ]] && is_executable_file_path "$candidate"; then
      echo "$candidate"
      return 0
    fi
  fi

  local discovered_path
  discovered_path=$(find /usr/sbin /usr/bin /usr/local/sbin /usr/local/bin -maxdepth 1 -type f -name nginx -perm -111 2>/dev/null | head -n1 || true)
  if [[ -n "$discovered_path" ]]; then
    echo "$discovered_path"
    return 0
  fi

  return 1
}

get_nginx_bin() {
  if [[ -n "${NGINX_BIN:-}" ]] && is_executable_file_path "$NGINX_BIN"; then
    echo "$NGINX_BIN"
    return 0
  fi

  local resolved_path
  resolved_path=$(resolve_nginx_binary_path) || return 1
  NGINX_BIN="$resolved_path"
  export NGINX_BIN
  echo "$resolved_path"
}

has_nginx_service_unit() {
  command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files --type=service 2>/dev/null | grep -q '^nginx\.service'
}

has_nginx_runtime() {
  get_nginx_bin >/dev/null 2>&1 && return 0
  has_nginx_service_unit && return 0
  [[ -f /etc/nginx/nginx.conf ]] && return 0
  return 1
}

run_nginx_config_test() {
  local nginx_bin
  nginx_bin=$(get_nginx_bin 2>/dev/null || true)

  if [[ -n "$nginx_bin" ]]; then
    "$nginx_bin" -t
    return $?
  fi

  if has_nginx_service_unit; then
    systemctl reload nginx
    return $?
  fi

  return 1
}

remove_nginx() {
  systemctl stop nginx 2>/dev/null || true
  systemctl disable nginx 2>/dev/null || true
  systemctl reset-failed nginx 2>/dev/null || true

  apt-get purge -y nginx nginx-* nginx-common nginx-core nginx-full nginx-light nginx-extras >/dev/null 2>&1

  rm -f /usr/sbin/nginx /usr/bin/nginx
  rm -rf /etc/nginx /var/log/nginx /var/lib/nginx /usr/share/nginx \
         /etc/default/nginx /run/nginx.pid /var/www/html \
         /etc/systemd/system/nginx.service \
         /etc/systemd/system/multi-user.target.wants/nginx.service

  echo -e "🗑️ Removed NGINX configuration, binaries and related files."
}

install_nginx() {
  echo -e "\n🌐 \e[1mInstalling Nginx (Reverse Proxy)...\e[0m"

  local nginx_bin
  nginx_bin=$(get_nginx_bin 2>/dev/null || true)

  if ! has_nginx_runtime; then
    apt-get update -y >/dev/null 2>&1
    if apt-get install -y nginx >/dev/null 2>&1; then
      nginx_bin=$(get_nginx_bin 2>/dev/null || true)
      if [[ -z "$nginx_bin" && ! -f /etc/nginx/nginx.conf ]] && ! has_nginx_service_unit; then
        echo -e "❌ \e[31mNginx package installed, but no usable nginx runtime could be detected.\e[0m"
        exit 1
      fi
      echo "✅ Nginx installed."
    else
      echo -e "❌ \e[31mFailed to install Nginx – aborting setup.\e[0m"
      exit 1
    fi
  else
    echo "✅ Nginx is already installed."
  fi

  if [[ -n "$nginx_bin" ]]; then
    echo "✅ Nginx binary verified: $nginx_bin"
  elif has_nginx_service_unit || [[ -f /etc/nginx/nginx.conf ]]; then
    echo "✅ Nginx runtime verified via existing service/config."
  fi

  echo -e "\n🔌 \e[1mEnabling and starting Nginx...\e[0m"
  if systemctl enable nginx >/dev/null 2>&1 && systemctl start nginx >/dev/null 2>&1; then
    echo "✅ Nginx service is running."
  else
    echo -e "❌ \e[31mFailed to start or enable Nginx.\e[0m"
    exit 1
  fi
}

_normalize_cloudflare_real_ip_ranges() {
  local raw_ranges="$1"
  local normalized=()
  local line

  while IFS= read -r line; do
    line="${line//$'\r'/}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    if [[ "$line" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]] || [[ "$line" =~ ^[0-9A-Fa-f:]+(/[0-9]{1,3})?$ ]]; then
      normalized+=("$line")
    fi
  done <<< "$raw_ranges"

  printf '%s\n' "${normalized[@]}"
}

_write_cloudflare_real_ip_conf() {
  local destination_file="$1"
  local normalized_v4="$2"
  local normalized_v6="$3"

  {
    echo "# Auto-generated: Trust Cloudflare to provide real client IP"
    echo "# This file is managed by setup scripts."
    echo "real_ip_header CF-Connecting-IP;"
    echo "real_ip_recursive on;"
    echo "set_real_ip_from 127.0.0.1/32;"
    echo "set_real_ip_from ::1/128;"

    if [[ -n "$normalized_v4" ]]; then
      while IFS= read -r cidr_v4; do
        [[ -n "$cidr_v4" ]] && echo "set_real_ip_from $cidr_v4;"
      done <<< "$normalized_v4"
    fi

    if [[ -n "$normalized_v6" ]]; then
      while IFS= read -r cidr_v6; do
        [[ -n "$cidr_v6" ]] && echo "set_real_ip_from $cidr_v6;"
      done <<< "$normalized_v6"
    fi
  } >"$destination_file"
}

force_nginx_log_symlink_rotation() {
  local log_dir="$1"
  local today
  local nginx_bin
  today=$(date +"%d-%m-%Y")

  local access_path="$log_dir/access"
  local error_path="$log_dir/error"

  mkdir -p "$access_path" "$error_path"
  touch "$access_path/$today.txt" "$error_path/$today.txt"

  rm -f "$access_path/access.log" "$error_path/error.log"
  ln -sf "$access_path/$today.txt" "$access_path/access.log"
  ln -sf "$error_path/$today.txt" "$error_path/error.log"

  nginx_bin=$(get_nginx_bin 2>/dev/null || true)
  if [[ -n "$nginx_bin" ]]; then
    systemctl kill --signal=SIGUSR1 nginx 2>/dev/null || "$nginx_bin" -s reopen
  fi
}

setup_nginx_log_timer() {
  local timer_path="/etc/systemd/system/nginx-loglink.timer"
  local service_path="/etc/systemd/system/nginx-loglink.service"
  local script_path="/usr/local/bin/nginx-loglink"

  if systemctl list-timers --all | grep -q nginx-loglink.timer; then
    echo -e "⏱️ \033[1mSystemd timer already set up:\033[0m nginx-loglink.timer"
    local next_run
    next_run=$(systemctl list-timers | grep nginx-loglink.timer | awk '{print $1, $2}')
    echo -e "📆 Next execution: \033[36m$next_run\033[0m"
    return
  fi

  echo -e "\n🛠️ \033[1mSetting up daily Nginx log rotation timer...\033[0m"
  local nginx_bin
  nginx_bin=$(get_nginx_bin 2>/dev/null || echo "/usr/sbin/nginx")

  mkdir -p "$(dirname "$script_path")"

  {
    echo "#!/bin/bash"
    echo "set -e"
    echo "today=\$(date +\"%d-%m-%Y\")"
    echo "find \"$APP_BASE_DIR\" -type d -path \"*/$LOGS_DIR/$WEB_LOGS_ACCESS_DIR\" | while read -r access_path; do"
    echo "  error_path=\"\${access_path%/$WEB_LOGS_ACCESS_DIR}/$WEB_LOGS_ERROR_DIR\""
    echo "  mkdir -p \"\$access_path\" \"\$error_path\""
    echo "  touch \"\$access_path/\$today.txt\" \"\$error_path/\$today.txt\""
    echo "  rm -f \"\$access_path/access.log\" \"\$error_path/error.log\""
    echo "  ln -sf \"\$access_path/\$today.txt\" \"\$access_path/access.log\""
    echo "  ln -sf \"\$error_path/\$today.txt\" \"\$error_path/error.log\""
    echo "done"
    echo "systemctl kill --signal=SIGUSR1 nginx 2>/dev/null || \"$nginx_bin\" -s reopen"
    echo ""
    echo "# Delete logs older than 30 days"
    echo "find \"$APP_BASE_DIR\" -type d -path \"*/$LOGS_DIR/$WEB_LOGS_ACCESS_DIR\" | while read -r access_path; do"
    echo "  find \"\$access_path\" -name \"*.txt\" -mtime +30 -delete"
    echo "  error_path=\"\${access_path%/$WEB_LOGS_ACCESS_DIR}/$WEB_LOGS_ERROR_DIR\""
    echo "  find \"\$error_path\" -name \"*.txt\" -mtime +30 -delete"
    echo "done"
    echo ""
    echo "# Delete app logs older than 30 days"
    echo "find \"$APP_BASE_DIR\" -type d -path \"*/$LOGS_DIR\" | while read -r log_base; do"
    echo "  find \"\$log_base\" -maxdepth 1 -name \"*.log\" -mtime +30 -delete"
    echo "done"
  } > "$script_path"


  chmod +x "$script_path"
  echo -e "📄 Created log rotation script at: \033[2m$script_path\033[0m"

  {
    echo "[Unit]"
    echo "Description=Rotate Nginx log symlinks daily"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "ExecStart=$script_path"
  } > "$service_path"
  echo -e "🧩 Created systemd service file: \033[2m$service_path\033[0m"

  {
    echo "[Unit]"
    echo "Description=Daily Nginx loglink rotation timer"
    echo
    echo "[Timer]"
    echo "OnCalendar=*-*-* 00:01:00"
    echo "Persistent=true"
    echo
    echo "[Install]"
    echo "WantedBy=timers.target"
  } > "$timer_path"
  echo -e "⏲️ Created systemd timer file: \033[2m$timer_path\033[0m"

  systemctl daemon-reload
  systemctl enable --now nginx-loglink.timer

  local next_run
  next_run=$(systemctl list-timers | grep nginx-loglink.timer | awk '{print $1, $2}')
  echo -e "✅ \033[32mTimer activated.\033[0m Next execution: \033[36m$next_run\033[0m"
}

create_cloudflare_real_ip_conf() {
  local conf_dir="/etc/nginx/conf.d"
  local conf_file="$conf_dir/realip-cloudflare.conf"
  local tmp_file
  local backup_file=""
  local nginx_test_output=""
  tmp_file="$(mktemp -t realip.XXXXXXXX)"

  echo -e "\n🛡️ Configuring Nginx to trust Cloudflare real client IP (IPv4 preferred)..."

  mkdir -p "$conf_dir"

  local ips_v4="" ips_v6=""
  local normalized_v4="" normalized_v6=""
  if ips_v4="$(curl -fsS https://www.cloudflare.com/ips-v4)"; then
    :
  else
    echo "⚠️ Could not fetch Cloudflare IPv4 ranges. Using existing config if present."
  fi

  if ips_v6="$(curl -fsS https://www.cloudflare.com/ips-v6)"; then
    :
  else
    echo "⚠️ Could not fetch Cloudflare IPv6 ranges. Using existing config if present."
  fi

  normalized_v4=$(_normalize_cloudflare_real_ip_ranges "$ips_v4")
  normalized_v6=$(_normalize_cloudflare_real_ip_ranges "$ips_v6")

  if [[ -z "$normalized_v4" && -z "$normalized_v6" && -f "$conf_file" ]]; then
    echo "ℹ️ Keeping existing Cloudflare real IP config because no fresh IP ranges could be fetched."
    rm -f "$tmp_file"
    return 0
  fi

  _write_cloudflare_real_ip_conf "$tmp_file" "$normalized_v4" "$normalized_v6"

  if [[ -f "$conf_file" ]]; then
    backup_file="$(mktemp -t realip-backup.XXXXXXXX)"
    cp "$conf_file" "$backup_file"
  fi

  mv -f "$tmp_file" "$conf_file"
  chmod 0644 "$conf_file"

  if nginx_test_output=$(run_nginx_config_test 2>&1); then
    systemctl reload nginx
    rm -f "$backup_file"
    echo -e "✅ Cloudflare real IP config applied."
    return 0
  fi

  echo -e "⚠️ Nginx rejected Cloudflare real IP config:"
  echo "$nginx_test_output"

  if [[ -n "$backup_file" && -f "$backup_file" ]]; then
    mv -f "$backup_file" "$conf_file"
  else
    rm -f "$conf_file"
  fi

  if nginx_test_output=$(run_nginx_config_test 2>&1); then
    systemctl reload nginx >/dev/null 2>&1 || true
    echo "⚠️ Cloudflare real IP config was rolled back. Deployment will continue without it."
    return 0
  fi

  echo -e "❌ Nginx is still invalid after Cloudflare real IP rollback:"
  echo "$nginx_test_output"
  return 1
}

create_nginx_config() {
  local conf_path="/etc/nginx/sites-available/$HOSTNAME_FQDN"
  local conf_link="/etc/nginx/sites-enabled/$HOSTNAME_FQDN"
  local cert_path="/etc/letsencrypt/live/$HOSTNAME_FQDN/fullchain.pem"
  local key_path="/etc/letsencrypt/live/$HOSTNAME_FQDN/privkey.pem"

  local base_folder
  base_folder="$APP_BASE_DIR/${DOMAIN//./.}/$( [[ "$HOSTNAME_FQDN" == "$DOMAIN" ]] && echo root || echo "${HOSTNAME_FQDN%%."$DOMAIN"}")"
  local log_dir="$base_folder/$LOGS_DIR"
  local access_dir="$log_dir/$WEB_LOGS_ACCESS_DIR"
  local error_dir="$log_dir/$WEB_LOGS_ERROR_DIR"

  mkdir -p "$access_dir" "$error_dir"
  chown -R www-data:www-data "$log_dir"
  chmod -R 755 "$log_dir"

  # Ensure log_format uses nginx's resolved real client IP.
  if grep -q "log_format timed_combined" /etc/nginx/nginx.conf; then
    sed -i "s/\\\$client_ip_preferring_v4/\\\$remote_addr/g" /etc/nginx/nginx.conf
  else
    sed -i "/http {/a\    log_format timed_combined '\$remote_addr - \$remote_user [\$time_local] \"\$request\" \$status \$body_bytes_sent \"\$http_referer\" \"\$http_user_agent\"';" /etc/nginx/nginx.conf
  fi

  echo -e "\n⚙️ \033[1mCreating Nginx config for:\033[0m \033[36m$HOSTNAME_FQDN → localhost:$KESTREL_PORT\033[0m"

  {
    echo "server {"
    echo "    listen 80;"
    echo "    listen [::]:80;"
    echo "    server_name $HOSTNAME_FQDN;"
    echo "    return 301 https://\$host\$request_uri;"
    echo "}"
    echo
    echo "server {"
    echo "    listen 443 ssl http2;"
    echo "    listen [::]:443 ssl http2;"
    echo "    server_name $HOSTNAME_FQDN;"
    echo "    ssl_certificate $cert_path;"
    echo "    ssl_certificate_key $key_path;"
    echo "    ssl_protocols TLSv1.2 TLSv1.3;"
    echo "    ssl_ciphers HIGH:!aNULL:!MD5;"
    echo "    ssl_prefer_server_ciphers on;"
    echo "    include /etc/nginx/mime.types;"
    echo
    echo "    access_log $access_dir/access.log timed_combined;"
    echo "    error_log  $error_dir/error.log;"
    echo
    echo "    add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;"
    echo "    add_header X-Content-Type-Options nosniff;"
    echo "    add_header X-Frame-Options DENY;"
    echo "    add_header Referrer-Policy no-referrer-when-downgrade;"
    echo "    add_header X-Robots-Tag \"index, follow\";"
    echo "    add_header Content-Security-Policy \"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://localhost:$KESTREL_PORT wss://localhost:$KESTREL_PORT;\";"
    echo
    echo "    location / {"
    echo "        proxy_pass http://127.0.0.1:$KESTREL_PORT;"
    echo "        proxy_http_version 1.1;"
    echo "        proxy_set_header Upgrade \$http_upgrade;"
    echo "        proxy_set_header Connection \"upgrade\";"
    echo "        proxy_set_header Host \$host;"
    echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
    echo "        proxy_set_header X-Forwarded-Host \$host;"
    echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
    echo "        proxy_set_header X-Real-IP \$remote_addr;"
    echo "        proxy_cache_bypass \$http_upgrade;"
    echo "        proxy_set_header X-Forwarded-Server \$host;"
    echo "        add_header Cache-Control \"no-store\";"
    echo "    }"
    echo "}"
  } > "$conf_path"

  ln -sf "$conf_path" "$conf_link"

  if run_nginx_config_test >/dev/null 2>&1; then
    systemctl reload nginx
    echo -e "✅ Nginx config applied and reloaded."
    force_nginx_log_symlink_rotation "$log_dir"
  else
    echo -e "❌ \033[31mNginx config test failed.\033[0m Please check manually."
    return 1
  fi
}

remove_nginx_log_timer() {
  local timer_path="/etc/systemd/system/nginx-loglink.timer"
  local service_path="/etc/systemd/system/nginx-loglink.service"
  local script_path="/usr/local/bin/nginx-loglink"

  echo -e "\n🧹 \e[1mRemoving NGINX log rotation timer and related components...\e[0m"

  if systemctl list-timers --all | grep -q nginx-loglink.timer; then
    echo -e "⏹️ Disabling and stopping nginx-loglink.timer..."
    systemctl disable --now nginx-loglink.timer 2>/dev/null || true
  fi

  if systemctl list-units --all | grep -q nginx-loglink.service; then
    echo -e "❌ Disabling nginx-loglink.service..."
    systemctl disable nginx-loglink.service 2>/dev/null || true
  fi

  echo -e "🧽 Removing timer, service and script files..."
  rm -f "$timer_path" "$service_path" "$script_path"

  systemctl daemon-reexec
  systemctl daemon-reload

  echo -e "✅ \e[32mNGINX log timer removed.\e[0m"
}

setup_nginx_for_blazor_app() {
  if [[ -z "$HOSTNAME_FQDN" || -z "$KESTREL_PORT" ]]; then
    echo "❌ Required variables HOSTNAME_FQDN or KESTREL_PORT are missing." >&2
    return 1
  fi

  install_nginx
  create_cloudflare_real_ip_conf || return 1
  create_nginx_config || return 1
  setup_nginx_log_timer

  echo -e "\n🌐 \033[1mApp is now accessible at:\033[0m 🔗 \033[1;34mhttps://$HOSTNAME_FQDN\033[0m"
}

get_nginx_config_value() {
  local fqdn="$1"
  local setting="$2"
  local conf_path="/etc/nginx/sites-available/$fqdn"
  
  [[ ! -f "$conf_path" ]] && return 1
  
  case "$setting" in
    ssl_protocols)
      grep -oP "ssl_protocols\s+\K[^;]+" "$conf_path" | head -n1 || echo "TLSv1.2 TLSv1.3"
      ;;
    ssl_ciphers)
      grep -oP "ssl_ciphers\s+\K[^;]+" "$conf_path" | head -n1 || echo "HIGH:!aNULL:!MD5"
      ;;
    hsts_enabled)
      grep -q "Strict-Transport-Security" "$conf_path" && echo "✅" || echo "❌"
      ;;
    hsts_max_age)
      grep -oP "max-age=\K[0-9]+" "$conf_path" | head -n1 || echo "63072000"
      ;;
    x_frame_options)
      grep -oP "X-Frame-Options\s+\K[^;]+" "$conf_path" | head -n1 || echo "DENY"
      ;;
    x_content_type)
      grep -q "X-Content-Type-Options nosniff" "$conf_path" && echo "✅" || echo "❌"
      ;;
    referrer_policy)
      grep -oP "Referrer-Policy\s+\K[^;]+" "$conf_path" | head -n1 || echo "no-referrer-when-downgrade"
      ;;
    http_version)
      grep -q "listen 443 ssl http2" "$conf_path" && echo "HTTP/2" || echo "HTTP/1.1"
      ;;
    proxy_http_version)
      grep -oP "proxy_http_version\s+\K[^;]+" "$conf_path" | head -n1 || echo "1.1"
      ;;
    websocket_support)
      grep -q "proxy_set_header Upgrade" "$conf_path" && echo "✅" || echo "❌"
      ;;
  esac
}

update_nginx_ssl_protocols() {
  local fqdn="$1"
  local protocols="$2"
  local conf_path="/etc/nginx/sites-available/$fqdn"
  
  [[ ! -f "$conf_path" ]] && return 1
  
  sed -i "s|ssl_protocols .*|ssl_protocols $protocols;|g" "$conf_path"
  
  if run_nginx_config_test >/dev/null 2>&1; then
    systemctl reload nginx
    echo -e "✅ SSL protocols updated to: \e[36m$protocols\e[0m"
    return 0
  else
    echo -e "❌ \e[31mNginx config test failed. Reverting changes...\e[0m"
    return 1
  fi
}

update_nginx_hsts_max_age() {
  local fqdn="$1"
  local max_age="$2"
  local conf_path="/etc/nginx/sites-available/$fqdn"
  
  [[ ! -f "$conf_path" ]] && return 1
  
  sed -i "s|max-age=[0-9]*|max-age=$max_age|g" "$conf_path"
  
  if run_nginx_config_test >/dev/null 2>&1; then
    systemctl reload nginx
    echo -e "✅ HSTS max-age updated to: \e[36m$max_age seconds\e[0m"
    return 0
  else
    echo -e "❌ \e[31mNginx config test failed. Reverting changes...\e[0m"
    return 1
  fi
}

update_nginx_x_frame_options() {
  local fqdn="$1"
  local value="$2"
  local conf_path="/etc/nginx/sites-available/$fqdn"
  
  [[ ! -f "$conf_path" ]] && return 1
  
  sed -i "s|X-Frame-Options .*|X-Frame-Options $value;|g" "$conf_path"
  
  if run_nginx_config_test >/dev/null 2>&1; then
    systemctl reload nginx
    echo -e "✅ X-Frame-Options updated to: \e[36m$value\e[0m"
    return 0
  else
    echo -e "❌ \e[31mNginx config test failed. Reverting changes...\e[0m"
    return 1
  fi
}

update_nginx_referrer_policy() {
  local fqdn="$1"
  local value="$2"
  local conf_path="/etc/nginx/sites-available/$fqdn"
  
  [[ ! -f "$conf_path" ]] && return 1
  
  sed -i "s|Referrer-Policy .*|Referrer-Policy $value;|g" "$conf_path"
  
  if run_nginx_config_test >/dev/null 2>&1; then
    systemctl reload nginx
    echo -e "✅ Referrer-Policy updated to: \e[36m$value\e[0m"
    return 0
  else
    echo -e "❌ \e[31mNginx config test failed. Reverting changes...\e[0m"
    return 1
  fi
}

show_nginx_settings_menu() {
  local fqdn="$1"
  local conf_path="/etc/nginx/sites-available/$fqdn"
  
  if [[ ! -f "$conf_path" ]]; then
    clear
    echo -e "\n❌ \e[1;31mNginx config file not found:\e[0m \e[2m$conf_path\e[0m"
    print_press_any_key
    return 1
  fi
  
  while true; do
    clear
    echo -e "\n⚙️ \e[1;34mNginx Settings\e[0m | \e[36m$fqdn\e[0m"
    print_double_line
    
    # Read current settings
    local ssl_protocols hsts_enabled hsts_max_age x_frame x_content referrer_policy
    local http_version proxy_http ws_support
    
    ssl_protocols=$(get_nginx_config_value "$fqdn" "ssl_protocols")
    hsts_enabled=$(get_nginx_config_value "$fqdn" "hsts_enabled")
    hsts_max_age=$(get_nginx_config_value "$fqdn" "hsts_max_age")
    x_frame=$(get_nginx_config_value "$fqdn" "x_frame_options")
    x_content=$(get_nginx_config_value "$fqdn" "x_content_type")
    referrer_policy=$(get_nginx_config_value "$fqdn" "referrer_policy")
    http_version=$(get_nginx_config_value "$fqdn" "http_version")
    proxy_http=$(get_nginx_config_value "$fqdn" "proxy_http_version")
    ws_support=$(get_nginx_config_value "$fqdn" "websocket_support")
    
    # Display current settings
    echo -e "\n📋 \e[1mCurrent Configuration\e[0m"
    print_line
    
    printf "🔒 %-30s \e[36m%-30s\e[0m\n" "SSL/TLS Protocols:" "$ssl_protocols"
    printf "🛡️ %-30s %s  \e[2m(max-age: \e[0m\e[36m%s\e[0m\e[2m seconds)\e[0m\n" "HSTS Enabled:" "$hsts_enabled" "$hsts_max_age"
    printf "🖼️ %-30s \e[36m%-30s\e[0m\n" "X-Frame-Options:" "$x_frame"
    printf "📄 %-30s %s\n" "X-Content-Type-Options:" "$x_content"
    printf "🔗 %-30s \e[36m%-30s\e[0m\n" "Referrer-Policy:" "$referrer_policy"
    printf "🌐 %-30s \e[36m%-30s\e[0m\n" "HTTP Version:" "$http_version"
    printf "🔌 %-30s \e[36m%-30s\e[0m\n" "Proxy HTTP Version:" "$proxy_http"
    printf "🔄 %-30s %s\n" "WebSocket Support:" "$ws_support"
    
    print_line
    echo -e "\n 1) 🔒 Edit SSL/TLS Protocols       2) 🛡️  Edit HSTS Max-Age"
    echo -e " 3) 🖼️  Edit X-Frame-Options        4) 🔗 Edit Referrer-Policy"
    echo -e " 5) 📂 View Full Config             6) ♻️  Reload Nginx Config"
    echo -e " 7) 🧪 Test Nginx Config            $(print_back_to_menu)"
    
    read_menu_choice 7
    
    case "$REPLY" in
      1)
        while true; do
          clear
          echo -e "\n🔒 \e[1mEdit SSL/TLS Protocols\e[0m"
          print_line
          echo -e "Current: \e[36m$ssl_protocols\e[0m\n"
          
          echo -e "ℹ️  \e[1mInfo:\e[0m SSL/TLS protocols determine which encryption versions"
          echo -e "   are allowed for HTTPS connections. Newer versions are more secure"
          echo -e "   but may not be supported by very old browsers.\n"
          
          echo -e " 1) TLSv1.2 TLSv1.3  \e[2m(Recommended - secure and compatible)\e[0m"
          echo -e " 2) TLSv1.3          \e[2m(Most secure - may not support older clients)\e[0m"
          echo -e " 3) TLSv1.2          \e[2m(Legacy support - less secure)\e[0m"
          echo -e " $(print_back_to_menu)"
          
          read_menu_choice 3
          
          case "$REPLY" in
            1)
              update_nginx_ssl_protocols "$fqdn" "TLSv1.2 TLSv1.3"
              print_press_any_key
              break
              ;;
            2)
              update_nginx_ssl_protocols "$fqdn" "TLSv1.3"
              print_press_any_key
              break
              ;;
            3)
              update_nginx_ssl_protocols "$fqdn" "TLSv1.2"
              print_press_any_key
              break
              ;;
            q|Q) break ;;
          esac
        done
        ;;
      2)
        while true; do
          clear
          echo -e "\n🛡️ \e[1mEdit HSTS Max-Age\e[0m"
          print_line
          echo -e "Current: \e[36m$hsts_max_age seconds\e[0m"
          echo -e "        (≈ $((hsts_max_age / 86400)) days)\n"
          
          echo -e "ℹ️  \e[1mInfo:\e[0m HSTS (HTTP Strict Transport Security) tells browsers"
          echo -e "   to always use HTTPS when visiting your site. The max-age value"
          echo -e "   determines how long browsers remember this setting.\n"
          
          echo -e " 1) 15768000 seconds  \e[2m(6 months - for testing)\e[0m"
          echo -e " 2) 31536000 seconds  \e[2m(1 year - standard)\e[0m"
          echo -e " 3) 63072000 seconds  \e[2m(2 years - recommended)\e[0m"
          echo -e " $(print_back_to_menu)"
          
          read_menu_choice 3
          
          case "$REPLY" in
            1)
              update_nginx_hsts_max_age "$fqdn" "15768000"
              print_press_any_key
              break
              ;;
            2)
              update_nginx_hsts_max_age "$fqdn" "31536000"
              print_press_any_key
              break
              ;;
            3)
              update_nginx_hsts_max_age "$fqdn" "63072000"
              print_press_any_key
              break
              ;;
            q|Q) break ;;
          esac
        done
        ;;
      3)
        while true; do
          clear
          echo -e "\n🖼️ \e[1mEdit X-Frame-Options\e[0m"
          print_line
          echo -e "Current: \e[36m$x_frame\e[0m\n"
          
          echo -e "ℹ️  \e[1mInfo:\e[0m X-Frame-Options protects against clickjacking attacks"
          echo -e "   by controlling whether your site can be embedded in frames/iframes.\n"
          
          echo -e " 1) DENY         \e[2m(Never allow framing - most secure)\e[0m"
          echo -e " 2) SAMEORIGIN   \e[2m(Allow framing only from same domain)\e[0m"
          echo -e " $(print_back_to_menu)"
          
          read_menu_choice 2
          
          case "$REPLY" in
            1)
              update_nginx_x_frame_options "$fqdn" "DENY"
              print_press_any_key
              break
              ;;
            2)
              update_nginx_x_frame_options "$fqdn" "SAMEORIGIN"
              print_press_any_key
              break
              ;;
            q|Q) break ;;
          esac
        done
        ;;
      4)
        while true; do
          clear
          echo -e "\n🔗 \e[1mEdit Referrer-Policy\e[0m"
          print_line
          echo -e "Current: \e[36m$referrer_policy\e[0m\n"
          
          echo -e "ℹ️  \e[1mInfo:\e[0m Referrer-Policy controls how much information about"
          echo -e "   the referring page is sent when users navigate to other sites.\n"
          
          echo -e " 1) no-referrer                      \e[2m(Never send referrer - most private)\e[0m"
          echo -e " 2) no-referrer-when-downgrade       \e[2m(Send referrer only on HTTPS - balanced)\e[0m"
          echo -e " 3) origin                           \e[2m(Send only domain, not full URL)\e[0m"
          echo -e " 4) origin-when-cross-origin         \e[2m(Full URL same-site, domain only cross-site)\e[0m"
          echo -e " 5) same-origin                      \e[2m(Send referrer only to same domain)\e[0m"
          echo -e " 6) strict-origin                    \e[2m(Send domain only on HTTPS)\e[0m"
          echo -e " 7) strict-origin-when-cross-origin  \e[2m(Strict version of option 4)\e[0m"
          echo -e " $(print_back_to_menu)"
          
          read_menu_choice 7
          
          case "$REPLY" in
            1)
              update_nginx_referrer_policy "$fqdn" "no-referrer"
              print_press_any_key
              break
              ;;
            2)
              update_nginx_referrer_policy "$fqdn" "no-referrer-when-downgrade"
              print_press_any_key
              break
              ;;
            3)
              update_nginx_referrer_policy "$fqdn" "origin"
              print_press_any_key
              break
              ;;
            4)
              update_nginx_referrer_policy "$fqdn" "origin-when-cross-origin"
              print_press_any_key
              break
              ;;
            5)
              update_nginx_referrer_policy "$fqdn" "same-origin"
              print_press_any_key
              break
              ;;
            6)
              update_nginx_referrer_policy "$fqdn" "strict-origin"
              print_press_any_key
              break
              ;;
            7)
              update_nginx_referrer_policy "$fqdn" "strict-origin-when-cross-origin"
              print_press_any_key
              break
              ;;
            q|Q) break ;;
          esac
        done
        ;;
      5)
        clear
        echo -e "\n📂 \e[1mFull Nginx Config\e[0m | \e[36m$fqdn\e[0m"
        print_line
        echo ""
        cat "$conf_path"
        echo ""
        print_press_any_key
        ;;
      6)
        clear
        echo -e "\n♻️ \e[1mReloading Nginx...\e[0m"
        if run_nginx_config_test >/dev/null 2>&1; then
          if systemctl reload nginx; then
            echo -e "✅ \e[32mNginx reloaded successfully\e[0m"
          else
            echo -e "❌ \e[31mFailed to reload Nginx\e[0m"
          fi
        else
          echo -e "❌ \e[31mNginx config test failed\e[0m"
          echo -e "\nRunning detailed test:"
          run_nginx_config_test
        fi
        print_press_any_key
        ;;
      7)
        clear
        echo -e "\n🧪 \e[1mTesting Nginx Config...\e[0m"
        echo ""
        if run_nginx_config_test; then
          echo -e "\n✅ \e[32mConfiguration test passed\e[0m"
        else
          echo -e "\n❌ \e[31mConfiguration test failed\e[0m"
        fi
        print_press_any_key
        ;;
      q|Q) return 0 ;;
    esac
  done
}
