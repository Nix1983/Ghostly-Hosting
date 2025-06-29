#!/bin/bash
# shellcheck disable=SC1091
set -e

source ../lib/const.sh
source ../lib/meta_data.sh

declare -g META_BASE="/tmp/meta_test"
declare -g META_DIR1="$META_BASE/app1"
declare -g META_DIR2="$META_BASE/app2"
declare -g META_DIR3="$META_BASE/app3"

prepare_meta_test_data() {
  mkdir -p "$META_DIR1" "$META_DIR2" "$META_DIR3"

  echo '{' > "$META_DIR1/meta.json"
  echo '  "repo_owner": "TestUser",' >> "$META_DIR1/meta.json"
  echo '  "repo_name": "ShortNameApp",' >> "$META_DIR1/meta.json"
  echo '  "ref_type": "branch",' >> "$META_DIR1/meta.json"
  echo '  "ref_name": "main",' >> "$META_DIR1/meta.json"
  echo '  "commit": "1111111111111111111111111111111111111111"' >> "$META_DIR1/meta.json"
  echo '}' >> "$META_DIR1/meta.json"

  echo '{' > "$META_DIR2/meta.json"
  echo '  "repo_owner": "AnotherOwner",' >> "$META_DIR2/meta.json"
  echo '  "repo_name": "VeryLongRepositoryNameThatWillBeShortened",' >> "$META_DIR2/meta.json"
  echo '  "ref_type": "tag",' >> "$META_DIR2/meta.json"
  echo '  "ref_name": "v1.0.0",' >> "$META_DIR2/meta.json"
  echo '  "commit": "2222222222222222222222222222222222222222"' >> "$META_DIR2/meta.json"
  echo '}' >> "$META_DIR2/meta.json"

  echo '{ "repo_owner": "MissingFieldsInc" }' > "$META_DIR3/meta.json"
}

cleanup_meta_test_data() {
  rm -rf "$META_BASE"
}

test_get_repo_owner_from_meta() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    result=$(get_repo_owner_from_meta "$input")
    if [[ "$result" == "$expected" ]]; then
      echo "✅ get_repo_owner_from_meta => $result"
    else
      echo "❌ get_repo_owner_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1" "TestUser"
  run_case "$META_DIR2" "AnotherOwner"
  run_case "$META_DIR3" "MissingFieldsInc"
}

test_get_repo_name_from_meta() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    result=$(get_repo_name_from_meta "$input" 20)
    if [[ "$result" == "$expected" ]]; then
      echo "✅ get_repo_name_from_meta => $result"
    else
      echo "❌ get_repo_name_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1" "ShortNameApp"
  run_case "$META_DIR2" "VeryLongRepositor..."
  run_case "$META_DIR3" "–"
}

test_get_ref_type_from_meta() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    result=$(get_ref_type_from_meta "$input")
    if [[ "$result" == "$expected" ]]; then
      echo "✅ get_ref_type_from_meta => $result"
    else
      echo "❌ get_ref_type_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1" "branch"
  run_case "$META_DIR2" "tag"
  run_case "$META_DIR3" "–"
}

test_get_ref_name_from_meta() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    result=$(get_ref_name_from_meta "$input")
    if [[ "$result" == "$expected" ]]; then
      echo "✅ get_ref_name_from_meta => $result"
    else
      echo "❌ get_ref_name_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1" "main"
  run_case "$META_DIR2" "v1.0.0"
  run_case "$META_DIR3" "–"
}

test_get_commit_from_meta() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    result=$(get_commit_from_meta "$input")
    if [[ "$result" == "$expected" ]]; then
      echo "✅ get_commit_from_meta => $result"
    else
      echo "❌ get_commit_from_meta: got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "$META_DIR1" "1111111111111111111111111111111111111111"
  run_case "$META_DIR2" "2222222222222222222222222222222222222222"
  run_case "$META_DIR3" "–"
}

# Hauptablauf
prepare_meta_test_data

test_get_repo_owner_from_meta
test_get_repo_name_from_meta
test_get_ref_type_from_meta
test_get_ref_name_from_meta
test_get_commit_from_meta

cleanup_meta_test_data

echo -e "\n✅ All meta field tests passed."
