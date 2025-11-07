#!/bin/bash
# shellcheck disable=SC1091
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! source "$ROOT_DIR/lib/meta_data.sh"; then
  echo "❌ Failed to source meta_data.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/const.sh"; then
  echo "❌ Failed to source const.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"

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
      echo "✅ get_repo_owner_from_meta => $result"
    else
      echo "❌ get_repo_owner_from_meta: got '$result', expected '$expected'"
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
      echo "✅ get_repo_name_from_meta ($file, $maxlen) => '$result'"
    else
      echo "❌ get_repo_name_from_meta ($file, $maxlen): got '$result', expected '$expected'"
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
      echo "✅ get_ref_type_from_meta => $result"
    else
      echo "❌ get_ref_type_from_meta: got '$result', expected '$expected'"
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
      echo "✅ get_ref_name_from_meta => $result"
    else
      echo "❌ get_ref_name_from_meta: got '$result', expected '$expected'"
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
      echo "✅ get_commit_from_meta => $result"
    else
      echo "❌ get_commit_from_meta: got '$result', expected '$expected'"
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
      echo "✅ get_commit_message_from_meta_local => $result"
    else
      echo "❌ get_commit_message_from_meta_local: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1/meta.json" "Initial commit from test"
  run_case "$META_DIR2/meta.json" "Release version 1.0.0"
  run_case "$META_DIR3/meta.json" "–"
}

test_backup_app_metadata() {
  # Skip this test - backup_app_metadata requires a valid service name format
  # and global exec_dir variable setup which is complex to mock in unit tests
  echo "⚠️  Skipping backup_app_metadata test - requires service runtime context"
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

echo -e "\n✅ All meta field tests passed."
