#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! source "$ROOT_DIR/lib/common.sh"; then
  echo " Failed to source common.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/version.sh"; then
  echo " Failed to source version.sh"
  exit 1
fi

echo " SOURCES LOADED"

test_version_file_exists() {
  echo "Testing: VERSION file exists"
  local version_file="$ROOT_DIR/lib/VERSION"
  
  if [[ -f "$version_file" ]]; then
    echo " VERSION file exists at $version_file"
  else
    echo " VERSION file not found at $version_file"
    return 1
  fi
}

test_get_app_version() {
  echo "Testing: get_app_version function"
  local version
  version=$(get_app_version)
  
  if [[ -n "$version" && "$version" != "unknown" ]]; then
    echo " get_app_version returned: $version"
  else
    echo " get_app_version returned invalid version: $version"
    return 1
  fi
}

test_version_format() {
  echo "Testing: Version format (semantic versioning)"
  local version
  version=$(get_app_version)
  
  # Check if version matches semantic versioning pattern (x.y.z)
  if [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo " Version format is valid: $version"
  else
    echo " Version format is invalid: $version (expected x.y.z)"
    return 1
  fi
}

test_format_version_display() {
  echo "Testing: format_version_display function"
  local formatted
  formatted=$(format_version_display)
  
  # Check if version starts with 'v'
  if [[ "$formatted" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo " format_version_display returned: $formatted"
  else
    echo " format_version_display returned invalid format: $formatted (expected vx.y.z)"
    return 1
  fi
}

test_version_file_content() {
  echo "Testing: VERSION file content is clean"
  local version_file="$ROOT_DIR/lib/VERSION"
  local raw_content
  raw_content=$(cat "$version_file")
  
  # Check for no leading/trailing whitespace
  if [[ "$raw_content" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo " VERSION file content is clean: $raw_content"
  else
    echo "  VERSION file may have whitespace or invalid format: '$raw_content'"
    # Still pass if get_app_version works correctly
    local cleaned
    cleaned=$(get_app_version)
    if [[ "$cleaned" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo " get_app_version correctly cleaned the version: $cleaned"
    else
      echo " VERSION file content invalid even after cleaning"
      return 1
    fi
  fi
}

# Run all tests
echo "═══════════════════════════════════════════════════════════════"
echo "Running Version Tests"
echo "═══════════════════════════════════════════════════════════════"
echo ""

FAILED_TESTS=0

test_version_file_exists || ((FAILED_TESTS++))
echo ""

test_get_app_version || ((FAILED_TESTS++))
echo ""

test_version_format || ((FAILED_TESTS++))
echo ""

test_format_version_display || ((FAILED_TESTS++))
echo ""

test_version_file_content || ((FAILED_TESTS++))
echo ""

echo "═══════════════════════════════════════════════════════════════"
if [[ $FAILED_TESTS -eq 0 ]]; then
  echo " All version tests passed!"
  exit 0
else
  echo " $FAILED_TESTS test(s) failed"
  exit 1
fi
