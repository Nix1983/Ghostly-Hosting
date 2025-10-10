#!/bin/bash
set -e

declare -A _CLOUDFLARE_PROXY_RESTORE_MAP=()

if ! declare -F get_cloudflare_record_proxy_flag >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  source ./lib/cloudflare.sh
fi

remove_certbot() {
  systemctl stop certbot.timer 2>/dev/null || true
  systemctl disable certbot.timer 2>/dev/null || true
  systemctl reset-failed certbot.timer 2>/dev/null || true

  apt-get purge -y certbot python3-certbot certbot-doc >/dev/null 2>&1

  rm -rf /etc/letsencrypt /var/lib/letsencrypt /var/log/letsencrypt

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

_disable_cloudflare_proxy_for_acme() {
  _CLOUDFLARE_PROXY_RESTORE_MAP=()

  if [[ -z "$HOSTNAME_FQDN" ]]; then
    return 1
  fi

  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" ]]; then
    return 1
  fi

  if ! resolve_cloudflare_zone_id "$HOSTNAME_FQDN" >/dev/null 2>&1; then
    echo "⚠️  Unable to resolve Cloudflare zone – skipping proxy toggle."
    return 1
  fi

  local changed=false
  local missing_state=false
  local all_disabled=true
  local -a domains=("$HOSTNAME_FQDN")
  [[ -n "${WWW_HOSTNAME_FQDN:-}" ]] && domains+=("$WWW_HOSTNAME_FQDN")

  for domain in "${domains[@]}"; do
    local -a record_types=()
    if [[ -n "${WWW_HOSTNAME_FQDN:-}" && "$domain" == "$WWW_HOSTNAME_FQDN" ]]; then
      record_types=("CNAME")
    else
      record_types=("A" "AAAA")
    fi

    for record_type in "${record_types[@]}"; do
      local record_json current_state

      if ! record_json=$(_get_cloudflare_dns_record "$record_type" "$domain"); then
        continue
      fi

      current_state=$(echo "$record_json" | jq -r '.proxied // empty')

      if [[ -z "$current_state" ]]; then
        missing_state=true
        all_disabled=false
        printf "   ⚠️  Unable to determine proxy state for %s %s – skipping.\n" "$record_type" "$domain"
        continue
      fi

      if [[ "$current_state" == "false" ]]; then
        continue
      fi

      if [[ "$changed" == false ]]; then
        echo "☁️  Temporarily disabling Cloudflare proxy for ACME validation..."
        changed=true
      fi

      all_disabled=false
      _CLOUDFLARE_PROXY_RESTORE_MAP["$domain|$record_type"]="true"

      if set_cloudflare_record_proxy_flag "$record_type" "$domain" "false"; then
        if wait_for_cloudflare_proxy_state "$record_type" "$domain" "false" 15 2; then
          printf "   ↪️  %s %s → proxy OFF\n" "$record_type" "$domain"
        else
          printf "   ⚠️  Proxy change for %s %s not yet visible – please verify manually.\n" "$record_type" "$domain"
        fi
      else
        printf "   ⚠️  Could not disable proxy for %s %s\n" "$record_type" "$domain"
      fi
    done
  done

  if [[ "$changed" == true ]]; then
    echo "   ℹ️  Proxy settings will be restored after certificate issuance."
  elif [[ "$all_disabled" == true && "$missing_state" == false ]]; then
    echo "☁️  Cloudflare proxy already disabled for ACME validation."
  fi

  return 0
}

_restore_cloudflare_proxy_after_acme() {
  if [[ ${#_CLOUDFLARE_PROXY_RESTORE_MAP[@]} -eq 0 ]]; then
    return 0
  fi

  echo "☁️  Restoring Cloudflare proxy configuration..."

  local key domain record_type
  for key in "${!_CLOUDFLARE_PROXY_RESTORE_MAP[@]}"; do
    domain="${key%%|*}"
    record_type="${key##*|}"

    if set_cloudflare_record_proxy_flag "$record_type" "$domain" "true"; then
      if wait_for_cloudflare_proxy_state "$record_type" "$domain" "true" 15 2; then
        printf "   ↩️  %s %s → proxy ON\n" "$record_type" "$domain"
      else
        printf "   ⚠️  Proxy restoration for %s %s not yet visible – please verify manually.\n" "$record_type" "$domain"
      fi
    else
      printf "   ⚠️  Could not restore proxy for %s %s\n" "$record_type" "$domain"
    fi
  done

  _CLOUDFLARE_PROXY_RESTORE_MAP=()
}

_check_certificate_validity() {
  local path="/etc/letsencrypt/live/$HOSTNAME_FQDN/fullchain.pem"
  if [[ -f "$path" ]]; then
    local cn
    cn=$(openssl x509 -noout -subject -in "$path" | grep -o "CN *= *[^ ,]*" | cut -d= -f2 | xargs)

    local -a expected_domains=("$HOSTNAME_FQDN")
    [[ -n "${WWW_HOSTNAME_FQDN:-}" ]] && expected_domains+=("$WWW_HOSTNAME_FQDN")

    local san_entries san_list
    san_entries=$(openssl x509 -noout -text -in "$path" 2>/dev/null | grep -Eo 'DNS:[^,]+' | sed 's/DNS://g' | tr -d ' ')
    san_list=$(printf '%s\n' $san_entries)

    if [[ "$cn" != "$HOSTNAME_FQDN" ]]; then
      echo "⚠️  Certificate found but CN mismatch: CN=$cn"
      return 1
    fi

    for domain in "${expected_domains[@]}"; do
      if [[ -z "$san_list" ]] || ! grep -Fxq "$domain" <<< "$san_list"; then
        echo "⚠️  Certificate missing SAN entry for $domain"
        return 1
      fi
    done

    echo "✅ Valid certificate found: CN=$cn"
    return 0
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

  local cert_domains=("$HOSTNAME_FQDN")
  [[ -n "${WWW_HOSTNAME_FQDN:-}" ]] && cert_domains+=("$WWW_HOSTNAME_FQDN")

  local domain_args=()
  for domain in "${cert_domains[@]}"; do
    domain_args+=('-d' "$domain")
  done

  local domain_list=""
  for domain in "${cert_domains[@]}"; do
    domain_list+="$domain, "
  done
  domain_list=${domain_list%, }

  echo "🔄 Requesting new Let's Encrypt certificate for ${domain_list:-$HOSTNAME_FQDN}..."
  _disable_cloudflare_proxy_for_acme || true
  _stop_nginx_if_running
  sleep 2
  if ! certbot certonly --standalone "${domain_args[@]}" --email "admin@$DOMAIN" --non-interactive --agree-tos; then
    echo "⚠️  First attempt failed. Retrying in 10 seconds..."
    sleep 10

    if ! certbot certonly --standalone "${domain_args[@]}" --email "admin@$DOMAIN" --non-interactive --agree-tos; then
      echo "❌ Certificate request failed after retry. Aborting."
      _start_nginx_if_stopped
      _restore_cloudflare_proxy_after_acme
      exit 1
    fi
  fi

  _start_nginx_if_stopped
  _restore_cloudflare_proxy_after_acme

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

