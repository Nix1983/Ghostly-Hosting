#!/bin/bash
set -euo pipefail

# Constants
META_MARKER="__PAYLOAD_BELOW__"
TMP_DIR=".bin_tmp"
DEPLOY_DIR="deploy"
PAYLOAD_TAR="$DEPLOY_DIR/payload.tar.gz"
PAYLOAD_GPG="$DEPLOY_DIR/payload.tar.gz.gpg"
PAYLOAD_B64="$DEPLOY_DIR/payload.tar.gz.b64"
OUTPUT_BINARY="/usr/local/bin/ghostlyHosting"

export NEEDRESTART_MODE=a

# Cleanup function for error handling
cleanup_on_error() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "❌ Build failed with error code $exit_code. Cleaning up..."
  fi
  rm -rf "$TMP_DIR" "$DEPLOY_DIR"
}

# Set trap for cleanup on exit
trap cleanup_on_error EXIT

# Validate sudo access early
validate_sudo_access() {
  if ! sudo -n true 2>/dev/null; then
    echo "🔐 This script requires sudo access. Please enter your password if prompted."
    if ! sudo -v; then
      echo "❌ Cannot obtain sudo privileges. Exiting."
      exit 1
    fi
  fi
}

# Validate output directory is writable
validate_output_directory() {
  local output_dir
  output_dir=$(dirname "$OUTPUT_BINARY")
  
  if [[ ! -d "$output_dir" ]]; then
    echo "❌ Output directory $output_dir does not exist."
    exit 1
  fi
  
  if [[ ! -w "$output_dir" ]]; then
    echo "❌ Output directory $output_dir is not writable."
    exit 1
  fi
  
  if [[ -f "$OUTPUT_BINARY" ]]; then
    echo "⚠️  Binary already exists at: $OUTPUT_BINARY"
    read -rp "Do you want to overwrite it? (y/N): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo "❌ Aborted by user."
      exit 1
    fi
  fi
}

# Validate required files exist
validate_required_files() {
  local missing_files=()
  
  if [[ ! -d "config" ]]; then
    missing_files+=("config")
  fi
  
  if [[ ! -d "lib" ]]; then
    missing_files+=("lib")
  fi
  
  if [[ ! -f "start.sh" ]]; then
    missing_files+=("start.sh")
  fi
  
  if [[ ${#missing_files[@]} -gt 0 ]]; then
    echo "❌ Required files/directories not found: ${missing_files[*]}"
    echo "   Please run this script from the repository root."
    exit 1
  fi
}

# Check for required GPG_KEY
if [[ -z "${GPG_KEY:-}" ]]; then
  GPG_KEY=$(head -c 32 /dev/urandom | base64)
  echo "🔐 Using auto-generated one-time GPG_KEY"
  echo "   (Key is not displayed for security reasons)"
fi

install_if_missing() {
  local package="$1"
  if ! dpkg -s "$package" >/dev/null 2>&1; then
    echo "📦 Installing $package..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq "$package"
  fi
}

check_and_install_dependencies() {
  install_if_missing build-essential
  install_if_missing tar
  install_if_missing coreutils
  install_if_missing gnupg

  if ! command -v base64 >/dev/null; then
    echo "❌ base64 command is missing."
    exit 1
  fi
  if ! command -v gpg >/dev/null; then
    echo "❌ gpg is missing."
    exit 1
  fi
}

read_expiry_date() {
  local date_input
  while true; do
    printf "Enter expiration date for the binary (YYYY-MM-DD, Enter = no limit): "
    read -r date_input
    if [[ -z "$date_input" ]]; then
      EXPIRY=""
      break
    elif [[ "$date_input" =~ ^20[2-9][0-9]-[01][0-9]-[0-3][0-9]$ ]]; then
      EXPIRY="$date_input"
      if ! date -d "$EXPIRY" +%Y-%m-%d >/dev/null 2>&1; then
        echo "❌ Invalid date. Format correct, but date does not exist."
      else
        break
      fi
    else
      echo "❌ Invalid format. Please use YYYY-MM-DD."
    fi
  done
}

prepare_payload() {
  echo "🧩 Creating payload..."
  rm -rf "$TMP_DIR" "$DEPLOY_DIR"
  mkdir -p "$TMP_DIR" "$DEPLOY_DIR"

  cp -r config "$TMP_DIR/"
  cp -r lib "$TMP_DIR/"
  cp start.sh "$TMP_DIR/"
  cp LICENSE README.md "$TMP_DIR/" 2>/dev/null || true

  # Ensure no .env file is included
  rm -f "$TMP_DIR/.env"

  if [[ -n "$EXPIRY" ]]; then
    echo "$EXPIRY" >"$TMP_DIR/.expiry"
  fi

  tar -czf "$PAYLOAD_TAR" -C "$TMP_DIR" .

  echo "🔐 Encrypting payload..."
  if ! gpg --symmetric --cipher-algo AES256 --batch --passphrase "$GPG_KEY" \
    --output "$PAYLOAD_GPG" "$PAYLOAD_TAR" 2>/dev/null; then
    echo "❌ Failed to encrypt payload."
    exit 1
  fi

  echo "📦 Encoding encrypted payload..."
  base64 "$PAYLOAD_GPG" >"$PAYLOAD_B64"

  PAYLOAD_HASH=$(sha256sum "$PAYLOAD_TAR" | awk '{print $1}')
}

create_launcher() {
  echo "🚀 Creating self-contained binary at $OUTPUT_BINARY..."
  {
    echo "#!/bin/bash"
    echo "set -euo pipefail"
    echo
    echo "# Cleanup on exit"
    echo "cleanup_launcher() {"
    echo "  rm -rf \"\${TMPDIR:-}\""
    echo "}"
    echo "trap cleanup_launcher EXIT"
    echo
    echo "TMPDIR=\"\$(mktemp -d)\""
    echo "SCRIPT_FILE=\"\$0\""
    echo "PAYLOAD_LINE=\$(awk '/^$META_MARKER/{ print NR + 1; exit }' \"\$SCRIPT_FILE\")"
    echo
    echo "if [[ -z \"\$PAYLOAD_LINE\" || ! \"\$PAYLOAD_LINE\" =~ ^[0-9]+\$ ]]; then"
    echo "  echo \"❌ Failed to find payload marker.\""
    echo "  exit 1"
    echo "fi"
    echo
    echo "tail -n +\"\$PAYLOAD_LINE\" \"\$SCRIPT_FILE\" > \"\$TMPDIR/payload.tar.gz.b64\" 2>/dev/null || {"
    echo "  echo \"❌ Failed to extract payload.\""
    echo "  exit 1"
    echo "}"
    echo
    echo "if ! base64 -d \"\$TMPDIR/payload.tar.gz.b64\" > \"\$TMPDIR/payload.tar.gz.gpg\" 2>/dev/null; then"
    echo "  echo \"❌ Failed to decode payload.\""
    echo "  exit 1"
    echo "fi"
    echo
    echo "# Read GPG key from environment or prompt"
    echo "if [[ -z \"\${GPG_KEY:-}\" ]]; then"
    echo "  read -rsp \"🔑 Enter GPG passphrase: \" GPG_KEY"
    echo "  echo"
    echo "fi"
    echo
    echo "if ! gpg --batch --passphrase \"\$GPG_KEY\" --decrypt \"\$TMPDIR/payload.tar.gz.gpg\" > \"\$TMPDIR/payload.tar.gz\" 2>/dev/null; then"
    echo "  echo \"❌ Failed to decrypt payload. Wrong passphrase?\""
    echo "  exit 1"
    echo "fi"
    echo
    echo "# Verify payload hash"
    echo "EXPECTED_HASH=\"$PAYLOAD_HASH\""
    echo "ACTUAL_HASH=\$(sha256sum \"\$TMPDIR/payload.tar.gz\" | awk '{print \$1}')"
    echo "if [[ \"\$EXPECTED_HASH\" != \"\$ACTUAL_HASH\" ]]; then"
    echo "  echo \"❌ Payload hash mismatch. Aborting.\""
    echo "  exit 1"
    echo "fi"
    echo
    echo "if ! tar -xzf \"\$TMPDIR/payload.tar.gz\" -C \"\$TMPDIR\" 2>/dev/null; then"
    echo "  echo \"❌ Failed to extract payload.\""
    echo "  exit 1"
    echo "fi"
    echo
    echo "# Check expiry"
    echo "if [[ -f \"\$TMPDIR/.expiry\" ]]; then"
    echo "  EXPIRY=\$(cat \"\$TMPDIR/.expiry\")"
    echo "  NOW=\$(date +%s)"
    echo "  EXPIRES=\$(date -d \"\$EXPIRY\" +%s 2>/dev/null || echo 0)"
    echo "  if [[ \"\$NOW\" -gt \"\$EXPIRES\" ]]; then"
    echo "    echo \"❌ Trial expired on \$EXPIRY.\""
    echo "    exit 1"
    echo "  fi"
    echo "fi"
    echo
    echo "cd \"\$TMPDIR\""
    echo "chmod +x start.sh"
    echo "./start.sh"
    echo
    echo "exit 0"
    echo "$META_MARKER"
    cat "$PAYLOAD_B64"
  } >"$OUTPUT_BINARY"

  chmod +x "$OUTPUT_BINARY"
  echo "✅ Installed ghostlyHosting to $OUTPUT_BINARY"
}

finalize_binary() {
  echo "✅ Final binary created in: $OUTPUT_BINARY"
  echo "📊 Binary size: $(du -h "$OUTPUT_BINARY" | cut -f1)"
}

cleanup() {
  echo "🧼 Cleaning up build files..."
  rm -rf "$TMP_DIR" "$PAYLOAD_TAR" "$PAYLOAD_GPG" "$PAYLOAD_B64"
}

# MAIN
validate_sudo_access
validate_output_directory
validate_required_files
check_and_install_dependencies
read_expiry_date
prepare_payload
create_launcher
finalize_binary
cleanup

# Clear the error trap as we succeeded
trap - EXIT
echo "🎉 Build completed successfully!"
