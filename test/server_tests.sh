#!/bin/bash
# Unit tests for server.sh functions
# Note: We don't use set -e because we want to continue running tests even if some fail
# shellcheck disable=SC1091,SC2317

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "================================================================"
echo "Server Setup Tests"
echo "================================================================"

# Source required libraries
if ! source "$ROOT_DIR/lib/const.sh"; then
  echo "FAIL Failed to source const.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/common.sh"; then
  echo "FAIL Failed to source common.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/print.sh"; then
  echo "FAIL Failed to source print.sh"
  exit 1
fi

pushd "$ROOT_DIR" >/dev/null || exit 1
if ! source "$ROOT_DIR/lib/server.sh"; then
  popd >/dev/null || true
  echo "FAIL Failed to source server.sh in test shell"
  exit 1
fi
popd >/dev/null || true

echo "PASS SOURCES LOADED"
echo ""

# Test 1: Check if server.sh exists and is readable
test_server_script_exists() {
  echo "Running test_server_script_exists"

  if [[ -f "$ROOT_DIR/lib/server.sh" ]]; then
    echo "PASS server.sh exists"
  else
    echo "FAIL server.sh does not exist"
    return 1
  fi

  if [[ -r "$ROOT_DIR/lib/server.sh" ]]; then
    echo "PASS server.sh is readable"
  else
    echo "FAIL server.sh is not readable"
    return 1
  fi

  return 0
}

# Test 2: Check if server.sh can be sourced
test_server_script_sources() {
  echo "Running test_server_script_sources"

  if timeout 10 bash -c "cd '$ROOT_DIR' && source lib/const.sh && source lib/common.sh && source lib/print.sh && source lib/server.sh && echo success" 2>/dev/null | grep -q "success"; then
    echo "PASS server.sh sources successfully with dependencies"
    return 0
  else
    echo "FAIL server.sh failed to source"
    return 1
  fi
}

# Test 3: Check nginx module exists
test_nginx_module_exists() {
  echo "Running test_nginx_module_exists"

  if [[ -f "$ROOT_DIR/lib/nginx.sh" ]]; then
    echo "PASS nginx.sh module exists"
    return 0
  else
    echo "FAIL nginx.sh module does not exist"
    return 1
  fi
}

# Test 4: Check dotnet module exists
test_dotnet_module_exists() {
  echo "Running test_dotnet_module_exists"

  if [[ -f "$ROOT_DIR/lib/dotnet.sh" ]]; then
    echo "PASS dotnet.sh module exists"
    return 0
  else
    echo "FAIL dotnet.sh module does not exist"
    return 1
  fi
}

# Test 5: Check fail2ban module exists
test_fail2ban_module_exists() {
  echo "Running test_fail2ban_module_exists"

  if [[ -f "$ROOT_DIR/lib/fail2ban.sh" ]]; then
    echo "PASS fail2ban.sh module exists"
    return 0
  else
    echo "FAIL fail2ban.sh module does not exist"
    return 1
  fi
}

# Test 6: Check timezone module exists
test_timezone_module_exists() {
  echo "Running test_timezone_module_exists"

  if [[ -f "$ROOT_DIR/lib/timezone.sh" ]]; then
    echo "PASS timezone.sh module exists"
    return 0
  else
    echo "FAIL timezone.sh module does not exist"
    return 1
  fi
}

# Test 7: Validate server.sh syntax
test_server_script_syntax() {
  echo "Running test_server_script_syntax"

  if bash -n "$ROOT_DIR/lib/server.sh" 2>/dev/null; then
    echo "PASS server.sh has valid syntax"
    return 0
  else
    echo "FAIL server.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/server.sh"
    return 1
  fi
}

# Test 8: Validate all server-related module syntax
test_server_modules_syntax() {
  echo "Running test_server_modules_syntax"

  local modules=(
    "nginx.sh"
    "dotnet.sh"
    "fail2ban.sh"
    "timezone.sh"
    "certbot.sh"
  )

  local module
  for module in "${modules[@]}"; do
    if bash -n "$ROOT_DIR/lib/$module" 2>/dev/null; then
      echo "PASS $module has valid syntax"
    else
      echo "FAIL $module has syntax errors"
      return 1
    fi
  done

  return 0
}

# Test 9: Nginx family package variants should count as installed
test_find_installed_package_name_from_status_lines_supports_nginx_variants() {
  echo "Running test_find_installed_package_name_from_status_lines_supports_nginx_variants"

  local status_lines
  status_lines=$'nginx-common\tinstall ok installed\nnginx-core\tinstall ok installed\n'

  local result
  result=$(find_installed_package_name_from_status_lines "nginx" "$status_lines")

  if [[ "$result" == "nginx-common" || "$result" == "nginx-core" ]]; then
    echo "PASS nginx family package variants are detected as installed"
    return 0
  fi

  echo "FAIL Expected nginx family package to be detected, got: '$result'"
  return 1
}

# Test 10: Status binary lookup should handle binaries outside PATH
test_resolve_status_binary_path_supports_known_fallbacks() {
  echo "Running test_resolve_status_binary_path_supports_known_fallbacks"

  local fake_bin="/tmp/ghostly-nginx-status-bin-$$"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin"
  chmod +x "$fake_bin"

  local result
  result=$(resolve_status_binary_path "definitely-missing-binary" "$fake_bin")

  rm -f "$fake_bin"

  if [[ "$result" == "$fake_bin" ]]; then
    echo "PASS resolve_status_binary_path falls back to known executable paths"
    return 0
  fi

  echo "FAIL Expected fallback binary path '$fake_bin', got: '$result'"
  return 1
}

# Test 11: Pending update detection should work for alternative package names
test_pending_updates_include_package_supports_variants() {
  echo "Running test_pending_updates_include_package_supports_variants"

  local pending_updates
  pending_updates=$'Listing...\nnginx-core/noble-updates 1.24.0 amd64 [upgradable from: 1.22.1]\n'

  if pending_updates_include_package "$pending_updates" "nginx-core" "nginx"; then
    echo "PASS pending_updates_include_package matches nginx variant packages"
    return 0
  fi

  echo "FAIL Expected nginx-core pending update to be detected"
  return 1
}

# Test 12: Init check should accept nginx family packages as initialized
test_is_server_component_available_detects_nginx_from_family_package() {
  echo "Running test_is_server_component_available_detects_nginx_from_family_package"

  if (
    get_installed_status_package_name() {
      if [[ "$1" == "nginx" ]]; then
        echo "nginx-common"
        return 0
      fi
      return 1
    }
    resolve_status_binary_path() { return 1; }
    systemd_unit_exists() { return 1; }
    is_server_component_available nginx
  ); then
    echo "PASS init check accepts nginx family package variants"
    return 0
  fi

  echo "FAIL Expected nginx family package to satisfy init check"
  return 1
}

# Test 13: install_fail2ban must be defined (not the old typo intsall_fail2ban)
test_install_fail2ban_function_name() {
  echo "Running test_install_fail2ban_function_name"

  if declare -f install_fail2ban >/dev/null 2>&1; then
    echo "PASS install_fail2ban is correctly defined in fail2ban.sh"
  else
    echo "FAIL install_fail2ban is NOT defined – the typo intsall_fail2ban may still be present"
    return 1
  fi

  if declare -f intsall_fail2ban >/dev/null 2>&1; then
    echo "FAIL intsall_fail2ban (typo) is still defined in fail2ban.sh"
    return 1
  else
    echo "PASS intsall_fail2ban (typo) is absent"
  fi

  return 0
}

# Test 14: init_server calls install_fail2ban (not the old typo)
test_init_server_calls_correct_fail2ban_function() {
  echo "Running test_init_server_calls_correct_fail2ban_function"

  if grep -q "install_fail2ban" "$ROOT_DIR/lib/server.sh"; then
    echo "PASS server.sh calls install_fail2ban (correct)"
  else
    echo "FAIL server.sh does not call install_fail2ban"
    return 1
  fi

  if grep -q "intsall_fail2ban" "$ROOT_DIR/lib/server.sh"; then
    echo "FAIL server.sh still calls intsall_fail2ban (typo)"
    return 1
  else
    echo "PASS server.sh does not contain intsall_fail2ban (typo)"
  fi

  return 0
}

TESTS=(
  "test_server_script_exists"
  "test_server_script_sources"
  "test_nginx_module_exists"
  "test_dotnet_module_exists"
  "test_fail2ban_module_exists"
  "test_timezone_module_exists"
  "test_server_script_syntax"
  "test_server_modules_syntax"
  "test_find_installed_package_name_from_status_lines_supports_nginx_variants"
  "test_resolve_status_binary_path_supports_known_fallbacks"
  "test_pending_updates_include_package_supports_variants"
  "test_is_server_component_available_detects_nginx_from_family_package"
  "test_install_fail2ban_function_name"
  "test_init_server_calls_correct_fail2ban_function"
)

FAILED=0
PASSED=0

set +e

for test in "${TESTS[@]}"; do
  echo ""
  if $test; then
    ((PASSED++))
  else
    ((FAILED++))
  fi
done

set -e

echo ""
echo "================================================================"
echo "Server Tests Summary"
echo "================================================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  exit 1
else
  echo "PASS All server tests passed!"
  exit 0
fi
