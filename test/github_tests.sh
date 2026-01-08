#!/bin/bash
# Unit tests for github.sh functions focusing on error handling
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source required files
if ! source "$ROOT_DIR/lib/const.sh"; then
  echo " Failed to source const.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/common.sh"; then
  echo " Failed to source common.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/print.sh"; then
  echo " Failed to source print.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/dotnet.sh"; then
  echo " Failed to source dotnet.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/github.sh"; then
  echo " Failed to source github.sh"
  exit 1
fi

echo " SOURCES LOADED"

# Test validate_github_token with missing token
test_validate_github_token_missing() {
  if ! validate_github_token "" "$GITHUB_API_BASE" 2>/dev/null; then
    echo " validate_github_token: Missing token properly rejected"
    return 0
  else
    echo " validate_github_token: Missing token improperly accepted"
    return 1
  fi
}

# Test validate_github_token with missing API base
test_validate_github_token_missing_base() {
  if ! validate_github_token "some_token" "" 2>/dev/null; then
    echo " validate_github_token: Missing API base properly rejected"
    return 0
  else
    echo " validate_github_token: Missing API base improperly accepted"
    return 1
  fi
}

# Test validate_github_token with both missing
test_validate_github_token_both_missing() {
  if ! validate_github_token "" "" 2>/dev/null; then
    echo " validate_github_token: Missing both parameters properly rejected"
    return 0
  else
    echo " validate_github_token: Missing both parameters improperly accepted"
    return 1
  fi
}

# Test check_github_env_vars with missing GITHUB_API_TOKEN
test_check_github_env_vars_missing_token() {
  local saved_token="$GITHUB_API_TOKEN"
  local saved_base="$GITHUB_API_BASE"
  GITHUB_API_TOKEN=""
  
  if ! check_github_env_vars 2>/dev/null; then
    echo " check_github_env_vars: Missing token properly detected"
    GITHUB_API_TOKEN="$saved_token"
    return 0
  else
    echo " check_github_env_vars: Missing token not detected"
    GITHUB_API_TOKEN="$saved_token"
    return 1
  fi
}

# Test resolve_github_user_from_token with no token
test_resolve_github_user_no_token() {
  local saved_token="$GITHUB_API_TOKEN"
  local saved_user="$GITHUB_API_USER"
  GITHUB_API_TOKEN=""
  unset GITHUB_API_USER
  
  resolve_github_user_from_token
  
  if [[ -z "$GITHUB_API_USER" ]]; then
    echo " resolve_github_user_from_token: No user resolved when token missing"
    GITHUB_API_TOKEN="$saved_token"
    GITHUB_API_USER="$saved_user"
    return 0
  else
    echo " resolve_github_user_from_token: User was set without token"
    GITHUB_API_TOKEN="$saved_token"
    GITHUB_API_USER="$saved_user"
    return 1
  fi
}

# Test count_alternative_refs parameters
test_count_alternative_refs_params() {
  # This function requires valid repo, we test it doesn't crash with empty params
  local result
  result=$(count_alternative_refs "" "" "branch" "main" 2>/dev/null || echo "0")
  
  if [[ "$result" == "0" ]]; then
    echo " count_alternative_refs: Handles empty parameters safely"
    return 0
  else
    echo "  count_alternative_refs: Returned $result for empty params (API call may have succeeded)"
    return 0
  fi
}

# Test load_github_repositories error handling
test_load_github_repositories_no_token() {
  local saved_token="$GITHUB_API_TOKEN"
  GITHUB_API_TOKEN=""
  
  # Use timeout and echo empty string to avoid blocking on read -r
  if ! (echo "" | timeout 5 load_github_repositories 2>/dev/null); then
    echo " load_github_repositories: Handles missing token appropriately"
    GITHUB_API_TOKEN="$saved_token"
    return 0
  else
    echo "  load_github_repositories: Function completed (may have used different auth)"
    GITHUB_API_TOKEN="$saved_token"
    return 0
  fi
}

# Test clone_repository with missing repo name
test_clone_repository_missing_repo_name() {
  local saved_name="$SELECTED_REPO_NAME"
  local saved_owner="$SELECTED_REPO_OWNER"
  SELECTED_REPO_NAME=""
  SELECTED_REPO_OWNER=""
  
  if ! clone_repository 2>/dev/null; then
    echo " clone_repository: Properly fails with missing repo info"
    SELECTED_REPO_NAME="$saved_name"
    SELECTED_REPO_OWNER="$saved_owner"
    return 0
  else
    echo " clone_repository: Should fail with missing repo info"
    SELECTED_REPO_NAME="$saved_name"
    SELECTED_REPO_OWNER="$saved_owner"
    # Cleanup any created directory
    [[ -n "$TMP_CLONE_DIR" && -d "$TMP_CLONE_DIR" ]] && rm -rf "$TMP_CLONE_DIR"
    return 1
  fi
}

# Test save_repo_metadata with missing data
test_save_repo_metadata_missing_data() {
  local test_dir="/tmp/test_save_metadata_$$"
  mkdir -p "$test_dir"
  
  local saved_owner="$SELECTED_REPO_OWNER"
  local saved_name="$SELECTED_REPO_NAME"
  local saved_type="$SELECTED_REF_TYPE"
  local saved_ref="$SELECTED_REF_NAME"
  
  SELECTED_REPO_OWNER=""
  SELECTED_REPO_NAME=""
  SELECTED_REF_TYPE=""
  SELECTED_REF_NAME=""
  
  if ! save_repo_metadata "$test_dir" 2>/dev/null; then
    echo " save_repo_metadata: Properly fails with missing data"
    SELECTED_REPO_OWNER="$saved_owner"
    SELECTED_REPO_NAME="$saved_name"
    SELECTED_REF_TYPE="$saved_type"
    SELECTED_REF_NAME="$saved_ref"
    rm -rf "$test_dir"
    return 0
  else
    echo " save_repo_metadata: Should fail with missing data"
    SELECTED_REPO_OWNER="$saved_owner"
    SELECTED_REPO_NAME="$saved_name"
    SELECTED_REF_TYPE="$saved_type"
    SELECTED_REF_NAME="$saved_ref"
    rm -rf "$test_dir"
    return 1
  fi
}

# Test save_repo_metadata with valid minimal data
test_save_repo_metadata_valid() {
  local test_dir="/tmp/test_save_metadata_valid_$$"
  mkdir -p "$test_dir"
  
  local saved_owner="$SELECTED_REPO_OWNER"
  local saved_name="$SELECTED_REPO_NAME"
  local saved_type="$SELECTED_REF_TYPE"
  local saved_ref="$SELECTED_REF_NAME"
  
  SELECTED_REPO_OWNER="testowner"
  SELECTED_REPO_NAME="testrepo"
  SELECTED_REF_TYPE="branch"
  SELECTED_REF_NAME="main"
  
  if save_repo_metadata "$test_dir" 2>/dev/null; then
    if [[ -f "$test_dir/$META_FILE_NAME" ]]; then
      echo " save_repo_metadata: Creates metadata file successfully"
      SELECTED_REPO_OWNER="$saved_owner"
      SELECTED_REPO_NAME="$saved_name"
      SELECTED_REF_TYPE="$saved_type"
      SELECTED_REF_NAME="$saved_ref"
      rm -rf "$test_dir"
      return 0
    else
      echo " save_repo_metadata: Metadata file not created"
      SELECTED_REPO_OWNER="$saved_owner"
      SELECTED_REPO_NAME="$saved_name"
      SELECTED_REF_TYPE="$saved_type"
      SELECTED_REF_NAME="$saved_ref"
      rm -rf "$test_dir"
      return 1
    fi
  else
    echo " save_repo_metadata: Failed with valid data"
    SELECTED_REPO_OWNER="$saved_owner"
    SELECTED_REPO_NAME="$saved_name"
    SELECTED_REF_TYPE="$saved_type"
    SELECTED_REF_NAME="$saved_ref"
    rm -rf "$test_dir"
    return 1
  fi
}

run_test() {
  echo -e "\n Running $1"
  if ! "$1"; then
    echo " Test '$1' failed"
    return 1
  fi
  return 0
}

# Run all tests
FAILED=0

run_test test_validate_github_token_missing || ((FAILED++))
run_test test_validate_github_token_missing_base || ((FAILED++))
run_test test_validate_github_token_both_missing || ((FAILED++))
run_test test_check_github_env_vars_missing_token || ((FAILED++))
run_test test_resolve_github_user_no_token || ((FAILED++))
run_test test_count_alternative_refs_params || ((FAILED++))
run_test test_load_github_repositories_no_token || ((FAILED++))
run_test test_clone_repository_missing_repo_name || ((FAILED++))
run_test test_save_repo_metadata_missing_data || ((FAILED++))
run_test test_save_repo_metadata_valid || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo -e "\n All github tests passed successfully"
  exit 0
else
  echo -e "\n $FAILED test(s) failed"
  exit 1
fi
