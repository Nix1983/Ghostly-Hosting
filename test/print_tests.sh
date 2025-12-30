#!/bin/bash
# Unit tests for print.sh functions
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the print module
if ! source "$ROOT_DIR/lib/print.sh"; then
  echo "❌ Failed to source print.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test print.sh syntax
test_print_syntax() {
  echo ""
  echo "🔧 Running test_print_syntax"
  
  if bash -n "$ROOT_DIR/lib/print.sh" 2>/dev/null; then
    echo "✅ print.sh: Valid bash syntax"
    return 0
  else
    echo "❌ print.sh: Syntax errors detected"
    return 1
  fi
}

# Test that all print functions exist
test_print_functions_exist() {
  echo ""
  echo "🔧 Running test_print_functions_exist"
  
  local failed=0
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
    if declare -f "$func" >/dev/null; then
      echo "✅ print: $func function exists"
    else
      echo "❌ print: $func function missing"
      failed=1
    fi
  done
  
  return $failed
}

# Test print_select_prompt output
test_print_select_prompt_output() {
  echo ""
  echo "🔧 Running test_print_select_prompt_output"
  
  local output
  output=$(print_select_prompt 3)
  
  if [[ "$output" == "Please select [1–3, q]: " ]]; then
    echo "✅ print_select_prompt: Correct output for max=3"
  else
    echo "❌ print_select_prompt: Unexpected output: $output"
    return 1
  fi
  
  output=$(print_select_prompt 0)
  if [[ "$output" == "Please select [q]: " ]]; then
    echo "✅ print_select_prompt: Correct output for max=0"
  else
    echo "❌ print_select_prompt: Unexpected output for max=0: $output"
    return 1
  fi
  
  return 0
}

# Test print_line output length
test_print_line_output() {
  echo ""
  echo "🔧 Running test_print_line_output"
  
  local line
  line=$(print_line)
  local length=${#line}
  
  # Line should be consistent length (checking it's a reasonable length)
  if [[ $length -gt 100 ]]; then
    echo "✅ print_line: Produces line of length $length"
    return 0
  else
    echo "❌ print_line: Line too short: $length characters"
    return 1
  fi
}

# Test print_double_line output length
test_print_double_line_output() {
  echo ""
  echo "🔧 Running test_print_double_line_output"
  
  local line
  line=$(print_double_line)
  local length=${#line}
  
  # Double line should be same length as regular line
  if [[ $length -gt 100 ]]; then
    echo "✅ print_double_line: Produces line of length $length"
    return 0
  else
    echo "❌ print_double_line: Line too short: $length characters"
    return 1
  fi
}

# Run all tests
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Print Module Tests"
echo "════════════════════════════════════════════════════════════════"

FAILED_TESTS=0

test_print_syntax || ((FAILED_TESTS++))
test_print_functions_exist || ((FAILED_TESTS++))
test_print_select_prompt_output || ((FAILED_TESTS++))
test_print_line_output || ((FAILED_TESTS++))
test_print_double_line_output || ((FAILED_TESTS++))

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Print Tests Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $((5 - FAILED_TESTS))"
echo "Failed: $FAILED_TESTS"
echo ""

if [[ $FAILED_TESTS -eq 0 ]]; then
  echo "✅ All print tests passed!"
  exit 0
else
  echo "❌ $FAILED_TESTS print test(s) failed"
  exit 1
fi
