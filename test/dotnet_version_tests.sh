#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! source "$ROOT_DIR/lib/const.sh"; then
  echo " Failed to source const.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/dotnet.sh"; then
  echo " Failed to source dotnet.sh"
  exit 1
fi

echo " SOURCES LOADED"

test_is_valid_dotnet_version() {
  echo ""
  echo "Testing is_valid_dotnet_version function..."
  echo "─────────────────────────────────────────────────────────────────"
  
  # Valid versions >= 6.0
  if is_valid_dotnet_version "6.0"; then
    echo " 6.0 is valid"
  else
    echo " 6.0 should be valid"
    return 1
  fi
  
  if is_valid_dotnet_version "7.0"; then
    echo " 7.0 is valid"
  else
    echo " 7.0 should be valid"
    return 1
  fi
  
  if is_valid_dotnet_version "8.0"; then
    echo " 8.0 is valid"
  else
    echo " 8.0 should be valid"
    return 1
  fi
  
  if is_valid_dotnet_version "9.0"; then
    echo " 9.0 is valid"
  else
    echo " 9.0 should be valid"
    return 1
  fi
  
  # Future versions should be valid
  if is_valid_dotnet_version "10.0"; then
    echo " 10.0 is valid (future version)"
  else
    echo " 10.0 should be valid (future version)"
    return 1
  fi
  
  if is_valid_dotnet_version "11.0"; then
    echo " 11.0 is valid (future version)"
  else
    echo " 11.0 should be valid (future version)"
    return 1
  fi
  
  if is_valid_dotnet_version "15.0"; then
    echo " 15.0 is valid (future version)"
  else
    echo " 15.0 should be valid (future version)"
    return 1
  fi
  
  # Invalid versions < 6.0
  if is_valid_dotnet_version "5.0"; then
    echo " 5.0 should be invalid (< 6.0)"
    return 1
  else
    echo " 5.0 is invalid (< 6.0)"
  fi
  
  if is_valid_dotnet_version "4.8"; then
    echo " 4.8 should be invalid (< 6.0)"
    return 1
  else
    echo " 4.8 is invalid (< 6.0)"
  fi
  
  # Invalid format
  if is_valid_dotnet_version "invalid"; then
    echo " 'invalid' should be invalid format"
    return 1
  else
    echo " 'invalid' is invalid format"
  fi
  
  if is_valid_dotnet_version "8"; then
    echo " '8' should be invalid format (missing .0)"
    return 1
  else
    echo " '8' is invalid format (missing .0)"
  fi
  
  if is_valid_dotnet_version "8.0.1"; then
    echo " '8.0.1' should be invalid format (too many parts)"
    return 1
  else
    echo " '8.0.1' is invalid format (too many parts)"
  fi
}

test_get_available_dotnet_versions() {
  echo ""
  echo "Testing get_available_dotnet_versions function..."
  echo "─────────────────────────────────────────────────────────────────"
  
  # Call the function
  get_available_dotnet_versions
  
  # Check that SUPPORTED_DOTNET_VERSIONS is not empty
  if (( ${#SUPPORTED_DOTNET_VERSIONS[@]} == 0 )); then
    echo " SUPPORTED_DOTNET_VERSIONS should not be empty"
    return 1
  else
    echo " SUPPORTED_DOTNET_VERSIONS is populated with ${#SUPPORTED_DOTNET_VERSIONS[@]} versions"
  fi
  
  # Check that all versions are valid
  local all_valid=true
  for ver in "${SUPPORTED_DOTNET_VERSIONS[@]}"; do
    if ! is_valid_dotnet_version "$ver"; then
      echo " Version $ver in SUPPORTED_DOTNET_VERSIONS is not valid"
      all_valid=false
    fi
  done
  
  if $all_valid; then
    echo " All versions in SUPPORTED_DOTNET_VERSIONS are valid"
  else
    return 1
  fi
  
  # Display detected versions
  echo " Detected .NET versions: ${SUPPORTED_DOTNET_VERSIONS[*]}"
}

test_baseline_versions_exist() {
  echo ""
  echo "Testing BASELINE_DOTNET_VERSIONS constant..."
  echo "─────────────────────────────────────────────────────────────────"
  
  if (( ${#BASELINE_DOTNET_VERSIONS[@]} == 0 )); then
    echo " BASELINE_DOTNET_VERSIONS should not be empty"
    return 1
  else
    echo " BASELINE_DOTNET_VERSIONS has ${#BASELINE_DOTNET_VERSIONS[@]} versions"
  fi
  
  # Check that baseline versions include at least 6.0, 7.0, 8.0, 9.0
  local required_versions=("6.0" "7.0" "8.0" "9.0")
  for req_ver in "${required_versions[@]}"; do
    local found=false
    for baseline_ver in "${BASELINE_DOTNET_VERSIONS[@]}"; do
      if [[ "$baseline_ver" == "$req_ver" ]]; then
        found=true
        break
      fi
    done
    
    if $found; then
      echo " Baseline includes $req_ver"
    else
      echo " Baseline should include $req_ver"
      return 1
    fi
  done
  
  echo " Baseline versions: ${BASELINE_DOTNET_VERSIONS[*]}"
}

test_min_dotnet_version_constant() {
  echo ""
  echo "Testing MIN_DOTNET_VERSION constant..."
  echo "─────────────────────────────────────────────────────────────────"
  
  if [[ -z "$MIN_DOTNET_VERSION" ]]; then
    echo " MIN_DOTNET_VERSION should be set"
    return 1
  else
    echo " MIN_DOTNET_VERSION is set to: $MIN_DOTNET_VERSION"
  fi
  
  if [[ "$MIN_DOTNET_VERSION" == "6.0" ]]; then
    echo " MIN_DOTNET_VERSION is 6.0 as expected"
  else
    echo " MIN_DOTNET_VERSION should be 6.0, got: $MIN_DOTNET_VERSION"
    return 1
  fi
}

test_target_framework_parsing() {
  echo ""
  echo "Testing target framework parsing logic..."
  echo "─────────────────────────────────────────────────────────────────"
  
  # Test different TargetFramework formats
  local test_cases=(
    "net6.0:6.0"
    "net7.0:7.0"
    "net8.0:8.0"
    "net9.0:9.0"
    "net10:10.0"
    "net10.0:10.0"
    "net11:11.0"
    "net15:15.0"
  )
  
  for test_case in "${test_cases[@]}"; do
    local tf="${test_case%%:*}"
    local expected="${test_case##*:}"
    
    # Simulate the parsing logic from detect_required_dotnet_versions
    local basever
    basever=$(echo "$tf" | grep -oE 'net([0-9]+)(\.0)?' | sed -E 's/^net//;s/\.0$//')
    
    # Apply the normalization
    if [[ "$basever" =~ ^[0-9]+$ ]]; then
      basever="$basever.0"
    fi
    
    if [[ "$basever" == "$expected" ]]; then
      echo " $tf -> $basever (expected: $expected)"
    else
      echo " $tf -> $basever (expected: $expected)"
      return 1
    fi
    
    # Also verify it passes validation
    if ! is_valid_dotnet_version "$basever"; then
      echo " Parsed version $basever failed validation"
      return 1
    fi
  done
}

# Run all tests
echo "════════════════════════════════════════════════════════════════"
echo ".NET Version Support Tests"
echo "════════════════════════════════════════════════════════════════"

test_baseline_versions_exist
test_min_dotnet_version_constant
test_is_valid_dotnet_version
test_target_framework_parsing
test_get_available_dotnet_versions

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " All .NET version tests passed!"
echo "════════════════════════════════════════════════════════════════"
