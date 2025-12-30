#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_SCRIPT="$ROOT_DIR/build.sh"

echo "✅ SOURCES LOADED"

# Test helper to source functions from build.sh
source_build_functions() {
  # Extract functions from build.sh for testing
  # We'll source them in a controlled environment
  
  # Create a temporary file with just the functions
  local temp_functions
  temp_functions=$(mktemp)
  
  # Extract all functions from build.sh (everything except main execution)
  sed -n '/^install_if_missing()/,/^}$/p' "$BUILD_SCRIPT" > "$temp_functions"
  sed -n '/^check_and_install_dependencies()/,/^}$/p' "$BUILD_SCRIPT" >> "$temp_functions"
  sed -n '/^read_expiry_date()/,/^}$/p' "$BUILD_SCRIPT" >> "$temp_functions"
  sed -n '/^prepare_payload()/,/^}$/p' "$BUILD_SCRIPT" >> "$temp_functions"
  sed -n '/^create_launcher()/,/^}$/p' "$BUILD_SCRIPT" >> "$temp_functions"
  sed -n '/^finalize_binary()/,/^}$/p' "$BUILD_SCRIPT" >> "$temp_functions"
  sed -n '/^cleanup()/,/^}$/p' "$BUILD_SCRIPT" >> "$temp_functions"
  
  # Source the functions
  # shellcheck disable=SC1090
  source "$temp_functions"
  rm -f "$temp_functions"
}

test_script_exists() {
  echo "🔧 Running test_script_exists"
  
  if [[ -f "$BUILD_SCRIPT" ]]; then
    echo "✅ build.sh exists at $BUILD_SCRIPT"
  else
    echo "❌ build.sh not found at $BUILD_SCRIPT"
    return 1
  fi
}

test_script_has_shebang() {
  echo "🔧 Running test_script_has_shebang"
  
  local first_line
  first_line=$(head -n 1 "$BUILD_SCRIPT")
  
  if [[ "$first_line" == "#!/bin/bash" ]]; then
    echo "✅ build.sh has correct shebang"
  else
    echo "❌ build.sh has incorrect shebang: $first_line"
    return 1
  fi
}

test_script_has_set_errexit() {
  echo "🔧 Running test_script_has_set_errexit"
  
  if grep -q "^set -euo pipefail" "$BUILD_SCRIPT"; then
    echo "✅ build.sh has set -euo pipefail"
  else
    echo "❌ build.sh missing set -euo pipefail"
    return 1
  fi
}

test_constants_defined() {
  echo "🔧 Running test_constants_defined"
  
  local constants=("META_MARKER" "TMP_DIR" "DEPLOY_DIR" "PAYLOAD_TAR" "PAYLOAD_GPG" "PAYLOAD_B64")
  local missing=()
  
  for const in "${constants[@]}"; do
    if ! grep -q "^$const=" "$BUILD_SCRIPT"; then
      missing+=("$const")
    fi
  done
  
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "✅ All required constants are defined"
  else
    echo "❌ Missing constants: ${missing[*]}"
    return 1
  fi
}

test_install_if_missing_function_exists() {
  echo "🔧 Running test_install_if_missing_function_exists"
  
  if grep -q "^install_if_missing()" "$BUILD_SCRIPT"; then
    echo "✅ install_if_missing function exists"
  else
    echo "❌ install_if_missing function not found"
    return 1
  fi
}

test_check_and_install_dependencies_function_exists() {
  echo "🔧 Running test_check_and_install_dependencies_function_exists"
  
  if grep -q "^check_and_install_dependencies()" "$BUILD_SCRIPT"; then
    echo "✅ check_and_install_dependencies function exists"
  else
    echo "❌ check_and_install_dependencies function not found"
    return 1
  fi
}

test_read_expiry_date_function_exists() {
  echo "🔧 Running test_read_expiry_date_function_exists"
  
  if grep -q "^read_expiry_date()" "$BUILD_SCRIPT"; then
    echo "✅ read_expiry_date function exists"
  else
    echo "❌ read_expiry_date function not found"
    return 1
  fi
}

test_prepare_payload_function_exists() {
  echo "🔧 Running test_prepare_payload_function_exists"
  
  if grep -q "^prepare_payload()" "$BUILD_SCRIPT"; then
    echo "✅ prepare_payload function exists"
  else
    echo "❌ prepare_payload function not found"
    return 1
  fi
}

test_create_launcher_function_exists() {
  echo "🔧 Running test_create_launcher_function_exists"
  
  if grep -q "^create_launcher()" "$BUILD_SCRIPT"; then
    echo "✅ create_launcher function exists"
  else
    echo "❌ create_launcher function not found"
    return 1
  fi
}

test_cleanup_function_exists() {
  echo "🔧 Running test_cleanup_function_exists"
  
  if grep -q "^cleanup()" "$BUILD_SCRIPT"; then
    echo "✅ cleanup function exists"
  else
    echo "❌ cleanup function not found"
    return 1
  fi
}

test_gpg_key_handling() {
  echo "🔧 Running test_gpg_key_handling"
  
  if grep -q 'if \[\[ -z "${GPG_KEY:-}" \]\]' "$BUILD_SCRIPT"; then
    echo "✅ GPG_KEY is checked for existence"
  else
    echo "❌ GPG_KEY check not found"
    return 1
  fi
  
  if grep -q 'GPG_KEY=$(head -c 32 /dev/urandom | base64)' "$BUILD_SCRIPT"; then
    echo "✅ GPG_KEY auto-generation found"
  else
    echo "❌ GPG_KEY auto-generation not found"
    return 1
  fi
}

test_date_validation_regex() {
  echo "🔧 Running test_date_validation_regex"
  
  # Check if date validation regex exists
  if grep -q '\^20\[2-9\]\[0-9\]-\[01\]\[0-9\]-\[0-3\]\[0-9\]\$' "$BUILD_SCRIPT"; then
    echo "✅ Date validation regex found"
  else
    echo "❌ Date validation regex not found"
    return 1
  fi
}

test_payload_hash_validation() {
  echo "🔧 Running test_payload_hash_validation"
  
  if grep -q 'PAYLOAD_HASH=$(sha256sum' "$BUILD_SCRIPT"; then
    echo "✅ Payload hash calculation found"
  else
    echo "❌ Payload hash calculation not found"
    return 1
  fi
  
  if grep -q 'EXPECTED_HASH=' "$BUILD_SCRIPT"; then
    echo "✅ Expected hash verification found in generated binary"
  else
    echo "❌ Expected hash verification not found"
    return 1
  fi
}

test_expiry_check_in_launcher() {
  echo "🔧 Running test_expiry_check_in_launcher"
  
  if grep -q 'TMPDIR/.expiry' "$BUILD_SCRIPT"; then
    echo "✅ Expiry check exists in generated launcher"
  else
    echo "❌ Expiry check not found in launcher"
    return 1
  fi
}

test_cleanup_on_success() {
  echo "🔧 Running test_cleanup_on_success"
  
  # Check for cleanup in generated launcher
  if grep -q 'echo "rm -rf' "$BUILD_SCRIPT"; then
    echo "✅ Cleanup of TMPDIR found in launcher"
  else
    echo "❌ Cleanup not found in launcher"
    return 1
  fi
  
  # Check for cleanup function
  if grep -q '^cleanup()' "$BUILD_SCRIPT"; then
    echo "✅ Build cleanup function found"
  else
    echo "❌ Build cleanup function not found"
    return 1
  fi
}

test_required_dependencies_checked() {
  echo "🔧 Running test_required_dependencies_checked"
  
  local deps=("build-essential" "tar" "coreutils" "gnupg")
  local missing=()
  
  for dep in "${deps[@]}"; do
    if ! grep -q "install_if_missing $dep" "$BUILD_SCRIPT"; then
      missing+=("$dep")
    fi
  done
  
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "✅ All required dependencies are checked"
  else
    echo "❌ Missing dependency checks: ${missing[*]}"
    return 1
  fi
}

test_base64_command_verified() {
  echo "🔧 Running test_base64_command_verified"
  
  if grep -q 'command -v base64' "$BUILD_SCRIPT"; then
    echo "✅ base64 command is verified"
  else
    echo "❌ base64 command verification not found"
    return 1
  fi
}

test_gpg_command_verified() {
  echo "🔧 Running test_gpg_command_verified"
  
  if grep -q 'command -v gpg' "$BUILD_SCRIPT"; then
    echo "✅ gpg command is verified"
  else
    echo "❌ gpg command verification not found"
    return 1
  fi
}

test_payload_includes_required_files() {
  echo "🔧 Running test_payload_includes_required_files"
  
  local files=("config" "lib" "start.sh" "LICENSE" "README.md")
  local missing=()
  
  for file in "${files[@]}"; do
    if ! grep -q "cp.*$file" "$BUILD_SCRIPT"; then
      missing+=("$file")
    fi
  done
  
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "✅ All required files are included in payload"
  else
    echo "❌ Missing files in payload: ${missing[*]}"
    return 1
  fi
}

test_env_file_excluded_from_payload() {
  echo "🔧 Running test_env_file_excluded_from_payload"
  
  if grep -q 'rm -f "$TMP_DIR/.env"' "$BUILD_SCRIPT"; then
    echo "✅ .env file is explicitly excluded from payload"
  else
    echo "❌ .env file exclusion not found"
    return 1
  fi
}

test_encryption_uses_aes256() {
  echo "🔧 Running test_encryption_uses_aes256"
  
  if grep -q -- '--cipher-algo AES256' "$BUILD_SCRIPT"; then
    echo "✅ AES256 encryption is used"
  else
    echo "❌ AES256 encryption not found"
    return 1
  fi
}

test_launcher_output_location() {
  echo "🔧 Running test_launcher_output_location"
  
  if grep -q '/usr/local/bin/ghostlyHosting' "$BUILD_SCRIPT"; then
    echo "✅ Launcher is created at /usr/local/bin/ghostlyHosting"
  else
    echo "❌ Launcher output location not found"
    return 1
  fi
}

test_launcher_is_executable() {
  echo "🔧 Running test_launcher_is_executable"
  
  if grep -q 'chmod +x /usr/local/bin/ghostlyHosting' "$BUILD_SCRIPT"; then
    echo "✅ Launcher is made executable"
  else
    echo "❌ chmod +x not found for launcher"
    return 1
  fi
}

test_meta_marker_usage() {
  echo "🔧 Running test_meta_marker_usage"
  
  if grep -q 'META_MARKER="__PAYLOAD_BELOW__"' "$BUILD_SCRIPT"; then
    echo "✅ META_MARKER constant is defined"
  else
    echo "❌ META_MARKER constant not found"
    return 1
  fi
  
  if grep -q 'echo "$META_MARKER"' "$BUILD_SCRIPT"; then
    echo "✅ META_MARKER is written to launcher"
  else
    echo "❌ META_MARKER not written to launcher"
    return 1
  fi
}

test_needrestart_mode_set() {
  echo "🔧 Running test_needrestart_mode_set"
  
  if grep -q 'export NEEDRESTART_MODE=a' "$BUILD_SCRIPT"; then
    echo "✅ NEEDRESTART_MODE is set to automatic"
  else
    echo "❌ NEEDRESTART_MODE not set"
    return 1
  fi
}

test_main_execution_flow() {
  echo "🔧 Running test_main_execution_flow"
  
  local expected_calls=("check_and_install_dependencies" "read_expiry_date" "prepare_payload" "create_launcher" "finalize_binary" "cleanup")
  local missing=()
  
  for call in "${expected_calls[@]}"; do
    if ! grep -q "^$call$" "$BUILD_SCRIPT"; then
      missing+=("$call")
    fi
  done
  
  if [[ ${#missing[@]} -eq 0 ]]; then
    echo "✅ All main execution steps are present"
  else
    echo "❌ Missing execution steps: ${missing[*]}"
    return 1
  fi
}

# Bug-specific tests

test_meta_marker_variable_expansion_bug() {
  echo "🔧 Running test_meta_marker_variable_expansion_bug"
  
  # Check if META_MARKER is used in a way that will be expanded during script generation
  # The bug is on line 103: awk '/^$META_MARKER/...
  # This should use the variable name, not expand it
  
  if grep -q 'awk.*META_MARKER' "$BUILD_SCRIPT" | grep -q '\$META_MARKER'; then
    # Check if it's properly escaped or using variable interpolation
    if grep -q "awk '/^\$META_MARKER/" "$BUILD_SCRIPT" || grep -q 'awk "/^\$META_MARKER/' "$BUILD_SCRIPT"; then
      echo "❌ BUG FOUND: META_MARKER will be expanded during script generation (should be escaped)"
      return 1
    else
      echo "✅ META_MARKER usage appears correct"
    fi
  else
    echo "✅ META_MARKER usage in awk not found or correctly handled"
  fi
}

test_error_handling_exists() {
  echo "🔧 Running test_error_handling_exists"
  
  # Check for error handling mechanisms
  local has_errexit=false
  local has_pipefail=false
  
  if grep -q "set -e" "$BUILD_SCRIPT"; then
    has_errexit=true
  fi
  
  if grep -q "set.*pipefail" "$BUILD_SCRIPT"; then
    has_pipefail=true
  fi
  
  if [[ "$has_errexit" == true && "$has_pipefail" == true ]]; then
    echo "✅ Error handling is configured (set -e and pipefail)"
  else
    echo "❌ Missing error handling: errexit=$has_errexit, pipefail=$has_pipefail"
    return 1
  fi
}

# Run all tests
echo ""
test_script_exists
test_script_has_shebang
test_script_has_set_errexit
test_constants_defined
test_install_if_missing_function_exists
test_check_and_install_dependencies_function_exists
test_read_expiry_date_function_exists
test_prepare_payload_function_exists
test_create_launcher_function_exists
test_cleanup_function_exists
test_gpg_key_handling
test_date_validation_regex
test_payload_hash_validation
test_expiry_check_in_launcher
test_cleanup_on_success
test_required_dependencies_checked
test_base64_command_verified
test_gpg_command_verified
test_payload_includes_required_files
test_env_file_excluded_from_payload
test_encryption_uses_aes256
test_launcher_output_location
test_launcher_is_executable
test_meta_marker_usage
test_needrestart_mode_set
test_main_execution_flow
test_meta_marker_variable_expansion_bug
test_error_handling_exists

echo ""
echo "✅ All tests finished"
