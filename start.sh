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

  echo -e "\n🚨 \e[1;31mMissing system tools detected:\e[0m \e[36m${missing_tools[*]}\e[0m"
  print_double_line
  echo -e "🧩 These tools are required for general system operations."
  echo -e "📌 \e[2mNote: This installation is only needed on first run.\e[0m"
  echo -e "📦 Installing missing components... \e[2mPlease wait\e[0m"


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

log_step() {
  echo -e "\n🔹 \e[36mRunning:\e[0m $1"
}

init_and_load_env

log_step "Loading server IP"
load_server_ip_once

log_step "Validating required environment variables"
check_required_env_or_exit

log_step "Ensuring required system tools"
ensure_required_tools_installed

log_step "Launching main menu"
main_menu

