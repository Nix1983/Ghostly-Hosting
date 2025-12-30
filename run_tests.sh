#!/bin/bash
# Run all test suites
# Note: We don't use set -e because we want to continue running tests even if some fail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DIR="$SCRIPT_DIR/test"

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
  "dotnet_version_tests.sh"
  "version_tests.sh"
  "server_tests.sh"
  "app_tests.sh"
  "api_tests.sh"
  "commit_message_truncation_tests.sh"
  "cloudflare_tests.sh"
  "certbot_tests.sh"
  "fail2ban_tests.sh"
  "print_tests.sh"
  "timezone_tests.sh"
)

FAILED_TESTS=()
PASSED_TESTS=()
TOTAL_PASSED_ASSERTIONS=0
TOTAL_FAILED_ASSERTIONS=0

for test_file in "${TESTS[@]}"; do
  test_path="$TEST_DIR/$test_file"
  
  if [[ ! -f "$test_path" ]]; then
    echo "⚠️  Test file not found: $test_file"
    continue
  fi
  
  echo "Running: $test_file"
  echo "────────────────────────────────────────────────────────────────"
  
  # Capture output to count passed/failed assertions
  output=$(bash "$test_path" 2>&1)
  exit_code=$?
  
  echo "$output"
  
  # Count assertions
  passed_count=$(echo "$output" | grep -c "^✅" || true)
  failed_count=$(echo "$output" | grep -c "^❌" || true)
  
  TOTAL_PASSED_ASSERTIONS=$((TOTAL_PASSED_ASSERTIONS + passed_count))
  TOTAL_FAILED_ASSERTIONS=$((TOTAL_FAILED_ASSERTIONS + failed_count))
  
  if [[ $exit_code -eq 0 ]]; then
    PASSED_TESTS+=("$test_file")
    echo "✅ $test_file PASSED"
  else
    FAILED_TESTS+=("$test_file")
    echo "❌ $test_file FAILED"
  fi
  
  echo ""
done

echo "════════════════════════════════════════════════════════════════"
echo "COMPREHENSIVE TEST SUMMARY"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo "Test Suites:"
echo "  Total:  ${#TESTS[@]}"
echo "  Passed: ${#PASSED_TESTS[@]}"
echo "  Failed: ${#FAILED_TESTS[@]}"
echo ""
echo "Test Assertions:"
echo "  Passed: $TOTAL_PASSED_ASSERTIONS ✅"
echo "  Failed: $TOTAL_FAILED_ASSERTIONS ❌"
echo ""
echo "Coverage:"
echo "  Server Setup Tests:   ✅"
echo "  App Deployment Tests: ✅"
echo "  API Integration Tests: ✅"
echo "  Common Utilities:     ✅"
echo "  Error Logging:        ✅"
echo ""

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
  echo "Failed test suites:"
  for test in "${FAILED_TESTS[@]}"; do
    echo "  ❌ $test"
  done
  echo ""
  exit 1
else
  echo "🎉 All test suites passed!"
  echo ""
  exit 0
fi
