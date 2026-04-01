#!/bin/bash
# shellcheck disable=SC1091
source ./lib/const.sh
source ./lib/common.sh
source ./lib/server_manager.sh
source ./lib/app_manager.sh
source ./lib/upcloud.sh
source ./lib/github.sh

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

  # Display spinner
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
    i=$(((i + 1) % 4))
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

init_and_load_env() {
  if [[ -n "${__ENV_LOADED_ALREADY:-}" ]]; then
    return 0
  fi

  CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostly-hosting"
  ENV_FILE="$CONFIG_DIR/.env.secure"
  mkdir -p "$CONFIG_DIR"

  # Migrate from old .env to .env.secure
  if [[ -f "$CONFIG_DIR/.env" ]] && [[ ! -f "$ENV_FILE" ]]; then
    echo "🔄 Migrating configuration to new format..."
    mv "$CONFIG_DIR/.env" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "✅ Migration complete"
  fi

  local updated=false
  local upcloud_ok=false github_ok=false cloudflare_ok=false

  if [[ ! -f "$ENV_FILE" ]]; then
    clear
    echo -e "\e[1;36m👻 Welcome to GhostlyHosting — Effortless .NET Self-Hosting\e[0m"
    print_double_line
    echo -e "💡 Host unlimited .NET apps for just \e[1m\$3/month\e[0m on \e[35mUpCloud\e[0m"
    echo -e "🔄 \e[1;33mGitHub-integrated deployments\e[0m — auto-update from your repo"
    echo -e "☁️ HTTPS, DNS & secure proxy via \e[38;5;117mCloudflare\e[0m (DDoS & caching included)"
    echo -e "🛡️ Built-in firewall, PTR setup & uptime monitoring"
    echo -e "🔁 One-command app updates & rollbacks (commit-based)"
    echo -e "💾 Minimal encrypted backups — fast, compact, restorable"
    echo -e "🔒 All credentials are \e[38;5;28msecurely stored\e[0m and stay on your server"
    print_line
    echo -e "🚀 \e[1mThis setup only runs once.\e[0m"
    echo -e "   Your server will now be fully prepared for secure .NET hosting."
    echo -e "   Just a few questions, and everything will be ready."
    print_line
    echo -e "\n⏎ Press Enter to get started..."
    read -r
  fi

  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" 2>/dev/null || true && set +a

  # Check UpCloud
  if ! validate_upcloud_token "${UPCLOUD_API_TOKEN:-}"; then
    while true; do
      clear
      echo -e "\e[1;35m🟣 UpCloud API Setup\e[0m"
      print_double_line
      echo -e "🔧 Used to:"
      echo -e "   • Create and manage \e[1mfirewall rules\e[0m"
      echo -e "   • Configure \e[1mPTR (reverse DNS)\e[0m records"
      echo -e "   • Identify your account for deployments"
      echo
      echo -e "💡 UpCloud uses \e[1musername:password\e[0m Basic authentication"
      echo -e "   Enter your UpCloud account email and password below"
      echo -en "🔗 Sign up at: "
      echo -e "\e]8;;https://signup.upcloud.com/?promo=AW9TF8\e\\UpCloud.com\e]8;;\e\\ 🡕"
      print_line

      read -rsp "🔑 Enter UpCloud credentials (email:password): " UPCLOUD_API_TOKEN && echo

      if validate_upcloud_token "$UPCLOUD_API_TOKEN"; then
        upcloud_ok=true
        updated=true
        break
      fi

      echo -e "\n❌ \e[31mAuthentication failed – invalid UpCloud credentials.\e[0m"
      echo -e "📝 \e[2mFormat must be: email:password (e.g. user@example.com:mypassword)\e[0m"
      echo -e "🔐 \e[2mWithout valid credentials, hosting features cannot be used.\e[0m"
      sleep 1
    done
  else
    upcloud_ok=true
  fi

  # Check GitHub
  if ! validate_github_token "${GITHUB_API_TOKEN:-}" "$GITHUB_API_BASE"; then
    while true; do
      clear
      echo -e "\e[1;33m🐙 GitHub API Setup\e[0m"
      print_double_line
      echo -e "🔧 Used to:"
      echo -e "   • \e[1mDeploy apps\e[0m directly from repositories"
      echo -e "   • \e[1mAuto-update\e[0m using commit detection"
      echo -e "   • Manage \e[1mbackups tied to commits\e[0m for easy rollback"
      echo
      echo -e "🔐 Recommended scopes:"
      echo -e "   • repo"
      echo -e "   • read:org  \e[2m(optional, if using org repos)\e[0m"
      echo -en "🔗 Generate token at: "
      echo -e "\e]8;;https://github.com/settings/tokens\e\\GitHub Page\e]8;;\e\\ 🡕"
      print_line

      read -rp "🔑 Enter GitHub API Token: " GITHUB_API_TOKEN

      if validate_github_token "$GITHUB_API_TOKEN" "$GITHUB_API_BASE"; then
        github_ok=true
        updated=true
        break
      fi

      echo -e "\n❌ \e[31mInvalid GitHub token – access denied.\e[0m"
      echo -e "🔐 \e[2mWithout this token, deployments are not possible.\e[0m"
      sleep 1
    done
  else
    github_ok=true
  fi

  # Check Cloudflare
  if ! validate_cloudflare_token "${CLOUDFLARE_API_TOKEN:-}"; then
    while true; do
      clear
      echo -e "\e[1;34m☁️  Cloudflare API Setup\e[0m"
      print_double_line
      echo -e "🔧 Used to:"
      echo -e "   • Manage \e[1mDNS records\e[0m automatically"
      echo -e "   • Enable HTTPS using \e[1mLet's Encrypt\e[0m"
      echo -e "   • Activate Cloudflare \e[1mproxy mode\e[0m for extra security"
      echo
      echo -e "🛡️  Benefits:"
      echo -e "   • \e[1mFree\e[0m DDoS protection & global CDN"
      echo -e "   • \e[1mHTTPS without open ports\e[0m"
      echo
      echo -e "🔐 Recommended token scopes:"
      echo -e "   • Zone:DNS:Edit"
      echo -e "   • Zone:Zone:Read"
      echo -en "🔗 Create token at: "
      echo -e "\e]8;;https://dash.cloudflare.com/profile/api-tokens\e\\Cloudflare Page\e]8;;\e\\ 🡕"
      print_line

      read -rp "🔑 Enter Cloudflare API Token: " CLOUDFLARE_API_TOKEN

      if validate_cloudflare_token "$CLOUDFLARE_API_TOKEN"; then
        cloudflare_ok=true
        updated=true
        break
      fi

      echo -e "\n❌ \e[31mInvalid Cloudflare token – access denied.\e[0m"
      echo -e "🔐 \e[2mWithout this token, DNS & SSL setup cannot work.\e[0m"
      sleep 2
    done
  else
    cloudflare_ok=true
  fi

  if [[ "$updated" == true ]]; then
    {
      echo "CLOUDFLARE_API_TOKEN=\"$CLOUDFLARE_API_TOKEN\""
      echo "UPCLOUD_API_TOKEN=\"$UPCLOUD_API_TOKEN\""
      echo "GITHUB_API_TOKEN=\"$GITHUB_API_TOKEN\""
    } >"$ENV_FILE"
    chmod 600 "$ENV_FILE"

    echo -e "\n✅ \e[1;32mYour configuration has been saved securely.\e[0m"
    echo -e "📁 Stored at: \e[2m$ENV_FILE\e[0m"
    echo -en "\n"
    [[ "$upcloud_ok" == true ]] && echo -en "🟢 UpCloud\t" || echo -en "🔴 UpCloud\t"
    [[ "$github_ok" == true ]] && echo -en "🟢 GitHub\t" || echo -en "🔴 GitHub\t"
    [[ "$cloudflare_ok" == true ]] && echo -en "🟢 Cloudflare\n" || echo -en "🔴 Cloudflare\n"
    echo -e "\n⏎ Press Enter to continue..."
    read -r
  fi

  __ENV_LOADED_ALREADY=1
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

ensure_required_tools_installed

init_and_load_env

load_server_ip_once

main_menu
