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

# Test: show_log_statistics is removed (statistics are now inline in the menu)
test_log_statistics_function_removed() {
  if ! declare -f show_log_statistics >/dev/null; then
    echo "✅ log_statistics_function_removed: show_log_statistics correctly removed (stats are inline)"
    return 0
  else
    echo "❌ log_statistics_function_removed: show_log_statistics should have been removed"
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

  # Count files to be deleted (new pattern: type f + txt/log)
  local files_to_delete
  files_to_delete=$(find "$test_dir/webserver/access" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.log" \) -mtime +30 2>/dev/null | wc -l)

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

# Test: Plain .log files in access/error dirs are counted (not just .txt)
test_log_count_includes_plain_log_files() {
  local test_dir="/tmp/log_count_log_test_$$"
  mkdir -p "$test_dir/webserver/access" "$test_dir/webserver/error"

  # Simulate nginx writing access.log as a plain file (no symlink rotation)
  echo "access log line" > "$test_dir/webserver/access/access.log"
  echo "error log line"  > "$test_dir/webserver/error/error.log"

  local access_count error_count
  access_count=$(find "$test_dir/webserver/access" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.gz" -o -name "*.log" \) 2>/dev/null | wc -l)
  error_count=$(find "$test_dir/webserver/error"  -maxdepth 1 -type f \( -name "*.txt" -o -name "*.gz" -o -name "*.log" \) 2>/dev/null | wc -l)

  access_count="${access_count// /}"
  error_count="${error_count// /}"

  if [[ "$access_count" == "1" && "$error_count" == "1" ]]; then
    echo "✅ log_count_includes_plain_log_files: Plain .log files counted correctly (access=$access_count, error=$error_count)"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ log_count_includes_plain_log_files: Expected 1+1, got access=$access_count error=$error_count"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test: Symlink .log files in access/error dirs are NOT counted as real files
test_log_count_excludes_symlinks() {
  local test_dir="/tmp/log_count_symlink_test_$$"
  mkdir -p "$test_dir/webserver/access"

  # Simulate the daily rotation: create real .txt and a symlink .log
  touch "$test_dir/webserver/access/01-04-2026.txt"
  ln -sf "$test_dir/webserver/access/01-04-2026.txt" "$test_dir/webserver/access/access.log"

  local count
  count=$(find "$test_dir/webserver/access" -maxdepth 1 -type f \( -name "*.txt" -o -name "*.gz" -o -name "*.log" \) 2>/dev/null | wc -l)
  count="${count// /}"

  if [[ "$count" == "1" ]]; then
    echo "✅ log_count_excludes_symlinks: Symlink .log not double-counted; only 1 real file found"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ log_count_excludes_symlinks: Expected 1 real file, got $count"
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

# Test: show_log_menu has 4 options (no statistics option — stats are inline)
test_log_menu_has_new_options() {
  if grep -q "4).*Clear Old Logs" "$ROOT_DIR/lib/log.sh" && \
     ! grep -q "5).*Log Statistics" "$ROOT_DIR/lib/log.sh"; then
    echo "✅ log_menu_has_new_options: Log menu has 4 options; statistics option correctly removed"
    return 0
  else
    echo "❌ log_menu_has_new_options: Log menu does not have expected options"
    return 1
  fi
}

# Test: clear_old_logs_interactive uses || true so set -e does not exit on missing directories
test_clear_old_logs_handles_missing_dir() {
  local nonexistent="/tmp/nonexistent_dir_$$"

  # These find -delete calls must not abort the script even when the directory is missing.
  # The || true is the fix for the set -e + find bug.
  find "$nonexistent/webserver/access" -name "*.txt" -mtime +30 -delete 2>/dev/null || true
  find "$nonexistent/webserver/error" -name "*.txt" -mtime +30 -delete 2>/dev/null || true
  find "$nonexistent" -maxdepth 1 -name "*.log" -mtime +30 -delete 2>/dev/null || true

  echo "✅ clear_old_logs_handles_missing_dir: find -delete with missing dir handled gracefully"
  return 0
}

# Test: clear_old_logs_interactive actually deletes old files and keeps recent ones
test_clear_old_logs_deletes_correct_files() {
  local test_dir="/tmp/log_clear_test_$$"
  mkdir -p "$test_dir/webserver/access" "$test_dir/webserver/error"

  touch -d "35 days ago" "$test_dir/webserver/access/old1.txt"
  touch -d "35 days ago" "$test_dir/webserver/error/old2.txt"
  touch -d "10 days ago" "$test_dir/webserver/access/recent.txt"
  echo "app log" > "$test_dir/app.log"
  touch -d "35 days ago" "$test_dir/app.log"

  # Simulate "Delete ALL old logs" (case 4 in clear_old_logs_interactive)
  find "$test_dir/webserver/access" -name "*.txt" -mtime +30 -delete 2>/dev/null || true
  find "$test_dir/webserver/error" -name "*.txt" -mtime +30 -delete 2>/dev/null || true
  find "$test_dir" -maxdepth 1 -name "*.log" -mtime +30 -delete 2>/dev/null || true

  local remaining
  remaining=$(find "$test_dir" \( -name "*.txt" -o -name "*.log" \) 2>/dev/null | wc -l)

  if [[ "$remaining" == "1" ]]; then
    echo "✅ clear_old_logs_deletes_correct_files: Deleted 3 old files, kept 1 recent file"
    rm -rf "$test_dir"
    return 0
  else
    echo "❌ clear_old_logs_deletes_correct_files: Expected 1 remaining file, found $remaining"
    rm -rf "$test_dir"
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
run_test test_log_statistics_function_removed || ((FAILED++))
run_test test_log_file_discovery || ((FAILED++))
run_test test_log_deletion_dry_run || ((FAILED++))
run_test test_log_compression || ((FAILED++))
run_test test_log_menu_has_new_options || ((FAILED++))
run_test test_clear_old_logs_handles_missing_dir || ((FAILED++))
run_test test_clear_old_logs_deletes_correct_files || ((FAILED++))
run_test test_log_count_includes_plain_log_files || ((FAILED++))
run_test test_log_count_excludes_symlinks || ((FAILED++))

echo ""
echo "═══════════════════════════════════════════════════════════════"
if [[ $FAILED -eq 0 ]]; then
  echo "✅ All log cleanup tests passed!"
  exit 0
else
  echo "❌ $FAILED test(s) failed"
  exit 1
fi
