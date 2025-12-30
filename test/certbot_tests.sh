#!/bin/bash
# Unit tests for certbot.sh functions
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

if ! source "$ROOT_DIR/lib/certbot.sh"; then
  echo "❌ Failed to source certbot.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test certbot functions exist
test_certbot_functions_exist() {
  local functions=(
    "install_certbot"
    "remove_certbot"
    "delete_certbot_certificate"
    "run_certbot_workflow"
    "check_certbot_status"
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
test_certbot_private_functions_exist() {
  local functions=(
    "_check_required_tools"
    "_ensure_certbot_installed"
    "_stop_nginx_if_running"
    "_start_nginx_if_stopped"
    "_check_certificate_validity"
    "_obtain_or_verify_certificate"
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

# Test delete_certbot_certificate with empty HOSTNAME_FQDN
test_delete_certbot_certificate_empty_hostname() {
  local saved_hostname="${HOSTNAME_FQDN:-}"
  HOSTNAME_FQDN=""
  
  if ! delete_certbot_certificate 2>/dev/null; then
    echo "✅ delete_certbot_certificate: Empty HOSTNAME_FQDN properly rejected"
    HOSTNAME_FQDN="$saved_hostname"
    return 0
  else
    echo "❌ delete_certbot_certificate: Empty HOSTNAME_FQDN should be rejected"
    HOSTNAME_FQDN="$saved_hostname"
    return 1
  fi
}

# Test delete_certbot_certificate with unset HOSTNAME_FQDN
test_delete_certbot_certificate_unset_hostname() {
  if ! (unset HOSTNAME_FQDN; delete_certbot_certificate 2>/dev/null); then
    echo "✅ delete_certbot_certificate: Unset HOSTNAME_FQDN properly handled"
    return 0
  else
    echo "❌ delete_certbot_certificate: Unset HOSTNAME_FQDN should be rejected"
    return 1
  fi
}

# Test certbot.sh has valid syntax
test_certbot_syntax() {
  if bash -n "$ROOT_DIR/lib/certbot.sh" 2>/dev/null; then
    echo "✅ certbot.sh has valid syntax"
    return 0
  else
    echo "❌ certbot.sh has syntax errors"
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

run_test test_certbot_syntax || ((FAILED++))
run_test test_certbot_functions_exist || ((FAILED++))
run_test test_certbot_private_functions_exist || ((FAILED++))
run_test test_delete_certbot_certificate_empty_hostname || ((FAILED++))
run_test test_delete_certbot_certificate_unset_hostname || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All Certbot tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
