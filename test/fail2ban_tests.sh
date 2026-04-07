#!/bin/bash
# Unit tests for fail2ban.sh – pure-logic tests that do not require a running
# fail2ban daemon.  Tests that depend on systemctl / fail2ban-client are
# skipped automatically when those tools are unavailable.
# Note: We do NOT use set -e so that test failures don't abort the suite.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "Fail2Ban Tests"
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

pushd "$ROOT_DIR" >/dev/null || exit 1
if ! source "./lib/fail2ban.sh"; then
  echo "❌ Failed to source fail2ban.sh"
  popd >/dev/null || true
  exit 1
fi
popd >/dev/null || exit 1

# Override CONFIG_FILE AFTER sourcing so fail2ban.sh's default doesn't win
CONFIG_FILE=$(mktemp)
export CONFIG_FILE

echo "✅ SOURCES LOADED"
echo ""

# ---------------------------------------------------------------------------
# Test 1: fail2ban.sh exists and has valid syntax
# ---------------------------------------------------------------------------
test_fail2ban_syntax() {
  echo "🔧 Running test_fail2ban_syntax"
  if bash -n "$ROOT_DIR/lib/fail2ban.sh" 2>/dev/null; then
    echo "✅ fail2ban.sh has valid syntax"
    return 0
  else
    echo "❌ fail2ban.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/fail2ban.sh"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Test 2: install_fail2ban function exists (catches the intsall_ typo)
# ---------------------------------------------------------------------------
test_install_fail2ban_function_exists() {
  echo "🔧 Running test_install_fail2ban_function_exists"
  if declare -f install_fail2ban >/dev/null 2>&1; then
    echo "✅ install_fail2ban is defined"
    return 0
  else
    echo "❌ install_fail2ban is NOT defined (typo intsall_fail2ban still present?)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Test 3: intsall_fail2ban (typo) must NOT exist
# ---------------------------------------------------------------------------
test_typo_function_absent() {
  echo "🔧 Running test_typo_function_absent"
  if declare -f intsall_fail2ban >/dev/null 2>&1; then
    echo "❌ intsall_fail2ban (typo) is still defined – fix the typo"
    return 1
  else
    echo "✅ intsall_fail2ban (typo) is absent"
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Test 4: load_f2b_whitelist_entries reads ignoreip entries from config
# ---------------------------------------------------------------------------
test_load_f2b_whitelist_entries() {
  echo "🔧 Running test_load_f2b_whitelist_entries"

  cat > "$CONFIG_FILE" <<'EOF'
[DEFAULT]
ignoreip = 127.0.0.1

[sshd]
ignoreip = 192.168.1.10 10.0.0.5
EOF

  declare -A wl_map
  if ! load_f2b_whitelist_entries wl_map; then
    echo "❌ load_f2b_whitelist_entries returned false for non-empty config"
    return 1
  fi

  if [[ "${#wl_map[@]}" -ne 3 ]]; then
    echo "❌ Expected 3 whitelist entries, got ${#wl_map[@]}"
    return 1
  fi

  local found_default=false found_sshd=false
  for key in "${!wl_map[@]}"; do
    entry="${wl_map[$key]}"
    [[ "$entry" == "127.0.0.1|DEFAULT" ]]    && found_default=true
    [[ "$entry" == "192.168.1.10|sshd" ]]    && found_sshd=true
  done

  if ! $found_default; then
    echo "❌ 127.0.0.1|DEFAULT not found in whitelist map"
    return 1
  fi
  if ! $found_sshd; then
    echo "❌ 192.168.1.10|sshd not found in whitelist map"
    return 1
  fi

  echo "✅ load_f2b_whitelist_entries parsed entries correctly"
  return 0
}

# ---------------------------------------------------------------------------
# Test 5: load_f2b_whitelist_entries returns false for empty config
# ---------------------------------------------------------------------------
test_load_f2b_whitelist_entries_empty() {
  echo "🔧 Running test_load_f2b_whitelist_entries_empty"

  cat > "$CONFIG_FILE" <<'EOF'
[DEFAULT]
bantime = -1
EOF

  declare -A wl_map
  if load_f2b_whitelist_entries wl_map; then
    echo "❌ Expected false return for config with no ignoreip entries"
    return 1
  fi

  echo "✅ load_f2b_whitelist_entries correctly returned false for empty config"
  return 0
}

# ---------------------------------------------------------------------------
# Test 6: remove_ip_from_whitelist_by_ip removes the IP from config
# ---------------------------------------------------------------------------
test_remove_ip_from_whitelist_by_ip() {
  echo "🔧 Running test_remove_ip_from_whitelist_by_ip"

  cat > "$CONFIG_FILE" <<'EOF'
[sshd]
ignoreip = 1.2.3.4 5.6.7.8
EOF

  remove_ip_from_whitelist_by_ip "1.2.3.4" "sshd"

  if grep -q "1.2.3.4" "$CONFIG_FILE"; then
    echo "❌ IP 1.2.3.4 still present after removal"
    return 1
  fi

  if ! grep -q "5.6.7.8" "$CONFIG_FILE"; then
    echo "❌ IP 5.6.7.8 was incorrectly removed"
    return 1
  fi

  echo "✅ remove_ip_from_whitelist_by_ip removed only the target IP"
  return 0
}

# ---------------------------------------------------------------------------
# Test 7: add_ip_to_whitelist writes ignoreip – not bannedip
# ---------------------------------------------------------------------------
test_whitelist_uses_ignoreip_not_bannedip() {
  echo "🔧 Running test_whitelist_uses_ignoreip_not_bannedip"

  # Verify no trace of "bannedip" remains in fail2ban.sh after the rewrite
  if grep -v "^[[:space:]]*#" "$ROOT_DIR/lib/fail2ban.sh" | grep -q "bannedip"; then
    echo "❌ 'bannedip' key still present in fail2ban.sh – must be fully removed"
    return 1
  fi

  echo "✅ fail2ban.sh no longer contains the invalid 'bannedip' key"
  return 0
}

# ---------------------------------------------------------------------------
# Test 8: blocklist functions use fail2ban-client, not config file writes
# ---------------------------------------------------------------------------
test_blocklist_uses_fail2ban_client() {
  echo "🔧 Running test_blocklist_uses_fail2ban_client"

  # add_ip_to_blocklist should call fail2ban-client, not write to CONFIG_FILE
  if grep -A 50 "^add_ip_to_blocklist()" "$ROOT_DIR/lib/fail2ban.sh" | grep -q "tee -a\|sed -i.*bannedip"; then
    echo "❌ add_ip_to_blocklist still writes bannedip to config file"
    return 1
  fi

  if ! grep -A 50 "^add_ip_to_blocklist()" "$ROOT_DIR/lib/fail2ban.sh" | grep -q "fail2ban-client"; then
    echo "❌ add_ip_to_blocklist does not use fail2ban-client"
    return 1
  fi

  echo "✅ add_ip_to_blocklist uses fail2ban-client"
  return 0
}

# ---------------------------------------------------------------------------
# Test 9: no eval in fail2ban.sh (replaced by declare -n)
# ---------------------------------------------------------------------------
test_no_eval_in_fail2ban() {
  echo "🔧 Running test_no_eval_in_fail2ban"

  if grep -nE '^\s+eval\s' "$ROOT_DIR/lib/fail2ban.sh" | grep -v "^#"; then
    echo "❌ Found eval usage in fail2ban.sh – should be replaced with declare -n"
    return 1
  fi

  echo "✅ No eval statements found in fail2ban.sh"
  return 0
}

# ---------------------------------------------------------------------------
# Test 10: no sudo in fail2ban.sh (script runs as root)
# ---------------------------------------------------------------------------
test_no_sudo_in_fail2ban() {
  echo "🔧 Running test_no_sudo_in_fail2ban"

  if grep -nE '\bsudo\b' "$ROOT_DIR/lib/fail2ban.sh" | grep -v "^#"; then
    echo "❌ Found sudo usage in fail2ban.sh – unnecessary when running as root"
    return 1
  fi

  echo "✅ No sudo calls found in fail2ban.sh"
  return 0
}

# ---------------------------------------------------------------------------
# Test 11: get_whitelist_entry_list returns sorted list
# ---------------------------------------------------------------------------
test_get_whitelist_entry_list() {
  echo "🔧 Running test_get_whitelist_entry_list"

  cat > "$CONFIG_FILE" <<'EOF'
[DEFAULT]
ignoreip = 10.0.0.1

[sshd]
ignoreip = 10.0.0.2
EOF

  declare -a list
  if ! get_whitelist_entry_list list; then
    echo "❌ get_whitelist_entry_list returned false for non-empty config"
    return 1
  fi

  if [[ "${#list[@]}" -ne 2 ]]; then
    echo "❌ Expected 2 entries, got ${#list[@]}"
    return 1
  fi

  echo "✅ get_whitelist_entry_list returned correct number of entries"
  return 0
}

# ---------------------------------------------------------------------------
# Test 12: configure_f2b writes valid sections to CONFIG_FILE
# ---------------------------------------------------------------------------
test_configure_f2b_writes_config() {
  echo "🔧 Running test_configure_f2b_writes_config"

  # Stub out systemctl restart so it doesn't fail in CI
  systemctl() { return 0; }
  export -f systemctl

  configure_f2b

  unset -f systemctl

  if ! grep -q "^\[DEFAULT\]" "$CONFIG_FILE"; then
    echo "❌ [DEFAULT] section missing"
    return 1
  fi

  if ! grep -q "bantime = -1" "$CONFIG_FILE"; then
    echo "❌ bantime = -1 missing"
    return 1
  fi

  if ! grep -q "^\[sshd\]" "$CONFIG_FILE"; then
    echo "❌ [sshd] section missing"
    return 1
  fi

  if ! grep -q "^\[nginx-http-auth\]" "$CONFIG_FILE"; then
    echo "❌ [nginx-http-auth] section missing"
    return 1
  fi

  if grep -q "bannedip" "$CONFIG_FILE"; then
    echo "❌ Invalid 'bannedip' key written by configure_f2b"
    return 1
  fi

  echo "✅ configure_f2b writes correct jail.local configuration"
  return 0
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
TESTS=(
  "test_fail2ban_syntax"
  "test_install_fail2ban_function_exists"
  "test_typo_function_absent"
  "test_load_f2b_whitelist_entries"
  "test_load_f2b_whitelist_entries_empty"
  "test_remove_ip_from_whitelist_by_ip"
  "test_whitelist_uses_ignoreip_not_bannedip"
  "test_blocklist_uses_fail2ban_client"
  "test_no_eval_in_fail2ban"
  "test_no_sudo_in_fail2ban"
  "test_get_whitelist_entry_list"
  "test_configure_f2b_writes_config"
)

FAILED=0
PASSED=0

set +e

for test_fn in "${TESTS[@]}"; do
  echo ""
  if $test_fn; then
    ((PASSED++))
  else
    ((FAILED++))
  fi
done

set -e

# Cleanup temp config
rm -f "$CONFIG_FILE"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Fail2Ban Tests Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  exit 1
else
  echo "✅ All fail2ban tests passed!"
  exit 0
fi
