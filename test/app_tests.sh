#!/bin/bash
# Unit tests for app.sh and app deployment functions
# Note: We don't use set -e because we want to continue running tests even if some fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "App Deployment Tests"
echo "════════════════════════════════════════════════════════════════"

# Source required libraries
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

echo "✅ SOURCES LOADED"
echo ""

pushd "$ROOT_DIR" >/dev/null || exit 1
if ! source "./lib/app.sh"; then
  echo "âŒ Failed to source app.sh"
  popd >/dev/null || true
  exit 1
fi
popd >/dev/null || exit 1

# Test 1: Check if app.sh exists and is readable
test_app_script_exists() {
  echo "🔧 Running test_app_script_exists"
  
  if [[ -f "$ROOT_DIR/lib/app.sh" ]]; then
    echo "✅ app.sh exists"
  else
    echo "❌ app.sh does not exist"
    return 1
  fi
  
  if [[ -r "$ROOT_DIR/lib/app.sh" ]]; then
    echo "✅ app.sh is readable"
  else
    echo "❌ app.sh is not readable"
    return 1
  fi
  
  return 0
}

# Test 2: Check if app_manager.sh exists
test_app_manager_exists() {
  echo "🔧 Running test_app_manager_exists"
  
  if [[ -f "$ROOT_DIR/lib/app_manager.sh" ]]; then
    echo "✅ app_manager.sh exists"
    return 0
  else
    echo "❌ app_manager.sh does not exist"
    return 1
  fi
}

# Test 3: Validate app.sh syntax
test_app_script_syntax() {
  echo "🔧 Running test_app_script_syntax"
  
  if bash -n "$ROOT_DIR/lib/app.sh" 2>/dev/null; then
    echo "✅ app.sh has valid syntax"
    return 0
  else
    echo "❌ app.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/app.sh"
    return 1
  fi
}

# Test 4: Validate app_manager.sh syntax
test_app_manager_syntax() {
  echo "🔧 Running test_app_manager_syntax"
  
  if bash -n "$ROOT_DIR/lib/app_manager.sh" 2>/dev/null; then
    echo "✅ app_manager.sh has valid syntax"
    return 0
  else
    echo "❌ app_manager.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/app_manager.sh"
    return 1
  fi
}

# Test 5: Check git module exists
test_git_module_exists() {
  echo "🔧 Running test_git_module_exists"
  
  if [[ -f "$ROOT_DIR/lib/git.sh" ]]; then
    echo "✅ git.sh module exists"
    return 0
  else
    echo "❌ git.sh module does not exist"
    return 1
  fi
}

# Test 6: Test is_valid_kestrel_service_name function
test_is_valid_kestrel_service_name() {
  echo "🔧 Running test_is_valid_kestrel_service_name"
  
  # Valid service names
  if is_valid_kestrel_service_name "myapp@ghostlypick.com:5000.service"; then
    echo "✅ Valid service name accepted: myapp@ghostlypick.com:5000.service"
  else
    echo "❌ Valid service name rejected: myapp@ghostlypick.com:5000.service"
    return 1
  fi
  
  if is_valid_kestrel_service_name "@ghostlypick.com:5001.service"; then
    echo "✅ Valid service name accepted: @ghostlypick.com:5001.service"
  else
    echo "❌ Valid service name rejected: @ghostlypick.com:5001.service"
    return 1
  fi
  
  # Invalid service names
  if ! is_valid_kestrel_service_name "invalid-service-name.service"; then
    echo "✅ Invalid service name rejected: invalid-service-name.service"
  else
    echo "❌ Invalid service name accepted: invalid-service-name.service"
    return 1
  fi
  
  return 0
}

# Test 7: Check deployment dependencies exist
test_deployment_dependencies() {
  echo "🔧 Running test_deployment_dependencies"
  
  local modules=(
    "cloudflare.sh"
    "certbot.sh"
    "git.sh"
    "log.sh"
  )
  
  for module in "${modules[@]}"; do
    if [[ -f "$ROOT_DIR/lib/$module" ]]; then
      echo "✅ Dependency module exists: $module"
    else
      echo "❌ Dependency module missing: $module"
      return 1
    fi
  done
  
  return 0
}

# Test 8: Parse the active SSL certificate path from nginx config
test_get_nginx_ssl_certificate_path_from_conf() {
  echo "ðŸ”§ Running test_get_nginx_ssl_certificate_path_from_conf"

  local test_config result
  test_config=$(mktemp)

  cat > "$test_config" <<'EOF'
server {
    listen 443 ssl http2;
    server_name ghostlyinc.com;
    ssl_certificate /etc/letsencrypt/live/ghostlyinc.com-0001/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/ghostlyinc.com-0001/privkey.pem;
}
EOF

  result=$(get_nginx_ssl_certificate_path_from_conf "$test_config")
  rm -f "$test_config"

  if [[ "$result" == "/etc/letsencrypt/live/ghostlyinc.com-0001/fullchain.pem" ]]; then
    echo "âœ… Active nginx certificate path parsed correctly"
    return 0
  fi

  echo "âŒ Expected nginx certificate path was not parsed, got: '$result'"
  return 1
}

# Test 9: Certbot renewal hooks should handle nginx stop/start/reload
test_write_certbot_nginx_renewal_hooks() {
  echo "🔧 Running test_write_certbot_nginx_renewal_hooks"

  local tmpdir pre_hook post_hook deploy_hook pre_content post_content deploy_content
  tmpdir=$(mktemp -d)
  pre_hook="$tmpdir/pre.sh"
  post_hook="$tmpdir/post.sh"
  deploy_hook="$tmpdir/deploy.sh"

  write_certbot_nginx_pre_hook "$pre_hook"
  write_certbot_nginx_post_hook "$post_hook"
  write_certbot_nginx_reload_hook "$deploy_hook"

  pre_content=$(cat "$pre_hook")
  post_content=$(cat "$post_hook")
  deploy_content=$(cat "$deploy_hook")

  if [[ ! -x "$pre_hook" || ! -x "$post_hook" || ! -x "$deploy_hook" ]]; then
    echo "❌ One or more hook files are not executable"
    rm -rf "$tmpdir"
    return 1
  fi

  if [[ "$pre_content" != *"systemctl stop nginx"* ]]; then
    echo "❌ Pre-hook does not stop nginx"
    rm -rf "$tmpdir"
    return 1
  fi

  if [[ "$post_content" != *"systemctl start nginx"* ]]; then
    echo "❌ Post-hook does not start nginx"
    rm -rf "$tmpdir"
    return 1
  fi

  if [[ "$deploy_content" != *"systemctl reload nginx"* ]]; then
    echo "❌ Deploy-hook does not reload nginx"
    rm -rf "$tmpdir"
    return 1
  fi

  rm -rf "$tmpdir"
  echo "✅ Certbot renewal hooks manage nginx stop/start/reload"
  return 0
}

# Test 10: Format SSL status from timestamps without relying on local cert files
test_format_ssl_certificate_status_from_timestamp() {
  echo "ðŸ”§ Running test_format_ssl_certificate_status_from_timestamp"

  local valid_result expired_result
  valid_result=$(format_ssl_certificate_status_from_timestamp 1738368000 1735689600)
  expired_result=$(format_ssl_certificate_status_from_timestamp 1735603200 1735689600)

  if [[ "$valid_result" != "2025-02-01 (31d) valid" ]]; then
    echo "âŒ Unexpected valid SSL status: '$valid_result'"
    return 1
  fi

  if [[ "$expired_result" != "2024-12-31 (expired 1d ago)" ]]; then
    echo "âŒ Unexpected expired SSL status: '$expired_result'"
    return 1
  fi

  echo "âœ… SSL status formatting handles valid and expired certificates"
  return 0
}

# Test 11: Public edge SSL status should format independently from origin SSL
test_get_edge_ssl_certificate_status_format() {
  echo "🔧 Running test_get_edge_ssl_certificate_status_format"

  local result
  result=$(format_ssl_certificate_status_from_timestamp 1777377251 1774742400)

  if [[ "$result" != "2026-04-28 (30d) valid" ]]; then
    echo "❌ Unexpected edge SSL status: '$result'"
    return 1
  fi

  echo "✅ Edge SSL status formatting is stable"
  return 0
}

# Run all tests
TESTS=(
  "test_app_script_exists"
  "test_app_manager_exists"
  "test_app_script_syntax"
  "test_app_manager_syntax"
  "test_git_module_exists"
  "test_is_valid_kestrel_service_name"
  "test_deployment_dependencies"
  "test_get_nginx_ssl_certificate_path_from_conf"
  "test_write_certbot_nginx_renewal_hooks"
  "test_format_ssl_certificate_status_from_timestamp"
  "test_get_edge_ssl_certificate_status_format"
)

FAILED=0
PASSED=0

# Disable exit on error for test execution
set +e

for test in "${TESTS[@]}"; do
  echo ""
  if $test; then
    ((PASSED++))
  else
    ((FAILED++))
  fi
done

# Re-enable exit on error
set -e

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "App Deployment Tests Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  exit 1
else
  echo "✅ All app deployment tests passed!"
  exit 0
fi
