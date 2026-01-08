#!/bin/bash
# Unit tests for cloudflare.sh functions
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required files
if ! source "$ROOT_DIR/lib/const.sh"; then
  echo " Failed to source const.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/common.sh"; then
  echo " Failed to source common.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/cloudflare.sh"; then
  echo " Failed to source cloudflare.sh"
  exit 1
fi

echo " SOURCES LOADED"

# Test validate_cloudflare_token with empty token
test_validate_cloudflare_token_empty() {
  echo ""
  echo " Running test_validate_cloudflare_token_empty"
  
  if validate_cloudflare_token "" 2>/dev/null; then
    echo " validate_cloudflare_token: Empty token improperly accepted"
    return 1
  else
    echo " validate_cloudflare_token: Empty token properly rejected"
    return 0
  fi
}

# Test validate_cloudflare_token with invalid token format
test_validate_cloudflare_token_invalid() {
  echo ""
  echo " Running test_validate_cloudflare_token_invalid"
  
  if validate_cloudflare_token "invalid_token_12345" 2>/dev/null; then
    echo " validate_cloudflare_token: Invalid token improperly accepted"
    return 1
  else
    echo " validate_cloudflare_token: Invalid token properly rejected"
    return 0
  fi
}

# Test resolve_cloudflare_zone_id with missing token
test_resolve_cloudflare_zone_id_missing_token() {
  echo ""
  echo " Running test_resolve_cloudflare_zone_id_missing_token"
  
  local saved_token="$CLOUDFLARE_API_TOKEN"
  CLOUDFLARE_API_TOKEN=""
  
  if resolve_cloudflare_zone_id "example.com" 2>/dev/null; then
    echo " resolve_cloudflare_zone_id: Should fail with missing token"
    CLOUDFLARE_API_TOKEN="$saved_token"
    return 1
  else
    echo " resolve_cloudflare_zone_id: Properly fails with missing token"
    CLOUDFLARE_API_TOKEN="$saved_token"
    return 0
  fi
}

# Test resolve_cloudflare_zone_id with missing domain
test_resolve_cloudflare_zone_id_missing_domain() {
  echo ""
  echo " Running test_resolve_cloudflare_zone_id_missing_domain"
  
  local saved_token="$CLOUDFLARE_API_TOKEN"
  CLOUDFLARE_API_TOKEN="test_token"
  
  if resolve_cloudflare_zone_id "" 2>/dev/null; then
    echo " resolve_cloudflare_zone_id: Should fail with missing domain"
    CLOUDFLARE_API_TOKEN="$saved_token"
    return 1
  else
    echo " resolve_cloudflare_zone_id: Properly fails with missing domain"
    CLOUDFLARE_API_TOKEN="$saved_token"
    return 0
  fi
}

# Test resolve_cloudflare_zone_id with missing API base
test_resolve_cloudflare_zone_id_missing_base() {
  echo ""
  echo " Running test_resolve_cloudflare_zone_id_missing_base"
  
  # Skip this test since CLOUDFLARE_API_BASE is a readonly constant
  echo " resolve_cloudflare_zone_id: API base is readonly constant (test skipped)"
  return 0
}

# Test module sources successfully
test_cloudflare_syntax() {
  echo ""
  echo " Running test_cloudflare_syntax"
  
  if bash -n "$ROOT_DIR/lib/cloudflare.sh" 2>/dev/null; then
    echo " cloudflare.sh: Valid bash syntax"
    return 0
  else
    echo " cloudflare.sh: Syntax errors detected"
    return 1
  fi
}

# Test that critical functions exist
test_cloudflare_functions_exist() {
  echo ""
  echo " Running test_cloudflare_functions_exist"
  
  local failed=0
  
  if declare -f validate_cloudflare_token >/dev/null; then
    echo " cloudflare: validate_cloudflare_token function exists"
  else
    echo " cloudflare: validate_cloudflare_token function missing"
    failed=1
  fi
  
  if declare -f resolve_cloudflare_zone_id >/dev/null; then
    echo " cloudflare: resolve_cloudflare_zone_id function exists"
  else
    echo " cloudflare: resolve_cloudflare_zone_id function missing"
    failed=1
  fi
  
  return $failed
}

# Run all tests
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Cloudflare Module Tests"
echo "════════════════════════════════════════════════════════════════"

FAILED_TESTS=0

test_cloudflare_syntax || ((FAILED_TESTS++))
test_cloudflare_functions_exist || ((FAILED_TESTS++))
test_validate_cloudflare_token_empty || ((FAILED_TESTS++))
test_validate_cloudflare_token_invalid || ((FAILED_TESTS++))
test_resolve_cloudflare_zone_id_missing_token || ((FAILED_TESTS++))
test_resolve_cloudflare_zone_id_missing_domain || ((FAILED_TESTS++))
test_resolve_cloudflare_zone_id_missing_base || ((FAILED_TESTS++))

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Cloudflare Tests Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $((7 - FAILED_TESTS))"
echo "Failed: $FAILED_TESTS"
echo ""

if [[ $FAILED_TESTS -eq 0 ]]; then
  echo " All cloudflare tests passed!"
  exit 0
else
  echo " $FAILED_TESTS cloudflare test(s) failed"
  exit 1
fi
