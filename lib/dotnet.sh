#!/bin/bash
# shellcheck disable=SC1091
set -e

install_dotnet_version() {
  local version="$1"
  local install_dir="/opt/dotnet"

  if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^$version"; then
    echo "✅ .NET SDK $version is already installed."
    return 0
  fi

  echo "⬇️  Installing .NET SDK $version..."
  curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh

  if ! /tmp/dotnet-install.sh --channel "$version" --install-dir "$install_dir" --no-path; then
    echo "❌ Failed to install .NET SDK version: $version" >&2
    return 1
  fi

  echo "✅ .NET SDK $version installed to $install_dir"
}


delete_dotnet_version() {
  local version="$1"
  local install_dir="/opt/dotnet/sdk"

  mapfile -t matching_versions < <(find "$install_dir" -maxdepth 1 -type d -printf "%f\n" | grep -E "^$version")
  if (( ${#matching_versions[@]} == 0 )); then
    echo "⚠️  No SDKs matching version $version found."
    return 1
  fi

  echo ""
  echo "🗑️  The following .NET SDK versions will be removed:"
  echo "──────────────────────────────────────────────────────"
  for ver in "${matching_versions[@]}"; do
    printf " • .NET %s\n" "$ver"
  done
  echo "──────────────────────────────────────────────────────"

  for ver in "${matching_versions[@]}"; do
    rm -rf -- "$install_dir/${ver:?}"
  done

  echo "✅ .NET SDK $version removed successfully."
}

check_apps_using_sdk() {
  local version="$1"
  local root="/var/www"
  grep -r "\"$version\"" "$root" 2>/dev/null | grep global.json | cut -d: -f1 | uniq
}

find_dotnet_executable_dll() {
  local publish_dir="$1"

  if [[ -z "$publish_dir" || ! -d "$publish_dir" ]]; then
    echo "❌ Invalid or missing publish directory: $publish_dir" >&2
    return 1
  fi

  local dll
  dll=$(find "$publish_dir" -maxdepth 1 -type f -name '*.dll' | while read -r f; do
    local base="${f%.dll}"
    if [[ -f "$base.runtimeconfig.json" ]]; then
      basename "$f"
      return 0
    fi
  done)

  if [[ -z "$dll" ]]; then
    echo "❌ No executable DLL found in $publish_dir" >&2
    return 1
  fi

  echo "$dll"
  return 0
}

show_dotnet_version_menu() {
  local install_dir="/opt/dotnet"
  local versions=("5.0" "6.0" "7.0" "8.0" "9.0")

  while true; do
    clear
    echo -e "\n🧰 \e[1;34m.NET SDK Management\e[0m"
    echo "═════════════════════════════════════════════════════════════════════════════════"

    for i in "${!versions[@]}"; do
      local ver="${versions[$i]}"
      local status="➕  Not installed"
      local usage="0"
      local disk="–       "
      local realver="–"

      if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^$ver"; then
        status="✅  Installed"
        realver=$("$install_dir/dotnet" --list-sdks | grep "^$ver" | awk '{print $1}')
        usage=$(check_apps_using_sdk "$ver" | wc -l)
        disk=$(du -sh "$install_dir/sdk"/* 2>/dev/null | grep "$ver" | awk '{sum+=$1} END{print sum " MB"}')
      fi

      printf " %d) .NET %-4s │ %-20s │ 📦 Apps: %-4s │ 💾 Size: %-8s │ 🔢 Version: %-15s\n" \
        $((i + 1)) "$ver" "$status" "$usage" "$disk" "$realver"
    done

    echo -e "\n d) 🗑️  Delete version     q) 🔙 Back to main menu"
    echo "───────────────────────────────────────────────────────────────────────────────"
    printf "Install version [1–%d], delete [d], or quit [q]: " "${#versions[@]}"
    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      q|Q) return ;;
      d|D)
        while true; do
          clear
          echo -e "\n🗑️  \e[1;31mDelete installed .NET SDK\e[0m"
          echo "═════════════════════════════════════════════════════════════"
          local index=1
          declare -A deletable
          for dir in "$install_dir/sdk"/*; do
            [[ -d "$dir" ]] || continue
            local name
            name=$(basename "$dir")
            local basever=${name%%.*}.${name#*.}
            printf " %d) .NET %s\n" "$index" "$name"
            deletable[$index]="$basever"
            ((index++))
          done

          if [[ "${#deletable[@]}" -eq 0 ]]; then
            echo "⚠️  No installed SDKs found."
            read -rsn1 -p $'\nPress any key to return...' _
            break
          fi

          echo -e " q) 🔙 Cancel"
          echo "─────────────────────────────────────────────────────────────"
          printf "Select version number to delete: "
          IFS= read -rsn1 delsel
          echo ""

          if [[ "$delsel" == "q" || "$delsel" == "Q" ]]; then
            break
          elif [[ "$delsel" =~ ^[0-9]+$ ]] && [[ -n "${deletable[$delsel]}" ]]; then
            delete_dotnet_version "${deletable[$delsel]}"
            read -rsn1 -p $'\n✅ Deleted. Press any key to return...' _
            break
          else
            echo "❌ Invalid selection. Returning..."
            sleep 1
            break
          fi
        done
        ;;
      [1-9])
        if (( choice >= 1 && choice <= ${#versions[@]} )); then
          local version="net${versions[$((choice - 1))]}"
          install_dotnet_version "$version"
          read -rsn1 -p $'\n✅ Done. Press any key to return...' _
        fi
        ;;
      *)
        echo "❌ Invalid selection."
        sleep 1
        ;;
    esac
  done
}

finalize_blazor_deployment() {
  if [[ -z "$HOSTNAME_FQDN" || -z "$DOMAIN" || -z "$TMP_PUBLISH_DIR" ]]; then
    echo "❌ Required environment variables missing (HOSTNAME_FQDN, DOMAIN, TMP_PUBLISH_DIR)." >&2
    return 1
  fi

  local domain="$DOMAIN"
  local subfolder service_name target_path
  service_name="blazor-${HOSTNAME_FQDN//./-}.service"

  if [[ "$HOSTNAME_FQDN" == "$DOMAIN" ]]; then
    subfolder="root"
  else
    subfolder="${HOSTNAME_FQDN%%.*}"
  fi

  target_path="/var/www/$domain/$subfolder"
  export PUBLISH_DIR="$target_path"

  echo "📁 Target path: $target_path"

  if systemctl list-unit-files | grep -q "^$service_name"; then
    if systemctl is-active --quiet "$service_name"; then
      echo "⏹️ Stopping existing service: $service_name"
      systemctl stop "$service_name"
    fi
  fi

  if [[ -d "$target_path" ]]; then
    echo "🧹 Removing existing app folder..."
    rm -rf "$target_path"
  fi

  echo "📂 Copying app to $target_path"
  mkdir -p "$target_path"
  cp -r "$TMP_PUBLISH_DIR"/* "$target_path"/ || {
    echo "❌ Failed to copy files to $target_path" >&2
    return 1
  }

  DLL_NAME=$(find_dotnet_executable_dll "$target_path") || return 1
  export DLL_NAME

  echo "✅ App copied and DLL detected: $DLL_NAME"
}

create_and_start_blazor_service() {
  local fqdn="$HOSTNAME_FQDN"
  local port="$KESTREL_PORT"
  local publish_dir="$PUBLISH_DIR"
  local dll_name="$DLL_NAME"
  local service_name="blazor-${fqdn//./-}.service"
  local service_path="/etc/systemd/system/$service_name"

  if [[ -z "$fqdn" || -z "$port" || -z "$publish_dir" || -z "$dll_name" ]]; then
    echo "❌ Missing required values (fqdn, port, publish_dir, dll_name)" >&2
    return 1
  fi

  echo -e "\n⚙️  Creating systemd service: \033[1;36m$service_name\033[0m"

  {
    echo "[Unit]"
    echo "Description=Blazor App for $fqdn"
    echo "After=network.target"
    echo ""
    echo "[Service]"
    echo "WorkingDirectory=$publish_dir"
    echo "ExecStart=/opt/dotnet/dotnet $publish_dir/$dll_name"
    echo "Restart=always"
    echo "RestartSec=10"
    echo "KillSignal=SIGINT"
    echo "SyslogIdentifier=blazor-$fqdn"
    echo "Environment=ASPNETCORE_URLS=http://localhost:$port"
    echo "Environment=DOTNET_RUNNING_IN_CONTAINER=false"
    echo "Environment=DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false"
    echo ""
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } | tee "$service_path" >/dev/null

  echo "🔄 Reloading systemd daemon..."
  systemctl daemon-reexec
  systemctl daemon-reload

  echo "🔒 Enabling and starting $service_name..."
  systemctl enable "$service_name"
  systemctl start "$service_name"

  if systemctl is-active --quiet "$service_name"; then
    echo "✅ Service $service_name started successfully."
  else
    echo "❌ Failed to start service $service_name." >&2
    journalctl -u "$service_name" --no-pager -n 20
    return 1
  fi
}


