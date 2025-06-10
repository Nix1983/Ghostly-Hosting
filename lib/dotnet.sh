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

  # Check if already installed
  if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^$version"; then
    echo -e "✅ .NET SDK $version is already installed in \033[36m$install_dir\033[0m"
  else
    echo -e "⬇️  Downloading and installing SDK $version ..."
    curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    chmod +x /tmp/dotnet-install.sh
    /tmp/dotnet-install.sh --channel "$version" --install-dir "$install_dir" --no-path
    echo -e "✅ Installed .NET SDK $version to $install_dir"
  fi

  # Add to profile if missing
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

setup_blazor_service() {
  local dotnet_path="/opt/dotnet"
  local hostname="$HOSTNAME_FQDN"
  local port="$KESTREL_PORT"
  local version="$DOTNET_VERSION"
  local root_domain subdomain domain_dir app_dir dll_name service_name choice appname_base

  if [[ -z "$hostname" || -z "$version" ]]; then
    echo "❌ Missing required variables: HOSTNAME_FQDN or DOTNET_VERSION."
    return 1
  fi

  # Wenn kein Port gesetzt ist, einen freien Port finden
  if [[ -z "$port" ]]; then
    echo "⚠️ No KESTREL_PORT set, finding free port..."
    port=$(find_free_kestrel_port) || {
      echo "❌ Failed to find free port"
      return 1
    }
    echo "🔹 Using port: $port"
  fi

  # Split FQDN into root domain and subdomain
  root_domain="$DOMAIN"
  if [[ "$hostname" == "$root_domain" ]]; then
    subdomain="root"
    appname_base="${root_domain%%.*}"
  else
    subdomain="${hostname%%."$root_domain"}"
    appname_base="$subdomain"
  fi

  domain_dir="/var/www/$root_domain"
  app_dir="$domain_dir/$subdomain/publish"
  mkdir -p "$app_dir"

  printf "\n📁 App directory: \033[36m%s\033[0m\n" "$app_dir"

  # Ask for DLL name
  while true; do
    echo ""
    echo "📦 Choose the name of your main DLL file (without .dll)"
    echo "────────────────────────────────────────────"
    echo " 1) Enter manually"
    echo " 2) Use domain-based name → ${appname_base//./-}.dll"
    echo "────────────────────────────────────────────"
    read -rp "❓ Your choice [1/2]: " choice

    case "$choice" in
      1)
        read -rp "✏️  Enter your DLL name (without .dll): " dll_name
        break
        ;;
      2)
        dll_name="${appname_base//./-}"
        printf "✅ Using: \033[1;32m%s.dll\033[0m\n" "$dll_name"
        break
        ;;
      *)
        echo "❌ Invalid selection. Please choose 1 or 2."
        ;;
    esac
  done

  # Generate systemd unit
  service_name="blazor-${root_domain//./-}-${subdomain}.service"
  local unit_file="/etc/systemd/system/$service_name"

  printf "\n🛠 Creating systemd service: \033[36m%s\033[0m\n" "$service_name"

  {
    echo "[Unit]"
    echo "Description=Blazor App – $hostname"
    echo "After=network.target"
    echo ""
    echo "[Service]"
    echo "WorkingDirectory=$app_dir"
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

  systemctl daemon-reexec
  systemctl daemon-reload
  systemctl enable "$service_name"
  systemctl restart "$service_name"

  printf "\n✅ Service \033[1;32m%s\033[0m has been enabled and restarted.\n" "$service_name"
  printf "➤ Check status with: \033[36msystemctl status %s\033[0m\n" "$service_name"
}