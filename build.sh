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
  install_if_missing shc
  install_if_missing tar

  if ! command -v gcc >/dev/null && ! command -v cc >/dev/null; then
    echo "❌ No working C compiler found, even though build-essential is installed."
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
      if ! SHC_EXPIRY=$(date -d "$EXPIRY" +%m/%d/%Y 2>/dev/null); then
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
  rm -rf .bin_tmp deploy/ run.sh run.sh.x.c
  mkdir -p .bin_tmp deploy

  cp -r config .bin_tmp/
  cp -r lib .bin_tmp/
  cp start.sh .bin_tmp/
  cp LICENSE README.md .bin_tmp/ 2>/dev/null || true

  tar -czf deploy/payload.tar.gz -C .bin_tmp .
}

create_launcher_script() {
  echo "🚀 Creating run.sh..."

  {
    echo "#!/bin/bash"
    echo "set -e"
    echo
    echo "SCRIPT_SOURCE_DIR=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)\""
    echo "PAYLOAD=\"\$SCRIPT_SOURCE_DIR/payload.tar.gz\""
    echo
    echo "if [[ ! -f \"\$PAYLOAD\" ]]; then"
    echo "  echo \"❌ payload.tar.gz is missing.\""
    echo "  exit 1"
    echo "fi"
    echo
    echo "TMPDIR=\"\$(mktemp -d)\""
    echo "tar -xzf \"\$PAYLOAD\" -C \"\$TMPDIR\""
    echo
    echo "# Copy .env from source directory if present"
    echo "if [[ -f \"\$SCRIPT_SOURCE_DIR/.env\" ]]; then"
    echo "  cp \"\$SCRIPT_SOURCE_DIR/.env\" \"\$TMPDIR/.env\""
    echo "fi"
    echo
    echo "cd \"\$TMPDIR\""
    echo "chmod +x start.sh"
    echo "./start.sh"
  } > run.sh

  chmod +x run.sh
}

compile_binary() {
  local outfile="deploy/blazor_hosting_suite"
  if [[ -n "${EXPIRY:-}" ]]; then
    outfile="deploy/blazor_hosting_suite_trial_${EXPIRY}"
    echo "🛡️  Compiling binary with expiration date $SHC_EXPIRY..."
    shc -e "$SHC_EXPIRY" -f run.sh -o "$outfile"
  else
    echo "🛡️  Compiling binary without expiration date..."
    shc -f run.sh -o "$outfile"
  fi

  echo "✅ Binary created: $outfile"
}

cleanup() {
  echo "🧼 Cleaning up..."
  rm -rf .bin_tmp run.sh run.sh.x.c
}

# MAIN
check_and_install_dependencies
read_expiry_date
fix_permissions_if_needed
prepare_payload
create_launcher_script
compile_binary
cleanup
