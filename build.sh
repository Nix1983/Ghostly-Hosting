#!/bin/bash
set -euo pipefail

# Constants
META_MARKER="__PAYLOAD_BELOW__"
TMP_DIR=".bin_tmp"
DEPLOY_DIR="deploy"
PAYLOAD_TAR="$DEPLOY_DIR/payload.tar.gz"
PAYLOAD_GPG="$DEPLOY_DIR/payload.tar.gz.gpg"
PAYLOAD_B64="$DEPLOY_DIR/payload.tar.gz.b64"

# Check for required GPG_KEY
if [[ -z "${GPG_KEY:-}" ]]; then
  GPG_KEY=$(head -c 32 /dev/urandom | base64)
  echo "🔐 Using auto-generated one-time GPG_KEY: $GPG_KEY"
fi

install_if_missing() {
  local package="$1"
  if ! dpkg -s "$package" >/dev/null 2>&1; then
    echo "📦 Installing $package..."
    sudo apt-get update
    sudo apt-get install -y "$package"
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

  if [[ -n "$EXPIRY" ]]; then
    echo "$EXPIRY" > "$TMP_DIR/.expiry"
  fi

  tar -czf "$PAYLOAD_TAR" -C "$TMP_DIR" .

  echo "🔐 Encrypting payload..."
  gpg --symmetric --cipher-algo AES256 --batch --passphrase "$GPG_KEY" \
      --output "$PAYLOAD_GPG" "$PAYLOAD_TAR"

  echo "📦 Encoding encrypted payload..."
  base64 "$PAYLOAD_GPG" > "$PAYLOAD_B64"

  PAYLOAD_HASH=$(sha256sum "$PAYLOAD_TAR" | awk '{print $1}')
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
  } > /usr/local/bin/ghostlyHosting

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