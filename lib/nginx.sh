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

# 🔎 Find the next available TCP port (starting at 5000)
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


# 🧾 Create a dedicated Nginx config for the given hostname
# Returns: assigned kestrel port via stdout
create_nginx_config() {
  local hostname="$1"

  if [[ -z "$hostname" ]]; then
    echo "❌ Missing hostname argument."
    return 1
  fi

  # 🔍 Dynamically assign Kestrel port
  local kestrel_port
  kestrel_port=$(find_free_kestrel_port) || return 1

  local conf_path="/etc/nginx/sites-available/$hostname"
  local conf_link="/etc/nginx/sites-enabled/$hostname"

  echo -e "\n⚙️  Creating Nginx config for \033[1;34m$hostname\033[0m → \033[36mlocalhost:$kestrel_port\033[0m"

  cat >"$conf_path" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name $hostname;

    location / {
        proxy_pass         http://localhost:$kestrel_port;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade \$http_upgrade;
        proxy_set_header   Connection keep-alive;
        proxy_set_header   Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;

        # Disable caching for dynamic content
        add_header Cache-Control "no-store";

        # SEO & security headers
        add_header X-Content-Type-Options nosniff;
        add_header X-Frame-Options DENY;
        add_header Referrer-Policy no-referrer-when-downgrade;
        add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline';";

        # WebSocket support
        proxy_set_header Connection \$http_connection;
    }

    # Static file caching
    location ~* \.(?:ico|css|js|gif|jpe?g|png|woff2?|eot|ttf|svg)$ {
        expires 30d;
        access_log off;
        add_header Cache-Control "public";
    }
}
EOF

  ln -sf "$conf_path" "$conf_link"

  echo "🔁 Reloading Nginx..."
  nginx -t && systemctl reload nginx
  echo -e "✅ Nginx configuration applied for \033[1;32m$hostname\033[0m"

  echo "$kestrel_port"
}

# 🧠 Setup Nginx for a given Blazor app FQDN (returns port)
setup_nginx_for_blazor_app() {
  local fqdn="$1"

  if [[ -z "$fqdn" ]]; then
    echo "❌ FQDN (hostname) is required."
    return 1
  fi

  install_nginx_if_missing
  create_nginx_config "$fqdn"
}
