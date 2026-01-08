#!/bin/bash
# shellcheck disable=SC1091
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! source "$ROOT_DIR/lib/meta_data.sh"; then
  echo " Failed to source meta_data.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/const.sh"; then
  echo " Failed to source const.sh"
  exit 1
fi

echo " SOURCES LOADED"

declare -g META_BASE="/tmp/meta_test"
declare -g META_DIR1="$META_BASE/app1"
declare -g META_DIR2="$META_BASE/app2"
declare -g META_DIR3="$META_BASE/app3"

prepare_meta_test_data() {
  mkdir -p "$META_DIR1" "$META_DIR2" "$META_DIR3"

  printf '{\n  "repo_owner": "TestUser",\n  "repo_name": "ShortNameApp",\n  "ref_type": "branch",\n  "ref_name": "main",\n  "commit": "1111111111111111111111111111111111111111",\n  "commit_message": "Initial commit from test"\n}\n' > "$META_DIR1/meta.json"

  printf '{\n  "repo_owner": "AnotherOwner",\n  "repo_name": "VeryLongRepositoryNameThatWillBeShortened",\n  "ref_type": "tag",\n  "ref_name": "v1.0.0",\n  "commit": "2222222222222222222222222222222222222222",\n  "commit_message": "Release version 1.0.0"\n}\n' > "$META_DIR2/meta.json"

  echo '{ "repo_owner": "MissingFieldsInc" }' > "$META_DIR3/meta.json"
}

cleanup_meta_test_data() {
  rm -rf "$META_BASE"
}

test_get_repo_owner_from_meta() {
  run_case() {
    local file="$1"
    local expected="$2"
    local result
    result=$(get_repo_owner_from_meta "$file")
    if [[ "$result" == "$expected" ]]; then
      echo " get_repo_owner_from_meta => $result"
    else
      echo " get_repo_owner_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1/meta.json" "TestUser"
  run_case "$META_DIR2/meta.json" "AnotherOwner"
  run_case "$META_DIR3/meta.json" "MissingFieldsInc"
}

test_get_repo_name_from_meta() {
  run_case() {
    local file="$1"
    local maxlen="$2"
    local expected="$3"
    local result

    if [[ -n "$maxlen" ]]; then
      result=$(get_repo_name_from_meta "$file" "$maxlen")
    else
      result=$(get_repo_name_from_meta "$file")
    fi

    if [[ "$result" == "$expected" ]]; then
      echo " get_repo_name_from_meta ($file, $maxlen) => '$result'"
    else
      echo " get_repo_name_from_meta ($file, $maxlen): got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1/meta.json" 20 "ShortNameApp"
  run_case "$META_DIR2/meta.json" 20 "VeryLongRepositor..."
  run_case "$META_DIR2/meta.json" "" "VeryLongRepositoryNameThatWillBeShortened"
  run_case "$META_DIR3/meta.json" 20 "–"
  run_case "$META_DIR3/meta.json" "" "–"
}

test_get_ref_type_from_meta() {
  run_case() {
    local file="$1"
    local expected="$2"
    local result
    result=$(get_ref_type_from_meta "$file")
    if [[ "$result" == "$expected" ]]; then
      echo " get_ref_type_from_meta => $result"
    else
      echo " get_ref_type_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1/meta.json" "branch"
  run_case "$META_DIR2/meta.json" "tag"
  run_case "$META_DIR3/meta.json" "–"
}

test_get_ref_name_from_meta() {
  run_case() {
    local file="$1"
    local expected="$2"
    local result
    result=$(get_ref_name_from_meta "$file")
    if [[ "$result" == "$expected" ]]; then
      echo " get_ref_name_from_meta => $result"
    else
      echo " get_ref_name_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1/meta.json" "main"
  run_case "$META_DIR2/meta.json" "v1.0.0"
  run_case "$META_DIR3/meta.json" "–"
}

test_get_commit_from_meta() {
  run_case() {
    local file="$1"
    local expected="$2"
    local result
    result=$(get_commit_from_meta "$file")
    if [[ "$result" == "$expected" ]]; then
      echo " get_commit_from_meta => $result"
    else
      echo " get_commit_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1/meta.json" "1111111111111111111111111111111111111111"
  run_case "$META_DIR2/meta.json" "2222222222222222222222222222222222222222"
  run_case "$META_DIR3/meta.json" "–"
}

test_get_commit_message_from_meta_local() {
  run_case() {
    local file="$1"
    local expected="$2"
    local result
    result=$(jq -r '.commit_message // "–"' "$file")
    if [[ "$result" == "$expected" ]]; then
      echo " get_commit_message_from_meta_local => $result"
    else
      echo " get_commit_message_from_meta_local: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1/meta.json" "Initial commit from test"
  run_case "$META_DIR2/meta.json" "Release version 1.0.0"
  run_case "$META_DIR3/meta.json" "–"
}

test_backup_app_metadata() {
  # Setup: Use /tmp for test to avoid permission issues
  local test_base="/tmp/meta_backup_test_$$"
  local test_service="testapp@example.com:5000.service"
  local test_app_dir="$test_base/example.com/testapp"
  local backup_dir="$test_app_dir/backups"
  local meta_file="$test_app_dir/meta.json"
  
  # Create test directory structure
  mkdir -p "$test_app_dir"
  
  # Create a test meta.json file
  cat > "$meta_file" << 'EOF'
{
  "repo_owner": "TestOwner",
  "repo_name": "TestRepo",
  "ref_type": "branch",
  "ref_name": "main",
  "commit": "abc123def456",
  "commit_message": "Test commit message"
}
EOF
  
  # Temporarily override APP_BASE_DIR and exec_dir for testing
  local old_app_base_dir="${APP_BASE_DIR}"
  local old_exec_dir="${exec_dir:-}"
  
  # Unset readonly variable and set new value for testing
  # We can't actually change readonly vars in bash, so we need to mock resolve_backup_folder_from_service_name
  export exec_dir="$test_app_dir"
  
  # Create a wrapper that mocks resolve_backup_folder_from_service_name for this test
  eval "$(cat << 'WRAPPER_EOF'
_original_resolve_backup_folder_from_service_name="$(declare -f resolve_backup_folder_from_service_name)"

resolve_backup_folder_from_service_name() {
  local service="$1"
  # For test service, return our test backup directory
  if [[ "$service" == "testapp@example.com:5000.service" ]]; then
    echo "/tmp/meta_backup_test_$$/example.com/testapp/backups/"
    return 0
  fi
  # Otherwise use original implementation
  eval "${_original_resolve_backup_folder_from_service_name#*\{}"
}
WRAPPER_EOF
)"
  
  # Test 1: backup_app_metadata creates a backup file
  if backup_app_metadata "$test_service" 2>/dev/null; then
    local backup_count=$(find "$backup_dir" -name "meta-*.json" 2>/dev/null | wc -l)
    if [[ "$backup_count" -eq 1 ]]; then
      echo " backup_app_metadata: Successfully created backup file"
    else
      echo " backup_app_metadata: Expected 1 backup file, found $backup_count"
      export exec_dir="$old_exec_dir"
      rm -rf "$test_base"
      return 1
    fi
  else
    echo " backup_app_metadata: Function failed unexpectedly"
    export exec_dir="$old_exec_dir"
    rm -rf "$test_base"
    return 1
  fi
  
  # Test 2: Duplicate backups with same commit are deduplicated
  sleep 1  # Ensure different timestamp
  if backup_app_metadata "$test_service" 2>/dev/null; then
    local backup_count=$(find "$backup_dir" -name "meta-*.json" 2>/dev/null | wc -l)
    if [[ "$backup_count" -eq 1 ]]; then
      echo " backup_app_metadata: Correctly deduplicated backup with same commit"
    else
      echo " backup_app_metadata: Expected 1 backup file after deduplication, found $backup_count"
      export exec_dir="$old_exec_dir"
      rm -rf "$test_base"
      return 1
    fi
  else
    echo " backup_app_metadata: Second backup failed"
    export exec_dir="$old_exec_dir"
    rm -rf "$test_base"
    return 1
  fi
  
  # Test 3: Different commit creates a new backup
  # Update meta file with different commit
  cat > "$meta_file" << 'EOF'
{
  "repo_owner": "TestOwner",
  "repo_name": "TestRepo",
  "ref_type": "branch",
  "ref_name": "main",
  "commit": "xyz789uvw012",
  "commit_message": "Different commit"
}
EOF
  
  sleep 1  # Ensure different timestamp
  if backup_app_metadata "$test_service" 2>/dev/null; then
    local backup_count=$(find "$backup_dir" -name "meta-*.json" 2>/dev/null | wc -l)
    if [[ "$backup_count" -eq 2 ]]; then
      echo " backup_app_metadata: Correctly created backup for different commit"
    else
      echo " backup_app_metadata: Expected 2 backup files, found $backup_count"
      export exec_dir="$old_exec_dir"
      rm -rf "$test_base"
      return 1
    fi
  else
    echo " backup_app_metadata: Third backup failed"
    export exec_dir="$old_exec_dir"
    rm -rf "$test_base"
    return 1
  fi
  
  # Test 4: Backup fails when meta file is missing
  rm -f "$meta_file"
  if backup_app_metadata "$test_service" 2>/dev/null; then
    echo " backup_app_metadata: Should fail when meta file is missing"
    export exec_dir="$old_exec_dir"
    rm -rf "$test_base"
    return 1
  else
    echo " backup_app_metadata: Correctly failed when meta file is missing"
  fi
  
  # Restore original function
  eval "${_original_resolve_backup_folder_from_service_name}"
  
  # Cleanup
  export exec_dir="$old_exec_dir"
  rm -rf "$test_base"
  return 0
}

# Hauptablauf
prepare_meta_test_data

test_get_repo_owner_from_meta
test_get_repo_name_from_meta
test_get_ref_type_from_meta
test_get_ref_name_from_meta
test_get_commit_from_meta
test_get_commit_message_from_meta_local
test_backup_app_metadata

cleanup_meta_test_data

echo -e "\n All meta field tests passed."
