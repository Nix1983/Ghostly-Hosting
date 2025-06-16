#!/bin/bash
# shellcheck disable=SC1091
set -e

# 🌐 Load common utilities
source ./lib/common.sh

# 📦 Install Nginx if not already installed
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

create_nginx_config() {
  local conf_path="/etc/nginx/sites-available/$HOSTNAME_FQDN"
  local conf_link="/etc/nginx/sites-enabled/$HOSTNAME_FQDN"
  local cert_path="/etc/letsencrypt/live/$HOSTNAME_FQDN/fullchain.pem"
  local key_path="/etc/letsencrypt/live/$HOSTNAME_FQDN/privkey.pem"

  echo -e "\n⚙️  \033[1mCreating Nginx config for:\033[0m \033[36m$HOSTNAME_FQDN → localhost:$KESTREL_PORT\033[0m"

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
    echo "    add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;"
    echo "    add_header X-Content-Type-Options nosniff;"
    echo "    add_header X-Frame-Options DENY;"
    echo "    add_header Referrer-Policy no-referrer-when-downgrade;"
    echo "    add_header X-Robots-Tag \"index, follow\";"
    echo "    add_header Content-Security-Policy \"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://localhost:$KESTREL_PORT wss://localhost:$KESTREL_PORT;\";"
    echo
    echo "    location / {"
    echo "        proxy_pass http://localhost:$KESTREL_PORT;"
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
  else
    echo -e "❌ \033[31mNginx config test failed.\033[0m Please check manually."
    return 1
  fi
}

setup_nginx_for_blazor_app() {
  if [[ -z "$HOSTNAME_FQDN" || -z "$KESTREL_PORT" ]]; then
    echo "❌ Required variables HOSTNAME_FQDN or KESTREL_PORT are missing." >&2
    return 1
  fi

  install_nginx_if_missing
  create_nginx_config || return 1

  echo -e "\n🌐 \033[1mBlazor App is now accessible at:\033[0m"
  echo -e "🔗 \033[1;34mhttps://$HOSTNAME_FQDN\033[0m"
}
