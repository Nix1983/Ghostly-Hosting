#!/bin/bash
# Additional unit tests for error logging integration in common.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source log.sh first to enable logging
if ! source "$ROOT_DIR/lib/log.sh"; then
  echo "❌ Failed to source log.sh"
  exit 1
fi

# Source common.sh which includes _safe_log
if ! source "$ROOT_DIR/lib/common.sh"; then
  echo "❌ Failed to source common.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test _safe_log helper function exists
test_safe_log_exists() {
  if declare -f _safe_log >/dev/null 2>&1; then
    echo "✅ _safe_log: Helper function exists"
    return 0
  else
    echo "❌ _safe_log: Helper function not found"
    return 1
  fi
}

# Test _safe_log with error level
test_safe_log_error() {
  local test_dir="/tmp/test_safe_log_error_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  _safe_log error "test_context" "test error message"
  
  if [[ -f "$ERROR_LOG_FILE" ]] && grep -q "ERROR" "$ERROR_LOG_FILE"; then
    echo "✅ _safe_log: Error level works correctly"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ _safe_log: Error level didn't log"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test _safe_log with warning level
test_safe_log_warning() {
  local test_dir="/tmp/test_safe_log_warning_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  _safe_log warning "test_context" "test warning message"
  
  if [[ -f "$ERROR_LOG_FILE" ]] && grep -q "WARNING" "$ERROR_LOG_FILE"; then
    echo "✅ _safe_log: Warning level works correctly"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ _safe_log: Warning level didn't log"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test _safe_log with info level
test_safe_log_info() {
  local test_dir="/tmp/test_safe_log_info_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  _safe_log info "test_context" "test info message"
  
  if [[ -f "$ERROR_LOG_FILE" ]] && grep -q "INFO" "$ERROR_LOG_FILE"; then
    echo "✅ _safe_log: Info level works correctly"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ _safe_log: Info level didn't log"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test _safe_log with debug level
test_safe_log_debug() {
  local test_dir="/tmp/test_safe_log_debug_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  DEBUG_MODE="true"
  
  _safe_log debug "test_context" "test debug message" 2>/dev/null
  
  if [[ -f "$ERROR_LOG_FILE" ]] && grep -q "DEBUG" "$ERROR_LOG_FILE"; then
    echo "✅ _safe_log: Debug level works correctly"
    rm -rf "$test_dir"
    DEBUG_MODE="false"
    return 0
  else
    echo "❌ _safe_log: Debug level didn't log"
    rm -rf "$test_dir"
    DEBUG_MODE="false"
    return 1
  fi
}

# Test is_valid_ipv4 logs debug messages
test_is_valid_ipv4_logging() {
  local test_dir="/tmp/test_ipv4_logging_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  DEBUG_MODE="true"
  
  # Test with invalid IP
  is_valid_ipv4 "999.999.999.999" 2>/dev/null || true
  
  if [[ -f "$ERROR_LOG_FILE" ]] && grep -q "is_valid_ipv4" "$ERROR_LOG_FILE"; then
    echo "✅ is_valid_ipv4: Logs debug messages correctly"
    rm -rf "$test_dir"
    DEBUG_MODE="false"
    return 0
  else
    echo "❌ is_valid_ipv4: Debug logging not working"
    rm -rf "$test_dir"
    DEBUG_MODE="false"
    return 1
  fi
}

# Test load_env_once logs appropriately
test_load_env_once_logging() {
  local test_dir="/tmp/test_load_env_logging_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  # Reset the guard
  unset __ENV_LOADED_ALREADY
  
  # Try to load from non-existent directory
  (cd "$test_dir" && load_env_once 2>/dev/null) || true
  
  if [[ -f "$ERROR_LOG_FILE" ]] && grep -q "load_env_once" "$ERROR_LOG_FILE"; then
    echo "✅ load_env_once: Logs warnings correctly"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ load_env_once: Warning logging not working"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test get_project_root error handling
test_get_project_root_logging() {
  local test_dir="/tmp/test_project_root_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  # get_project_root should succeed
  local result
  result=$(get_project_root)
  
  if [[ -n "$result" ]]; then
    echo "✅ get_project_root: Returns valid path"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ get_project_root: Returned empty path"
    rm -rf "$test_dir"
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

run_test test_safe_log_exists || ((FAILED++))
run_test test_safe_log_error || ((FAILED++))
run_test test_safe_log_warning || ((FAILED++))
run_test test_safe_log_info || ((FAILED++))
run_test test_safe_log_debug || ((FAILED++))
run_test test_is_valid_ipv4_logging || ((FAILED++))
run_test test_load_env_once_logging || ((FAILED++))
run_test test_get_project_root_logging || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All common error logging tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
