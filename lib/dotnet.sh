#!/bin/bash
# shellcheck disable=SC1091
set -e

# Global variables to be accessed in other modules
declare -g DOTNET_Version=""
declare -g TMP_PUBLISH_DIR=""

install_dotnet_version() {
  local install_dir="/opt/dotnet"

  # Check if DOTNET_Version is set
  if [[ -z "$DOTNET_Version" ]]; then
    echo -e "\n❌ \e[31mNo .NET SDK version specified.\e[0m"
    echo -e "💡 Make sure to run \e[36mdetect_required_dotnet_versions\e[0m before installing."
    return 1
  fi

  if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^$DOTNET_Version"; then
    echo -e "\n✅ .NET SDK $DOTNET_Version is already installed."
    return 0
  fi

  echo -e "\n🧩 Installing .NET SDK $DOTNET_Version..."
  curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh

  if ! /tmp/dotnet-install.sh --channel "$DOTNET_Version" --install-dir "$install_dir" --no-path; then
    echo -e "❌ Failed to install .NET SDK version: $DOTNET_Version" >&2
    return 1
  fi

  echo -e "\n✅ .NET SDK $DOTNET_Version installed to $install_dir"
  return 0
}

detect_required_dotnet_versions() {
  local dir="${TMP_CLONE_DIR:-.}"
  local main_project=""
  local version=""

  if [[ ! -d "$dir" ]]; then
    echo -e "\n❌ \e[31mProject directory not found:\e[0m $dir"
    return 1
  fi

  # Step 1: Check for .sln and try to extract first project
  local sln
  sln=$(find "$dir" -maxdepth 1 -name "*.sln" | head -n 1)

  if [[ -n "$sln" ]]; then
    echo -e "\n📘 Found solution file: \e[2m${sln##*/}\e[0m"

    main_project=$(grep -oE '[^"]+\.csproj' "$sln" | head -n 1)
    main_project="$dir/$main_project"
  fi

  # Step 2: If no .sln or no .csproj found, fallback to first .csproj in root
  if [[ ! -f "$main_project" ]]; then
    main_project=$(find "$dir" -maxdepth 2 -name "*.csproj" | head -n 1)
  fi
  
  if [[ ! -f "$main_project" ]]; then
    echo -e "\n❌ \e[31mNo project file (.csproj) found in the repository.\e[0m"
    echo -e "⚠️ This does not appear to be a .NET project and is currently not supported."
    return 1
  fi


  echo -e "📄 Main project: \e[36m${main_project#"$dir"/}\e[0m"

  # Extract TargetFramework(s)
  local tf_raw
  tf_raw=$(grep -oE '<TargetFrameworks?>[^<]+' "$main_project" | sed -E 's/<[^>]+>//g' | tr ';' '\n')

  if [[ -z "$tf_raw" ]]; then
    echo -e "\n⚠️  \e[33mNo TargetFramework found in:\e[0m ${main_project##*/}"
    return 1
  fi

  # Pick highest version
  local candidates=()
  while IFS= read -r v; do
    local basever
    basever=$(echo "$v" | grep -oE '[0-9]+\.[0-9]+' || true)
    [[ -n "$basever" ]] && candidates+=("$basever")
  done <<< "$tf_raw"

  if (( ${#candidates[@]} == 0 )); then
    echo -e "\n⚠️  \e[33mCould not parse any usable .NET version.\e[0m"
    return 1
  fi

  # Sort and pick highest
  mapfile -t candidates < <(printf "%s\n" "${candidates[@]}" | sort -Vu)
  version="${candidates[-1]}"

  # Output + export
  echo -e "\n🔍 Required .NET SDK version: \e[36m$version\e[0m"
  DOTNET_Version="$version"
  export DOTNET_Version
  MAIN_PROJECT_FILE="$main_project"
  export MAIN_PROJECT_FILE
  return 0
}

delete_dotnet_version() {
  local install_dir="/opt/dotnet/sdk"
  local selected

  while true; do
    local index=1
    declare -A deletable

    clear
    echo -e "\n🗑️  \e[1;31mDelete installed .NET SDK\e[0m"
    echo "═════════════════════════════════════════════════════════════"

    for dir in "$install_dir"/*; do
      [[ -d "$dir" ]] || continue
      local name
      name=$(basename "$dir")
      local basever
      basever=$(echo "$name" | cut -d'.' -f1,2)
      local used=""

      if check_apps_using_sdk "$basever"; then
        used=" (🚫 in use – cannot be deleted)"
      else
        deletable[$index]="$basever"
      fi

      printf " %d) .NET %s%s\n" "$index" "$name" "$used"
      ((index++))
    done

    if [[ "${#deletable[@]}" -eq 0 ]]; then
      echo -e "\n⚠️  No deletable SDK versions found."
      read -rsn1 -p $'\n↩️  Press any key to return...'
      return
    fi

    echo -e "\n q) 🔙 Cancel"
    echo "─────────────────────────────────────────────────────────────"
    printf "Select version number to delete: "
    IFS= read -rsn1 selected
    echo ""

    if [[ "$selected" == "q" || "$selected" == "Q" ]]; then
      return
    elif [[ "$selected" =~ ^[0-9]+$ ]] && [[ -n "${deletable[$selected]}" ]]; then
      local version="${deletable[$selected]}"

      mapfile -t matching_versions < <(find "$install_dir" -maxdepth 1 -type d -printf "%f\n" | grep -E "^$version")
      if (( ${#matching_versions[@]} == 0 )); then
        echo "⚠️  No SDKs matching version $version found."
        return 1
      fi

      echo ""
      echo "🗑️  The following .NET SDK versions will be removed:"
      echo "──────────────────────────────────────────────────────"
      for ver in "${matching_versions[@]}"; do
        printf "🧩 .NET %s\n" "$ver"
      done
      echo "──────────────────────────────────────────────────────"

      for ver in "${matching_versions[@]}"; do
        rm -rf -- "$install_dir/${ver:?}"
      done

      echo "✅ .NET SDK $version removed successfully."
      read -rsn1 -p $'\n↩️  Press any key to return...'
      return
    else
      echo "❌ Invalid selection. Please try again..."
      sleep 1
      continue
    fi
  done
}

publish_dotnet_project() {
  if [[ -z "$MAIN_PROJECT_FILE" || ! -f "$MAIN_PROJECT_FILE" ]]; then
    echo -e "\n❌ \e[31mMain project file not found.\e[0m"
    return 1
  fi

  if [[ -z "$DOTNET_Version" ]]; then
    echo -e "\n❌ \e[31mNo .NET SDK version specified.\e[0m"
    return 1
  fi

  TMP_PUBLISH_DIR="/tmp-clone/publish-${SELECTED_REPO_NAME}"
  export TMP_PUBLISH_DIR

  if [[ -d "$TMP_PUBLISH_DIR" ]]; then
    echo -e "\n♻️  Removing previous publish directory: \e[2m$TMP_PUBLISH_DIR\e[0m"
    rm -rf "$TMP_PUBLISH_DIR"
  fi

  echo -e "\n🚀 Publishing project..."
  echo -e "📄 Project: \e[36m${MAIN_PROJECT_FILE##*/}\e[0m"
  echo -e "📦 Output:  \e[2m$TMP_PUBLISH_DIR\e[0m"

  local log_file="/tmp-clone/publish-${SELECTED_REPO_NAME}.log"
  rm -f "$log_file"

  # Run publish and show a simple spinner while waiting
  (
    /opt/dotnet/dotnet publish "$MAIN_PROJECT_FILE" \
      --configuration Release \
      --output "$TMP_PUBLISH_DIR" \
      --nologo \
      --verbosity minimal
  ) >"$log_file" 2>&1 &
  local pid=$!

  local spin='-\|/'
  local i=0

  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % 4 ))
    printf "\r⏳ Publishing... %s" "${spin:$i:1}"
    sleep 0.2
  done
  printf "\r"

  wait "$pid"
  local status=$?

  if (( status != 0 )); then
    echo -e "\n❌ \e[31mPublish failed.\e[0m"
    echo -e "📜 Output from dotnet publish:\n"
    sed 's/^/   /' "$log_file"
    return 1
  fi

  echo -e "✅ Project successfully published to: \e[2m$TMP_PUBLISH_DIR\e[0m"
  return 0
}

deploy_to_nodomain_folder() {
  local base_dir="/var/www/nodomain"
  local target_dir="$base_dir/$SELECTED_REPO_NAME"
  export PUBLISH_DIR="$target_dir"

  mkdir -p "$base_dir"

  # Check if target already exists
  if [[ -d "$target_dir" ]]; then
    echo -e "\n⚠️  Deployment folder already exists: \e[2m$target_dir\e[0m"
    echo -e "  This may overwrite a currently running app.\n"
    echo -e " 1) 🛑 Stop service and overwrite"
    echo -e " 2) 🚫 Cancel deployment"
    echo -ne "\n❓ Your choice [1–2]: "
    read -r choice

    if [[ "$choice" != "1" ]]; then
      echo -e "\n↩️  Deployment cancelled by user."
      return 1
    fi

    # Stop systemd service if it exists
    local service="blazor-${SELECTED_REPO_NAME}.service"
    if systemctl list-units --type=service | grep -q "$service"; then
      echo -e "\n🛑 Stopping service: \e[36m$service\e[0m"
      systemctl stop "$service"
    fi

    echo -e "\n♻️  Removing existing directory: \e[2m$target_dir\e[0m"
    rm -rf "$target_dir"
  fi

  echo -e "\n📂 Copying published files to: \e[36m$target_dir\e[0m"
  mkdir -p "$target_dir"

  if ! cp -r "$TMP_PUBLISH_DIR"/. "$target_dir"; then
    echo -e "\n❌ \e[31mFailed to copy published files.\e[0m"
    return 1
  fi

  echo -e "✅ Files successfully copied to: \e[2m$target_dir\e[0m"

  # Restart service if it was previously installed
  local service="blazor-${SELECTED_REPO_NAME}.service"
  if systemctl list-unit-files | grep -q "$service"; then
    echo -e "🔁 Restarting service: \e[36m$service\e[0m"
    systemctl start "$service"
  fi

  return 0
}

cleanup_temp_folders() {
  echo -e "\n🧹 Cleaning up temporary folders..."

  if [[ -n "$TMP_CLONE_DIR" && -d "$TMP_CLONE_DIR" ]]; then
    echo -e "   🔻 Removing clone folder: \e[2m$TMP_CLONE_DIR\e[0m"
    rm -rf "$TMP_CLONE_DIR"
  fi

  if [[ -n "$TMP_PUBLISH_DIR" && -d "$TMP_PUBLISH_DIR" ]]; then
    echo -e "   🔻 Removing publish folder: \e[2m$TMP_PUBLISH_DIR\e[0m"
    rm -rf "$TMP_PUBLISH_DIR"
  fi

  local log_file="/tmp-clone/publish-${SELECTED_REPO_NAME}.log"
  if [[ -f "$log_file" ]]; then
    echo -e "   🗑️ Removing log file: \e[2m$log_file\e[0m"
    rm -f "$log_file"
  fi

  echo -e "✅ Temporary files cleaned up."
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

check_apps_using_sdk() {
  local version="$1"
  local root="/var/www"
  local file
  local matched=""

  while IFS= read -r file; do
    while IFS= read -r full; do
      local short
      short=$(echo "$full" | cut -d'.' -f1,2)
      if [[ "$short" == "$version" ]]; then
        matched="yes"
        break 2
      fi
    done < <(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]\+"' "$file" | cut -d'"' -f4)
  done < <(find "$root" -type f -name "*.runtimeconfig.json" 2>/dev/null)

  [[ "$matched" == "yes" ]]
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
      local used="➕ Not used"
      local disk="–       "
      local realver="–"

      if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^$ver"; then
        status="✅  Installed"
        realver=$("$install_dir/dotnet" --list-sdks | grep "^$ver" | awk '{print $1}')
        disk=$(du -sh "$install_dir/sdk"/* 2>/dev/null | grep "$ver" | awk '{sum+=$1} END{print sum " MB"}')
      fi

      if check_apps_using_sdk "$ver"; then
        used="✅ Used"
      fi

      printf " %d) .NET %-4s │ %-20s │ %-12s │ 💾 Size: %-8s │ 🔢 Version: %-15s\n" \
        $((i + 1)) "$ver" "$status" "$used" "$disk" "$realver"
    done

    echo -e "\n d) 🗑️  Delete version     q) 🔙 Back to main menu"
    echo "───────────────────────────────────────────────────────────────────────────────"
    printf "Install version [1–%d], delete [d], or quit [q]: " "${#versions[@]}"
    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      q|Q) return ;;
      d|D) delete_dotnet_version ;;
      [1-9])
        if (( choice >= 1 && choice <= ${#versions[@]} )); then
          DOTNET_Version="${versions[$((choice - 1))]}"
          export DOTNET_Version
          install_dotnet_version
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


