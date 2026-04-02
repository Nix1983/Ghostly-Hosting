#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
START_FILE="$ROOT_DIR/start.sh"

cd "$ROOT_DIR"
# shellcheck disable=SC1091
source "./start.sh"

echo "✅ START TESTS READY"

test_start_uses_masked_token_prompts() {
  if grep -Eq '_read_secret_with_asterisks ".*UpCloud API Token: " UPCLOUD_API_TOKEN' "$START_FILE" \
    && grep -Eq '_read_secret_with_asterisks ".*GitHub API Token: " GITHUB_API_TOKEN' "$START_FILE" \
    && grep -Eq '_read_secret_with_asterisks ".*Cloudflare API Token: " CLOUDFLARE_API_TOKEN' "$START_FILE"; then
    echo "✅ start.sh: All first-run token prompts use masked asterisk input"
    return 0
  fi

  echo "❌ start.sh: Expected all first-run token prompts to use _read_secret_with_asterisks"
  return 1
}

test_start_shows_upcloud_scope_hint() {
  if grep -q "another UpCloud account/subaccount" "$START_FILE"; then
    echo "✅ start.sh: UpCloud scope hint is present"
    return 0
  fi

  echo "❌ start.sh: UpCloud scope hint missing"
  return 1
}

test_required_tool_package_mapping_for_xz() {
  local package_name
  package_name=$(get_required_system_package_for_tool "xz")

  if [[ "$package_name" == "xz-utils" ]]; then
    echo "✅ start.sh: xz maps to apt package xz-utils"
    return 0
  fi

  echo "❌ start.sh: Expected xz to map to xz-utils, got: $package_name"
  return 1
}

test_required_tools_include_xz() {
  if grep -Eq 'required_tools=\(.*xz.*\)' "$START_FILE"; then
    echo "✅ start.sh: xz is part of the required first-run tools"
    return 0
  fi

  echo "❌ start.sh: Expected xz in required_tools"
  return 1
}

FAILED=0

test_start_uses_masked_token_prompts || ((FAILED++))
test_start_shows_upcloud_scope_hint || ((FAILED++))
test_required_tool_package_mapping_for_xz || ((FAILED++))
test_required_tools_include_xz || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All start tests passed successfully"
  exit 0
fi

echo "❌ $FAILED start test(s) failed"
exit 1
