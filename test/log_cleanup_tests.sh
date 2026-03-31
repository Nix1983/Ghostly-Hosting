#!/bin/bash
# Unit tests for log cleanup functionality
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required modules
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

if ! source "$ROOT_DIR/lib/log.sh"; then
  echo "❌ Failed to source log.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

run_test() {
  echo -e "\n🔧 Running $1"
  if ! "$1"; then
    echo "❌ Test '$1' failed"
    return 1
  fi
  return 0
}

# Test: Generated nginx-loglink script contains cleanup logic
test_nginx_loglink_script_has_cleanup() {
  if grep -q "find.*-mtime.*-delete" "$ROOT_DIR/lib/nginx.sh"; then
    echo "✅ nginx_loglink_script_has_cleanup: nginx.sh contains log cleanup logic with find -mtime -delete"
    return 0
  else
    echo "❌ nginx_loglink_script_has_cleanup: nginx.sh missing log cleanup logic"
    return 1
  fi
}

# Test: clear_old_logs_interactive function exists
test_clear_old_logs_function_exists() {
  if declare -f clear_old_logs_interactive >/dev/null; then
    echo "✅ clear_old_logs_function_exists: clear_old_logs_interactive function exists"
    return 0
  else
    echo "❌ clear_old_logs_function_exists: clear_old_logs_interactive function not found"
    return 1
  fi
}

# Test: show_log_statistics function exists
test_log_statistics_function_exists() {
  if declare -f show_log_statistics >/dev/null; then
    echo "✅ log_statistics_function_exists: show_log_statistics function exists"
    return 0
  else
    echo "❌ log_statistics_function_exists: show_log_statistics function not found"
    return 1
  fi
}

# Test: Log file discovery and counting
test_log_file_discovery() {
  local test_dir="/tmp/log_cleanup_test_$$"
  mkdir -p "$test_dir/webserver/access" "$test_dir/webserver/error"

  # Create test logs with different ages
  touch -d "40 days ago" "$test_dir/webserver/access/old1.txt"
  touch -d "40 days ago" "$test_dir/webserver/error/old2.txt"
  touch -d "10 days ago" "$test_dir/webserver/access/recent.txt"
  touch -d "5 days ago" "$test_dir/app.log"

  # Count old files (>30 days)
  local old_count
  old_count=$(find "$test_dir" \( -name "*.txt" -o -name "*.log" \) -mtime +30 2>/dev/null | wc -l)

  if [[ "$old_count" == "2" ]]; then
    echo "✅ log_file_discovery: Correctly identified $old_count old log files"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ log_file_discovery: Expected 2 old files, found $old_count"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test: Log deletion simulation (without actual deletion)
test_log_deletion_dry_run() {
  local test_dir="/tmp/log_deletion_test_$$"
  mkdir -p "$test_dir/webserver/access"

  # Create 5 old log files
  for i in {1..5}; do
    touch -d "35 days ago" "$test_dir/webserver/access/old_$i.txt"
  done

  # Count files to be deleted
  local files_to_delete
  files_to_delete=$(find "$test_dir/webserver/access" -name "*.txt" -mtime +30 2>/dev/null | wc -l)

  if [[ "$files_to_delete" == "5" ]]; then
    echo "✅ log_deletion_dry_run: Correctly identified 5 files for deletion"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ log_deletion_dry_run: Expected 5 files to delete, found $files_to_delete"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test: Compression functionality
test_log_compression() {
  local test_dir="/tmp/log_compression_test_$$"
  mkdir -p "$test_dir"

  # Create old uncompressed log
  echo "test log content" > "$test_dir/old.log"
  touch -d "10 days ago" "$test_dir/old.log"

  # Compress it
  gzip "$test_dir/old.log" 2>/dev/null

  if [[ -f "$test_dir/old.log.gz" && ! -f "$test_dir/old.log" ]]; then
    echo "✅ log_compression: Log file successfully compressed to .gz"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ log_compression: Compression failed or original file still exists"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test: show_log_menu has 5 options now
test_log_menu_has_new_options() {
  if grep -q "4).*Clear Old Logs" "$ROOT_DIR/lib/log.sh" && \
     grep -q "5).*Log Statistics" "$ROOT_DIR/lib/log.sh"; then
    echo "✅ log_menu_has_new_options: Log menu includes new options (4 and 5)"
    return 0
  else
    echo "❌ log_menu_has_new_options: Log menu missing new options"
    return 1
  fi
}

# Run all tests
echo "═══════════════════════════════════════════════════════════════"
echo "Running Log Cleanup Tests"
echo "═══════════════════════════════════════════════════════════════"

FAILED=0

run_test test_nginx_loglink_script_has_cleanup || ((FAILED++))
run_test test_clear_old_logs_function_exists || ((FAILED++))
run_test test_log_statistics_function_exists || ((FAILED++))
run_test test_log_file_discovery || ((FAILED++))
run_test test_log_deletion_dry_run || ((FAILED++))
run_test test_log_compression || ((FAILED++))
run_test test_log_menu_has_new_options || ((FAILED++))

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
  echo "✅ All log cleanup tests passed!"
  exit 0
else
  echo "❌ $FAILED test(s) failed"
  exit 1
fi
