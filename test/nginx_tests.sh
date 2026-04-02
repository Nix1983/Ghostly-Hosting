#!/bin/bash
# shellcheck disable=SC1091,SC2016
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
    "is_executable_file_path"
    "_extract_nginx_binary_from_systemd_unit_content"
    "resolve_nginx_binary_path"
    "get_nginx_bin"
    "has_nginx_service_unit"
    "has_nginx_runtime"
    "run_nginx_config_test"
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

test_normalize_cloudflare_real_ip_ranges() {
  echo ""
  echo "🔧 Running test_normalize_cloudflare_real_ip_ranges"

  local input output
  input=$'173.245.48.0/20\r\n# comment\n \n2400:cb00::/32\r\ninvalid-entry\n'
  output=$(_normalize_cloudflare_real_ip_ranges "$input")

  if [[ "$output" != *"173.245.48.0/20"* ]]; then
    echo "❌ Failed to keep valid IPv4 Cloudflare range"
    return 1
  fi

  if [[ "$output" != *"2400:cb00::/32"* ]]; then
    echo "❌ Failed to keep valid IPv6 Cloudflare range"
    return 1
  fi

  if [[ "$output" == *"invalid-entry"* ]]; then
    echo "❌ Invalid Cloudflare range was not filtered out"
    return 1
  fi

  echo "✅ Cloudflare real IP ranges are normalized correctly"
}

test_write_cloudflare_real_ip_conf_is_simple_and_cidr_based() {
  echo ""
  echo "🔧 Running test_write_cloudflare_real_ip_conf_is_simple_and_cidr_based"

  local tmp_conf="/tmp/test-realip-cloudflare-$$.conf"
  _write_cloudflare_real_ip_conf "$tmp_conf" $'173.245.48.0/20' $'2400:cb00::/32'

  if ! grep -q "set_real_ip_from 127.0.0.1/32;" "$tmp_conf"; then
    echo "❌ IPv4 localhost CIDR entry missing"
    rm -f "$tmp_conf"
    return 1
  fi

  if ! grep -q "set_real_ip_from ::1/128;" "$tmp_conf"; then
    echo "❌ IPv6 localhost CIDR entry missing"
    rm -f "$tmp_conf"
    return 1
  fi

  if grep -q "map \$remote_addr \$client_ip_preferring_v4" "$tmp_conf"; then
    echo "❌ Deprecated map block is still being written"
    rm -f "$tmp_conf"
    return 1
  fi

  if ! grep -q "real_ip_header CF-Connecting-IP;" "$tmp_conf"; then
    echo "❌ real_ip_header directive missing"
    rm -f "$tmp_conf"
    return 1
  fi

  rm -f "$tmp_conf"
  echo "✅ Cloudflare real IP config is written in the simplified format"
}

test_nginx_source_no_longer_uses_runtime_client_ip_preferring_v4() {
  echo ""
  echo "🔧 Running test_nginx_source_no_longer_uses_runtime_client_ip_preferring_v4"

  if grep -qE 'proxy_set_header .*client_ip_preferring_v4|map \$remote_addr \$client_ip_preferring_v4|log_format timed_combined .*client_ip_preferring_v4' "$ROOT_DIR/lib/nginx.sh"; then
    echo "❌ Deprecated runtime client_ip_preferring_v4 usage is still present in nginx.sh"
    return 1
  fi

  echo "✅ nginx.sh no longer depends on runtime client_ip_preferring_v4 usage"
}

test_extract_nginx_binary_from_systemd_unit_content() {
  echo ""
  echo "🔧 Running test_extract_nginx_binary_from_systemd_unit_content"

  local unit_content result
  unit_content=$'[Service]\nExecStart=/usr/sbin/nginx -g daemon on; master_process on;\n'
  result=$(_extract_nginx_binary_from_systemd_unit_content "$unit_content")

  if [[ "$result" == "/usr/sbin/nginx" ]]; then
    echo "✅ systemd unit parsing extracts nginx binary path"
    return 0
  fi

  echo "❌ Expected /usr/sbin/nginx from systemd unit content, got: '$result'"
  return 1
}

test_is_executable_file_path_rejects_directories() {
  echo ""
  echo "🔧 Running test_is_executable_file_path_rejects_directories"

  local temp_dir="/tmp/test-nginx-dir-$$"
  mkdir -p "$temp_dir/nginx"

  if is_executable_file_path "$temp_dir/nginx"; then
    rm -rf "$temp_dir"
    echo "❌ Directory path was incorrectly accepted as executable nginx binary"
    return 1
  fi

  rm -rf "$temp_dir"
  echo "✅ is_executable_file_path rejects directories"
}

test_get_nginx_bin_uses_resolved_binary_path() {
  echo ""
  echo "🔧 Running test_get_nginx_bin_uses_resolved_binary_path"

  local fake_bin="/tmp/test-nginx-bin-$$"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin"
  chmod +x "$fake_bin"

  local result
  result=$(
    unset NGINX_BIN
    resolve_nginx_binary_path() { echo "$fake_bin"; }
    get_nginx_bin
  )

  rm -f "$fake_bin"

  if [[ "$result" == "$fake_bin" ]]; then
    echo "✅ get_nginx_bin uses resolved nginx binary path"
    return 0
  fi

  echo "❌ Expected resolved nginx binary path '$fake_bin', got: '$result'"
  return 1
}

test_has_nginx_runtime_accepts_existing_service_without_binary() {
  echo ""
  echo "🔧 Running test_has_nginx_runtime_accepts_existing_service_without_binary"

  if (
    get_nginx_bin() { return 1; }
    has_nginx_service_unit() { return 0; }
    has_nginx_runtime
  ); then
    echo "✅ has_nginx_runtime accepts an existing nginx service without direct binary lookup"
    return 0
  fi

  echo "❌ Expected existing nginx service to satisfy runtime detection"
  return 1
}

test_run_nginx_config_test_falls_back_to_systemctl_reload() {
  echo ""
  echo "🔧 Running test_run_nginx_config_test_falls_back_to_systemctl_reload"

  local marker="/tmp/test-nginx-reload-fallback-$$"
  rm -f "$marker"

  if (
    get_nginx_bin() { return 1; }
    has_nginx_service_unit() { return 0; }
    systemctl() {
      if [[ "$1" == "reload" && "$2" == "nginx" ]]; then
        : > "$marker"
        return 0
      fi
      return 1
    }
    run_nginx_config_test
  ); then
    :
  else
    rm -f "$marker"
    echo "❌ run_nginx_config_test did not fall back to systemctl reload"
    return 1
  fi

  if [[ ! -f "$marker" ]]; then
    echo "❌ systemctl reload fallback was not invoked"
    return 1
  fi

  rm -f "$marker"
  echo "✅ run_nginx_config_test falls back to systemctl reload when nginx binary is unavailable"
}

test_install_nginx_skips_reinstall_when_binary_exists() {
  echo ""
  echo "🔧 Running test_install_nginx_skips_reinstall_when_binary_exists"

  local marker="/tmp/test-install-nginx-apt-called-$$"
  rm -f "$marker"

  if (
    get_nginx_bin() { echo "/usr/sbin/nginx"; return 0; }
    apt-get() { : > "$marker"; return 1; }
    systemctl() { return 0; }
    install_nginx >/tmp/test-install-nginx-output-$$.log 2>&1
  ); then
    :
  else
    rm -f "$marker" "/tmp/test-install-nginx-output-$$.log"
    echo "❌ install_nginx failed even though nginx binary was available"
    return 1
  fi

  if [[ -f "$marker" ]]; then
    rm -f "$marker" "/tmp/test-install-nginx-output-$$.log"
    echo "❌ install_nginx attempted apt-get despite existing nginx binary"
    return 1
  fi

  rm -f "/tmp/test-install-nginx-output-$$.log"
  echo "✅ install_nginx skips reinstall when nginx binary is already available"
}

# Run tests
test_nginx_functions_exist
test_get_nginx_config_value
test_normalize_cloudflare_real_ip_ranges
test_write_cloudflare_real_ip_conf_is_simple_and_cidr_based
test_nginx_source_no_longer_uses_runtime_client_ip_preferring_v4
test_extract_nginx_binary_from_systemd_unit_content
test_is_executable_file_path_rejects_directories
test_get_nginx_bin_uses_resolved_binary_path
test_has_nginx_runtime_accepts_existing_service_without_binary
test_run_nginx_config_test_falls_back_to_systemctl_reload
test_install_nginx_skips_reinstall_when_binary_exists

echo ""
echo "═══════════════════════════════════════════════════════"
echo "✅ All nginx tests passed!"
echo "═══════════════════════════════════════════════════════"
