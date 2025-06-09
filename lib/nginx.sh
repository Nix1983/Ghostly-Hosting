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

find_free_kestrel_port() {
  local base_port=5000
  local max_port=5099
  local port

  for ((port = base_port; port <= max_port; port++)); do
    # Check if port is already in use
    if ss -tuln | grep -q ":$port\\b"; then
      continue
    fi

    # Check if port is already used in existing Nginx configs
    if grep -r "localhost:$port" /etc/nginx/sites-available/ >/dev/null 2>&1; then
      continue
    fi

    echo "$port"
    return 0
  done

  echo "❌ No free port found between $base_port and $max_port" >&2
  return 1
}

create_nginx_config() {
  local hostname="$1"

  if [[ -z "$hostname" ]]; then
    echo "❌ Missing hostname argument."
    return 1
  fi

  local kestrel_port
  kestrel_port=$(find_free_kestrel_port) || return 1

  local conf_path="/etc/nginx/sites-available/$hostname"
  local conf_link="/etc/nginx/sites-enabled/$hostname"

  echo -e "\n⚙️  Creating Nginx config for \033[1;34m$hostname\033[0m → \033[36mlocalhost:$kestrel_port\033[0m"

  {
    printf "server {\n"
    printf "    listen 80;\n"
    printf "    listen [::]:80;\n"
    printf "    server_name %s;\n" "$hostname"

    printf "\n    location / {\n"
    printf "        proxy_pass http://localhost:%s;\n" "$kestrel_port"
    printf "        proxy_http_version 1.1;\n"
    printf "        proxy_set_header Upgrade \$http_upgrade;\n"
    printf "        proxy_set_header Connection keep-alive;\n"
    printf "        proxy_set_header Host \$host;\n"
    printf "        proxy_cache_bypass \$http_upgrade;\n"
    printf "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n"
    printf "        proxy_set_header X-Forwarded-Proto \$scheme;\n"
    printf "        proxy_set_header Connection \$http_connection;\n"
    printf "        add_header Cache-Control \"no-store\";\n"
    printf "        add_header X-Content-Type-Options nosniff;\n"
    printf "        add_header X-Frame-Options DENY;\n"
    printf "        add_header Referrer-Policy no-referrer-when-downgrade;\n"
    printf "        add_header Content-Security-Policy \"default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';\";\n"
    printf "    }\n"

    printf "\n    location ~* \\.(" 
    printf "ico|css|js|gif|jpe?g|png|woff2?|eot|ttf|svg"
    printf ")$ {\n"
    printf "        expires 30d;\n"
    printf "        access_log off;\n"
    printf "        add_header Cache-Control \"public\";\n"
    printf "    }\n"

    printf "}\n"
  } > "$conf_path"

  ln -sf "$conf_path" "$conf_link"

  echo "🔁 Reloading Nginx..."
  if nginx -t; then
    systemctl reload nginx
    echo -e "✅ Nginx configuration applied for \033[1;32m$hostname\033[0m"
  else
    echo -e "❌ \033[31mNginx configuration test failed. See above for errors.\033[0m"
  fi

  echo "$kestrel_port"
}

setup_nginx_for_blazor_app() {
  local fqdn="$1"

  if [[ -z "$fqdn" ]]; then
    echo "❌ FQDN (hostname) is required."
    return 1
  fi

  install_nginx_if_missing
  create_nginx_config "$fqdn"
}
