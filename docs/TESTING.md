# Testing Guide

This document describes the test suite for the GhostlyHosting project and how to run and write tests.

## Test Suite Overview

The project includes comprehensive unit tests for all major components:

| Test File | Tests | Purpose |
|-----------|-------|---------|
| `test/common_tests.sh` | 58 | Core utility functions (domain parsing, service names, etc.) |
| `test/meta_data_tests.sh` | 5 | Metadata file handling |
| `test/log_tests.sh` | 9 | Error logging system |
| `test/common_error_logging_tests.sh` | 8 | Error logging integration |
| `test/upcloud_tests.sh` | 5 | UpCloud API error handling |
| `test/github_tests.sh` | 10 | GitHub API error handling |
| **Total** | **95** | |

## Running Tests

### Run All Tests

```bash
# From project root
for test in test/*.sh; do
  echo "Running $(basename $test)..."
  bash "$test"
  echo ""
done
```

### Run Individual Test Suite

```bash
# Core utility tests
bash test/common_tests.sh

# Metadata tests
bash test/meta_data_tests.sh

# Logging tests
bash test/log_tests.sh

# Error logging integration
bash test/common_error_logging_tests.sh

# UpCloud API tests
bash test/upcloud_tests.sh

# GitHub API tests
bash test/github_tests.sh
```

### Run Specific Test

Each test file contains multiple test functions. You can run a specific test by modifying the script temporarily or by extracting the test function.

## Test Structure

All tests follow a consistent structure:

```bash
#!/bin/bash
set -e

# Load required modules
source ./lib/common.sh
source ./lib/const.sh

# Test function
test_function_name() {
  # Arrange - set up test data
  local test_input="value"
  
  # Act - call the function being tested
  local result=$(function_to_test "$test_input")
  
  # Assert - verify the result
  if [[ "$result" == "expected" ]]; then
    echo "✅ test_function_name: passed"
    return 0
  else
    echo "❌ test_function_name: failed"
    return 1
  fi
}

# Run test
run_test test_function_name
```

## Test Categories

### 1. Unit Tests (test/common_tests.sh)

Tests individual functions in isolation:

```bash
# Test domain parsing
test_resolve_domain_from_service_name() {
  input="myapp@example.com:5000.service"
  expected="myapp.example.com"
  result=$(resolve_domain_from_service_name "$input")
  [[ "$result" == "$expected" ]]
}
```

### 2. Error Handling Tests

Tests that functions properly handle and log errors:

```bash
# Test missing parameter handling
test_validate_token_missing() {
  if ! validate_upcloud_token "" 2>/dev/null; then
    echo "✅ Missing token properly rejected"
    return 0
  fi
  return 1
}
```

### 3. Integration Tests

Tests that components work together:

```bash
# Test logging integration
test_load_env_once_logging() {
  ERROR_LOG_FILE="/tmp/test.log"
  load_env_once 2>/dev/null || true
  grep -q "load_env_once" "$ERROR_LOG_FILE"
}
```

## Writing New Tests

### Step 1: Choose Test File

- **lib/common.sh functions** → test/common_tests.sh
- **lib/upcloud.sh functions** → test/upcloud_tests.sh
- **lib/github.sh functions** → test/github_tests.sh
- **Error logging** → test/log_tests.sh
- **New module** → create test/module_name_tests.sh

### Step 2: Write Test Function

```bash
test_my_new_function() {
  # Test description
  local test_dir="/tmp/test_$$"
  mkdir -p "$test_dir"
  
  # Test code
  my_new_function "input" > "$test_dir/output"
  
  # Verification
  if [[ -f "$test_dir/output" ]]; then
    echo "✅ my_new_function: works correctly"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ my_new_function: failed"
    rm -rf "$test_dir"
    return 1
  fi
}
```

### Step 3: Add to Test Runner

```bash
# At the end of the test file
run_test test_my_new_function || ((FAILED++))
```

## Test Best Practices

### 1. Test Isolation

- Each test should be independent
- Use temporary directories for file operations
- Clean up after tests

```bash
test_example() {
  local test_dir="/tmp/test_$$"
  mkdir -p "$test_dir"
  
  # Test code here
  
  # Always cleanup
  rm -rf "$test_dir"
}
```

### 2. Clear Test Names

Use descriptive names that explain what is being tested:

```bash
# Good
test_validate_token_with_empty_string()
test_clone_repository_missing_credentials()

# Less clear
test_validation()
test_clone()
```

### 3. Test Error Paths

Don't just test the happy path - test failures too:

```bash
# Test success
test_function_valid_input()

# Test failures
test_function_invalid_input()
test_function_missing_parameters()
test_function_permission_denied()
```

### 4. Mock External Dependencies

For functions that call external APIs, save/mock environment variables:

```bash
test_api_call() {
  local saved_token="$API_TOKEN"
  API_TOKEN="test_token"
  
  # Test code
  
  # Restore
  API_TOKEN="$saved_token"
}
```

### 5. Verify Logging

For functions with error logging, verify logs are created:

```bash
test_function_logs_errors() {
  local test_log="/tmp/test_$$.log"
  ERROR_LOG_FILE="$test_log"
  
  function_that_should_log_error
  
  if grep -q "ERROR" "$test_log"; then
    echo "✅ Error logged correctly"
    rm -f "$test_log"
    return 0
  fi
  
  rm -f "$test_log"
  return 1
}
```

## Continuous Testing

### Before Committing

Always run all tests before committing changes:

```bash
# Quick check
bash test/common_tests.sh && \
bash test/log_tests.sh && \
bash test/common_error_logging_tests.sh

# Full suite
for test in test/*.sh; do bash "$test" || exit 1; done
```

### Test-Driven Development

1. Write a failing test for new functionality
2. Implement the feature
3. Verify test passes
4. Refactor if needed
5. Verify test still passes

## Debugging Failed Tests

### Enable Debug Output

```bash
# Run with debug output
bash -x test/common_tests.sh

# Or add debug mode
DEBUG_MODE=true bash test/log_tests.sh
```

### Check Specific Test

```bash
# Extract and run single test function
source test/common_tests.sh
test_resolve_domain_from_service_name
```

### Common Issues

1. **Test fails intermittently**: May be timing or cleanup issue
   - Add delays between operations
   - Ensure proper cleanup

2. **Permission errors**: Test may need sudo or different user
   - Mock file operations
   - Use /tmp for test files

3. **Environment conflicts**: Previous test may have left state
   - Add proper cleanup
   - Reset environment variables

## Test Coverage

Current test coverage focuses on:

✅ Core utility functions (domain parsing, IP validation, etc.)
✅ Error handling paths
✅ Logging system
✅ API token validation
✅ Metadata operations

Areas that could use more tests:
- Nginx configuration generation
- Firewall rule management
- Certificate management
- Backup/restore operations

## Adding New Test Suites

To add a new test suite for a new module:

1. Create test file: `test/module_name_tests.sh`
2. Follow the template structure
3. Source required dependencies
4. Write test functions
5. Add test runner at the end
6. Document in this guide

Example template:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$ROOT_DIR/lib/const.sh"
source "$ROOT_DIR/lib/common.sh"
source "$ROOT_DIR/lib/module_name.sh"

echo "✅ SOURCES LOADED"

test_function_one() {
  # Test implementation
  echo "✅ test_function_one: passed"
  return 0
}

test_function_two() {
  # Test implementation
  echo "✅ test_function_two: passed"
  return 0
}

run_test() {
  echo -e "\n🔧 Running $1"
  if ! "$1"; then
    echo "❌ Test '$1' failed"
    return 1
  fi
  return 0
}

FAILED=0
run_test test_function_one || ((FAILED++))
run_test test_function_two || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All tests passed"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
```

## CI/CD Integration

Tests are designed to run in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
test:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v2
    - name: Run tests
      run: |
        for test in test/*.sh; do
          bash "$test" || exit 1
        done
```

## Performance Considerations

Tests are designed to be fast:
- Unit tests: < 1 second each
- Integration tests: < 5 seconds each
- Full suite: < 30 seconds

If tests become slow:
1. Review external calls (API, network)
2. Check for unnecessary sleeps
3. Optimize test data generation
4. Consider parallel test execution
