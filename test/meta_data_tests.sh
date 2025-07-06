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

  cat > "$META_DIR1/meta.json" <<EOF
{
  "repo_owner": "TestUser",
  "repo_name": "ShortNameApp",
  "ref_type": "branch",
  "ref_name": "main",
  "commit": "1111111111111111111111111111111111111111"
}
EOF

  cat > "$META_DIR2/meta.json" <<EOF
{
  "repo_owner": "AnotherOwner",
  "repo_name": "VeryLongRepositoryNameThatWillBeShortened",
  "ref_type": "tag",
  "ref_name": "v1.0.0",
  "commit": "2222222222222222222222222222222222222222"
}
EOF

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

test_backup_app_metadata() {
  local test_dir="/tmp/test_backup_meta"
  local meta_file="$test_dir/meta.json"
  local backup_dir="$test_dir/$BACKUP_DIR"
  local commit="3333333333333333333333333333333333333333"

  mkdir -p "$test_dir"
  rm -rf "$backup_dir"
  mkdir -p "$backup_dir"

  cat > "$meta_file" <<EOF
{
  "repo_owner": "BackupTestUser",
  "repo_name": "BackupApp",
  "ref_type": "branch",
  "ref_name": "main",
  "commit": "$commit"
}
EOF

  backup_app_metadata "$test_dir"
  sleep 1
  backup_app_metadata "$test_dir"
  sleep 1
  backup_app_metadata "$test_dir"

  local count
  count=$(find "$backup_dir" -type f -name 'meta-*.json' | wc -l)

  if [[ "$count" -eq 1 ]]; then
    echo "✅ backup_app_metadata => only latest backup kept"
  else
    echo "❌ backup_app_metadata => expected 1 file, found $count"
    find "$backup_dir" -type f
    rm -rf "$test_dir"
    return 1
  fi

  rm -rf "$test_dir"
}

# Hauptablauf
prepare_meta_test_data

test_get_repo_owner_from_meta
test_get_repo_name_from_meta
test_get_ref_type_from_meta
test_get_ref_name_from_meta
test_get_commit_from_meta
test_backup_app_metadata

cleanup_meta_test_data

echo -e "\n✅ All meta field tests passed."
