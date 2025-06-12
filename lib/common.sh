#!/bin/bash
set -e

load_env() {
  # 🔐 Load Cloudflare and UpCloud credentials from .env file
  local ENV_FILE="./.env"

  if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    # shellcheck disable=SC1091
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +o allexport
  else
    echo "❌ Error: Environment file '$ENV_FILE' not found."
    exit 1
  fi

  # Check required variables
  local missing=0
  for var in CLOUDFLARE_API_TOKEN CLOUDFLARE_API_BASE UPCLOUD_API_USER UPCLOUD_API_PASS UPCLOUD_API_BASE; do
    if [[ -z "${!var}" ]]; then
      echo "❌ Required variable '$var' is missing or empty in .env"
      missing=1
    fi
  done

  if [[ "$missing" -eq 1 ]]; then
    exit 1
  fi
}

get_server_ip() {
  local silent_mode=false

  if [[ "$1" == "--silent" ]]; then
    silent_mode=true
  fi

  if [[ -z "${SERVER_IPv4:-}" ]]; then
    SERVER_IPv4=$(curl -s -4 https://api.ipify.org)
  fi

  if [[ -z "${SERVER_IPv6:-}" ]]; then
    SERVER_IPv6=$(curl -s -6 https://api64.ipify.org)
  fi

  if [[ "$silent_mode" == false ]]; then
    printf "\n🌐 \033[1mServer Public IP Information:\033[0m\n"
    printf "───────────────────────────────────────────────\n"
    printf " 🌍 IPv4 Address: \033[1;36m%s\033[0m\n" "${SERVER_IPv4:-Unavailable}"
    printf " 🌐 IPv6 Address: \033[1;36m%s\033[0m\n" "${SERVER_IPv6:-Unavailable}"
  fi
}

set_timezone_to_vienna() {
  echo -e "\n🕒 \e[1mConfiguring timezone...\e[0m"

  local desired_tz="Europe/Vienna"
  local current_tz

  current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")

  if [[ "$current_tz" == "$desired_tz" ]]; then
    echo -e "✅ Timezone already set correctly: \e[1;32m$desired_tz\e[0m"
  else
    echo -e "🔄 Current timezone: \e[33m$current_tz\e[0m"
    echo -e "⚙️ Changing timezone to: \e[1;34m$desired_tz\e[0m"
    timedatectl set-timezone "$desired_tz"
    sleep 1
    echo -e "✅ Timezone successfully updated: \e[1;32m$desired_tz\e[0m"
  fi

  echo -e "🕒 Current system time: \e[36m$(date)\e[0m"
}

set_swap() {
  echo -e "\n🧮 \e[1;34mChecking swap space...\e[0m"
  echo "─────────────────────────────────────────────────────────────"

  if free | grep -q "Swap: *0"; then
    echo -e "🔧 \e[33mNo active swap detected.\e[0m"
    echo -e "📦 Creating 2 GB swap file at \e[36m/swapfile\e[0m ..."

    if fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none; then
      chmod 600 /swapfile
      mkswap /swapfile >/dev/null
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
      echo -e "✅ \e[1;32mSwap file successfully created and activated.\e[0m"
    else
      echo -e "❌ \e[1;31mFailed to create swap file.\e[0m"
    fi
  else
    echo -e "✅ \e[1;32mSwap space is already configured.\e[0m"
  fi
}

update_server() {
  echo "📦 Updating system packages (non-interactive)..."
  export DEBIAN_FRONTEND=noninteractive

  apt update
  apt -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      -y upgrade

  echo "🧹 Removing unused packages..."
  apt -y autoremove

  echo "🧼 Cleaning up cached .deb packages..."
  apt -y autoclean
}

get_project_root() {
  local i=0
  local source

  # Durchlaufe BASH_SOURCE-Stack, bis wir aus dem lib-Verzeichnis kommen
  while source="${BASH_SOURCE[$i]}"; do
    if [[ "$source" == */lib/common.sh ]]; then
      break
    fi
    ((i++)) || break
  done

  # Fallback falls nicht gefunden
  [[ -z "$source" ]] && source="${BASH_SOURCE[0]}"

  local dir
  dir="$(cd -P "$(dirname "$source")/.." >/dev/null 2>&1 && pwd)"
  echo "$dir"
}








