#!/bin/bash
set -euo pipefail

install_if_missing() {
  local package="$1"
  if ! dpkg -s "$package" >/dev/null 2>&1; then
    echo "📦 Installiere $package..."
    sudo apt-get update
    sudo apt-get install -y "$package"
  fi
}

check_and_install_dependencies() {
  install_if_missing build-essential
  install_if_missing shc
  install_if_missing tar

  if ! command -v gcc >/dev/null && ! command -v cc >/dev/null; then
    echo "❌ Kein funktionsfähiger C-Compiler gefunden, obwohl build-essential installiert ist."
    exit 1
  fi
}

fix_permissions_if_needed() {
  if [[ -e deploy && ! -w deploy ]]; then
    echo "⚠️  Kein Schreibzugriff auf deploy/. Setze Rechte mit sudo..."
    sudo chown -R "$USER":"$USER" deploy || true
    sudo chmod -R u+rw deploy || true
  fi
}

read_expiry_date() {
  local date_input
  while true; do
    printf "Bis wann soll die Binary gültig sein? (YYYY-MM-DD, Enter = unbegrenzt): "
    read -r date_input
    if [[ -z "$date_input" ]]; then
      EXPIRY=""
      break
    elif [[ "$date_input" =~ ^20[2-9][0-9]-[01][0-9]-[0-3][0-9]$ ]]; then
      EXPIRY="$date_input"
      if ! SHC_EXPIRY=$(date -d "$EXPIRY" +%m/%d/%Y 2>/dev/null); then
        echo "❌ Ungültiges Datum. Format korrekt, aber Datum existiert nicht."
      else
        break
      fi
    else
      echo "❌ Ungültiges Format. Bitte YYYY-MM-DD verwenden."
    fi
  done
}

prepare_payload() {
  echo "🧩 Erstelle Payload..."
  rm -rf .bin_tmp deploy/ run.sh run.sh.x.c
  mkdir -p .bin_tmp deploy

  cp -r config .bin_tmp/
  cp -r lib .bin_tmp/
  cp start.sh .bin_tmp/
  cp LICENSE README.md .bin_tmp/ 2>/dev/null || true

  tar -czf deploy/payload.tar.gz -C .bin_tmp .
}

create_launcher_script() {
  echo "🚀 Erstelle run.sh..."

  {
    echo "#!/bin/bash"
    echo "set -e"
    echo
    echo "SCRIPT_SOURCE_DIR=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)\""
    echo "PAYLOAD=\"\$SCRIPT_SOURCE_DIR/payload.tar.gz\""
    echo
    echo "if [[ ! -f \"\$PAYLOAD\" ]]; then"
    echo "  echo \"❌ payload.tar.gz fehlt.\""
    echo "  exit 1"
    echo "fi"
    echo
    echo "TMPDIR=\"\$(mktemp -d)\""
    echo "tar -xzf \"\$PAYLOAD\" -C \"\$TMPDIR\""
    echo
    echo "# .env vom Ursprungsverzeichnis mitkopieren"
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
    echo "🛡️  Kompiliere Binary mit Ablaufdatum $SHC_EXPIRY..."
    shc -e "$SHC_EXPIRY" -f run.sh -o "$outfile"
  else
    echo "🛡️  Kompiliere Binary ohne Ablaufdatum..."
    shc -f run.sh -o "$outfile"
  fi

  echo "✅ Binary erstellt: $outfile"
}

cleanup() {
  echo "🧼 Aufräumen..."
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
