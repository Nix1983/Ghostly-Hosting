#!/bin/bash
# Run all test suites
# Note: We don't use set -e because we want to continue running tests even if some fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "Running All Test Suites"
echo "════════════════════════════════════════════════════════════════"
echo ""

TESTS=(
  "common_tests.sh"
  "common_error_logging_tests.sh"
  "upcloud_tests.sh"
  "github_tests.sh"
  "log_tests.sh"
  "meta_data_tests.sh"
)

FAILED_TESTS=()
PASSED_TESTS=()

for test_file in "${TESTS[@]}"; do
  test_path="$SCRIPT_DIR/$test_file"
  
  if [[ ! -f "$test_path" ]]; then
    echo "⚠️  Test file not found: $test_file"
    continue
  fi
  
  echo "Running: $test_file"
  echo "────────────────────────────────────────────────────────────────"
  
  if bash "$test_path"; then
    PASSED_TESTS+=("$test_file")
    echo "✅ $test_file PASSED"
  else
    FAILED_TESTS+=("$test_file")
    echo "❌ $test_file FAILED"
  fi
  
  echo ""
done

echo "════════════════════════════════════════════════════════════════"
echo "Test Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Total tests: ${#TESTS[@]}"
echo "Passed: ${#PASSED_TESTS[@]}"
echo "Failed: ${#FAILED_TESTS[@]}"
echo ""

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  ❌ $test"
  done
  exit 1
else
  echo "✅ All tests passed!"
  exit 0
fi
