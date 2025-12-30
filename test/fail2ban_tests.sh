#!/bin/bash
# Unit tests for fail2ban.sh functions
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

if ! source "$ROOT_DIR/lib/fail2ban.sh"; then
  echo "❌ Failed to source fail2ban.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test fail2ban functions exist
test_fail2ban_functions_exist() {
  local functions=(
    "intsall_fail2ban"
    "remove_fail2ban"
    "configure_f2b"
    "show_f2b_status"
    "show_f2b_explanation"
    "show_f2b_menu"
    "add_ip_to_whitelist"
    "remove_ip_from_whitelist"
    "add_ip_to_blocklist"
    "remove_ip_from_blocklist"
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

# Test private helper functions exist
test_fail2ban_private_functions_exist() {
  local functions=(
    "load_f2b_whitelist_entries"
    "load_f2b_blocklist_entries"
    "print_f2b_ip_entries"
    "remove_ip_from_whitelist_by_ip"
    "remove_ip_from_blocklist_by_ip"
    "get_whitelist_entry_list"
    "get_blocklist_entry_list"
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

# Test CONFIG_FILE variable is set
test_config_file_variable() {
  if [[ -n "${CONFIG_FILE:-}" ]]; then
    if [[ "$CONFIG_FILE" == "/etc/fail2ban/jail.local" ]]; then
      echo "✅ CONFIG_FILE variable correctly set to: $CONFIG_FILE"
      return 0
    else
      echo "❌ CONFIG_FILE has unexpected value: $CONFIG_FILE"
      return 1
    fi
  else
    echo "❌ CONFIG_FILE variable not set"
    return 1
  fi
}

# Test fail2ban.sh has valid syntax
test_fail2ban_syntax() {
  if bash -n "$ROOT_DIR/lib/fail2ban.sh" 2>/dev/null; then
    echo "✅ fail2ban.sh has valid syntax"
    return 0
  else
    echo "❌ fail2ban.sh has syntax errors"
    return 1
  fi
}

# Test load_f2b_whitelist_entries with non-existent file
test_load_whitelist_entries_nonexistent_file() {
  # Temporarily backup CONFIG_FILE
  local saved_config="$CONFIG_FILE"
  CONFIG_FILE="/tmp/nonexistent_fail2ban_config_$$"
  
  declare -A test_map
  if ! load_f2b_whitelist_entries test_map 2>/dev/null; then
    echo "✅ load_f2b_whitelist_entries: Non-existent file properly handled"
    CONFIG_FILE="$saved_config"
    return 0
  else
    echo "❌ load_f2b_whitelist_entries: Should fail with non-existent file"
    CONFIG_FILE="$saved_config"
    return 1
  fi
}

# Test load_f2b_blocklist_entries with non-existent file
test_load_blocklist_entries_nonexistent_file() {
  # Temporarily backup CONFIG_FILE
  local saved_config="$CONFIG_FILE"
  CONFIG_FILE="/tmp/nonexistent_fail2ban_config_$$"
  
  declare -A test_map
  if ! load_f2b_blocklist_entries test_map 2>/dev/null; then
    echo "✅ load_f2b_blocklist_entries: Non-existent file properly handled"
    CONFIG_FILE="$saved_config"
    return 0
  else
    echo "❌ load_f2b_blocklist_entries: Should fail with non-existent file"
    CONFIG_FILE="$saved_config"
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

run_test test_fail2ban_syntax || ((FAILED++))
run_test test_config_file_variable || ((FAILED++))
run_test test_fail2ban_functions_exist || ((FAILED++))
run_test test_fail2ban_private_functions_exist || ((FAILED++))
run_test test_load_whitelist_entries_nonexistent_file || ((FAILED++))
run_test test_load_blocklist_entries_nonexistent_file || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All Fail2Ban tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
