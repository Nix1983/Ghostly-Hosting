#!/bin/bash
# Unit tests for print.sh functions
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required files
if ! source "$ROOT_DIR/lib/print.sh"; then
  echo "❌ Failed to source print.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test print functions exist
test_print_functions_exist() {
  local functions=(
    "print_cancel"
    "print_press_any_key"
    "print_invalid_selection"
    "print_back_to_menu"
    "print_select_prompt"
    "print_line"
    "print_double_line"
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

# Test print_select_prompt with zero
test_print_select_prompt_zero() {
  local output
  output=$(print_select_prompt 0)
  if [[ "$output" == *"[q]"* ]]; then
    echo "✅ print_select_prompt: Zero max handled correctly"
    return 0
  else
    echo "❌ print_select_prompt: Zero max not handled correctly"
    return 1
  fi
}

# Test print_select_prompt with positive number
test_print_select_prompt_positive() {
  local output
  output=$(print_select_prompt 5)
  if [[ "$output" == *"[1–5, q]"* ]]; then
    echo "✅ print_select_prompt: Positive number handled correctly"
    return 0
  else
    echo "❌ print_select_prompt: Output was: $output"
    return 1
  fi
}

# Test print_line produces output
test_print_line_output() {
  local output
  output=$(print_line)
  if [[ -n "$output" && "$output" == *"──"* ]]; then
    echo "✅ print_line: Produces line output"
    return 0
  else
    echo "❌ print_line: No output produced"
    return 1
  fi
}

# Test print_double_line produces output
test_print_double_line_output() {
  local output
  output=$(print_double_line)
  if [[ -n "$output" && "$output" == *"══"* ]]; then
    echo "✅ print_double_line: Produces double line output"
    return 0
  else
    echo "❌ print_double_line: No output produced"
    return 1
  fi
}

# Test print_back_to_menu produces output
test_print_back_to_menu_output() {
  local output
  output=$(print_back_to_menu)
  if [[ -n "$output" && "$output" == *"Back"* ]]; then
    echo "✅ print_back_to_menu: Produces menu text"
    return 0
  else
    echo "❌ print_back_to_menu: No output produced"
    return 1
  fi
}

# Test print.sh has valid syntax
test_print_syntax() {
  if bash -n "$ROOT_DIR/lib/print.sh" 2>/dev/null; then
    echo "✅ print.sh has valid syntax"
    return 0
  else
    echo "❌ print.sh has syntax errors"
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

run_test test_print_syntax || ((FAILED++))
run_test test_print_functions_exist || ((FAILED++))
run_test test_print_select_prompt_zero || ((FAILED++))
run_test test_print_select_prompt_positive || ((FAILED++))
run_test test_print_line_output || ((FAILED++))
run_test test_print_double_line_output || ((FAILED++))
run_test test_print_back_to_menu_output || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All print tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
