#!/bin/bash
# Unit tests for cloudflare.sh functions
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required files
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

if ! source "$ROOT_DIR/lib/cloudflare.sh"; then
  echo "❌ Failed to source cloudflare.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test validate_cloudflare_token with empty token
test_validate_cloudflare_token_empty() {
  if ! validate_cloudflare_token "" 2>/dev/null; then
    echo "✅ validate_cloudflare_token: Empty token properly rejected"
    return 0
  else
    echo "❌ validate_cloudflare_token: Empty token improperly accepted"
    return 1
  fi
}

# Test validate_cloudflare_token with invalid token
test_validate_cloudflare_token_invalid() {
  if ! validate_cloudflare_token "invalid_token_12345" 2>/dev/null; then
    echo "✅ validate_cloudflare_token: Invalid token properly rejected"
    return 0
  else
    echo "❌ validate_cloudflare_token: Invalid token improperly accepted"
    return 1
  fi
}

# Test resolve_cloudflare_zone_id with empty domain
test_resolve_cloudflare_zone_id_empty_domain() {
  local saved_token="${CLOUDFLARE_API_TOKEN:-}"
  CLOUDFLARE_API_TOKEN="test_token"
  
  if ! resolve_cloudflare_zone_id "" 2>/dev/null; then
    echo "✅ resolve_cloudflare_zone_id: Empty domain properly rejected"
    CLOUDFLARE_API_TOKEN="$saved_token"
    return 0
  else
    echo "❌ resolve_cloudflare_zone_id: Empty domain improperly accepted"
    CLOUDFLARE_API_TOKEN="$saved_token"
    return 1
  fi
}

# Test resolve_cloudflare_zone_id with missing token
test_resolve_cloudflare_zone_id_missing_token() {
  local saved_token="${CLOUDFLARE_API_TOKEN:-}"
  CLOUDFLARE_API_TOKEN=""
  
  if ! resolve_cloudflare_zone_id "example.com" 2>/dev/null; then
    echo "✅ resolve_cloudflare_zone_id: Missing token properly handled"
    CLOUDFLARE_API_TOKEN="$saved_token"
    return 0
  else
    echo "❌ resolve_cloudflare_zone_id: Missing token improperly handled"
    CLOUDFLARE_API_TOKEN="$saved_token"
    return 1
  fi
}

# Test has_cloudflare_dns_record with missing parameters
test_has_cloudflare_dns_record_missing_params() {
  output=$(has_cloudflare_dns_record "" "" "" "" 2>&1)
  if [[ "$output" == "❌" ]]; then
    echo "✅ has_cloudflare_dns_record: Missing parameters properly handled"
    return 0
  fi
  echo "❌ has_cloudflare_dns_record: Should reject missing parameters (got: $output)"
  return 1
}

# Test get_cloudflare_proxy_status with missing parameters
test_get_cloudflare_proxy_status_missing_params() {
  output=$(get_cloudflare_proxy_status "" "" "" 2>&1)
  if [[ "$output" == "❌" ]]; then
    echo "✅ get_cloudflare_proxy_status: Missing parameters properly handled"
    return 0
  fi
  echo "❌ get_cloudflare_proxy_status: Should reject missing parameters (got: $output)"
  return 1
}

# Test cloudflare.sh functions exist
test_cloudflare_functions_exist() {
  local functions=(
    "validate_cloudflare_token"
    "resolve_cloudflare_zone_id"
    "has_cloudflare_dns_record"
    "get_cloudflare_proxy_status"
    "toggle_cloudflare_proxy"
    "delete_cloudflare_dns_records"
  )
  
  for func in "${functions[@]}"; do
    if declare -f "$func" >/dev/null 2>&1; then
      echo "✅ $func function exists"
    else
      echo "❌ $func function missing"
      return 1
    fi
  done
  
  return 0
}

run_test() {
  echo -e "\n🔧 Running $1"
  if ! "$1"; then
    echo "❌ Test '$1' failed"
    return 1
  fi
  return 0
}

# Run all tests
FAILED=0

run_test test_cloudflare_functions_exist || ((FAILED++))
run_test test_validate_cloudflare_token_empty || ((FAILED++))
run_test test_validate_cloudflare_token_invalid || ((FAILED++))
run_test test_resolve_cloudflare_zone_id_empty_domain || ((FAILED++))
run_test test_resolve_cloudflare_zone_id_missing_token || ((FAILED++))
run_test test_has_cloudflare_dns_record_missing_params || ((FAILED++))
run_test test_get_cloudflare_proxy_status_missing_params || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All Cloudflare tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
