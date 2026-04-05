#!/bin/bash
# Unit tests for lib/firewall_provider.sh (provider abstraction layer)
# shellcheck disable=SC1091,SC2317

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "================================================================"
echo "Provider Abstraction Tests"
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

# Source provider modules
pushd "$ROOT_DIR" >/dev/null || exit 1

if ! source "$ROOT_DIR/lib/upcloud.sh"; then
  popd >/dev/null || true
  echo "❌ Failed to source upcloud.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/digitalocean.sh"; then
  popd >/dev/null || true
  echo "❌ Failed to source digitalocean.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/firewall_provider.sh"; then
  popd >/dev/null || true
  echo "❌ Failed to source firewall_provider.sh"
  exit 1
fi

popd >/dev/null || true

echo "✅ SOURCES LOADED"
echo ""

# =============================================================================
# Tests: get_provider_display_name
# =============================================================================

test_provider_display_name_upcloud() {
  CLOUD_PROVIDER="upcloud"
  local result
  result=$(get_provider_display_name)
  if [[ "$result" == "UpCloud" ]]; then
    echo "✅ get_provider_display_name: upcloud => 'UpCloud'"
    return 0
  else
    echo "❌ get_provider_display_name: upcloud => expected 'UpCloud', got '$result'"
    return 1
  fi
}

test_provider_display_name_digitalocean() {
  CLOUD_PROVIDER="digitalocean"
  local result
  result=$(get_provider_display_name)
  if [[ "$result" == "Digital Ocean" ]]; then
    echo "✅ get_provider_display_name: digitalocean => 'Digital Ocean'"
    return 0
  else
    echo "❌ get_provider_display_name: digitalocean => expected 'Digital Ocean', got '$result'"
    return 1
  fi
}

test_provider_display_name_other() {
  CLOUD_PROVIDER="other"
  local result
  result=$(get_provider_display_name)
  if [[ "$result" == "" ]]; then
    echo "✅ get_provider_display_name: other => ''"
    return 0
  else
    echo "❌ get_provider_display_name: other => expected '', got '$result'"
    return 1
  fi
}

test_provider_display_name_unknown() {
  CLOUD_PROVIDER="unknown_provider"
  local result
  result=$(get_provider_display_name)
  if [[ "$result" == "" ]]; then
    echo "✅ get_provider_display_name: unknown_provider => ''"
    return 0
  else
    echo "❌ get_provider_display_name: unknown_provider => expected '', got '$result'"
    return 1
  fi
}

test_provider_display_name_empty() {
  CLOUD_PROVIDER=""
  local result
  result=$(get_provider_display_name)
  if [[ "$result" == "" ]]; then
    echo "✅ get_provider_display_name: empty CLOUD_PROVIDER => ''"
    return 0
  else
    echo "❌ get_provider_display_name: empty CLOUD_PROVIDER => expected '', got '$result'"
    return 1
  fi
}

# =============================================================================
# Tests: apply_firewall_rules with 'other' provider
# =============================================================================

test_apply_firewall_rules_other_returns_zero() {
  CLOUD_PROVIDER="other"
  local output exit_code
  output=$(apply_firewall_rules 2>&1)
  exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    echo "✅ apply_firewall_rules: other provider => returns 0"
    return 0
  else
    echo "❌ apply_firewall_rules: other provider => expected exit 0, got $exit_code"
    return 1
  fi
}

test_apply_firewall_rules_other_shows_message() {
  CLOUD_PROVIDER="other"
  local output
  output=$(apply_firewall_rules 2>&1)
  if echo "$output" | grep -q "manually"; then
    echo "✅ apply_firewall_rules: other provider => shows manual firewall message"
    return 0
  else
    echo "❌ apply_firewall_rules: other provider => expected manual config message, got: $output"
    return 1
  fi
}

test_apply_firewall_rules_unknown_provider_returns_zero() {
  CLOUD_PROVIDER="nonexistent_provider"
  local exit_code
  apply_firewall_rules 2>/dev/null
  exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    echo "✅ apply_firewall_rules: unknown provider => returns 0"
    return 0
  else
    echo "❌ apply_firewall_rules: unknown provider => expected exit 0, got $exit_code"
    return 1
  fi
}

# =============================================================================
# Tests: delete_all_firewall_rules with 'other' provider
# =============================================================================

test_delete_all_firewall_rules_other_returns_zero() {
  CLOUD_PROVIDER="other"
  local exit_code
  delete_all_firewall_rules 2>/dev/null
  exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    echo "✅ delete_all_firewall_rules: other provider => returns 0"
    return 0
  else
    echo "❌ delete_all_firewall_rules: other provider => expected exit 0, got $exit_code"
    return 1
  fi
}

test_delete_all_firewall_rules_unknown_returns_zero() {
  CLOUD_PROVIDER="nonexistent_provider"
  local exit_code
  delete_all_firewall_rules 2>/dev/null
  exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    echo "✅ delete_all_firewall_rules: unknown provider => returns 0"
    return 0
  else
    echo "❌ delete_all_firewall_rules: unknown provider => expected exit 0, got $exit_code"
    return 1
  fi
}

# =============================================================================
# Tests: show_provider_menu with 'other' provider (should be a no-op)
# =============================================================================

test_show_provider_menu_other_returns_zero() {
  CLOUD_PROVIDER="other"
  local exit_code
  show_provider_menu 2>/dev/null
  exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    echo "✅ show_provider_menu: other provider => returns 0"
    return 0
  else
    echo "❌ show_provider_menu: other provider => expected exit 0, got $exit_code"
    return 1
  fi
}

# =============================================================================
# Tests: firewall_provider.sh file exists and is sourced
# =============================================================================

test_firewall_provider_file_exists() {
  if [[ -f "$ROOT_DIR/lib/firewall_provider.sh" ]]; then
    echo "✅ firewall_provider.sh: File exists"
    return 0
  else
    echo "❌ firewall_provider.sh: File not found"
    return 1
  fi
}

test_functions_are_defined() {
  local all_ok=true
  for fn in get_provider_display_name apply_firewall_rules delete_all_firewall_rules show_provider_menu; do
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
# Run all tests
# =============================================================================

FAILED=0

run_test() {
  local test_fn="$1"
  if ! $test_fn; then
    FAILED=$((FAILED + 1))
  fi
}

run_test test_provider_display_name_upcloud
run_test test_provider_display_name_digitalocean
run_test test_provider_display_name_other
run_test test_provider_display_name_unknown
run_test test_provider_display_name_empty
run_test test_apply_firewall_rules_other_returns_zero
run_test test_apply_firewall_rules_other_shows_message
run_test test_apply_firewall_rules_unknown_provider_returns_zero
run_test test_delete_all_firewall_rules_other_returns_zero
run_test test_delete_all_firewall_rules_unknown_returns_zero
run_test test_show_provider_menu_other_returns_zero
run_test test_firewall_provider_file_exists
run_test test_functions_are_defined

echo ""
if [[ $FAILED -eq 0 ]]; then
  echo "✅ All provider abstraction tests passed"
  exit 0
else
  echo "❌ $FAILED test(s) failed"
  exit 1
fi
