#!/bin/bash
set -e

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
  fi
}

_check_certificate_validity() {
  local path="/etc/letsencrypt/live/$HOSTNAME_FQDN/fullchain.pem"
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

_obtain_or_verify_certificate() {
  echo "🔒 Checking Let's Encrypt certificate for $HOSTNAME_FQDN..."

  if _check_certificate_validity; then
    return
  fi

  echo "🔄 Requesting new Let's Encrypt certificate..."
  _stop_nginx_if_running

  if ! certbot certonly --standalone -d "$HOSTNAME_FQDN" --email "admin@$DOMAIN" --non-interactive --agree-tos; then
    echo "❌ Certificate request failed. Aborting."
    _start_nginx_if_stopped
    exit 1
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

run_certbot_workflow() {
  _ensure_certbot_installed
  _check_required_tools
  _obtain_or_verify_certificate
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
