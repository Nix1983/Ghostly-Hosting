#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh

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


install_nginx_if_missing() {
  if ! command -v nginx >/dev/null 2>&1; then
    echo -e "\n📦 Installing Nginx (non-interactive)..."
    apt update -y
    apt install -y nginx
    systemctl enable nginx
    systemctl start nginx
    echo -e "✅ Nginx installed and started."
  else
    echo -e "✅ Nginx is already installed."
  fi
}

force_nginx_log_symlink_rotation() {
  local log_dir="$1"
  local today
  today=$(date +"%d-%m-%Y")

  local access_path="$log_dir/access"
  local error_path="$log_dir/error"

  mkdir -p "$access_path" "$error_path"
  touch "$access_path/$today.txt" "$error_path/$today.txt"

  rm -f "$access_path/access.log" "$error_path/error.log"
  ln -sf "$access_path/$today.txt" "$access_path/access.log"
  ln -sf "$error_path/$today.txt" "$error_path/error.log"

  systemctl kill --signal=SIGUSR1 nginx 2>/dev/null || nginx -s reopen
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
    echo "systemctl kill --signal=SIGUSR1 nginx 2>/dev/null || nginx -s reopen"
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

  if ! grep -q "log_format timed_combined" /etc/nginx/nginx.conf; then
    local logfmt
    logfmt="log_format timed_combined '\$remote_addr - \$remote_user [\$time_local] \"\$request\" \$status \$body_bytes_sent \"\$http_referer\" \"\$http_user_agent\"';"
    sed -i "/http {/a\    $logfmt" /etc/nginx/nginx.conf
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
    echo "    ssl_prefer_server_ciphers off;"
    echo "    ssl_ecdh_curve X25519:secp384r1:secp256r1;"
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
    echo "        proxy_cache_bypass \$http_upgrade;"
    echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
    echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
    echo "        add_header Cache-Control \"no-store\";"
    echo "    }"
    echo "}"
  } > "$conf_path"

  ln -sf "$conf_path" "$conf_link"

  if nginx -t &>/dev/null; then
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

  install_nginx_if_missing
  create_nginx_config || return 1
  setup_nginx_log_timer

  echo -e "\n🌐 \033[1mBlazor App is now accessible at:\033[0m 🔗 \033[1;34mhttps://$HOSTNAME_FQDN\033[0m"
}
