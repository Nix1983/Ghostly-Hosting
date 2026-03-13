#!/bin/bash
set -e

CERTBOT_NGINX_RELOAD_HOOK_PATH="${CERTBOT_NGINX_RELOAD_HOOK_PATH:-/etc/letsencrypt/renewal-hooks/deploy/ghostly-hosting-nginx-reload.sh}"
CERTBOT_NGINX_PRE_HOOK_PATH="${CERTBOT_NGINX_PRE_HOOK_PATH:-/etc/letsencrypt/renewal-hooks/pre/ghostly-hosting-nginx-stop.sh}"
CERTBOT_NGINX_POST_HOOK_PATH="${CERTBOT_NGINX_POST_HOOK_PATH:-/etc/letsencrypt/renewal-hooks/post/ghostly-hosting-nginx-start.sh}"
CERTBOT_NGINX_STATE_PATH="${CERTBOT_NGINX_STATE_PATH:-/var/lib/ghostly-hosting/certbot-nginx-running}"

_write_executable_hook() {
  local hook_path="$1"
  local hook_content="$2"
  local hook_dir

  hook_dir=$(dirname "$hook_path")
  mkdir -p "$hook_dir"
  printf "%s\n" "$hook_content" > "$hook_path"
  chmod 755 "$hook_path"
}

write_certbot_nginx_reload_hook() {
  local hook_path="${1:-$CERTBOT_NGINX_RELOAD_HOOK_PATH}"
  local hook_content

  hook_content='#!/bin/bash
set -e

if command -v nginx >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files --type=service 2>/dev/null | grep -q '\''^nginx\.service'\''; then
    nginx -t >/dev/null 2>&1 && systemctl reload nginx >/dev/null 2>&1 || true
  fi
fi'

  _write_executable_hook "$hook_path" "$hook_content"
}

write_certbot_nginx_pre_hook() {
  local hook_path="${1:-$CERTBOT_NGINX_PRE_HOOK_PATH}"
  local hook_content

  hook_content=$(cat <<EOF
#!/bin/bash
set -e

if command -v nginx >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
  if systemctl list-unit-files --type=service 2>/dev/null | grep -q '^nginx\.service'; then
    if systemctl is-active --quiet nginx; then
      mkdir -p "$(dirname "$CERTBOT_NGINX_STATE_PATH")"
      : > "$CERTBOT_NGINX_STATE_PATH"
      systemctl stop nginx >/dev/null 2>&1 || true
    else
      rm -f "$CERTBOT_NGINX_STATE_PATH"
    fi
  fi
fi
EOF
)

  _write_executable_hook "$hook_path" "$hook_content"
}

write_certbot_nginx_post_hook() {
  local hook_path="${1:-$CERTBOT_NGINX_POST_HOOK_PATH}"
  local hook_content

  hook_content=$(cat <<EOF
#!/bin/bash
set -e

if command -v systemctl >/dev/null 2>&1 && [[ -f "$CERTBOT_NGINX_STATE_PATH" ]]; then
  systemctl start nginx >/dev/null 2>&1 || true
  rm -f "$CERTBOT_NGINX_STATE_PATH"
fi
EOF
)

  _write_executable_hook "$hook_path" "$hook_content"
}

has_certbot_nginx_reload_hook() {
  local hook_path="${1:-$CERTBOT_NGINX_RELOAD_HOOK_PATH}"
  [[ -x "$hook_path" ]]
}

has_certbot_nginx_pre_hook() {
  local hook_path="${1:-$CERTBOT_NGINX_PRE_HOOK_PATH}"
  [[ -x "$hook_path" ]]
}

has_certbot_nginx_post_hook() {
  local hook_path="${1:-$CERTBOT_NGINX_POST_HOOK_PATH}"
  [[ -x "$hook_path" ]]
}

has_certbot_nginx_renewal_hooks() {
  has_certbot_nginx_pre_hook && has_certbot_nginx_post_hook && has_certbot_nginx_reload_hook
}

ensure_certbot_nginx_renewal_hooks() {
  if write_certbot_nginx_pre_hook "$CERTBOT_NGINX_PRE_HOOK_PATH" &&
     write_certbot_nginx_post_hook "$CERTBOT_NGINX_POST_HOOK_PATH" &&
     write_certbot_nginx_reload_hook "$CERTBOT_NGINX_RELOAD_HOOK_PATH"; then
    echo "✅ Certbot Nginx renewal hooks installed."
    return 0
  fi

  echo -e "❌ \e[31mFailed to install Certbot Nginx renewal hooks.\e[0m"
  return 1
}

remove_certbot() {
  systemctl stop certbot.timer 2>/dev/null || true
  systemctl disable certbot.timer 2>/dev/null || true
  systemctl reset-failed certbot.timer 2>/dev/null || true

  apt-get purge -y certbot python3-certbot certbot-doc >/dev/null 2>&1

  rm -rf /etc/letsencrypt /var/lib/letsencrypt /var/log/letsencrypt
  rm -f "$CERTBOT_NGINX_RELOAD_HOOK_PATH"
  rm -f "$CERTBOT_NGINX_PRE_HOOK_PATH"
  rm -f "$CERTBOT_NGINX_POST_HOOK_PATH"
  rm -f "$CERTBOT_NGINX_STATE_PATH"

  echo -e "🗑️ Removed Certbot and all certificate data."
}

install_certbot(){
   echo -e "\n📜 \e[1mInstalling Certbot (for HTTPS)...\e[0m"
  if ! command -v certbot >/dev/null 2>&1; then
    if apt-get install -y certbot python3-certbot >/dev/null 2>&1; then
      echo "✅ Certbot installed."
    else
      echo -e "❌ \e[31mFailed to install Certbot.\e[0m"
      exit 1
    fi
  else
    echo "✅ Certbot is already installed."
  fi

  if systemctl list-unit-files --type=timer | grep -q '^certbot.timer'; then
    systemctl enable certbot.timer >/dev/null 2>&1
    systemctl start certbot.timer >/dev/null 2>&1
    echo -e "✅ certbot.timer enabled."
  else
    echo -e "⚠️  \e[33mcertbot.timer not available on this system – skipping.\e[0m"
  fi

  ensure_certbot_nginx_renewal_hooks || exit 1
}

_check_required_tools() {
  for tool in openssl systemctl grep cut xargs; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "❌ Required tool '$tool' is missing. Please install it: apt install -y $tool"
      exit 1
    fi
  done
}

_ensure_certbot_installed() {
  if ! command -v certbot >/dev/null 2>&1; then
    echo "📦 Certbot not found – installing..."
    apt update && apt install -y certbot
  else
    echo "✅ Certbot is already installed."
  fi
}

_stop_nginx_if_running() {
  export NGINX_WAS_RUNNING=false
  if systemctl list-unit-files | grep -q '^nginx\.service'; then
    if systemctl is-active --quiet nginx; then
      echo "⏹️ Stopping running nginx service..."
      systemctl stop nginx
      export NGINX_WAS_RUNNING=true
    fi
  fi
}

_start_nginx_if_stopped() {
  if [[ "${NGINX_WAS_RUNNING:-false}" == true ]]; then
    echo "▶️  Restarting nginx service..."
    systemctl start nginx
    export NGINX_WAS_RUNNING=false
  fi
}

_check_certificate_validity() {
  local path
  path=$(_resolve_certbot_fullchain_path "$HOSTNAME_FQDN" 2>/dev/null || true)
  if [[ -f "$path" ]]; then
    local cn
    cn=$(openssl x509 -noout -subject -in "$path" | grep -o "CN *= *[^ ,]*" | cut -d= -f2 | xargs)
    if [[ "$cn" == "$HOSTNAME_FQDN" ]]; then
      echo "✅ Valid certificate found: CN=$cn"
      return 0
    else
      echo "⚠️  Certificate found but CN mismatch: CN=$cn"
      return 1
    fi
  else
    echo "❌ No certificate found."
    return 1
  fi
}

_derive_certbot_email_domain() {
  local fqdn="$1"
  echo "$fqdn" | awk -F. '{print $(NF-1)"."$NF}'
}

_resolve_certbot_fullchain_path() {
  local fqdn="${1:-$HOSTNAME_FQDN}"
  local cert_name
  local default_path="/etc/letsencrypt/live/$fqdn/fullchain.pem"

  if [[ -f "$default_path" ]]; then
    echo "$default_path"
    return 0
  fi

  cert_name=$(_resolve_certbot_cert_name "$fqdn" 2>/dev/null || true)
  [[ -n "$cert_name" ]] || return 1

  if [[ -f "/etc/letsencrypt/live/$cert_name/fullchain.pem" ]]; then
    echo "/etc/letsencrypt/live/$cert_name/fullchain.pem"
    return 0
  fi

  return 1
}

_resolve_certbot_cert_name() {
  local fqdn="$1"
  local certbot_cert_info current_name current_domains

  certbot_cert_info=$(certbot certificates 2>/dev/null || true)
  [[ -n "$certbot_cert_info" ]] || return 1

  while IFS= read -r line; do
    case "$line" in
      "  Certificate Name:"*)
        current_name=$(echo "$line" | cut -d: -f2- | xargs)
        ;;
      "    Domains:"*)
        current_domains=$(echo "$line" | cut -d: -f2- | xargs)
        if [[ " $current_domains " == *" $fqdn "* ]]; then
          echo "$current_name"
          return 0
        fi
        ;;
    esac
  done <<< "$certbot_cert_info"

  return 1
}

_obtain_or_verify_certificate() {
  echo "🔒 Checking Let's Encrypt certificate for $HOSTNAME_FQDN..."

  if _check_certificate_validity; then
    return
  fi

  echo "🔄 Requesting new Let's Encrypt certificate..."
  _stop_nginx_if_running
  sleep 2
  if ! certbot certonly --standalone -d "$HOSTNAME_FQDN" --email "admin@$DOMAIN" --non-interactive --agree-tos; then
    echo "⚠️  First attempt failed. Retrying in 10 seconds..."
    sleep 10

    if ! certbot certonly --standalone -d "$HOSTNAME_FQDN" --email "admin@$DOMAIN" --non-interactive --agree-tos; then
      echo "❌ Certificate request failed after retry. Aborting."
      _start_nginx_if_stopped
      exit 1
    fi
  fi

  _start_nginx_if_stopped

  echo "🔁 Verifying new certificate..."
  if _check_certificate_validity; then
    echo "✅ New certificate successfully created and valid."
  else
    echo "❌ Certificate created but invalid. Aborting."
    exit 1
  fi
}

delete_certbot_certificate() {
  if [[ -z "$HOSTNAME_FQDN" ]]; then
    echo -e "❌ \e[31mCannot delete certificate – HOSTNAME_FQDN is not set.\e[0m"
    return 1
  fi

  if ! command -v certbot >/dev/null 2>&1; then
    echo -e "❌ \e[31mCertbot is not installed.\e[0m"
    return 1
  fi

  local cert_name cert_path
  cert_name="$HOSTNAME_FQDN"
  cert_path="/etc/letsencrypt/live/$cert_name"

  if [[ ! -d "$cert_path" ]]; then
    echo -e "ℹ️ No certificate found for: \e[2m$cert_name\e[0m — skipping."
    return 0
  fi

  echo -e "\n🔐 \e[1mChecking for active certbot process...\e[0m"
  if pgrep -f certbot >/dev/null; then
    echo -e "⏳ Another certbot instance is running. Waiting up to 20s..."

    for _ in {1..20}; do
      sleep 1
      if ! pgrep -f certbot >/dev/null; then
        echo -e "✅ Previous certbot process has finished."
        break
      fi
    done

    if pgrep -f certbot >/dev/null; then
      echo -e "❌ \e[31mCertbot is still running after 20 seconds.\e[0m"
      echo -e "💡 Please wait or terminate the process manually before retrying."
      return 1
    fi
  fi

  echo -e "\n🧹 \e[1;31mDeleting Let's Encrypt certificate:\e[0m \e[36m$cert_name\e[0m"
  if certbot delete --cert-name "$cert_name" --non-interactive --quiet; then
    echo -e "✅ \e[32mCertificate successfully deleted.\e[0m"
  else
    echo -e "❌ \e[31mFailed to delete certificate.\e[0m"
    return 1
  fi
}




run_certbot_workflow() {
  _ensure_certbot_installed
  _check_required_tools
  ensure_certbot_nginx_renewal_hooks || return 1
  _obtain_or_verify_certificate
}

renew_certbot_certificate() {
  local fqdn="${1:-$HOSTNAME_FQDN}"
  local email_domain="${2:-$DOMAIN}"
  local cert_name

  if [[ -z "$fqdn" ]]; then
    echo -e "❌ \e[31mCannot renew certificate – hostname is missing.\e[0m"
    return 1
  fi

  if [[ -z "$email_domain" ]]; then
    email_domain=$(_derive_certbot_email_domain "$fqdn")
  fi

  _ensure_certbot_installed
  _check_required_tools
  ensure_certbot_nginx_renewal_hooks || return 1

  cert_name=$(_resolve_certbot_cert_name "$fqdn" 2>/dev/null || true)
  cert_name="${cert_name:-$fqdn}"

  echo -e "\n🔄 \e[1mRenewing SSL certificate for:\e[0m \e[36m$fqdn\e[0m"
  _stop_nginx_if_running
  sleep 2

  if ! certbot certonly --standalone --cert-name "$cert_name" -d "$fqdn" --email "admin@$email_domain" --non-interactive --agree-tos --force-renewal; then
    echo "⚠️  Renewal attempt failed. Retrying in 10 seconds..."
    sleep 10
    if ! certbot certonly --standalone --cert-name "$cert_name" -d "$fqdn" --email "admin@$email_domain" --non-interactive --agree-tos --force-renewal; then
      echo -e "❌ \e[31mCertificate renewal failed.\e[0m"
      _start_nginx_if_stopped
      return 1
    fi
  fi

  _start_nginx_if_stopped

  echo "🔁 Verifying renewed certificate..."
  if _check_certificate_validity; then
    echo "✅ Certificate renewed successfully."
    return 0
  fi

  echo -e "❌ \e[31mCertificate was renewed but verification failed.\e[0m"
  return 1
}

check_certbot_status() {
  clear
  echo ""
  echo -e "🔒 \e[1mCertbot Certificate Overview\e[0m"
  echo "────────────────────────────────────────────────────────────"

  if ! certbot_cert_info=$(certbot certificates 2>/dev/null); then
    echo "❌ Certbot does not seem installed or is malfunctioning."
    return 1
  fi

  get_cert_value() {
    echo "$certbot_cert_info" | grep -A3 "$1" | grep "$2" | awk -F: '{print $2}' | xargs
  }

  cert_domain=$(echo "$certbot_cert_info" | grep 'Certificate Name:' | head -n1 | cut -d: -f2 | xargs)
  cert_expiry=$(get_cert_value "$cert_domain" "Expiry Date")
  cert_path=$(get_cert_value "$cert_domain" "Certificate Path")

  expiry_ts=$(date -d "$cert_expiry" +%s 2>/dev/null)
  now_ts=$(date +%s)
  days_left=$(( (expiry_ts - now_ts) / 86400 ))

  if [[ -n "$cert_domain" ]]; then
    printf "✅ \e[1m%-42s\e[0m %s\n" "Certificate domain" "$cert_domain"
  else
    printf "⚠️ \e[1m%-42s\e[0m %s\n" "Certificate domain" "Not found"
  fi

  if [[ -n "$cert_path" && -f "$cert_path" ]]; then
    printf "✅ \e[1m%-42s\e[0m %s\n" "Certificate path" "$cert_path"
  else
    printf "⚠️ \e[1m%-42s\e[0m %s\n" "Certificate path" "Missing or invalid"
  fi

  if [[ $days_left -ge 0 ]]; then
    printf "✅ \e[1m%-42s\e[0m %s (in $days_left days)\n" "Valid until" "$cert_expiry"
  else
    printf "❌ \e[1m%-42s\e[0m %s (expired ${days_left#-} days ago!)\n" "Valid until" "$cert_expiry"
  fi

  if systemctl list-timers | grep -q certbot.timer; then
    timer_status=$(systemctl is-enabled certbot.timer 2>/dev/null)
    next_run=$(systemctl list-timers --all | grep certbot.timer | awk '{print $1, $2}')
    printf "✅ \e[1m%-42s\e[0m %s (next run: %s)\n" "Auto-renewal via systemd" "$timer_status" "$next_run"
    if has_certbot_nginx_renewal_hooks; then
      printf "✅ \e[1m%-42s\e[0m %s\n" "Nginx renewal hooks" "stop/start/reload installed"
    else
      printf "⚠️  \e[1m%-42s\e[0m %s\n" "Nginx renewal hooks" "Missing one or more hooks"
    fi
    printf "⚠️  \e[1m%-42s\e[0m %s\n" "Cronjob for certbot" "Not needed – systemd is active"
  else
    printf "⚠️  \e[1m%-42s\e[0m %s\n" "Auto-renewal via systemd" "Not active or missing"

    cron_check=$(crontab -l 2>/dev/null | grep certbot || true)
    if [[ -n "$cron_check" ]]; then
      printf "✅ \e[1m%-42s\e[0m %s\n" "Certbot cronjob found" "$cron_check"
    else
      printf "⚠️  \e[1m%-42s\e[0m %s\n" "Certbot cronjob" "Not found"
    fi
  fi

  echo ""
  echo -e "🧪 \e[1mDry-run to test auto-renewal\e[0m"

  nginx_was_running=false
  if systemctl list-unit-files | grep -q '^nginx\.service'; then
    if systemctl is-active --quiet nginx; then
      echo "⏹️ Stopping nginx for dry-run..."
      systemctl stop nginx
      nginx_was_running=true
    fi
  fi

  if certbot renew --dry-run >/dev/null 2>&1; then
    echo -e "✅ Dry-run successful – auto-renewal ready"
  else
    echo -e "❌ Dry-run failed – please check configuration!"
  fi

  if [[ "$nginx_was_running" == true ]]; then
    echo "▶️  Restarting nginx after dry-run..."
    systemctl start nginx
  fi

  echo ""
  echo -e "📍 \e[1mTip:\e[0m View more: \e[2mcertbot certificates\e[0m"
  echo -e "💡 \e[2mTip:\e[0m Use: \e[2mopenssl x509 -in cert.pem -noout -dates\e[0m"
  echo ""
}
