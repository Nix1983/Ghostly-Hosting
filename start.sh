#!/bin/bash
# shellcheck disable=SC1091

source ./lib/const.sh
source ./lib/common.sh
source ./lib/server_manager.sh
source ./lib/app_manager.sh


ensure_required_tools_installed() {
  local -a required_tools=(jq curl grep cut xargs)
  local -a missing_tools=()
  local tool

  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done

  if [[ ${#missing_tools[@]} -eq 0 ]]; then
    return 0
  fi

  echo -e "\n❌ \e[1mMissing required tools on this server:\e[0m \e[36m${missing_tools[*]}\e[0m"
  echo -e "💡 These tools are essential for API calls and JSON parsing."
  echo -ne "📦 Installing missing packages... \e[2mPlease wait\e[0m "

  # Spinner anzeigen
  local pid spinner i
  (
    apt-get update -qq >/dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing_tools[@]}" >/dev/null 2>&1
  ) &
  pid=$!
  spinner=("/" "-" "\\" "|")
  i=0
  while kill -0 "$pid" 2>/dev/null; do
    printf "\b%s" "${spinner[i]}"
    i=$(( (i + 1) % 4 ))
    sleep 0.1
  done
  wait "$pid"
  local exit_code=$?

  printf "\b"

  if [[ $exit_code -eq 0 ]]; then
    echo -e " ✅\n\e[32mAll required tools installed successfully.\e[0m"
  else
    echo -e " ❌\n\e[31mFailed to install required tools:\e[0m \e[36m${missing_tools[*]}\e[0m"
    exit 1
  fi
}

check_system_version_or_warn() {
  local version codename major_version
  version=$(lsb_release -ds 2>/dev/null || echo "Unknown")
  codename=$(lsb_release -cs 2>/dev/null || echo "unknown")
  major_version=$(lsb_release -rs 2>/dev/null | cut -d. -f1)

  if [[ "$codename" == "focal" ]]; then
    clear
    echo -e "\n📦 \e[1;33mLegacy Ubuntu Version Detected\e[0m"
    print_double_line
    echo -e "⚠️  \e[1mUbuntu $version ($codename) is outdated and no longer supported.\e[0m"
    echo -e "   • Brotli support is unavailable in official Nginx packages."
    echo -e "   • Performance enhancements may be missing."
    print_line
    echo -e "💡 \e[1mRecommended:\e[0m"
    echo -e "   • Use \e[32mUbuntu 22.04 LTS (Jammy)\e[0m for full support"
    echo -e "   • Or use \e[36mUbuntu 24.04 LTS (Noble)\e[0m – Brotli support coming soon"
    print_line
    read -rsn1 -p $'\n↩️  Press any key to exit...'
    clear
    exit 1
  fi

  if [[ "$major_version" -ge 24 ]]; then
     clear
     echo -e "\n📦 \e[1;33mNote: Limited Brotli Support on Ubuntu $version ($codename)\e[0m"
     print_double_line
     echo -e "⚠️  \e[1mBrotli compression is not available yet on this system.\e[0m"
     echo -e "   • Standard Gzip will be used temporarily."
     echo -e "   • Brotli module will be supported as soon as packaging is updated."
     print_line
     echo -e "💡 \e[1mYou have two options:\e[0m"
     echo -e "   • Wait for Brotli support in Ubuntu $codename and enable it later"
     echo -e "   • Use \e[32mUbuntu 22.04 LTS (Jammy)\e[0m for full Brotli support now"
     print_line
     read -rsn1 -p $'\n↩️  Press any key to continue...'
   fi

}

check_required_env_or_exit() {
  local version codename
  version=$(lsb_release -ds 2>/dev/null || echo "Unknown")
  codename=$(lsb_release -cs 2>/dev/null || echo "unknown")

  local missing_env=()
  [[ -z "$CLOUDFLARE_API_TOKEN" ]] && missing_env+=("CLOUDFLARE_API_TOKEN")
  [[ -z "$UPCLOUD_API_USER" ]]     && missing_env+=("UPCLOUD_API_USER")
  [[ -z "$UPCLOUD_API_PASS" ]]     && missing_env+=("UPCLOUD_API_PASS")
  [[ -z "$GITHUB_API_TOKEN" ]]     && missing_env+=("GITHUB_API_TOKEN")

  if (( ${#missing_env[@]} > 0 )); then
    clear
    echo -e "\n🧩 \e[1;31mMissing Required API Credentials\e[0m"
    print_double_line
    for var in "${missing_env[@]}"; do
      case "$var" in
        CLOUDFLARE_API_TOKEN) echo -e "❌ ☁️ CLOUDFLARE_API_TOKEN" ;;
        UPCLOUD_API_USER)     echo -e "❌ 🔑 UPCLOUD_API_USER" ;;
        UPCLOUD_API_PASS)     echo -e "❌ 🔑 UPCLOUD_API_PASS" ;;
        GITHUB_API_TOKEN)     echo -e "❌ 🐙 GITHUB_API_TOKEN" ;;
      esac
    done
    print_line
    echo -e "🖥️ \e[1mCurrent system:\e[0m \e[36m$version ($codename)\e[0m"
    print_line
    echo -e "💡 \e[1mExplanation:\e[0m"
    for var in "${missing_env[@]}"; do
      case "$var" in
        CLOUDFLARE_API_TOKEN)
          echo -e "   • Required for managing DNS and HTTPS certificates via Cloudflare."
          ;;
        UPCLOUD_API_USER)
          echo -e "   • Required to manage UpCloud firewall, PTR records, and more."
          ;;
        UPCLOUD_API_PASS)
          echo -e "   • Your UpCloud API password to authenticate requests."
          ;;
        GITHUB_API_TOKEN)
          echo -e "   • Needed to access private GitHub repositories and automate deployments."
          ;;
      esac
    done
    echo -e "\n📍 \e[2mSet these values in your .env file.\e[0m"
    print_line
    echo -e "🛑 \e[1;31mSetup cannot continue without these.\e[0m"
    read -rsn1 -p $'\n↩️  Press any key to exit...'
    clear
    exit 1
  fi
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

load_env_once
load_server_ip_once
check_system_version_or_warn
check_required_env_or_exit
ensure_required_tools_installed
main_menu
