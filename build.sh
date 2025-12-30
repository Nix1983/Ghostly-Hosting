#!/bin/bash
set -euo pipefail

# Constants
META_MARKER="__PAYLOAD_BELOW__"
TMP_DIR=".bin_tmp"
DEPLOY_DIR="deploy"
PAYLOAD_TAR="$DEPLOY_DIR/payload.tar.gz"
PAYLOAD_GPG="$DEPLOY_DIR/payload.tar.gz.gpg"
PAYLOAD_B64="$DEPLOY_DIR/payload.tar.gz.b64"

export NEEDRESTART_MODE=a

# Check for required GPG_KEY
if [[ -z "${GPG_KEY:-}" ]]; then
  GPG_KEY=$(head -c 32 /dev/urandom | base64)
  echo "🔐 Using auto-generated one-time GPG_KEY: $GPG_KEY"
fi

install_if_missing() {
  local package="$1"
  
  if [[ -z "$package" ]]; then
    echo "❌ No package name provided to install_if_missing"
    return 1
  fi
  
  if ! dpkg -s "$package" >/dev/null 2>&1; then
    echo "📦 Installing $package..."
    if ! sudo apt-get update -qq; then
      echo "❌ Failed to update package lists"
      return 1
    fi
    if ! sudo apt-get install -y "$package"; then
      echo "❌ Failed to install $package"
      return 1
    fi
    echo "✅ $package installed successfully"
  else
    echo "✅ $package is already installed"
  fi
  
  return 0
}

check_and_install_dependencies() {
  echo "🔍 Checking and installing dependencies..."
  
  local -a packages=(build-essential tar coreutils gnupg)
  local failed=0
  
  for package in "${packages[@]}"; do
    if ! install_if_missing "$package"; then
      echo "⚠️  Failed to install $package"
      ((failed++))
    fi
  done
  
  if [[ $failed -gt 0 ]]; then
    echo "❌ $failed package(s) failed to install"
    return 1
  fi

  # Verify required commands are available
  local -a commands=(base64 gpg tar)
  for cmd in "${commands[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "❌ Required command '$cmd' is still missing after installation"
      return 1
    fi
  done
  
  echo "✅ All dependencies are installed and available"
  return 0
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
  
  # Clean up any existing build artifacts
  if ! rm -rf "$TMP_DIR" "$DEPLOY_DIR"; then
    echo "❌ Failed to clean up existing directories"
    return 1
  fi
  
  if ! mkdir -p "$TMP_DIR" "$DEPLOY_DIR"; then
    echo "❌ Failed to create build directories"
    return 1
  fi

  # Copy required files
  if ! cp -r config "$TMP_DIR/"; then
    echo "❌ Failed to copy config directory"
    return 1
  fi
  
  if ! cp -r lib "$TMP_DIR/"; then
    echo "❌ Failed to copy lib directory"
    return 1
  fi
  
  if ! cp start.sh "$TMP_DIR/"; then
    echo "❌ Failed to copy start.sh"
    return 1
  fi
  
  # Copy optional files (non-critical)
  cp LICENSE README.md "$TMP_DIR/" 2>/dev/null || echo "ℹ️  Optional files (LICENSE, README.md) not copied"

  # Ensure no .env file is included (security measure)
  rm -f "$TMP_DIR/.env"

  # Add expiry date if specified
  if [[ -n "${EXPIRY:-}" ]]; then
    echo "$EXPIRY" >"$TMP_DIR/.expiry"
  fi

  # Create tarball
  echo "📦 Creating tarball..."
  if ! tar -czf "$PAYLOAD_TAR" -C "$TMP_DIR" .; then
    echo "❌ Failed to create tarball"
    return 1
  fi

  # Encrypt payload
  echo "🔐 Encrypting payload..."
  if ! gpg --symmetric --cipher-algo AES256 --batch --passphrase "$GPG_KEY" \
    --output "$PAYLOAD_GPG" "$PAYLOAD_TAR"; then
    echo "❌ Failed to encrypt payload"
    return 1
  fi

  # Encode encrypted payload
  echo "📦 Encoding encrypted payload..."
  if ! base64 "$PAYLOAD_GPG" >"$PAYLOAD_B64"; then
    echo "❌ Failed to encode payload"
    return 1
  fi

  # Calculate hash for verification
  if ! PAYLOAD_HASH=$(sha256sum "$PAYLOAD_TAR" | awk '{print $1}'); then
    echo "❌ Failed to calculate payload hash"
    return 1
  fi
  
  if [[ -z "$PAYLOAD_HASH" ]]; then
    echo "❌ Payload hash is empty"
    return 1
  fi
  
  echo "✅ Payload prepared successfully (hash: ${PAYLOAD_HASH:0:16}...)"
  return 0
}

create_launcher() {
  echo "🚀 Creating self-contained binary at /usr/local/bin/ghostlyHosting..."
  {
    echo "#!/bin/bash"
    echo "set -euo pipefail"
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
    echo "tail -n +\"\$PAYLOAD_LINE\" \"\$SCRIPT_FILE\" > \"\$TMPDIR/payload.tar.gz.b64\""
    echo "base64 -d \"\$TMPDIR/payload.tar.gz.b64\" > \"\$TMPDIR/payload.tar.gz.gpg\""
    echo "gpg --batch --passphrase '$GPG_KEY' --decrypt \"\$TMPDIR/payload.tar.gz.gpg\" > \"\$TMPDIR/payload.tar.gz\""
    echo
    echo "# Verify payload hash"
    echo "EXPECTED_HASH=\"$PAYLOAD_HASH\""
    echo "ACTUAL_HASH=\$(sha256sum \"\$TMPDIR/payload.tar.gz\" | awk '{print \$1}')"
    echo "if [[ \"\$EXPECTED_HASH\" != \"\$ACTUAL_HASH\" ]]; then"
    echo "  echo \"❌ Payload hash mismatch. Aborting.\""
    echo "  exit 1"
    echo "fi"
    echo
    echo "tar -xzf \"\$TMPDIR/payload.tar.gz\" -C \"\$TMPDIR\""
    echo
    echo "# Check expiry"
    echo "if [[ -f \"\$TMPDIR/.expiry\" ]]; then"
    echo "  EXPIRY=\$(cat \"\$TMPDIR/.expiry\")"
    echo "  NOW=\$(date +%s)"
    echo "  EXPIRES=\$(date -d \"\$EXPIRY\" +%s)"
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
    echo "rm -rf \"\$TMPDIR\""
    echo "exit 0"
    echo "$META_MARKER"
    cat "$PAYLOAD_B64"
  } >/usr/local/bin/ghostlyHosting

  chmod +x /usr/local/bin/ghostlyHosting
  echo "✅ Installed ghostlyHosting to /usr/local/bin/"
}

finalize_binary() {
  echo "✅ Final binary created in: /usr/local/bin/ghostlyHosting"
}

cleanup() {
  echo "🧼 Cleaning up build files..."
  rm -rf "$TMP_DIR" "$PAYLOAD_TAR" "$PAYLOAD_GPG" "$PAYLOAD_B64"
}

# MAIN
check_and_install_dependencies
read_expiry_date
prepare_payload
create_launcher
finalize_binary
cleanup
