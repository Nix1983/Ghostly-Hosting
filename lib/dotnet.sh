#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh

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

show_app_deployment_requirements() {
  clear
  echo -e "\n📋 \e[1;34mRequirements for Deploying a New App\e[0m"
  print_double_line

  echo -e "🔐 \e[1mGitHub Access\e[0m"
  echo -e "   • GitHub repository with your app source code"
  echo -e "   • GitHub Personal Access Token with at least:"
  echo -e "     → \e[36mrepo\e[0m (to read the repository)"
  echo

  echo -e "🌐 \e[1mDomain & DNS (Cloudflare)\e[0m"
  echo -e "   • Domain managed by Cloudflare"
  echo -e "   • Cloudflare Zone ID and API Token with:"
  echo -e "     → \e[36mZone:DNS:Edit\e[0m (for DNS automation)"
  echo

  echo -e "🛠️ \e[1mSupported Frameworks\e[0m"
  echo -e "   • .NET SDK (${SUPPORTED_DOTNET_VERSIONS[*]})"
  echo -e "   • Supported project types:"
  echo -e "     → \e[32mBlazor Server\e[0m"
  echo -e "     → \e[32mASP.NET Core Web App\e[0m (MVC / Razor Pages)"
  echo

  echo -e "📁 \e[1mStructure Expectations\e[0m"
  echo -e "   • Must include a valid \e[36m.csproj\e[0m file"
  echo -e "   • Must compile using: \e[36mdotnet publish\e[0m"
  echo -e "   • Must produce an executable DLL file"
  echo

  print_double_line
  echo -e "❓ Would you like to continue with deployment?\n"
  echo -e " 1) ✅ Yes, proceed to app selection        $(print_back_to_menu)"

  read_menu_choice 1
  case "$REPLY" in
    1) return 0 ;;
    q|Q) return 2 ;;
  esac
}

detect_required_dotnet_versions() {
  local dir="${TMP_CLONE_DIR:-.}"
  local main_project=""
  local version=""

  if [[ ! -d "$dir" ]]; then
    echo -e "\n❌ \e[31mProject directory not found:\e[0m $dir"
    return 1
  fi

  # Step 1: Check for .sln and try to extract first .csproj
  local sln
  sln=$(find "$dir" -maxdepth 1 -name "*.sln" | head -n 1)

  if [[ -n "$sln" ]]; then
    echo -e "\n📘 Found solution file: \e[2m${sln##*/}\e[0m"
    main_project=$(grep -oE '[^"]+\.csproj' "$sln" | head -n 1)
    main_project="$dir/$main_project"
  fi

  # Step 2: If no .csproj from solution, fallback to first .csproj in repo
  if [[ ! -f "$main_project" ]]; then
    main_project=$(find "$dir" -maxdepth 2 -name "*.csproj" | head -n 1)
  fi

  if [[ ! -f "$main_project" ]]; then
    echo -e "\n❌ \e[31mNo project file (.csproj) found in the repository.\e[0m"
    echo -e "⚠️ This does not appear to be a valid .NET project."
    return 1
  fi

  echo -e "📄 Main project: \e[36m${main_project#"$dir"/}\e[0m"

  # Step 3: Extract TargetFramework(s)
  local tf_raw
  tf_raw=$(grep -oE '<TargetFrameworks?>[^<]+' "$main_project" | sed -E 's/<[^>]+>//g' | tr ';' '\n')

  if [[ -z "$tf_raw" ]]; then
    echo -e "\n⚠️  \e[33mNo TargetFramework found in:\e[0m ${main_project##*/}"
    return 1
  fi

  # Step 4: Parse usable versions
  local candidates=()
  while IFS= read -r line; do
    local tf="$line"
    # Accept formats like net8, net8.0, net7.0-windows etc.
    local basever
    basever=$(echo "$tf" | grep -oE 'net([0-9]+)(\.0)?' | sed -E 's/^net//;s/\.0$//')
    case "$basever" in
      [6-9]) basever="$basever.0" ;;
    esac
    [[ -n "$basever" ]] && candidates+=("$basever")
  done <<< "$tf_raw"

  if (( ${#candidates[@]} == 0 )); then
    echo -e "\n⚠️  \e[33mCould not parse any usable .NET version.\e[0m"
    return 1
  fi

  mapfile -t candidates < <(printf "%s\n" "${candidates[@]}" | sort -Vu)
  version="${candidates[-1]}"

  # Step 5: Validate against supported versions
  local is_supported=false
  for supported in "${SUPPORTED_DOTNET_VERSIONS[@]}"; do
    if [[ "$version" == "$supported" ]]; then
      is_supported=true
      break
    fi
  done

  if [[ "$is_supported" == false ]]; then
    echo -e "\n❌ \e[1;31mUnsupported .NET version detected:\e[0m \e[36m$version\e[0m"
    echo -e "✅ Supported versions are:"
    for ver in "${SUPPORTED_DOTNET_VERSIONS[@]}"; do
      echo -e "   • \e[32m$ver\e[0m"
    done
    return 1
  fi

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

deploy_to_domain_folder() {
  local folder_name
  if [[ "$HOSTNAME_FQDN" == "$DOMAIN" ]]; then
    folder_name="$DOMAIN/root"
  else
    local subdomain="${HOSTNAME_FQDN%%."$DOMAIN"}"
    folder_name="$DOMAIN/$subdomain"
  fi

  local target_dir="$APP_BASE_DIR/$folder_name"
  export PUBLISH_DIR="$target_dir"

  mkdir -p "$APP_BASE_DIR"

  if [[ -d "$target_dir" ]]; then
    echo -e "\n⚠️  \e[33mDeployment folder already exists:\e[0m \e[2m$target_dir\e[0m"
    echo -e "   This may overwrite an existing app and its services.\n"
    echo -e "1) 🗑️ Delete and redeploy"
    echo -e "2) 🔙 Cancel deployment"

    read -rsn1 -p $'\n❓ Your choice [1–2]: ' choice
    echo

    if [[ "$choice" != "1" ]]; then
      echo -e "\n↩️  Deployment cancelled by user."
      return 1
    fi

    echo -e "\n🛑 \e[1mStopping and removing related services...\e[0m"
    local escaped_folder
    escaped_folder=$(echo "$folder_name" | sed 's/\//-/g')
    local service_name="blazor-${escaped_folder}.service"
    local service_path="/etc/systemd/system/$service_name"

    if systemctl list-units --type=service | grep -q "$service_name"; then
      echo -e "   ⏹️ Stopping: \e[36m$service_name\e[0m"
      systemctl stop "$service_name"
    fi

    if systemctl is-enabled "$service_name" &>/dev/null; then
      echo -e "   ❌ Disabling: \e[36m$service_name\e[0m"
      systemctl disable "$service_name" &>/dev/null
    fi

    if [[ -f "$service_path" ]]; then
      echo -e "   🧹 Removing: \e[36m$service_path\e[0m"
      rm -f "$service_path"
    fi

    echo -e "\n♻️ Removing old deployment folder: \e[2m$target_dir\e[0m"
    rm -rf "$target_dir"
  fi

  echo -e "\n📂 Copying published files to: \e[36m$target_dir\e[0m"
  mkdir -p "$target_dir"

  if ! cp -r "$TMP_PUBLISH_DIR"/. "$target_dir"; then
    echo -e "\n❌ \e[31mFailed to copy published files.\e[0m"
    return 1
  fi

  clean_published_output "$target_dir" "$SERVICE_NAME"
  echo -e "✅ Files successfully copied to: \e[2m$target_dir\e[0m"
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

clean_published_output() {
  local dir="$1"
  local service_name="$2"

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo -e "❌ \033[31mInvalid or missing publish directory:\033[0m \033[2m$dir\033[0m"
    return 1
  fi

  local env_value="Production"
  if [[ -n "$service_name" ]]; then
    env_value=$(systemctl show "$service_name" --property=Environment | grep -oP 'DOTNET_ENVIRONMENT=\K[^ ]+' || echo "Production")
  fi

  echo -e "\n🧹 \033[1mCleaning publish folder...\033[0m (\e[36mEnvironment: $env_value\e[0m)"

  local removed=false
  local file

  mapfile -t matches < <(find "$dir" -maxdepth 1 -type f \( \
    -name "web.config" -o \
    -name "*.pdb" -o \
    -name "*.deps.json" -o \
    -name "*.runtimeconfig.dev.json" \))

  for file in "${matches[@]}"; do
    case "$(basename "$file")" in
      web.config)
        echo -e "🗑️ Removing: \e[2mweb.config\e[0m \e[33m(Only required for IIS on Windows)\e[0m"
        ;;
      *)
        echo -e "🗑️ Removing: \e[2m$(basename "$file")\e[0m"
        ;;
    esac
    rm -f "$file"
    removed=true
  done

  if [[ "$env_value" != "Development" ]]; then
    mapfile -t devfiles < <(find "$dir" -maxdepth 1 -type f -name "*Development.json")
    for file in "${devfiles[@]}"; do
      echo -e "🗑️ Removing dev config: \e[2m$(basename "$file")\e[0m"
      rm -f "$file"
      removed=true
    done
  fi

  if [[ "$removed" != true ]]; then
    echo -e "✅ Nothing to clean. All good."
  fi

  return 0
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
  done < <(find "$APP_BASE_DIR" -type f -name "*.runtimeconfig.json" 2>/dev/null)

  [[ "$matched" == "yes" ]]
}

show_dotnet_version_menu() {
  local install_dir="/opt/dotnet"

  while true; do
    clear
    echo -e "\n🧰 \e[1;34m.NET SDK Management\e[0m"
    echo "═════════════════════════════════════════════════════════════════════════════════"

    for i in "${!SUPPORTED_DOTNET_VERSIONS[@]}"; do
      local ver="${SUPPORTED_DOTNET_VERSIONS[$i]}"
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
    printf "Install version [1–%d], delete [d], or quit [q]: " "${#SUPPORTED_DOTNET_VERSIONS[@]}"
    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      q|Q) return ;;
      d|D) delete_dotnet_version ;;
      [1-9])
        if (( choice >= 1 && choice <= ${#SUPPORTED_DOTNET_VERSIONS[@]} )); then
          DOTNET_Version="${SUPPORTED_DOTNET_VERSIONS[$((choice - 1))]}"
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

create_kestrel_service() {
  declare -g KESTREL_PORT=""
  declare -g SERVICE_NAME=""
  declare -g SERVICE_PATH=""
  declare -g DOTNET_DLL=""

  for port in {5000..5099}; do
    if ! lsof -i:"$port" &>/dev/null; then
      KESTREL_PORT="$port"
      break
    fi
  done

  if [[ -z "$KESTREL_PORT" ]]; then
    echo -e "\n❌ \033[31mNo available port in range 5000–5099.\033[0m"
    return 1
  fi

  local name_base sub
  if [[ "$HOSTNAME_FQDN" == "$DOMAIN" ]]; then
    name_base="${DOMAIN//./-}"
  else
    sub="${HOSTNAME_FQDN%."$DOMAIN"}"
    name_base="${sub//./-}-${DOMAIN//./-}"
  fi

  SERVICE_NAME="${name_base}-$KESTREL_PORT.service"
  SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"

  if systemctl list-units --type=service | grep -q "$SERVICE_NAME"; then
    echo -e "\n♻️  \033[33mReplacing existing service:\033[0m \033[36m$SERVICE_NAME\033[0m"
    echo -e "   ⏹️  Stopping service..."
    systemctl stop "$SERVICE_NAME" || true
    echo -e "   ❌ Disabling service..."
    systemctl disable "$SERVICE_NAME" &>/dev/null || true
    if [[ -f "$SERVICE_PATH" ]]; then
      echo -e "   🧹 Removing: \033[2m$SERVICE_PATH\033[0m"
      rm -f "$SERVICE_PATH"
    fi
  fi

  DOTNET_DLL=$(find_dotnet_executable_dll "$PUBLISH_DIR")
  if [[ -z "$DOTNET_DLL" ]]; then
    echo -e "\n❌ \033[31mCould not detect main .dll in: $PUBLISH_DIR\033[0m"
    return 1
  fi

  local log_dir="$PUBLISH_DIR/logs"
  mkdir -p "$log_dir"
  chown -R www-data:www-data "$log_dir"
  chmod -R 755 "$log_dir"

  echo -e "\n⚙️ \033[1mCreating systemd service:\033[0m \033[36m$SERVICE_NAME\033[0m"

  {
    echo "[Unit]"
    echo "Description=Blazor App for $HOSTNAME_FQDN"
    echo "After=network.target"
    echo
    echo "[Service]"
    echo "WorkingDirectory=$PUBLISH_DIR"
    echo "ExecStart=/opt/dotnet/dotnet $PUBLISH_DIR/$DOTNET_DLL --urls=http://0.0.0.0:$KESTREL_PORT"
    echo "Restart=always"
    echo "RestartSec=10"
    echo "SyslogIdentifier=$name_base"
    echo "User=www-data"
    echo "Environment=ASPNETCORE_URLS=http://0.0.0.0:$KESTREL_PORT"
    echo "Environment=DOTNET_ENVIRONMENT=Production"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } > "$SERVICE_PATH"

  chmod 644 "$SERVICE_PATH"
  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  systemctl start "$SERVICE_NAME"

  echo -e "✅ \033[32mService started:\033[0m \033[36m$SERVICE_NAME\033[0m"
}
