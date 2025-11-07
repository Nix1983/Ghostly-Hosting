#!/bin/bash
# Unit tests for server.sh functions
# Note: We don't use set -e because we want to continue running tests even if some fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "Server Setup Tests"
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

# Test 1: Check if server.sh exists and is readable
test_server_script_exists() {
  echo "🔧 Running test_server_script_exists"
  
  if [[ -f "$ROOT_DIR/lib/server.sh" ]]; then
    echo "✅ server.sh exists"
  else
    echo "❌ server.sh does not exist"
    return 1
  fi
  
  if [[ -r "$ROOT_DIR/lib/server.sh" ]]; then
    echo "✅ server.sh is readable"
  else
    echo "❌ server.sh is not readable"
    return 1
  fi
  
  return 0
}

# Test 2: Check if server.sh can be sourced
test_server_script_sources() {
  echo "🔧 Running test_server_script_sources"
  
  # Test with minimal environment - use timeout to prevent hanging
  if timeout 10 bash -c "cd '$ROOT_DIR' && source lib/const.sh && source lib/common.sh && source lib/print.sh && source lib/server.sh && echo 'success'" 2>/dev/null | grep -q "success"; then
    echo "✅ server.sh sources successfully with dependencies"
    return 0
  else
    echo "❌ server.sh failed to source"
    return 1
  fi
}

# Test 3: Check nginx module exists
test_nginx_module_exists() {
  echo "🔧 Running test_nginx_module_exists"
  
  if [[ -f "$ROOT_DIR/lib/nginx.sh" ]]; then
    echo "✅ nginx.sh module exists"
    return 0
  else
    echo "❌ nginx.sh module does not exist"
    return 1
  fi
}

# Test 4: Check dotnet module exists
test_dotnet_module_exists() {
  echo "🔧 Running test_dotnet_module_exists"
  
  if [[ -f "$ROOT_DIR/lib/dotnet.sh" ]]; then
    echo "✅ dotnet.sh module exists"
    return 0
  else
    echo "❌ dotnet.sh module does not exist"
    return 1
  fi
}

# Test 5: Check fail2ban module exists
test_fail2ban_module_exists() {
  echo "🔧 Running test_fail2ban_module_exists"
  
  if [[ -f "$ROOT_DIR/lib/fail2ban.sh" ]]; then
    echo "✅ fail2ban.sh module exists"
    return 0
  else
    echo "❌ fail2ban.sh module does not exist"
    return 1
  fi
}

# Test 6: Check timezone module exists
test_timezone_module_exists() {
  echo "🔧 Running test_timezone_module_exists"
  
  if [[ -f "$ROOT_DIR/lib/timezone.sh" ]]; then
    echo "✅ timezone.sh module exists"
    return 0
  else
    echo "❌ timezone.sh module does not exist"
    return 1
  fi
}

# Test 7: Validate server.sh syntax
test_server_script_syntax() {
  echo "🔧 Running test_server_script_syntax"
  
  if bash -n "$ROOT_DIR/lib/server.sh" 2>/dev/null; then
    echo "✅ server.sh has valid syntax"
    return 0
  else
    echo "❌ server.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/server.sh"
    return 1
  fi
}

# Test 8: Validate all server-related module syntax
test_server_modules_syntax() {
  echo "🔧 Running test_server_modules_syntax"
  
  local modules=(
    "nginx.sh"
    "dotnet.sh"
    "fail2ban.sh"
    "timezone.sh"
    "certbot.sh"
  )
  
  for module in "${modules[@]}"; do
    if bash -n "$ROOT_DIR/lib/$module" 2>/dev/null; then
      echo "✅ $module has valid syntax"
    else
      echo "❌ $module has syntax errors"
      return 1
    fi
  done
  
  return 0
}

# Run all tests
TESTS=(
  "test_server_script_exists"
  "test_server_script_sources"
  "test_nginx_module_exists"
  "test_dotnet_module_exists"
  "test_fail2ban_module_exists"
  "test_timezone_module_exists"
  "test_server_script_syntax"
  "test_server_modules_syntax"
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
echo "Server Tests Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  exit 1
else
  echo "✅ All server tests passed!"
  exit 0
fi
