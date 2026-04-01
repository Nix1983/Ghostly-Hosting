#!/bin/bash
# Unit tests for upcloud.sh functions focusing on error handling
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Note: const.sh defines readonly variables, so we must source it first
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

if ! source "$ROOT_DIR/lib/upcloud.sh"; then
  echo "❌ Failed to source upcloud.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test validate_upcloud_token with missing token
test_validate_upcloud_token_missing() {
  if ! validate_upcloud_token "" 2>/dev/null; then
    echo "✅ validate_upcloud_token: Missing token properly rejected"
    return 0
  else
    echo "❌ validate_upcloud_token: Missing token improperly accepted"
    return 1
  fi
}

# Test validate_upcloud_token with null token
test_validate_upcloud_token_null() {
  if ! validate_upcloud_token 2>/dev/null; then
    echo "✅ validate_upcloud_token: Null token properly rejected"
    return 0
  else
    echo "❌ validate_upcloud_token: Null token improperly accepted"
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip with missing IPv4
test_get_server_uuid_missing_ipv4() {
  unset SERVER_UUID
  SERVER_IPv4=""
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="some_token"
  
  if ! _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    echo "✅ _get_upcloud_server_uuid_by_ip: Missing IPv4 handled correctly"
    UPCLOUD_API_TOKEN="$saved_token"
    return 0
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Should have failed for missing IPv4"
    UPCLOUD_API_TOKEN="$saved_token"
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip with cached UUID
test_get_server_uuid_cached() {
  SERVER_UUID="cached-uuid"
  SERVER_IPv4="1.2.3.4"
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="some_token"
  
  if _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    if [[ "$SERVER_UUID" == "cached-uuid" ]]; then
      echo "✅ _get_upcloud_server_uuid_by_ip: Cached UUID used correctly"
      UPCLOUD_API_TOKEN="$saved_token"
      unset SERVER_UUID
      return 0
    else
      echo "❌ _get_upcloud_server_uuid_by_ip: Cached UUID was overwritten"
      UPCLOUD_API_TOKEN="$saved_token"
      unset SERVER_UUID
      return 1
    fi
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Failed with cached UUID"
    UPCLOUD_API_TOKEN="$saved_token"
    unset SERVER_UUID
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip with missing credentials
test_get_server_uuid_missing_creds() {
  unset SERVER_UUID
  SERVER_IPv4="1.2.3.4"
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN=""
  
  if ! _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    echo "✅ _get_upcloud_server_uuid_by_ip: Missing token handled correctly"
    UPCLOUD_API_TOKEN="$saved_token"
    return 0
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Should have failed for missing token"
    UPCLOUD_API_TOKEN="$saved_token"
    return 1
  fi
}

# Shared mock server list response used by UUID-lookup tests
_mock_server_list_response() {
  echo '{"servers":{"server":[{"uuid":"test-uuid-1234","ip_addresses":{"ip_address":[{"address":"10.0.0.1","family":"IPv4"}]}}]}}'
}

# Test _get_upcloud_server_uuid_by_ip resolves UUID from server list
test_get_server_uuid_from_server_list() {
  unset SERVER_UUID
  SERVER_IPv4="10.0.0.1"
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="mock_token"

  # Mock _upcloud_api_get to return a server list containing the target IP
  _upcloud_api_get() { _mock_server_list_response; }

  if _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    if [[ "$SERVER_UUID" == "test-uuid-1234" ]]; then
      echo "✅ _get_upcloud_server_uuid_by_ip: UUID resolved from server list correctly"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f _upcloud_api_get
      unset SERVER_UUID
      return 0
    else
      echo "❌ _get_upcloud_server_uuid_by_ip: Wrong UUID resolved: $SERVER_UUID"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f _upcloud_api_get
      unset SERVER_UUID
      return 1
    fi
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Failed to resolve UUID from server list"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_get
    unset SERVER_UUID
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip fails gracefully when IP not in server list
test_get_server_uuid_ip_not_found() {
  unset SERVER_UUID
  SERVER_IPv4="99.99.99.99"
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="mock_token"

  # Mock _upcloud_api_get to return a server list that does NOT contain the target IP
  _upcloud_api_get() { _mock_server_list_response; }

  if ! _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    echo "✅ _get_upcloud_server_uuid_by_ip: IP not found in server list handled correctly"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_get
    return 0
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Should have failed when IP not in server list"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_get
    unset SERVER_UUID
    return 1
  fi
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

run_test test_validate_upcloud_token_missing || ((FAILED++))
run_test test_validate_upcloud_token_null || ((FAILED++))
run_test test_get_server_uuid_missing_ipv4 || ((FAILED++))
run_test test_get_server_uuid_cached || ((FAILED++))
run_test test_get_server_uuid_missing_creds || ((FAILED++))
run_test test_get_server_uuid_from_server_list || ((FAILED++))
run_test test_get_server_uuid_ip_not_found || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All upcloud tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
