#!/bin/bash
set -euo pipefail

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

  if ! command -v gcc >/dev/null && ! command -v cc >/dev/null; then
    echo "❌ No working C compiler found, even though build-essential is installed."
    exit 1
  fi

  if ! command -v base64 >/dev/null; then
    echo "❌ base64 command is missing. Please ensure coreutils is installed."
    exit 1
  fi
}

fix_permissions_if_needed() {
  if [[ -e deploy && ! -w deploy ]]; then
    echo "⚠️  No write access to deploy/. Fixing permissions with sudo..."
    sudo chown -R "$USER":"$USER" deploy || true
    sudo chmod -R u+rw deploy || true
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
        echo "❌ Invalid date. Format is correct, but date does not exist."
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
  rm -rf .bin_tmp deploy/ run.sh
  mkdir -p .bin_tmp deploy

  cp -r config .bin_tmp/
  cp -r lib .bin_tmp/
  cp start.sh .bin_tmp/
  cp LICENSE README.md .bin_tmp/ 2>/dev/null || true

  tar -czf deploy/payload.tar.gz -C .bin_tmp .
}

create_embedded_launcher() {
  echo "🚀 Creating self-contained launcher with embedded payload..."

  {
    echo "#!/bin/bash"
    echo "set -e"
    echo
    echo "SCRIPT_DIR=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)\""
    echo "TMPDIR=\"\$(mktemp -d)\""
    echo
    echo "# Extract payload from this file after the marker"
    echo "SCRIPT_FILE=\"\$0\""
    echo "PAYLOAD_LINE=\$(awk '/^__PAYLOAD_BELOW__/{ print NR + 1; exit }' \"\$SCRIPT_FILE\")"
    echo "if [[ -z \"\$PAYLOAD_LINE\" || ! \"\$PAYLOAD_LINE\" =~ ^[0-9]+\$ ]]; then"
    echo "  echo \"❌ Failed to locate payload marker in script.\""
    echo "  exit 1"
    echo "fi"
    echo "tail -n +\"\$PAYLOAD_LINE\" \"\$SCRIPT_FILE\" > \"\$TMPDIR/payload.tar.gz.b64\""
    echo "base64 -d \"\$TMPDIR/payload.tar.gz.b64\" > \"\$TMPDIR/payload.tar.gz\""
    echo "tar -xzf \"\$TMPDIR/payload.tar.gz\" -C \"\$TMPDIR\""
    echo
    echo "# Optional .env copy"
    echo "if [[ -f \"\$SCRIPT_DIR/.env\" ]]; then"
    echo "  cp \"\$SCRIPT_DIR/.env\" \"\$TMPDIR/.env\""
    echo "fi"
    echo
    echo "cd \"\$TMPDIR\""
    echo "chmod +x start.sh"
    echo "./start.sh"
    echo
    echo "exit 0"
    echo "__PAYLOAD_BELOW__"
    base64 deploy/payload.tar.gz
  } > deploy/run.sh

  chmod +x deploy/run.sh
}

finalize_binary() {
  local outfile
  if [[ -n "${EXPIRY:-}" ]]; then
    outfile="deploy/blazor_hosting_suite_trial_${EXPIRY}"
  else
    outfile="deploy/blazor_hosting_suite"
  fi

  mv deploy/run.sh "$outfile"
  echo "✅ Self-contained binary created: $outfile"
}

cleanup() {
  echo "🧼 Cleaning up..."
  rm -rf .bin_tmp deploy/payload.tar.gz
}

# MAIN
check_and_install_dependencies
read_expiry_date
fix_permissions_if_needed
prepare_payload
create_embedded_launcher
finalize_binary
cleanup
