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

# Shared mock ip_address response used by UUID-lookup tests
_mock_server_list_response() {
  echo '{"ip_address":{"address":"10.0.0.1","family":"IPv4","server":"test-uuid-1234"}}'
}

# Mock server search response containing lightweight server list entries
_mock_server_search_response() {
  echo '{"servers":{"server":[{"uuid":"test-uuid-1234","title":"GhostlyHosting"}]}}'
}

# Mock server details response containing IP addresses for exact matching
_mock_server_detail_response() {
  echo '{"server":{"uuid":"test-uuid-1234","ip_addresses":{"ip_address":[{"address":"10.0.0.1","family":"IPv4"},{"address":"2001:db8::10","family":"IPv6"}]}}}'
}

# Mock server details response where the public IP is only present on networking interfaces
_mock_server_detail_networking_response() {
  echo '{"server":{"uuid":"test-uuid-5678","ip_addresses":{"ip_address":[{"address":"10.0.0.10","family":"IPv4"}]},"networking":{"interfaces":{"interface":[{"type":"public","ip_addresses":{"ip_address":[{"address":"212.147.228.206","family":"IPv4"}]}}]}}}}'
}

# Mock full server list response used when search lookup is insufficient
_mock_server_inventory_response() {
  echo '{"servers":{"server":[{"uuid":"test-uuid-5678","title":"GhostlyHosting","zone":"fi-hel1"}]}}'
}

_mock_nested_firewall_rules_response() {
  echo '{"firewall_rules":{"firewall_rule":{"firewall_rule":[{"direction":"in","family":"IPv4","protocol":"tcp","action":"accept","destination_port_start":"22","destination_port_end":"22","comment":"SSH access"},{"direction":"out","family":"IPv4","protocol":"udp","action":"accept","destination_port_start":"53","destination_port_end":"53","comment":"DNS"}]}}}'
}

# Mock response where firewall rules are nested deeper under server objects
_mock_recursive_firewall_rules_response() {
  echo '{"server":{"uuid":"srv-1","firewall":{"enabled":"yes"},"details":{"rules":{"items":[{"direction":"in","family":"IPv4","protocol":"tcp","action":"accept","destination_port_start":"22","destination_port_end":"22","comment":"SSH access","position":1},{"direction":"out","family":"IPv4","protocol":"udp","action":"accept","destination_port_start":"53","destination_port_end":"53","comment":"DNS","position":2}]}}}}'
}

# Test _get_upcloud_server_uuid_by_ip resolves UUID via UpCloud metadata service
test_get_server_uuid_from_metadata_service() {
  unset SERVER_UUID
  SERVER_IPv4="212.147.228.206"
  SERVER_IPv6=""
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="mock_token"

  curl() {
    if [[ "$*" == *"http://169.254.169.254/metadata/v1/instance_id"* ]]; then
      printf '00bf9504-a4cb-4839-88ff-124a2c95e169'
      return 0
    fi
    command curl "$@"
  }

  if _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    if [[ "$SERVER_UUID" == "00bf9504-a4cb-4839-88ff-124a2c95e169" ]]; then
      echo "✅ _get_upcloud_server_uuid_by_ip: UUID resolved via metadata service correctly"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f curl
      unset SERVER_UUID
      return 0
    else
      echo "❌ _get_upcloud_server_uuid_by_ip: Wrong UUID resolved from metadata service: $SERVER_UUID"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f curl
      unset SERVER_UUID
      return 1
    fi
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Failed to resolve UUID via metadata service"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f curl
    unset SERVER_UUID
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip resolves UUID via server search and server details
test_get_server_uuid_from_server_search() {
  unset SERVER_UUID
  SERVER_IPv4="10.0.0.1"
  SERVER_IPv6=""
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="mock_token"

  _upcloud_api_request() {
    local endpoint="$2"
    case "$endpoint" in
      "server?search=10.0.0.1")
        printf -v "$4" '%s' "$(_mock_server_search_response)"
        printf -v "$5" '200'
        ;;
      "server/test-uuid-1234")
        printf -v "$4" '%s' "$(_mock_server_detail_response)"
        printf -v "$5" '200'
        ;;
      *)
        printf -v "$4" '%s' ''
        printf -v "$5" '404'
        return 1
        ;;
    esac
  }

  if _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    if [[ "$SERVER_UUID" == "test-uuid-1234" ]]; then
      echo "✅ _get_upcloud_server_uuid_by_ip: UUID resolved via server search correctly"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f _upcloud_api_request
      unset SERVER_UUID
      return 0
    else
      echo "❌ _get_upcloud_server_uuid_by_ip: Wrong UUID resolved from server search: $SERVER_UUID"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f _upcloud_api_request
      unset SERVER_UUID
      return 1
    fi
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Failed to resolve UUID via server search"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_request
    unset SERVER_UUID
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip resolves UUID via full server list and networking interfaces
test_get_server_uuid_from_server_inventory() {
  unset SERVER_UUID
  SERVER_IPv4="212.147.228.206"
  SERVER_IPv6=""
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="mock_token"

  _upcloud_api_request() {
    local endpoint="$2"
    case "$endpoint" in
      "server?search=212.147.228.206")
        printf -v "$4" '%s' '{"servers":{"server":[]}}'
        printf -v "$5" '200'
        ;;
      "server")
        printf -v "$4" '%s' "$(_mock_server_inventory_response)"
        printf -v "$5" '200'
        ;;
      "server/test-uuid-5678")
        printf -v "$4" '%s' "$(_mock_server_detail_networking_response)"
        printf -v "$5" '200'
        ;;
      *)
        printf -v "$4" '%s' ''
        printf -v "$5" '404'
        return 1
        ;;
    esac
  }

  if _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    if [[ "$SERVER_UUID" == "test-uuid-5678" ]]; then
      echo "✅ _get_upcloud_server_uuid_by_ip: UUID resolved via full server inventory correctly"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f _upcloud_api_request
      unset SERVER_UUID
      return 0
    else
      echo "❌ _get_upcloud_server_uuid_by_ip: Wrong UUID resolved from full server inventory: $SERVER_UUID"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f _upcloud_api_request
      unset SERVER_UUID
      return 1
    fi
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Failed to resolve UUID via full server inventory"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_request
    unset SERVER_UUID
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip resolves UUID from ip_address endpoint
test_get_server_uuid_from_server_list() {
  unset SERVER_UUID
  SERVER_IPv4="10.0.0.1"
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="mock_token"

  # Mock _upcloud_api_request to return an ip_address response containing the server UUID
  _upcloud_api_request() {
    local endpoint="$2"
    case "$endpoint" in
      "server?search=10.0.0.1")
        printf -v "$4" '%s' '{"servers":{"server":[]}}'
        printf -v "$5" '200'
        ;;
      "server")
        printf -v "$4" '%s' '{"servers":{"server":[]}}'
        printf -v "$5" '200'
        ;;
      "ip_address/10.0.0.1")
        printf -v "$4" '%s' "$(_mock_server_list_response)"
        printf -v "$5" '200'
        ;;
      *)
        printf -v "$4" '%s' ''
        printf -v "$5" '404'
        return 1
        ;;
    esac
  }

  if _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    if [[ "$SERVER_UUID" == "test-uuid-1234" ]]; then
      echo "✅ _get_upcloud_server_uuid_by_ip: UUID resolved from ip_address endpoint correctly"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f _upcloud_api_request
      unset SERVER_UUID
      return 0
    else
      echo "❌ _get_upcloud_server_uuid_by_ip: Wrong UUID resolved: $SERVER_UUID"
      UPCLOUD_API_TOKEN="$saved_token"
      unset -f _upcloud_api_request
      unset SERVER_UUID
      return 1
    fi
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Failed to resolve UUID from ip_address endpoint"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_request
    unset SERVER_UUID
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip fails gracefully when IP not found (API error)
test_get_server_uuid_ip_not_found() {
  unset SERVER_UUID
  SERVER_IPv4="99.99.99.99"
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="mock_token"

  # Mock _upcloud_api_request to simulate a 404 (IP not found)
  _upcloud_api_request() {
    printf -v "$4" '%s' ''
    printf -v "$5" '404'
    return 1
  }

  if ! _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    echo "✅ _get_upcloud_server_uuid_by_ip: IP not found handled correctly"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_request
    return 0
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Should have failed when IP not found"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_request
    unset SERVER_UUID
    return 1
  fi
}

# Test _get_upcloud_server_uuid_by_ip fails when API returns an HTTP error
test_get_server_uuid_api_http_error() {
  unset SERVER_UUID
  SERVER_IPv4="10.0.0.1"
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  UPCLOUD_API_TOKEN="mock_token"

  # Mock _upcloud_api_request to simulate an HTTP error (e.g. 401 Unauthorized)
  _upcloud_api_request() {
    printf -v "$4" '%s' '{"type":"https://developers.upcloud.com/1.3/errors#ERROR_ACCESS_DENIED","errors":{"error_code":"AUTHENTICATION_FAILED"}}'
    printf -v "$5" '401'
    return 1
  }

  if ! _get_upcloud_server_uuid_by_ip 2>/dev/null; then
    echo "✅ _get_upcloud_server_uuid_by_ip: HTTP error from API handled correctly"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_request
    return 0
  else
    echo "❌ _get_upcloud_server_uuid_by_ip: Should have failed on HTTP error"
    UPCLOUD_API_TOKEN="$saved_token"
    unset -f _upcloud_api_request
    unset SERVER_UUID
    return 1
  fi
}

test_normalize_nested_firewall_rules_response() {
  local normalized count
  normalized=$(_mock_nested_firewall_rules_response | _normalize_upcloud_firewall_rules_array)
  count=$(echo "$normalized" | jq -r 'length' 2>/dev/null)

  if [[ "$count" == "2" ]]; then
    echo "✅ _normalize_upcloud_firewall_rules_array: Nested firewall rule wrapper normalized correctly"
    return 0
  fi

  echo "❌ _normalize_upcloud_firewall_rules_array: Expected 2 rules, got: $count"
  return 1
}

test_normalize_recursive_firewall_rules_response() {
  local normalized count
  normalized=$(_mock_recursive_firewall_rules_response | _normalize_upcloud_firewall_rules_array)
  count=$(echo "$normalized" | jq -r 'length' 2>/dev/null)

  if [[ "$count" == "2" ]]; then
    echo "✅ _normalize_upcloud_firewall_rules_array: Recursive firewall rule extraction works correctly"
    return 0
  fi

  echo "❌ _normalize_upcloud_firewall_rules_array: Expected 2 recursively found rules, got: $count"
  return 1
}

test_get_firewall_rule_lines_from_exact_response() {
  local response lines count
  response='{"firewall_rules":{"firewall_rule":[{"direction":"in","family":"IPv4","protocol":"tcp","action":"accept","destination_port_start":"22","destination_port_end":"22","comment":"SSH access","position":"1"},{"direction":"out","family":"IPv4","protocol":"udp","action":"accept","destination_port_start":"53","destination_port_end":"53","comment":"DNS","position":"2"}]}}'
  lines=$(_get_upcloud_firewall_rule_lines_from_response "$response")
  count=$(printf '%s\n' "$lines" | jq -s 'length' 2>/dev/null)

  if [[ "$count" == "2" ]]; then
    echo "✅ _get_upcloud_firewall_rule_lines_from_response: Exact array response extracted correctly"
    return 0
  fi

  echo "❌ _get_upcloud_firewall_rule_lines_from_response: Expected 2 extracted rules, got: $count"
  return 1
}

test_get_upcloud_firewall_rules_response_populates_caller_variable() {
  local body="" status=""

  _upcloud_api_request() {
    printf -v "$4" '%s' '{"firewall_rules":{"firewall_rule":[{"direction":"in","action":"accept","protocol":"tcp","family":"IPv4","position":"1"}]}}'
    printf -v "$5" '%s' '200'
    return 0
  }

  if _get_upcloud_firewall_rules_response body status 2>/dev/null; then
    if [[ "$status" == "200" ]] && [[ "$body" == *'"firewall_rules"'* ]]; then
      echo "✅ _get_upcloud_firewall_rules_response: Caller variables populated correctly"
      unset -f _upcloud_api_request
      return 0
    fi
  fi

  echo "❌ _get_upcloud_firewall_rules_response: Failed to populate caller variables"
  unset -f _upcloud_api_request
  return 1
}

test_delete_all_upcloud_firewall_rules_uses_bulk_reset() {
  local saved_token="${UPCLOUD_API_TOKEN:-}"
  local saved_uuid="${SERVER_UUID:-}"
  local bulk_called="false"
  local bulk_payload=""
  local output_file

  UPCLOUD_API_TOKEN="mock_token"
  SERVER_UUID="srv-test-123"
  DISABLE_CLEAR=true
  output_file=$(mktemp)

  _verify_upcloud_context() { return 0; }
  _get_upcloud_firewall_enabled_state() { printf 'enabled\n'; }
  _get_upcloud_firewall_rules_response() {
    if [[ "$1" == "remaining_response" ]]; then
      printf -v "$1" '%s' '{"firewall_rules":{"firewall_rule":[]}}'
    else
      printf -v "$1" '%s' '{"firewall_rules":{"firewall_rule":[{"direction":"in","family":"IPv4","protocol":"tcp","action":"accept","position":"1","destination_port_start":"22","destination_port_end":"22","comment":"SSH"}]}}'
    fi
    printf -v "$2" '%s' '200'
    return 0
  }
  _upcloud_api_request() {
    if [[ "$1" == "PUT" && "$2" == "server/$SERVER_UUID/firewall_rule" ]]; then
      bulk_called="true"
      bulk_payload="$3"
      printf -v "$4" '%s' '{}'
      printf -v "$5" '%s' '200'
      return 0
    fi
    printf -v "$4" '%s' '{}'
    printf -v "$5" '%s' '200'
    return 0
  }
  curl() {
    echo "unexpected curl fallback"
    return 99
  }

  if delete_all_upcloud_firewall_rules >"$output_file" 2>/dev/null; then
    if [[ "$bulk_called" == "true" ]] && [[ "$bulk_payload" == '{"firewall_rules":{"firewall_rule":[]}}' ]] && grep -q "fast bulk reset" "$output_file"; then
      echo "✅ delete_all_upcloud_firewall_rules: Fast bulk reset path used correctly"
      unset -f _verify_upcloud_context _get_upcloud_firewall_enabled_state _get_upcloud_firewall_rules_response _upcloud_api_request curl
      UPCLOUD_API_TOKEN="$saved_token"
      SERVER_UUID="$saved_uuid"
      unset DISABLE_CLEAR
      rm -f "$output_file"
      return 0
    fi
  fi

  echo "❌ delete_all_upcloud_firewall_rules: Fast bulk reset path not used as expected"
  unset -f _verify_upcloud_context _get_upcloud_firewall_enabled_state _get_upcloud_firewall_rules_response _upcloud_api_request curl
  UPCLOUD_API_TOKEN="$saved_token"
  SERVER_UUID="$saved_uuid"
  unset DISABLE_CLEAR
  rm -f "$output_file"
  return 1
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
run_test test_normalize_nested_firewall_rules_response || ((FAILED++))
run_test test_normalize_recursive_firewall_rules_response || ((FAILED++))
run_test test_get_firewall_rule_lines_from_exact_response || ((FAILED++))
run_test test_get_upcloud_firewall_rules_response_populates_caller_variable || ((FAILED++))
run_test test_delete_all_upcloud_firewall_rules_uses_bulk_reset || ((FAILED++))
run_test test_get_server_uuid_from_metadata_service || ((FAILED++))
run_test test_get_server_uuid_from_server_search || ((FAILED++))
run_test test_get_server_uuid_from_server_inventory || ((FAILED++))
run_test test_get_server_uuid_from_server_list || ((FAILED++))
run_test test_get_server_uuid_ip_not_found || ((FAILED++))
run_test test_get_server_uuid_api_http_error || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All upcloud tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
