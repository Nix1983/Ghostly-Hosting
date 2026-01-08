#!/bin/bash
# Unit tests for commit message truncation functionality
# Tests the behavior where long commit messages are truncated at the beginning
# with "..." prefix to show the most important part (the end) of the message

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "Commit Message Truncation Tests"
echo "════════════════════════════════════════════════════════════════"

# Test helper function that mimics the truncation logic in app.sh and meta_data.sh
truncate_message() {
  local message="$1"
  local max_length=40
  
  if (( ${#message} > max_length )); then
    echo "...${message: -37}"
  else
    echo "$message"
  fi
}

# Test 1: Short message should not be truncated
test_short_message_no_truncation() {
  echo " Running test_short_message_no_truncation"
  
  local input="Short commit message"
  local result
  result=$(truncate_message "$input")
  
  if [[ "$result" == "$input" ]]; then
    echo " Short message not truncated: '$result'"
    return 0
  else
    echo " Short message was incorrectly truncated to: '$result'"
    return 1
  fi
}

# Test 2: Long message should be truncated at the beginning
test_long_message_beginning_truncation() {
  echo " Running test_long_message_beginning_truncation"
  
  local input="This is a very long commit message that should be truncated at the beginning not at the end"
  local result
  result=$(truncate_message "$input")
  
  # Check that result starts with "..."
  if [[ "$result" == "..."* ]]; then
    echo " Long message starts with '...': '$result'"
  else
    echo " Long message doesn't start with '...': '$result'"
    return 1
  fi
  
  # Check that result is exactly 40 characters
  if [[ ${#result} -eq 40 ]]; then
    echo " Truncated message is exactly 40 characters"
  else
    echo " Truncated message is ${#result} characters, expected 40"
    return 1
  fi
  
  # Check that the end of the original message is visible
  if [[ "$result" == *"not at the end" ]]; then
    echo " End of original message is visible"
    return 0
  else
    echo " End of original message is not visible: '$result'"
    return 1
  fi
}

# Test 3: PR merge message should show feature name
test_pr_message_shows_feature() {
  echo " Running test_pr_message_shows_feature"
  
  local input="Merge pull request #403 from Nix1983/important-feature-name"
  local result
  result=$(truncate_message "$input")
  
  # Check that the feature name is visible in the result
  if [[ "$result" == *"important-feature-name" ]]; then
    echo " PR message shows feature name: '$result'"
    return 0
  else
    echo " PR message doesn't show feature name: '$result'"
    return 1
  fi
}

# Test 4: Message at exactly 40 characters should not be truncated
test_exact_length_no_truncation() {
  echo " Running test_exact_length_no_truncation"
  
  # Create a message with exactly 40 characters by padding
  local input="1234567890123456789012345678901234567890"
  local result
  result=$(truncate_message "$input")
  
  if [[ "$result" == "$input" && ${#result} -eq 40 ]]; then
    echo " Message at exactly 40 chars not truncated"
    return 0
  else
    echo " Message length: ${#input} -> ${#result} (expected 40 -> 40)"
    return 1
  fi
}

# Test 5: Empty message should be handled
test_empty_message() {
  echo " Running test_empty_message"
  
  local input=""
  local result
  result=$(truncate_message "$input")
  
  if [[ "$result" == "" ]]; then
    echo " Empty message handled correctly"
    return 0
  else
    echo " Empty message was modified to: '$result'"
    return 1
  fi
}

# Test 6: Very long message should still be exactly 40 chars
test_very_long_message_length() {
  echo " Running test_very_long_message_length"
  
  local input="This is an extremely long commit message with many words that goes on and on and on and should definitely be truncated but still show the important ending part"
  local result
  result=$(truncate_message "$input")
  
  if [[ ${#result} -eq 40 ]]; then
    echo " Very long message truncated to exactly 40 chars: '$result'"
    return 0
  else
    echo " Very long message is ${#result} chars, expected 40: '$result'"
    return 1
  fi
}

# Test 7: Compare old vs new truncation behavior
test_new_vs_old_truncation() {
  echo " Running test_new_vs_old_truncation"
  
  local input="Merge pull request #386 from Nix1983/some-important-feature"
  
  # Old behavior: truncate at end
  local old_result="${input:0:37}..."
  
  # New behavior: truncate at beginning
  local new_result
  new_result=$(truncate_message "$input")
  
  echo "  Old truncation: '$old_result'"
  echo "  New truncation: '$new_result'"
  
  # Old behavior would cut off the feature name
  if [[ "$old_result" != *"important-feature"* ]]; then
    echo " Old behavior does NOT show feature name (expected)"
  else
    echo "  Old behavior unexpectedly shows feature name"
  fi
  
  # New behavior should show the feature name
  if [[ "$new_result" == *"important-feature" ]]; then
    echo " New behavior DOES show feature name (expected)"
    return 0
  else
    echo " New behavior doesn't show feature name"
    return 1
  fi
}

# Run all tests
TESTS=(
  "test_short_message_no_truncation"
  "test_long_message_beginning_truncation"
  "test_pr_message_shows_feature"
  "test_exact_length_no_truncation"
  "test_empty_message"
  "test_very_long_message_length"
  "test_new_vs_old_truncation"
)

FAILED=0
PASSED=0

# Disable exit on error for test execution
set +e

for test in "${TESTS[@]}"; do
  echo ""
  if $test; then
    ((PASSED++))
  else
    ((FAILED++))
  fi
done

# Re-enable exit on error
set -e

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Commit Message Truncation Tests Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  exit 1
else
  echo " All commit message truncation tests passed!"
  exit 0
fi
