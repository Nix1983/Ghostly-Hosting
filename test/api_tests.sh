#!/bin/bash
# Unit tests for API integrations (GitHub, Cloudflare, UpCloud)
# Note: We don't use set -e because we want to continue running tests even if some fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "API Integration Tests"
echo "════════════════════════════════════════════════════════════════"

# Source required libraries
if ! source "$ROOT_DIR/lib/const.sh"; then
  echo " Failed to source const.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/common.sh"; then
  echo " Failed to source common.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/print.sh"; then
  echo " Failed to source print.sh"
  exit 1
fi

echo " SOURCES LOADED"
echo ""

# Test 1: Check if cloudflare.sh exists and is readable
test_cloudflare_module_exists() {
  echo " Running test_cloudflare_module_exists"
  
  if [[ -f "$ROOT_DIR/lib/cloudflare.sh" ]]; then
    echo " cloudflare.sh exists"
  else
    echo " cloudflare.sh does not exist"
    return 1
  fi
  
  if [[ -r "$ROOT_DIR/lib/cloudflare.sh" ]]; then
    echo " cloudflare.sh is readable"
  else
    echo " cloudflare.sh is not readable"
    return 1
  fi
  
  return 0
}

# Test 2: Check if upcloud.sh exists and is readable
test_upcloud_module_exists() {
  echo " Running test_upcloud_module_exists"
  
  if [[ -f "$ROOT_DIR/lib/upcloud.sh" ]]; then
    echo " upcloud.sh exists"
  else
    echo " upcloud.sh does not exist"
    return 1
  fi
  
  if [[ -r "$ROOT_DIR/lib/upcloud.sh" ]]; then
    echo " upcloud.sh is readable"
  else
    echo " upcloud.sh is not readable"
    return 1
  fi
  
  return 0
}

# Test 3: Check if github.sh exists and is readable
test_github_module_exists() {
  echo " Running test_github_module_exists"
  
  if [[ -f "$ROOT_DIR/lib/github.sh" ]]; then
    echo " github.sh exists"
  else
    echo " github.sh does not exist"
    return 1
  fi
  
  if [[ -r "$ROOT_DIR/lib/github.sh" ]]; then
    echo " github.sh is readable"
  else
    echo " github.sh is not readable"
    return 1
  fi
  
  return 0
}

# Test 4: Validate cloudflare.sh syntax
test_cloudflare_syntax() {
  echo " Running test_cloudflare_syntax"
  
  if bash -n "$ROOT_DIR/lib/cloudflare.sh" 2>/dev/null; then
    echo " cloudflare.sh has valid syntax"
    return 0
  else
    echo " cloudflare.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/cloudflare.sh"
    return 1
  fi
}

# Test 5: Validate upcloud.sh syntax
test_upcloud_syntax() {
  echo " Running test_upcloud_syntax"
  
  if bash -n "$ROOT_DIR/lib/upcloud.sh" 2>/dev/null; then
    echo " upcloud.sh has valid syntax"
    return 0
  else
    echo " upcloud.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/upcloud.sh"
    return 1
  fi
}

# Test 6: Validate github.sh syntax
test_github_syntax() {
  echo " Running test_github_syntax"
  
  if bash -n "$ROOT_DIR/lib/github.sh" 2>/dev/null; then
    echo " github.sh has valid syntax"
    return 0
  else
    echo " github.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/github.sh"
    return 1
  fi
}

# Test 7: Test UpCloud token validation
test_upcloud_token_validation() {
  echo " Running test_upcloud_token_validation"
  
  # Load upcloud.sh
  if ! source "$ROOT_DIR/lib/upcloud.sh"; then
    echo " Failed to source upcloud.sh"
    return 1
  fi
  
  # Test with missing token
  if ! validate_upcloud_token "" 2>/dev/null; then
    echo " validate_upcloud_token: Empty token properly rejected"
  else
    echo " validate_upcloud_token: Empty token improperly accepted"
    return 1
  fi
  
  # Test with null token
  if ! validate_upcloud_token 2>/dev/null; then
    echo " validate_upcloud_token: Null token properly rejected"
  else
    echo " validate_upcloud_token: Null token improperly accepted"
    return 1
  fi
  
  return 0
}

# Test 8: Test GitHub functions exist
test_github_functions_exist() {
  echo " Running test_github_functions_exist"
  
  # Load github.sh
  if ! source "$ROOT_DIR/lib/github.sh"; then
    echo " Failed to source github.sh"
    return 1
  fi
  
  # Check if key functions are defined
  if declare -f resolve_github_user_from_token >/dev/null 2>&1; then
    echo " resolve_github_user_from_token function exists"
  else
    echo " resolve_github_user_from_token function does not exist"
    return 1
  fi
  
  if declare -f validate_github_token >/dev/null 2>&1; then
    echo " validate_github_token function exists"
  else
    echo " validate_github_token function does not exist"
    return 1
  fi
  
  if declare -f clone_repository >/dev/null 2>&1; then
    echo " clone_repository function exists"
  else
    echo " clone_repository function does not exist"
    return 1
  fi
  
  return 0
}

# Test 9: Test Cloudflare module can be sourced
test_cloudflare_module_sources() {
  echo " Running test_cloudflare_module_sources"
  
  # Test with minimal environment - use timeout to prevent hanging
  if timeout 10 bash -c "cd '$ROOT_DIR' && source lib/const.sh && source lib/common.sh && source lib/cloudflare.sh && echo 'success'" 2>/dev/null | grep -q "success"; then
    echo " cloudflare.sh sources successfully"
    return 0
  else
    echo " cloudflare.sh failed to source"
    return 1
  fi
}

# Test 10: Test all API modules have required dependencies
test_api_dependencies() {
  echo " Running test_api_dependencies"
  
  # Check if curl is available (required for API calls)
  if command -v curl >/dev/null 2>&1; then
    echo " curl is available"
  else
    echo "  curl not available (required for API calls)"
  fi
  
  # Check if jq is available (required for JSON parsing)
  if command -v jq >/dev/null 2>&1; then
    echo " jq is available"
  else
    echo "  jq not available (required for JSON parsing)"
  fi
  
  return 0
}

# Run all tests
TESTS=(
  "test_cloudflare_module_exists"
  "test_upcloud_module_exists"
  "test_github_module_exists"
  "test_cloudflare_syntax"
  "test_upcloud_syntax"
  "test_github_syntax"
  "test_upcloud_token_validation"
  "test_github_functions_exist"
  "test_cloudflare_module_sources"
  "test_api_dependencies"
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
echo "API Integration Tests Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  exit 1
else
  echo " All API integration tests passed!"
  exit 0
fi
