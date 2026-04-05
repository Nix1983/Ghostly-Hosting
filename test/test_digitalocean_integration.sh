#!/bin/bash
# Integration tests for lib/digitalocean.sh
# Tests validate function contracts and error handling without real API calls.
# shellcheck disable=SC1091,SC2317

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "================================================================"
echo "Digital Ocean Integration Tests"
echo "================================================================"

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

pushd "$ROOT_DIR" >/dev/null || exit 1

if ! source "$ROOT_DIR/lib/digitalocean.sh"; then
  popd >/dev/null || true
  echo "❌ Failed to source digitalocean.sh"
  exit 1
fi

popd >/dev/null || true

echo "✅ SOURCES LOADED"
echo ""

# =============================================================================
# Tests: Token validation – missing / empty token
# =============================================================================

test_validate_digitalocean_token_missing() {
  if ! validate_digitalocean_token "" 2>/dev/null; then
    echo "✅ validate_digitalocean_token: Missing token properly rejected"
    return 0
  else
    echo "❌ validate_digitalocean_token: Missing token improperly accepted"
    return 1
  fi
}

test_validate_digitalocean_token_null() {
  if ! validate_digitalocean_token 2>/dev/null; then
    echo "✅ validate_digitalocean_token: Null token properly rejected"
    return 0
  else
    echo "❌ validate_digitalocean_token: Null token improperly accepted"
    return 1
  fi
}

# =============================================================================
# Tests: digitalocean.sh file and required functions exist
# =============================================================================

test_digitalocean_file_exists() {
  if [[ -f "$ROOT_DIR/lib/digitalocean.sh" ]]; then
    echo "✅ digitalocean.sh: File exists"
    return 0
  else
    echo "❌ digitalocean.sh: File not found"
    return 1
  fi
}

test_required_functions_defined() {
  local all_ok=true
  local -a required_functions=(
    "_digitalocean_api_request"
    "validate_digitalocean_token"
    "apply_digitalocean_firewall_rules"
    "delete_all_digitalocean_firewall_rules"
    "_show_digitalocean_firewall_status"
    "_enable_digitalocean_firewall"
    "_disable_digitalocean_firewall"
    "show_digitalocean_menu"
    "_configure_digitalocean_api_token"
  )
  for fn in "${required_functions[@]}"; do
    if declare -f "$fn" >/dev/null 2>&1; then
      echo "✅ Function '$fn' is defined"
    else
      echo "❌ Function '$fn' is NOT defined"
      all_ok=false
    fi
  done
  [[ "$all_ok" == true ]]
}

# =============================================================================
# Tests: apply_digitalocean_firewall_rules – missing token
# =============================================================================

test_apply_rules_missing_token() {
  local saved_token="${DIGITALOCEAN_API_TOKEN:-}"
  DIGITALOCEAN_API_TOKEN=""

  if ! apply_digitalocean_firewall_rules 2>/dev/null; then
    echo "✅ apply_digitalocean_firewall_rules: Missing token properly rejected"
    DIGITALOCEAN_API_TOKEN="$saved_token"
    return 0
  else
    echo "❌ apply_digitalocean_firewall_rules: Missing token improperly accepted"
    DIGITALOCEAN_API_TOKEN="$saved_token"
    return 1
  fi
}

# =============================================================================
# Tests: delete_all_digitalocean_firewall_rules – missing token
# =============================================================================

test_delete_rules_missing_token() {
  local saved_token="${DIGITALOCEAN_API_TOKEN:-}"
  DIGITALOCEAN_API_TOKEN=""

  if ! delete_all_digitalocean_firewall_rules 2>/dev/null; then
    echo "✅ delete_all_digitalocean_firewall_rules: Missing token properly rejected"
    DIGITALOCEAN_API_TOKEN="$saved_token"
    return 0
  else
    echo "❌ delete_all_digitalocean_firewall_rules: Missing token improperly accepted"
    DIGITALOCEAN_API_TOKEN="$saved_token"
    return 1
  fi
}

# =============================================================================
# Tests: _build_digitalocean_firewall_payload
# =============================================================================

test_build_payload_produces_valid_json() {
  local rules_file="$ROOT_DIR/config/desired_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: desired_firewall_rules.json not found"
    return 1
  fi

  local payload
  payload=$(_build_digitalocean_firewall_payload "$rules_file" 2>/dev/null)

  if [[ -z "$payload" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: Produced empty payload"
    return 1
  fi

  if ! echo "$payload" | jq . >/dev/null 2>&1; then
    echo "❌ _build_digitalocean_firewall_payload: Produced invalid JSON"
    return 1
  fi

  echo "✅ _build_digitalocean_firewall_payload: Produces valid JSON"
  return 0
}

test_build_payload_has_inbound_rules() {
  local rules_file="$ROOT_DIR/config/desired_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: desired_firewall_rules.json not found"
    return 1
  fi

  local payload inbound_count
  payload=$(_build_digitalocean_firewall_payload "$rules_file" 2>/dev/null)
  inbound_count=$(echo "$payload" | jq '.inbound_rules | length' 2>/dev/null)

  if [[ "$inbound_count" -gt 0 ]]; then
    echo "✅ _build_digitalocean_firewall_payload: Inbound rules present ($inbound_count rules)"
    return 0
  else
    echo "❌ _build_digitalocean_firewall_payload: No inbound rules in payload"
    return 1
  fi
}

test_build_payload_has_outbound_rules() {
  local rules_file="$ROOT_DIR/config/desired_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: desired_firewall_rules.json not found"
    return 1
  fi

  local payload outbound_count
  payload=$(_build_digitalocean_firewall_payload "$rules_file" 2>/dev/null)
  outbound_count=$(echo "$payload" | jq '.outbound_rules | length' 2>/dev/null)

  if [[ "$outbound_count" -gt 0 ]]; then
    echo "✅ _build_digitalocean_firewall_payload: Outbound rules present ($outbound_count rules)"
    return 0
  else
    echo "❌ _build_digitalocean_firewall_payload: No outbound rules in payload"
    return 1
  fi
}

test_build_payload_firewall_name() {
  local rules_file="$ROOT_DIR/config/desired_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: desired_firewall_rules.json not found"
    return 1
  fi

  local payload name
  payload=$(_build_digitalocean_firewall_payload "$rules_file" 2>/dev/null)
  name=$(echo "$payload" | jq -r '.name' 2>/dev/null)

  if [[ "$name" == "ghostly-hosting-firewall" ]]; then
    echo "✅ _build_digitalocean_firewall_payload: Firewall name is 'ghostly-hosting-firewall'"
    return 0
  else
    echo "❌ _build_digitalocean_firewall_payload: Expected name 'ghostly-hosting-firewall', got '$name'"
    return 1
  fi
}

test_build_payload_inbound_has_addresses() {
  local rules_file="$ROOT_DIR/config/desired_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: desired_firewall_rules.json not found"
    return 1
  fi

  local payload has_ipv4 has_ipv6
  payload=$(_build_digitalocean_firewall_payload "$rules_file" 2>/dev/null)
  has_ipv4=$(echo "$payload" | jq '[.inbound_rules[].sources.addresses[] | select(. == "0.0.0.0/0")] | length' 2>/dev/null)
  has_ipv6=$(echo "$payload" | jq '[.inbound_rules[].sources.addresses[] | select(. == "::/0")] | length' 2>/dev/null)

  if [[ "$has_ipv4" -gt 0 && "$has_ipv6" -gt 0 ]]; then
    echo "✅ _build_digitalocean_firewall_payload: Inbound rules include IPv4 and IPv6 addresses"
    return 0
  else
    echo "❌ _build_digitalocean_firewall_payload: Missing IPv4 ($has_ipv4) or IPv6 ($has_ipv6) in inbound rules"
    return 1
  fi
}

# =============================================================================
# Tests: DIGITALOCEAN_API_BASE is set
# =============================================================================

test_api_base_is_set() {
  if [[ -n "${DIGITALOCEAN_API_BASE:-}" ]]; then
    echo "✅ DIGITALOCEAN_API_BASE: Set to '${DIGITALOCEAN_API_BASE}'"
    return 0
  else
    echo "❌ DIGITALOCEAN_API_BASE: Not set"
    return 1
  fi
}

test_api_base_correct_url() {
  if [[ "${DIGITALOCEAN_API_BASE:-}" == "https://api.digitalocean.com/v2" ]]; then
    echo "✅ DIGITALOCEAN_API_BASE: Correct URL"
    return 0
  else
    echo "❌ DIGITALOCEAN_API_BASE: Expected 'https://api.digitalocean.com/v2', got '${DIGITALOCEAN_API_BASE:-}'"
    return 1
  fi
}

# =============================================================================
# Tests: _show_digitalocean_firewall_status – missing token
# =============================================================================

test_show_firewall_status_missing_token() {
  local saved_token="${DIGITALOCEAN_API_TOKEN:-}"
  DIGITALOCEAN_API_TOKEN=""

  if ! _show_digitalocean_firewall_status 2>/dev/null; then
    echo "✅ _show_digitalocean_firewall_status: Missing token properly rejected"
    DIGITALOCEAN_API_TOKEN="$saved_token"
    return 0
  else
    echo "❌ _show_digitalocean_firewall_status: Missing token improperly accepted"
    DIGITALOCEAN_API_TOKEN="$saved_token"
    return 1
  fi
}

# =============================================================================
# Run all tests
# =============================================================================

FAILED=0

run_test() {
  local test_fn="$1"
  if ! $test_fn; then
    FAILED=$((FAILED + 1))
  fi
}

run_test test_validate_digitalocean_token_missing
run_test test_validate_digitalocean_token_null
run_test test_digitalocean_file_exists
run_test test_required_functions_defined
run_test test_apply_rules_missing_token
run_test test_delete_rules_missing_token
run_test test_build_payload_produces_valid_json
run_test test_build_payload_has_inbound_rules
run_test test_build_payload_has_outbound_rules
run_test test_build_payload_firewall_name
run_test test_build_payload_inbound_has_addresses
run_test test_api_base_is_set
run_test test_api_base_correct_url
run_test test_show_firewall_status_missing_token

echo ""
if [[ $FAILED -eq 0 ]]; then
  echo "✅ All Digital Ocean integration tests passed"
  exit 0
else
  echo "❌ $FAILED test(s) failed"
  exit 1
fi
