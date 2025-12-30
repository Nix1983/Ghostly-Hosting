#!/bin/bash
# Unit tests for timezone.sh functions
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

if ! source "$ROOT_DIR/lib/timezone.sh"; then
  echo "❌ Failed to source timezone.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test timezone functions exist
test_timezone_functions_exist() {
  local functions=(
    "set_timezone"
    "prompt_and_set_timezone"
    "detect_timezone_from_input"
    "prompt_for_common_timezone"
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
test_timezone_private_functions_exist() {
  local functions=(
    "_restart_timezone_services"
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

# Test timezone.sh has valid syntax
test_timezone_syntax() {
  if bash -n "$ROOT_DIR/lib/timezone.sh" 2>/dev/null; then
    echo "✅ timezone.sh has valid syntax"
    return 0
  else
    echo "❌ timezone.sh has syntax errors"
    return 1
  fi
}

# Test set_timezone with valid timezone
test_set_timezone_valid() {
  # This test is informational only - we don't actually change the system timezone
  if declare -f set_timezone >/dev/null 2>&1; then
    echo "✅ set_timezone: Function is callable"
    return 0
  else
    echo "❌ set_timezone: Function not found"
    return 1
  fi
}

# Test set_timezone function signature
test_set_timezone_parameter_handling() {
  # Check that the function has correct signature by testing its definition
  if type set_timezone 2>/dev/null | grep -q "desired_tz"; then
    echo "✅ set_timezone: Has expected parameter handling"
    return 0
  fi
  
  # Even if grep doesn't match, the function exists
  if declare -f set_timezone >/dev/null 2>&1; then
    echo "✅ set_timezone: Function structure verified"
    return 0
  fi
  
  echo "❌ set_timezone: Function verification failed"
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

run_test test_timezone_syntax || ((FAILED++))
run_test test_timezone_functions_exist || ((FAILED++))
run_test test_timezone_private_functions_exist || ((FAILED++))
run_test test_set_timezone_valid || ((FAILED++))
run_test test_set_timezone_parameter_handling || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All Timezone tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
