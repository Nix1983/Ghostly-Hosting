#!/bin/bash
# shellcheck disable=SC1091

source ./lib/const.sh
source ./lib/common.sh
source ./lib/server_manager.sh
source ./lib/app_manager.sh

load_env
get_server_ip --silent

check_system_requirements_or_exit() {
  local missing=()
  local version codename
  version=$(lsb_release -ds 2>/dev/null || echo "Unknown")
  codename=$(lsb_release -cs 2>/dev/null || echo "unknown")

  # 🧪 Systempakete prüfen
  if ! apt-cache show libnginx-mod-brotli >/dev/null 2>&1; then
    missing+=("🌀 Brotli module for Nginx (libnginx-mod-brotli)")
  fi

  if ! command -v nginx >/dev/null 2>&1; then
    missing+=("🌐 Nginx (web proxy)")
  fi

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    missing+=("🛡️ Fail2Ban (security)")
  fi

  if ! command -v certbot >/dev/null 2>&1; then
    missing+=("🔐 Certbot (HTTPS via Let's Encrypt)")
  fi

  if ! command -v git >/dev/null 2>&1; then
    missing+=("🔧 Git (deployment tool)")
  fi

  # ☁️ API-Credentials prüfen
  [[ -z "$CLOUDFLARE_API_TOKEN" ]] && missing+=("☁️ CLOUDFLARE_API_TOKEN")
  [[ -z "$UPCLOUD_API_USER" ]]     && missing+=("🔑 UPCLOUD_API_USER")
  [[ -z "$UPCLOUD_API_PASS" ]]     && missing+=("🔑 UPCLOUD_API_PASS")
  [[ -z "$GITHUB_API_TOKEN" ]]     && missing+=("🐙 GITHUB_API_TOKEN")

  if (( ${#missing[@]} == 0 )); then
    return 0
  fi

  clear
  echo -e "\n🧩 \e[1;31mMissing System Requirements or API Credentials Detected\e[0m"
  print_double_line

  for item in "${missing[@]}"; do
    echo -e "❌ $item"
  done

  print_line
  echo -e "🖥️ \e[1mCurrent system:\e[0m \e[36m$version ($codename)\e[0m"

  print_line
  echo -e "💡 \e[1mDetails:\e[0m"
  [[ " ${missing[*]} " == *"libnginx-mod-brotli"* ]] && echo -e "   • Brotli is not available in Ubuntu 24.04 (Noble). Use Ubuntu 20.04 or 22.04 for support."
  [[ " ${missing[*]} " == *"CLOUDFLARE_API_TOKEN"* ]] && echo -e "   • \e[36mCLOUDFLARE_API_TOKEN\e[0m is required to manage DNS records via Cloudflare API."
  [[ " ${missing[*]} " == *"UPCLOUD_API_USER"* ]] && echo -e "   • \e[36mUPCLOUD_API_USER\e[0m is your UpCloud username to access the API."
  [[ " ${missing[*]} " == *"UPCLOUD_API_PASS"* ]] && echo -e "   • \e[36mUPCLOUD_API_PASS\e[0m is your UpCloud API password."
  [[ " ${missing[*]} " == *"GITHUB_API_TOKEN"* ]] && echo -e "   • \e[36mGITHUB_API_TOKEN\e[0m is required to clone private repositories and access repo metadata."

  echo -e "\n📍 \e[2mSet missing credentials in your .env file or export them before running this script.\e[0m"

  print_line
  echo -e "🛑 \e[1;31mCannot continue until all requirements are met.\e[0m"
  read -rsn1 -p $'\n↩️  Press any key to exit...'
  clear
  exit 1
}

main_menu() {
  local current="app" 
  while true; do
    if [[ "$current" == "server" ]]; then
      show_server_manager_menu || exit 0
      current="app"
    else
      show_app_manager_menu || exit 0
      current="server"
    fi
  done
}

check_system_requirements_or_exit
main_menu
