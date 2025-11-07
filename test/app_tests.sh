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

# Test 6: Test resolve_domain_from_app_dir function
test_resolve_domain_from_app_dir() {
  echo "🔧 Running test_resolve_domain_from_app_dir"
  
  local input expected result
  
  run_case() {
    input="$1"
    expected="$2"
    result=$(resolve_domain_from_app_dir "$input")
    if [[ "$result" == "$expected" ]]; then
      echo "✅ $input => $result"
    else
      echo "❌ $input => got '$result', expected '$expected'"
      return 1
    fi
  }
  
  run_case "/var/www/example.com/root" "example.com"
  run_case "/var/www/example.com/myapp" "myapp.example.com"
  run_case "/var/www/ghostly.at/frontend" "frontend.ghostly.at"
  run_case "/var/www/ghostly.at/root" "ghostly.at"
  
  return 0
}

# Test 7: Test is_valid_kestrel_service_name function
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

# Test 8: Check deployment dependencies exist
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

# Run all tests
TESTS=(
  "test_app_script_exists"
  "test_app_manager_exists"
  "test_app_script_syntax"
  "test_app_manager_syntax"
  "test_git_module_exists"
  "test_resolve_domain_from_app_dir"
  "test_is_valid_kestrel_service_name"
  "test_deployment_dependencies"
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
