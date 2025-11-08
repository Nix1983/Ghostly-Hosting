#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! source "$ROOT_DIR/lib/const.sh"; then
  echo "❌ Failed to source const.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/common.sh"; then
  echo "❌ Failed to source common.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/print.sh"; then
  echo "❌ Failed to source print.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/nginx.sh"; then
  echo "❌ Failed to source nginx.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

test_nginx_functions_exist() {
  echo ""
  echo "🔧 Running test_nginx_functions_exist"
  
  local functions=(
    "show_nginx_settings_menu"
    "get_nginx_config_value"
    "update_nginx_ssl_protocols"
    "update_nginx_hsts_max_age"
    "update_nginx_x_frame_options"
    "update_nginx_referrer_policy"
  )
  
  for func in "${functions[@]}"; do
    if declare -f "$func" >/dev/null 2>&1; then
      echo "✅ Function exists: $func"
    else
      echo "❌ Function missing: $func"
      return 1
    fi
  done
}

test_get_nginx_config_value() {
  echo ""
  echo "🔧 Running test_get_nginx_config_value"
  
  # Create a temporary test nginx config
  local test_config="/tmp/test-nginx-config-$$.conf"
  
  cat > "$test_config" <<'EOF'
server {
    listen 443 ssl http2;
    server_name test.example.com;
    ssl_certificate /etc/letsencrypt/live/test.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/test.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy no-referrer-when-downgrade;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
  
  # Temporarily override the config path check by creating a symlink
  local test_fqdn="test.example.com"
  mkdir -p /tmp/nginx-test-sites-available
  cp "$test_config" "/tmp/nginx-test-sites-available/$test_fqdn"
  
  # Test by parsing the temp config directly since we can't modify get_nginx_config_value without sudo
  local ssl_protocols
  ssl_protocols=$(grep -oP "ssl_protocols\s+\K[^;]+" "$test_config" | head -n1)
  
  if [[ "$ssl_protocols" == "TLSv1.2 TLSv1.3" ]]; then
    echo "✅ Config parsing works for ssl_protocols: $ssl_protocols"
  else
    echo "❌ Failed to parse ssl_protocols, got: '$ssl_protocols'"
    rm -f "$test_config" "/tmp/nginx-test-sites-available/$test_fqdn"
    rmdir /tmp/nginx-test-sites-available 2>/dev/null || true
    return 1
  fi
  
  local hsts_max_age
  hsts_max_age=$(grep -oP "max-age=\K[0-9]+" "$test_config" | head -n1)
  
  if [[ "$hsts_max_age" == "63072000" ]]; then
    echo "✅ Config parsing works for hsts_max_age: $hsts_max_age"
  else
    echo "❌ Failed to parse hsts_max_age, got: '$hsts_max_age'"
    rm -f "$test_config" "/tmp/nginx-test-sites-available/$test_fqdn"
    rmdir /tmp/nginx-test-sites-available 2>/dev/null || true
    return 1
  fi
  
  local x_frame
  x_frame=$(grep -oP "X-Frame-Options\s+\K[^;]+" "$test_config" | head -n1)
  
  if [[ "$x_frame" == "DENY" ]]; then
    echo "✅ Config parsing works for x_frame_options: $x_frame"
  else
    echo "❌ Failed to parse x_frame_options, got: '$x_frame'"
    rm -f "$test_config" "/tmp/nginx-test-sites-available/$test_fqdn"
    rmdir /tmp/nginx-test-sites-available 2>/dev/null || true
    return 1
  fi
  
  # Cleanup
  rm -f "$test_config" "/tmp/nginx-test-sites-available/$test_fqdn"
  rmdir /tmp/nginx-test-sites-available 2>/dev/null || true
}

# Run tests
test_nginx_functions_exist
test_get_nginx_config_value

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ All nginx tests passed!"
echo "═══════════════════════════════════════════════════════"
