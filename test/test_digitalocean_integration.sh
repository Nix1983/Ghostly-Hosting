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
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: digitalocean_firewall_rules.json not found"
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
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: digitalocean_firewall_rules.json not found"
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
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: digitalocean_firewall_rules.json not found"
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
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: digitalocean_firewall_rules.json not found"
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
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ _build_digitalocean_firewall_payload: digitalocean_firewall_rules.json not found"
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
# Tests: Provider-specific firewall rule files
# =============================================================================

test_digitalocean_rules_file_exists() {
  if [[ -f "$ROOT_DIR/config/digitalocean_firewall_rules.json" ]]; then
    echo "✅ digitalocean_firewall_rules.json: File exists"
    return 0
  else
    echo "❌ digitalocean_firewall_rules.json: File not found"
    return 1
  fi
}

test_upcloud_rules_file_exists() {
  if [[ -f "$ROOT_DIR/config/upcloud_firewall_rules.json" ]]; then
    echo "✅ upcloud_firewall_rules.json: File exists"
    return 0
  else
    echo "❌ upcloud_firewall_rules.json: File not found"
    return 1
  fi
}

test_digitalocean_rules_file_is_valid_json() {
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if jq . "$rules_file" >/dev/null 2>&1; then
    echo "✅ digitalocean_firewall_rules.json: Valid JSON"
    return 0
  else
    echo "❌ digitalocean_firewall_rules.json: Invalid JSON"
    return 1
  fi
}

test_upcloud_rules_file_is_valid_json() {
  local rules_file="$ROOT_DIR/config/upcloud_firewall_rules.json"
  if jq . "$rules_file" >/dev/null 2>&1; then
    echo "✅ upcloud_firewall_rules.json: Valid JSON"
    return 0
  else
    echo "❌ upcloud_firewall_rules.json: Invalid JSON"
    return 1
  fi
}

# DO rules file must not contain duplicate (protocol+port) combinations — having
# duplicates would cause a "duplicate rules" 422 error from the Digital Ocean API.
test_digitalocean_rules_no_duplicates() {
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ digitalocean_rules_no_duplicates: File not found"
    return 1
  fi

  local total unique
  total=$(jq '.firewall_rules.firewall_rule | length' "$rules_file" 2>/dev/null)
  unique=$(jq '.firewall_rules.firewall_rule | unique_by(.direction + .protocol + .destination_port_start) | length' "$rules_file" 2>/dev/null)

  if [[ "$total" == "$unique" ]]; then
    echo "✅ digitalocean_rules_no_duplicates: No duplicate rules ($total rules, all unique)"
    return 0
  else
    echo "❌ digitalocean_rules_no_duplicates: Found duplicates ($total rules, only $unique unique)"
    return 1
  fi
}

# UpCloud rules file must contain both IPv4 and IPv6 family entries.
test_upcloud_rules_has_ipv4_and_ipv6() {
  local rules_file="$ROOT_DIR/config/upcloud_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ upcloud_rules_has_ipv4_and_ipv6: File not found"
    return 1
  fi

  local ipv4_count ipv6_count
  ipv4_count=$(jq '[.firewall_rules.firewall_rule[] | select(.family == "IPv4")] | length' "$rules_file" 2>/dev/null)
  ipv6_count=$(jq '[.firewall_rules.firewall_rule[] | select(.family == "IPv6")] | length' "$rules_file" 2>/dev/null)

  if [[ "$ipv4_count" -gt 0 && "$ipv6_count" -gt 0 ]]; then
    echo "✅ upcloud_rules_has_ipv4_and_ipv6: Contains IPv4 ($ipv4_count) and IPv6 ($ipv6_count) rules"
    return 0
  else
    echo "❌ upcloud_rules_has_ipv4_and_ipv6: Missing IPv4 ($ipv4_count) or IPv6 ($ipv6_count) rules"
    return 1
  fi
}

# DO rules file must not contain the 'family' field (not used by Digital Ocean API).
test_digitalocean_rules_no_family_field() {
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ digitalocean_rules_no_family_field: File not found"
    return 1
  fi

  local family_count
  family_count=$(jq '[.firewall_rules.firewall_rule[] | select(has("family"))] | length' "$rules_file" 2>/dev/null)

  if [[ "$family_count" -eq 0 ]]; then
    echo "✅ digitalocean_rules_no_family_field: No 'family' field in rules (correct for DO format)"
    return 0
  else
    echo "❌ digitalocean_rules_no_family_field: Found $family_count rule(s) with unexpected 'family' field"
    return 1
  fi
}

# Both provider rule files must define the same logical set of ports and directions.
test_provider_rules_same_ports() {
  local do_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  local uc_file="$ROOT_DIR/config/upcloud_firewall_rules.json"

  if [[ ! -f "$do_file" || ! -f "$uc_file" ]]; then
    echo "❌ provider_rules_same_ports: One or both rule files missing"
    return 1
  fi

  local do_ports uc_ports
  do_ports=$(jq -r '[.firewall_rules.firewall_rule[] | .direction + ":" + .protocol + ":" + .destination_port_start] | unique | sort[]' "$do_file" 2>/dev/null)
  uc_ports=$(jq -r '[.firewall_rules.firewall_rule[] | .direction + ":" + .protocol + ":" + .destination_port_start] | unique | sort[]' "$uc_file" 2>/dev/null)

  if [[ "$do_ports" == "$uc_ports" ]]; then
    echo "✅ provider_rules_same_ports: Both provider rule files define identical port/direction sets"
    return 0
  else
    echo "❌ provider_rules_same_ports: Provider rule files differ in port/direction coverage"
    echo "   DO ports: $do_ports"
    echo "   UC ports: $uc_ports"
    return 1
  fi
}

# =============================================================================
# Tests: _build_digitalocean_firewall_payload uses DO-specific rules file
# =============================================================================

test_build_payload_uses_do_rules_file() {
  local do_rules="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$do_rules" ]]; then
    echo "❌ build_payload_uses_do_rules_file: digitalocean_firewall_rules.json not found"
    return 1
  fi

  local payload inbound outbound
  payload=$(_build_digitalocean_firewall_payload "$do_rules" 2>/dev/null)
  inbound=$(echo "$payload" | jq '.inbound_rules | length' 2>/dev/null)
  outbound=$(echo "$payload" | jq '.outbound_rules | length' 2>/dev/null)

  if [[ "$inbound" -gt 0 && "$outbound" -gt 0 ]]; then
    echo "✅ build_payload_uses_do_rules_file: Payload built from digitalocean_firewall_rules.json ($inbound inbound, $outbound outbound)"
    return 0
  else
    echo "❌ build_payload_uses_do_rules_file: Failed to build payload from digitalocean_firewall_rules.json"
    return 1
  fi
}

# Payload produced from DO rules file must not contain duplicate inbound rules.
test_build_payload_no_duplicate_inbound() {
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ build_payload_no_duplicate_inbound: digitalocean_firewall_rules.json not found"
    return 1
  fi

  local payload total unique
  payload=$(_build_digitalocean_firewall_payload "$rules_file" 2>/dev/null)
  total=$(echo "$payload" | jq '.inbound_rules | length' 2>/dev/null)
  unique=$(echo "$payload" | jq '.inbound_rules | unique_by(.protocol + ":" + .ports) | length' 2>/dev/null)

  if [[ "$total" == "$unique" ]]; then
    echo "✅ build_payload_no_duplicate_inbound: No duplicate inbound rules in payload ($total rules)"
    return 0
  else
    echo "❌ build_payload_no_duplicate_inbound: Payload contains duplicate inbound rules ($total total, $unique unique)"
    return 1
  fi
}

# Payload produced from DO rules file must not contain duplicate outbound rules.
test_build_payload_no_duplicate_outbound() {
  local rules_file="$ROOT_DIR/config/digitalocean_firewall_rules.json"
  if [[ ! -f "$rules_file" ]]; then
    echo "❌ build_payload_no_duplicate_outbound: digitalocean_firewall_rules.json not found"
    return 1
  fi

  local payload total unique
  payload=$(_build_digitalocean_firewall_payload "$rules_file" 2>/dev/null)
  total=$(echo "$payload" | jq '.outbound_rules | length' 2>/dev/null)
  unique=$(echo "$payload" | jq '.outbound_rules | unique_by(.protocol + ":" + .ports) | length' 2>/dev/null)

  if [[ "$total" == "$unique" ]]; then
    echo "✅ build_payload_no_duplicate_outbound: No duplicate outbound rules in payload ($total rules)"
    return 0
  else
    echo "❌ build_payload_no_duplicate_outbound: Payload contains duplicate outbound rules ($total total, $unique unique)"
    return 1
  fi
}



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
run_test test_digitalocean_rules_file_exists
run_test test_upcloud_rules_file_exists
run_test test_digitalocean_rules_file_is_valid_json
run_test test_upcloud_rules_file_is_valid_json
run_test test_digitalocean_rules_no_duplicates
run_test test_upcloud_rules_has_ipv4_and_ipv6
run_test test_digitalocean_rules_no_family_field
run_test test_provider_rules_same_ports
run_test test_build_payload_uses_do_rules_file
run_test test_build_payload_no_duplicate_inbound
run_test test_build_payload_no_duplicate_outbound

echo ""
if [[ $FAILED -eq 0 ]]; then
  echo "✅ All Digital Ocean integration tests passed"
  exit 0
else
  echo "❌ $FAILED test(s) failed"
  exit 1
fi
