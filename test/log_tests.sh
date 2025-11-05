#!/bin/bash
# Unit tests for log.sh error logging functions
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source log.sh which contains the error logging functions
if ! source "$ROOT_DIR/lib/log.sh"; then
  echo "❌ Failed to source log.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

# Test initialization
test_init_error_logging() {
  local test_dir="/tmp/test_log_init_$$"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  _init_error_logging
  
  if [[ -d "$test_dir" ]]; then
    echo "✅ _init_error_logging: Created log directory"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ _init_error_logging: Failed to create directory"
    return 1
  fi
}

# Test error logging
test_log_error() {
  local test_dir="/tmp/test_log_error_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  log_error "test_context" "test error message" 42
  
  if [[ -f "$ERROR_LOG_FILE" ]]; then
    if grep -q "ERROR" "$ERROR_LOG_FILE" && \
       grep -q "test_context" "$ERROR_LOG_FILE" && \
       grep -q "test error message" "$ERROR_LOG_FILE" && \
       grep -q "Exit code: 42" "$ERROR_LOG_FILE"; then
      echo "✅ log_error: Message logged correctly with all fields"
      rm -rf "$test_dir"
      return 0
    else
      echo "❌ log_error: Log content incomplete"
      cat "$ERROR_LOG_FILE"
      rm -rf "$test_dir"
      return 1
    fi
  else
    echo "❌ log_error: Log file not created"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test warning logging
test_log_warning() {
  local test_dir="/tmp/test_log_warning_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  log_warning "warning_context" "test warning message"
  
  if [[ -f "$ERROR_LOG_FILE" ]]; then
    if grep -q "WARNING" "$ERROR_LOG_FILE" && \
       grep -q "warning_context" "$ERROR_LOG_FILE" && \
       grep -q "test warning message" "$ERROR_LOG_FILE"; then
      echo "✅ log_warning: Warning logged correctly"
      rm -rf "$test_dir"
      return 0
    else
      echo "❌ log_warning: Log content incomplete"
      cat "$ERROR_LOG_FILE"
      rm -rf "$test_dir"
      return 1
    fi
  else
    echo "❌ log_warning: Log file not created"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test info logging
test_log_info() {
  local test_dir="/tmp/test_log_info_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  log_info "info_context" "test info message"
  
  if [[ -f "$ERROR_LOG_FILE" ]]; then
    if grep -q "INFO" "$ERROR_LOG_FILE" && \
       grep -q "info_context" "$ERROR_LOG_FILE" && \
       grep -q "test info message" "$ERROR_LOG_FILE"; then
      echo "✅ log_info: Info logged correctly"
      rm -rf "$test_dir"
      return 0
    else
      echo "❌ log_info: Log content incomplete"
      cat "$ERROR_LOG_FILE"
      rm -rf "$test_dir"
      return 1
    fi
  else
    echo "❌ log_info: Log file not created"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test debug logging with DEBUG_MODE off
test_log_debug_disabled() {
  local test_dir="/tmp/test_log_debug_off_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  DEBUG_MODE="false"
  
  log_debug "debug_context" "this should not appear"
  
  if [[ ! -f "$ERROR_LOG_FILE" ]] || ! grep -q "DEBUG" "$ERROR_LOG_FILE" 2>/dev/null; then
    echo "✅ log_debug: Debug disabled works correctly"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ log_debug: Debug logged when it shouldn't be"
    cat "$ERROR_LOG_FILE"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test debug logging with DEBUG_MODE on
test_log_debug_enabled() {
  local test_dir="/tmp/test_log_debug_on_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  DEBUG_MODE="true"
  
  log_debug "debug_context" "test debug message" 2>/dev/null
  
  if [[ -f "$ERROR_LOG_FILE" ]]; then
    if grep -q "DEBUG" "$ERROR_LOG_FILE" && \
       grep -q "debug_context" "$ERROR_LOG_FILE" && \
       grep -q "test debug message" "$ERROR_LOG_FILE"; then
      echo "✅ log_debug: Debug enabled works correctly"
      rm -rf "$test_dir"
      DEBUG_MODE="false"
      return 0
    else
      echo "❌ log_debug: Debug log content incomplete"
      cat "$ERROR_LOG_FILE"
      rm -rf "$test_dir"
      DEBUG_MODE="false"
      return 1
    fi
  else
    echo "❌ log_debug: Debug log file not created"
    rm -rf "$test_dir"
    DEBUG_MODE="false"
    return 1
  fi
}

# Test multiple log entries
test_multiple_log_entries() {
  local test_dir="/tmp/test_log_multi_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  log_error "ctx1" "error1"
  log_warning "ctx2" "warning1"
  log_info "ctx3" "info1"
  
  local count
  count=$(grep -c "^\[" "$ERROR_LOG_FILE" 2>/dev/null || echo "0")
  
  if [[ "$count" -ge 4 ]]; then  # 3 main entries + 1 exit code line
    echo "✅ Multiple log entries: All entries recorded ($count lines)"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ Multiple log entries: Expected at least 4 lines, got $count"
    cat "$ERROR_LOG_FILE"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test log file permissions fallback to /tmp
test_log_fallback_to_tmp() {
  local test_dir="/root/nonexistent_$$"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  _init_error_logging
  
  if [[ "$ERROR_LOG_DIR" == "/tmp/ghostly-hosting-logs" ]]; then
    echo "✅ Log fallback: Correctly fell back to /tmp"
    return 0
  else
    echo "❌ Log fallback: Did not fall back correctly. DIR=$ERROR_LOG_DIR"
    return 1
  fi
}

# Test timestamp format
test_timestamp_format() {
  local test_dir="/tmp/test_log_timestamp_$$"
  mkdir -p "$test_dir"
  ERROR_LOG_DIR="$test_dir"
  ERROR_LOG_FILE="$test_dir/error.log"
  
  log_info "timestamp_test" "checking timestamp"
  
  if [[ -f "$ERROR_LOG_FILE" ]]; then
    # Check if timestamp matches YYYY-MM-DD HH:MM:SS format
    if grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]' "$ERROR_LOG_FILE"; then
      echo "✅ Timestamp format: Correct format YYYY-MM-DD HH:MM:SS"
      rm -rf "$test_dir"
      return 0
    else
      echo "❌ Timestamp format: Incorrect format"
      cat "$ERROR_LOG_FILE"
      rm -rf "$test_dir"
      return 1
    fi
  else
    echo "❌ Timestamp format: Log file not created"
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

run_test test_init_error_logging || ((FAILED++))
run_test test_log_error || ((FAILED++))
run_test test_log_warning || ((FAILED++))
run_test test_log_info || ((FAILED++))
run_test test_log_debug_disabled || ((FAILED++))
run_test test_log_debug_enabled || ((FAILED++))
run_test test_multiple_log_entries || ((FAILED++))
run_test test_log_fallback_to_tmp || ((FAILED++))
run_test test_timestamp_format || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n✅ All log tests passed successfully"
  exit 0
else
  echo -e "\n❌ $FAILED test(s) failed"
  exit 1
fi
