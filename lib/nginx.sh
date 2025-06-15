#!/bin/bash
# shellcheck disable=SC1091

set -e

# Globaler Port für Kestrel
export KESTREL_PORT=""

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
  local hostname="$1"

  if [[ -z "$hostname" ]]; then
    echo "❌ Missing hostname argument." >&2
    return 1
  fi

  KESTREL_PORT=$(find_free_port) || return 1

  local conf_path="/etc/nginx/sites-available/$hostname"
  local conf_link="/etc/nginx/sites-enabled/$hostname"
  local cert_path="/etc/letsencrypt/live/$hostname/fullchain.pem"
  local key_path="/etc/letsencrypt/live/$hostname/privkey.pem"

  echo -e "\n⚙️  Creating Nginx config for \033[1;34m$hostname\033[0m → \033[36mlocalhost:$KESTREL_PORT\033[0m"

  {
    printf "server {\n"
    printf "    listen 80;\n"
    printf "    listen [::]:80;\n"
    printf "    server_name %s;\n" "$hostname"
    printf "    return 301 https://\$host\$request_uri;\n"
    printf "}\n\n"

    printf "server {\n"
    printf "    listen 443 ssl http2;\n"
    printf "    listen [::]:443 ssl http2;\n"
    printf "    server_name %s;\n" "$hostname"
    printf "    ssl_certificate %s;\n" "$cert_path"
    printf "    ssl_certificate_key %s;\n" "$key_path"
    printf "    ssl_protocols TLSv1.2 TLSv1.3;\n"
    printf "    ssl_ciphers HIGH:!aNULL:!MD5;\n"
    printf "    ssl_prefer_server_ciphers on;\n"
    printf "    include /etc/nginx/mime.types;\n"

    printf "    add_header Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\" always;\n"
    printf "    add_header X-Content-Type-Options nosniff;\n"
    printf "    add_header X-Frame-Options DENY;\n"
    printf "    add_header Referrer-Policy no-referrer-when-downgrade;\n"
    printf "    add_header X-Robots-Tag \"index, follow\";\n"
    printf "    add_header Content-Security-Policy \"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' ws://localhost:%s wss://localhost:%s;\";\n" "$KESTREL_PORT" "$KESTREL_PORT"

    printf "    location / {\n"
    printf "        proxy_pass http://localhost:%s;\n" "$KESTREL_PORT"
    printf "        proxy_http_version 1.1;\n"
    printf "        proxy_set_header Upgrade \$http_upgrade;\n"
    printf "        proxy_set_header Connection \"upgrade\";\n"
    printf "        proxy_set_header Host \$host;\n"
    printf "        proxy_cache_bypass \$http_upgrade;\n"
    printf "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n"
    printf "        proxy_set_header X-Forwarded-Proto \$scheme;\n"
    printf "        add_header Cache-Control \"no-store\";\n"
    printf "    }\n"
    printf "}\n"
  } > "$conf_path"

  ln -sf "$conf_path" "$conf_link"
  nginx -t && systemctl reload nginx && echo "✅ Nginx reloaded successfully." || echo "❌ Nginx config test failed."
}

setup_nginx_for_blazor_app() {
  local fqdn="$1"

  if [[ -z "$fqdn" ]]; then
    echo "❌ FQDN (hostname) is required." >&2
    return 1
  fi

  install_nginx_if_missing
  create_nginx_config "$fqdn" || return 1
}