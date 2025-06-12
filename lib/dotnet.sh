#!/bin/bash
# shellcheck disable=SC1091

set -e

install_dotnet() {
  local install_dir="/opt/dotnet"
  local -a versions=("6.0" "7.0" "8.0" "9.0")
  local selected version status

  echo ""
  echo -e "📦 \033[1m.NET SDK Installation\033[0m"
  echo -e "────────────────────────────────────────────"

  mkdir -p "$install_dir"

  while true; do
    echo -e "\nAvailable .NET Versions:\n"

    for idx in "${!versions[@]}"; do
      version="${versions[$idx]}"
      if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^$version"; then
        status="✅ installed"
      else
        status="➕ not installed"
      fi
      printf " %2d) .NET %s\t\t%s\n" "$((idx + 1))" "$version" "$status"
    done

    echo "────────────────────────────────────────────"
    printf "❓ Your choice [1–%d]: " "${#versions[@]}"
    read -r selected

    if [[ "$selected" =~ ^[1-9][0-9]*$ ]] && ((selected >= 1 && selected <= ${#versions[@]})); then
      version="${versions[$((selected - 1))]}"
      break
    else
      echo -e "\n❌ Invalid selection. Please choose a number between 1 and ${#versions[@]}."
    fi
  done

  echo -e "\n📦 Selected version: \033[1;32m.NET $version\033[0m"

  if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^$version"; then
    echo -e "✅ .NET SDK $version is already installed in \033[36m$install_dir\033[0m"
  else
    echo -e "⬇️  Downloading and installing SDK $version ..."
    curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    /tmp/dotnet-install.sh --channel "$version" --install-dir "$install_dir" --no-path
    echo -e "✅ Installed .NET SDK $version to $install_dir"
  fi

  if ! grep -q "$install_dir" ~/.profile; then
    {
      echo ""
      echo "# .NET SDK"
      echo "export DOTNET_ROOT=$install_dir"
      echo "export PATH=\"\$DOTNET_ROOT:\$PATH\""
    } >> ~/.profile
    echo -e "🔧 Updated \033[1m~/.profile\033[0m to include .NET path"
  fi

  export DOTNET_ROOT="$install_dir"
  export PATH="$DOTNET_ROOT:$PATH"
  export DOTNET_VERSION="$version"

  echo -e "✅ \033[1m.NET SDK $version is ready to use in this session.\033[0m"
}

_get_blazor_dll_name_from_config_or_wait() {
  local app_dir="$1"
  local config_file="$app_dir/blazor-config.json"
  local max_attempts=30
  local attempt=0
  local dll_name

  if [[ -f "$config_file" ]]; then
    dll_name=$(jq -r '.dll // empty' "$config_file" 2>/dev/null)
    if [[ -n "$dll_name" ]]; then
      echo "$dll_name"
      return 0
    fi
  fi

  echo "⏳ Waiting for publish folder to contain a valid DLL..."
  while (( attempt++ < max_attempts )); do
    dll_name=$(find "$app_dir" -maxdepth 1 -type f -name "*.dll" \
      ! -name "Microsoft.*" ! -name "System.*" ! -name "App.*" ! -name "*framework*" \
      -exec basename {} .dll \; | head -n1)

    if [[ -n "$dll_name" ]]; then
      echo "$dll_name"
      return 0
    fi

    sleep 2
  done

  echo "❌ No suitable DLL found in '$app_dir' after waiting. Aborting." >&2
  return 1
}

_watch_for_blazor_dll_update() {
  local app_dir="$1"
  local service_name="$2"
  local dotnet_path="$3"
  local new_dll

  echo "⏳ Watching for new DLL in: $app_dir"
  while true; do
    new_dll=$(find "$app_dir" -maxdepth 1 -type f -name "*.dll" \
      ! -name "Microsoft.*" ! -name "System.*" ! -name "App.*" ! -name "*framework*" \
      -exec basename {} .dll \; | grep -v "__waiting__" | head -n1)

    if [[ -n "$new_dll" ]]; then
      echo "✅ Detected real DLL: $new_dll – updating systemd unit..."

      sed -i "s|ExecStart=.*|ExecStart=$dotnet_path/dotnet $new_dll.dll|" "/etc/systemd/system/$service_name"
      systemctl daemon-reload
      systemctl restart "$service_name"

      echo "🔁 Service restarted with real DLL: $new_dll.dll"
      break
    fi

    sleep 2
  done
}

setup_blazor_service() {
  local dotnet_path="/opt/dotnet"
  local hostname="$HOSTNAME_FQDN"
  local port="$KESTREL_PORT"
  local version="$DOTNET_VERSION"
  local root_domain subdomain domain_dir app_dir dll_name service_name unit_file

  if [[ -z "$hostname" || -z "$version" ]]; then
    echo "❌ Missing required variables: HOSTNAME_FQDN or DOTNET_VERSION."
    return 1
  fi

  if [[ -z "$port" ]]; then
    echo "⚠️ No KESTREL_PORT set, finding free port..."
    port=$(find_free_kestrel_port) || {
      echo "❌ Failed to find free port"
      return 1
    }
    echo "🔹 Using port: $port"
  fi

  root_domain="$DOMAIN"
  if [[ "$hostname" == "$root_domain" ]]; then
    subdomain="root"
  else
    subdomain="${hostname%%."$root_domain"}"
  fi

  domain_dir="/var/www/$root_domain"
  app_dir="$domain_dir/$subdomain"
  mkdir -p "$app_dir"

  printf "\n📁 App directory: \033[36m%s\033[0m\n" "$app_dir"

  dll_name=$(_get_blazor_dll_name_from_config_or_wait "$app_dir")
  if [[ -z "$dll_name" ]]; then
    echo "⚠️ No DLL found – setting up dummy placeholder."
    dll_name="__waiting__"
  else
    echo -e "✅ Using detected DLL: \033[1;32m$dll_name.dll\033[0m"
  fi

  service_name="blazor-${root_domain//./-}-${subdomain}.service"
  unit_file="/etc/systemd/system/$service_name"

  printf "\n🛠 Creating systemd service: \033[36m%s\033[0m\n" "$service_name"

  {
    echo "[Unit]"
    echo "Description=Blazor App – $hostname"
    echo "After=network.target"
    echo ""
    echo "[Service]"
    echo "WorkingDirectory=$app_dir"
    echo "Environment=HOME=$app_dir"
    echo "Environment=ASPNETCORE_URLS=http://localhost:$port"
    echo "ExecStart=$dotnet_path/dotnet $dll_name.dll"
    echo "Restart=always"
    echo "RestartSec=10"
    echo "User=www-data"
    echo "SyslogIdentifier=blazor-${subdomain}"
    echo "Environment=ASPNETCORE_ENVIRONMENT=Production"
    echo ""
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } > "$unit_file"

  chown -R www-data:www-data "$domain_dir"
  chmod -R u+rwX "$domain_dir"

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable "$service_name"
  systemctl restart "$service_name"

  printf "\n✅ Service \033[1;32m%s\033[0m has been enabled and restarted.\n" "$service_name"
  printf "➤ Check status with: \033[36msystemctl status %s\033[0m\n" "$service_name"

  # Start watcher in background if dummy DLL was used
  if [[ "$dll_name" == "__waiting__" ]]; then
    watch_for_blazor_dll_update "$app_dir" "$service_name" "$dotnet_path" &
  fi
}

