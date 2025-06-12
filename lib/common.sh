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

show_server_health() {
  clear

  local tools=(hostname uptime ip curl grep awk sed free df systemctl apt lsb_release)
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo -e "❌ \e[31mMissing required tool:\e[0m $tool"
      return 1
    fi
  done

  # System Info
  local kernel os uptime boot time_zone
  kernel=$(uname -r)
  os=$(lsb_release -ds 2>/dev/null || grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
  uptime=$(uptime -p | sed 's/^/ /')
  boot=$(who -b | awk '{print $3, $4}')
  time_zone=$(date +'%Z (UTC %:::z)')

  # Network
  local ip_local ip_external gateway dns
  ip_local=$(hostname -I | awk '{print $1}')
  ip_external=$(curl -s https://api.ipify.org || echo "unavailable")
  gateway=$(ip route | awk '/default/ {print $3}')
  dns=$(grep 'nameserver' /etc/resolv.conf | awk '{print $2}' | paste -sd ',' -)

  # Memory (in MB)
  read -r _ mem_total mem_used mem_free _ mem_cache _ <<< \
    "$(free -m | awk '/^Mem:/ {print $1, $2, $3, $4, $5, $6, $7}')"
  local mem_usage_pct=$((100 * mem_used / mem_total))

  read -r _ swap_total swap_used swap_free <<< \
    "$(free -m | awk '/^Swap:/ {print $1, $2, $3, $4}')"
  local swap_usage_pct=0
  [[ "$swap_total" -gt 0 ]] && swap_usage_pct=$((100 * swap_used / swap_total))

  # Disk (in GB)
  read -r d_total d_used d_free d_perc <<< \
    "$(df -m / | awk 'NR==2 {print $2, $3, $4, $5}')"
  d_total=$((d_total / 1024))
  d_used=$((d_used / 1024))
  d_free=$((d_free / 1024))

  # CPU Load
  read -r load1 load5 load15 <<< \
    "$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//' | tr ',' ' ')"

  # Updates
  local updates_output updates_count
  updates_output=$(apt list --upgradable 2>/dev/null || true)
  updates_count=$(echo "$updates_output" | grep -vc "Listing..." || echo 0)

  # Services
  local services=(postfix ngnix)
  local service_line=""
  for svc in "${services[@]}"; do
    local icon="❌"
    if systemctl is-active "$svc" &>/dev/null; then
      icon="✅"
    fi
    service_line+="${svc} ${icon}   "
  done

  # Output
  echo -e "\e[1m🩺 Server Health Summary\e[0m"
  echo "════════════════════════════════════════════════════════════════════════════════════════════"
  printf "🖥️ %-13s %s\n" "Kernel:"       "$kernel"
  printf "🧾 %-13s %s\n" "OS:"           "$os"
  printf "⏳ %-12s %s\n" "Uptime:"       "$uptime"
  printf "♻️ %-13s %s\n" "Last boot:"    "$boot"
  printf "🕒 %-13s %s\n" "Time zone:"    "$time_zone"

  echo "────────────────────────────────────────────────────────────────────────────────────────────"
  printf "📡 %-13s %s\n" "Internal IP:"   "$ip_local"
  printf "🌍 %-13s %s\n" "External IP:"   "$ip_external"
  printf "🚪 %-13s %s\n" "Gateway:"       "$gateway"
  printf "🔎 %-13s %s\n" "DNS servers:"   "$dns"

  echo "────────────────────────────────────────────────────────────────────────────────────────────"
  printf "🧠 %-13s Total: %4sMB | Used: %4sMB | Free: %4sMB | Cache: %4sMB     Usage: %3s%%\n" \
    "RAM:" "$mem_total" "$mem_used" "$mem_free" "$mem_cache" "$mem_usage_pct"
  printf "📥 %-13s Total: %4sMB | Used: %4sMB | Free: %4sMB                     Usage: %3s%%\n" \
    "SWAP:" "$swap_total" "$swap_used" "$swap_free" "$swap_usage_pct"

  echo "────────────────────────────────────────────────────────────────────────────────────────────"
  printf "💾 %-13s Total: %2sG    | Used: %2sG    | Free: %2sG                        Usage:  %3s\n" \
    "Disk (/):" "$d_total" "$d_used" "$d_free" "$d_perc"
  printf "⚙️ %-13s 1 min: %s   | 5 min: %s  | 15 min: %s\n" \
    "CPU Load:" "$load1" "$load5" "$load15"
  printf "📦 %-13s %s\n" "Pending Updates:" "$updates_count"

  echo "────────────────────────────────────────────────────────────────────────────────────────────"
  echo -e "\e[1m🔌 Services:\e[0m"
  echo "   $service_line"
  echo "════════════════════════════════════════════════════════════════════════════════════════════"
  echo ""
}

set_swap() {
  if free | grep -q "Swap: *0"; then
    echo "🔧 No swap found – creating 2 GB swap file..."
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "✅ Swap file created and activated."
  else
    echo "✅ Swap is already present. No action required."
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