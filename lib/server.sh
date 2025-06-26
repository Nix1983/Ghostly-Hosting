#!/bin/bash
# shellcheck disable=SC1091
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh
source ./lib/print.sh
source ./lib/upcloud.sh
source ./lib/fail2ban.sh
source ./lib/github.sh
source ./lib/timezone.sh

show_server_health() {
  clear

  local tools=(hostname uptime ip curl grep awk sed free df systemctl apt lsb_release timedatectl)
  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo -e "❌ \e[31mMissing required tool:\e[0m $tool"
      return 1
    fi
  done

  # System Info
  local kernel os uptime boot time_zone_name time_zone_offset
  kernel=$(uname -r)
  os=$(lsb_release -ds 2>/dev/null || grep '^PRETTY_NAME=' /etc/os-release | cut -d= -f2- | tr -d '"')
  uptime=$(uptime -p | sed 's/^/ /')
  boot=$(who -b | awk '{print $3, $4}')
  time_zone_name=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "Unknown")
  time_zone_offset=$(date +'%Z (UTC %:::z)')

  # Network
  local ip_local ip_external gateway dns
  ip_local=$(hostname -I | awk '{print $1}')
  ip_external=$(curl -s https://api.ipify.org || echo "unavailable")
  gateway=$(ip route | awk '/default/ {print $3}')
  dns=$(grep 'nameserver' /etc/resolv.conf | awk '{print $2}' | paste -sd ',' -)

  # Memory (in MB)
  read -r _ mem_total mem_used mem_free _ mem_cache _ <<< "$(free -m | awk '/^Mem:/ {print $1, $2, $3, $4, $5, $6, $7}')"
  local mem_usage_pct=$((100 * mem_used / mem_total))

  read -r _ swap_total swap_used swap_free <<< "$(free -m | awk '/^Swap:/ {print $1, $2, $3, $4}')"
  local swap_usage_pct=0
  [[ "$swap_total" -gt 0 ]] && swap_usage_pct=$((100 * swap_used / swap_total))

  # Disk (in GB mit 2 Nachkommastellen)
  read -r d_total_kb d_used_kb d_free_kb d_perc <<< "$(df -k / | awk 'NR==2 {print $2, $3, $4, $5}')"
  d_total=$(awk "BEGIN {printf \"%.2f\", $d_total_kb / 1024 / 1024}")
  d_used=$(awk "BEGIN {printf \"%.2f\", $d_used_kb / 1024 / 1024}")
  d_free=$(awk "BEGIN {printf \"%.2f\", $d_free_kb / 1024 / 1024}")

  # CPU Load
  read -r load1 load5 load15 <<< "$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//' | tr ',' ' ')"

  # Updates
  local updates_output updates_count
  updates_output=$(apt list --upgradable 2>/dev/null || true)
  updates_output=$(apt list --upgradable 2>/dev/null || true)
  updates_count=$(echo "$updates_output" | grep -vc "Listing...") || updates_count=0

  # Services
  local services=(fail2ban nginx ssh systemd-timesyncd certbot.timer git)
  local service_line=""

  for svc in "${services[@]}"; do
    local icon="❌"
    if [[ "$svc" == "git" ]]; then
      command -v git >/dev/null 2>&1 && icon="✅"
    else
      if systemctl list-unit-files | grep -q "^$svc"; then
        if systemctl is-active "$svc" &>/dev/null; then
          icon="✅"
        elif systemctl is-enabled "$svc" &>/dev/null; then
          icon="⚠️"
        fi
      fi
    fi
    service_line+="$svc $icon   "
  done

  # Output
  echo -e "\e[1m🩺 Server Health Summary\e[0m"
  print_double_line
  printf "🖥️ %-13s \e[36m%s\e[0m\n" "Kernel:" "$kernel"
  printf "🧾 %-13s \e[36m%s\e[0m\n" "OS:" "$os"
  printf "⏳ %-12s \e[36m%s\e[0m\n" "Uptime:" "$uptime"
  printf "♻️ %-13s \e[36m%s\e[0m\n" "Last boot:" "$boot"
  printf "🕒 %-13s \e[36m%s\e[0m  \e[2m(%s)\e[0m\n" "Time zone:" "$time_zone_name" "$time_zone_offset"

  print_line
  printf "📡 %-13s \e[36m%s\e[0m\n" "Internal IP:" "$ip_local"
  printf "🌍 %-13s \e[36m%s\e[0m\n" "External IP:" "$ip_external"
  printf "🚪 %-13s \e[36m%s\e[0m\n" "Gateway:" "$gateway"
  printf "🔎 %-13s \e[36m%s\e[0m\n" "DNS servers:" "$dns"

  print_line
  printf "🧠 %-13s Total: \e[36m%4sMB\e[0m | Used: \e[33m%4sMB\e[0m | Free: \e[32m%4sMB\e[0m | Cache: \e[2m%4sMB\e[0m     Usage: \e[1m%3s%%\e[0m\n" \
    "RAM:" "$mem_total" "$mem_used" "$mem_free" "$mem_cache" "$mem_usage_pct"
  printf "📥 %-13s Total: \e[36m%4sMB\e[0m | Used: \e[33m%4sMB\e[0m | Free: \e[32m%4sMB\e[0m                     Usage: \e[1m%3s%%\e[0m\n" \
    "SWAP:" "$swap_total" "$swap_used" "$swap_free" "$swap_usage_pct"

  print_line
  printf "💾 %-13s Total: \e[36m%5sG\e[0m | Used: \e[33m%5sG\e[0m | Free: \e[32m%5sG\e[0m                     Usage:  \e[1m%3s\e[0m\n" \
    "Disk (/):" "$d_total" "$d_used" "$d_free" "$d_perc"
  printf "⚙️ %-13s 1 min:   \e[36m%s\e[0m | 5 min:  \e[36m%s\e[0m | 15 min: \e[36m%s\e[0m\n" \
    "CPU Load:" "$load1" "$load5" "$load15"
  printf "📦 %-13s \e[36m%s\e[0m\n" "Pending Updates:" "$updates_count"

  print_line
  echo -e "\e[1m🔌 Services:\e[0m"
  echo -e "   $service_line"
  print_double_line
  echo ""
}

check_and_offer_reboot() {
  if [[ -f /var/run/reboot-required ]]; then
    echo -e "\n🔁 \e[1;31mReboot required\e[0m"
    echo -e "\n⚠️ \e[1mYour system requires a reboot to complete updates.\e[0m"
    echo -e "🔌 SSH connection will be lost temporarily during reboot."
    echo -e "⏳ Wait ~\e[36m60 seconds\e[0m and reconnect manually after reboot."

    echo -e "\n❓ \e[1mWhat do you want to do?\e[0m"
    print_line
    echo -e " 1) ♻️  Reboot now    q) ⏭️  Skip reboot (you can run \e[36mreboot\e[0m manually later)"
    
    read_menu_choice 1

    case "$REPLY" in
      1)
        echo -e "\n♻️  Rebooting system..."
        sleep 2
        reboot
        exit 0
        ;;
      q|Q)
        ;;
    esac
  else
    echo -e "🔁 Reboot required: \e[1;32mNo\e[0m"
  fi
}

update_server_and_show_status() {
  clear
  echo -e "\n🔄 \e[1;34mSystem Update – Ubuntu Package Manager (APT)\e[0m"
  print_double_line

  echo -e "\n🛰️ \e[1mUpdating APT sources ...\e[0m"
  apt-get update -y >/dev/null 2>&1 && echo "✅ Package list updated." || echo "❌ Failed to update package list."

  echo -e "\n📦 \e[1mUpgrading installed packages ...\e[0m"
  apt-get -o Dpkg::Options::="--force-confdef" \
           -o Dpkg::Options::="--force-confold" \
           -y upgrade | tee /tmp/apt-upgrade.log | grep -E "upgraded|newly installed|removed" || echo "✅ All packages already up-to-date."

  echo -e "\n🧼 \e[1mCleaning up system ...\e[0m"
  apt-get -y autoremove >/dev/null 2>&1 && echo "✅ Unused packages removed."
  apt-get -y autoclean >/dev/null 2>&1 && echo "✅ Package cache cleaned."

  echo -e "\n🧠 \e[1mSystem Status\e[0m"
  print_line

  local kernel version
  kernel=$(uname -r)
  version=$(lsb_release -ds 2>/dev/null || echo "Unknown")

  echo -e "💻 OS Version:      \e[36m$version\e[0m"
  echo -e "🧬 Kernel:          \e[36m$kernel\e[0m"

  local pending_updates
  pending_updates=$(apt list --upgradable 2>/dev/null)

  # Check nginx
  if dpkg -l | grep -E "^ii" | grep -qw nginx; then
    if echo "$pending_updates" | grep -q "^nginx/"; then
      echo -e "🌐 Nginx:           \e[33mUpdate available\e[0m"
    else
      echo -e "🌐 Nginx:           \e[32mUp to date\e[0m"
    fi
  else
    echo -e "🌐 Nginx:           \e[2mNot installed\e[0m"
  fi

  # Check fail2ban
  if dpkg -l | grep -E "^ii" | grep -qw fail2ban; then
    if echo "$pending_updates" | grep -q "^fail2ban/"; then
      echo -e "🛡️ Fail2Ban:        \e[33mUpdate available\e[0m"
    else
      echo -e "🛡️ Fail2Ban:        \e[32mUp to date\e[0m"
    fi
  else
    echo -e "🛡️ Fail2Ban:        \e[2mNot installed\e[0m"
  fi

  # Check git (via command -v für echte Funktionsprüfung)
  if command -v git >/dev/null 2>&1; then
    if echo "$pending_updates" | grep -q "^git/"; then
      echo -e "🔧 Git:             \e[33mUpdate available\e[0m"
    else
      echo -e "🔧 Git:             \e[32mUp to date\e[0m"
    fi
  else
    echo -e "🔧 Git:             \e[2mNot installed\e[0m"
  fi

  echo -e "\n✅ \e[1mSystem update completed.\e[0m"
  print_line
  read -rsn1 -p $'\nPress any key to return to menu...'
}

show_init_server_prompt() {
  clear
  echo -e "\n🚀 \e[1;34mInitialize Server for Blazor Hosting\e[0m"
  print_double_line

  echo -e "\n📋 \e[1mThe following components will be installed and configured:\e[0m"
  print_line
  echo -e " 🌐 Nginx (Reverse Proxy)"
  echo -e " 🛡️ Fail2Ban (SSH protection)"
  echo -e " 🔐 Certbot (HTTPS / Let's Encrypt)"
  echo -e " 🔧 Git (for deployment)"
  echo -e " 🕒 Timezone will be set to Europe/Vienna"
  echo -e " 📦 Swap file for memory management"
  echo -e " ☁️ UpCloud firewall rules will be applied"
  echo -e " 📈 System update and package upgrade"
  print_line
  echo -e "💡 \e[3mYou can add apps after this setup is completed.\e[0m"

  echo -e "\n❓ \e[1mDo you want to initialize the server now?\e[0m"
  echo -e "\n 1) ✅ Yes, proceed with initialization  $(print_back_to_menu)"

  read_menu_choice 1

  if [[ "$REPLY" != "1" ]]; then
    return 1
  fi

  return 0
}

init_server() {
  clear
  echo -e "\n🚀 \e[1;34mInitialize Server for .NET Hosting\e[0m"
  print_double_line
  
  echo -e "\n🌐 \e[1mInstalling Nginx (Reverse Proxy)...\e[0m"
  if ! command -v nginx >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1
    if apt-get install -y nginx >/dev/null 2>&1; then
      echo "✅ Nginx installed."
    else
      echo -e "❌ \e[31mFailed to install Nginx – aborting setup.\e[0m"
      exit 1
    fi
  else
    echo "✅ Nginx is already installed."
  fi

  echo -e "\n🔌 \e[1mEnabling and starting Nginx...\e[0m"
  if systemctl enable nginx >/dev/null 2>&1 && systemctl start nginx >/dev/null 2>&1; then
    echo "✅ Nginx service is running."
  else
    echo -e "❌ \e[31mFailed to start or enable Nginx.\e[0m"
    exit 1
  fi

  echo -e "\n🛡️ \e[1mInstalling Fail2Ban (security)...\e[0m"
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    if apt-get install -y fail2ban >/dev/null 2>&1; then
      echo "✅ Fail2Ban installed."
    else
      echo -e "❌ \e[31mFailed to install Fail2Ban.\e[0m"
      exit 1
    fi
  else
    echo "✅ Fail2Ban is already installed."
  fi

  echo -e "\n🔐 \e[1mEnabling and starting Fail2Ban...\e[0m"
  if systemctl enable fail2ban >/dev/null 2>&1 && systemctl start fail2ban >/dev/null 2>&1; then
    echo "✅ Fail2Ban service is running."
  else
    echo -e "❌ \e[31mFailed to start or enable Fail2Ban.\e[0m"
    exit 1
  fi

  echo -e "\n📜 \e[1mInstalling Certbot (for HTTPS)...\e[0m"
  if ! command -v certbot >/dev/null 2>&1; then
    if apt-get install -y certbot >/dev/null 2>&1; then
      echo "✅ Certbot installed."
    else
      echo -e "❌ \e[31mFailed to install Certbot.\e[0m"
      exit 1
    fi
  else
    echo "✅ Certbot is already installed."
  fi

  echo -e "\n🔧 \e[1mInstalling Git (for deployments)...\e[0m"
  if ! command -v git >/dev/null 2>&1; then
    if apt-get install -y git >/dev/null 2>&1; then
      echo "✅ Git installed."
    else
      echo -e "❌ \e[31mFailed to install Git.\e[0m"
      exit 1
    fi
  else
    echo "✅ Git is already installed."
  fi

  export DISABLE_CLEAR=true
  set_swap
  apply_upcloud_firewall_rules
  configure_f2b
  update_server

  echo -e "\n🧩 \e[1mSystemd ready for .NET apps\e[0m"
  echo -e "   ➤ Apps will run as: \e[36m<sub>-<domain>-<port>.service\e[0m (e.g. blog-ghostlypick-com-5001.service)"
  echo -e "   ➤ You can add new apps anytime via:"
  echo -e "      📦 \e[1mApp Manager → Add new App\e[0m"

  echo -e "\n✅ \e[1mServer initialization completed.\e[0m"
  print_double_line
  read -rsn1 -p $'\nPress any key to return to menu...'
}

reset_server() {
  clear
  echo -e "\n🧨 \e[1;31mWARNING: FULL SERVER RESET\e[0m"
  print_double_line
  echo -e "\nThis operation will completely wipe all installed services and data:"
  print_line
  echo -e "🔸 Remove \e[36mnginx\e[0m and its configs"
  echo -e "🔸 Remove \e[36mfail2ban\e[0m and blocklists"
  echo -e "🔸 Remove \e[36mcertbot\e[0m and all certificates"
  echo -e "🔸 Remove \e[36mgit\e[0m and config"
  echo -e "🔸 Remove all .NET apps in \e[36m$APP_BASE_DIR/\e[0m"
  echo -e "🔸 Remove all systemd services for hosted .NET apps"
  echo -e "🔸 Remove \e[36m/opt/dotnet\e[0m and installed .NET SDKs"
  echo -e "🔸 Reset timezone to \e[36mUTC\e[0m"
  echo -e "🔸 Remove \e[36m/swapfile\e[0m"
  echo -e "🔸 Remove \e[36mufw\e[0m and firewall rules"
  echo -e "🔸 Remove all \e[36mUpCloud firewall rules\e[0m (via API)"
  print_line
  echo -e "⚠️ \e[1mThis cannot be undone.\e[0m"

  if ! confirm_action_code; then
    return 1
  fi


  echo -e "\n🚧 \e[1mResetting server – please wait...\e[0m"
  print_line
 
  # Dienste stoppen und entfernen
  systemctl stop nginx fail2ban 2>/dev/null || true
  systemctl disable nginx fail2ban 2>/dev/null || true
  apt-get purge -y nginx nginx-common nginx-core fail2ban certbot ufw git >/dev/null 2>&1
  apt-get autoremove -y >/dev/null 2>&1
  echo -e "🗑️ Removed nginx, fail2ban, certbot, git, ufw."

  # Fail2Ban Konfigurations- und Logdateien löschen
  rm -rf /etc/fail2ban /var/log/fail2ban* /var/lib/fail2ban
  echo -e "🗑️ Removed Fail2Ban configuration and log files."

  # Blazor systemd units löschen
  find /etc/systemd/system/ -name "blazor-*.service" -exec rm -f {} \;
  systemctl daemon-reload
  echo -e "🗑️ Removed all Blazor systemd services."

  # Apps & Zertifikate löschen
  rm -rf "${APP_BASE_DIR:?}/"* /etc/letsencrypt /var/lib/letsencrypt /var/log/letsencrypt
  echo -e "🗑️ Removed Blazor app folders and certificates."

  # Swap entfernen
  if [[ -f /swapfile ]]; then
    swapoff /swapfile
    rm -f /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    echo -e "🗑️ Removed swap file."
  fi

  # Timezone zurücksetzen
  timedatectl set-timezone UTC
  echo -e "🌐 Timezone reset to UTC."

  # .NET SDK entfernen
  if [[ -d /opt/dotnet ]]; then
    rm -rf /opt/dotnet
    sed -i '/DOTNET_ROOT/d' ~/.profile
    sed -i '/\/opt\/dotnet/d' ~/.profile
    echo -e "🗑️ Removed .NET SDKs and path configuration."
  fi

  # UpCloud Firewall Regeln löschen
  echo -e "🧱 Deleting UpCloud firewall rules..."
  export DISABLE_CLEAR=true
  delete_all_upcloud_firewall_rules

  echo -e "\n✅ \e[1;32mServer reset completed.\e[0m"
  print_double_line
  read -rsn1 -p $'\n↩️  Press any key to return to menu...'
}

ensure_server_initialized() {
  local missing=()

  # 🔍 Check for required system components
  command -v nginx >/dev/null 2>&1            || missing+=("🌐 Nginx (Reverse Proxy)")
  command -v fail2ban-client >/dev/null 2>&1  || missing+=("🛡️ Fail2Ban (SSH protection)")
  command -v certbot >/dev/null 2>&1          || missing+=("🔒 Certbot (HTTPS / Let's Encrypt)")
  command -v git >/dev/null 2>&1              || missing+=("🔧 Git (for deployments)")
  [[ -f /swapfile ]]                          || missing+=("📦 Swap file")

  if (( ${#missing[@]} == 0 )); then
    return 0
  fi

  clear
  echo -e "\n⚠️ \e[1;31mServer is not yet initialized for .NET App Hosting.\e[0m"
  echo -e "\nThe following components are missing:"
  print_line
  for item in "${missing[@]}"; do
    echo " ❌ $item"
  done
  print_line

  echo -e "\n🔧 \e[1mThe following will be configured by 'Init Server':\e[0m"
  echo -e "   • Nginx (Reverse Proxy)"
  echo -e "   • Fail2Ban (SSH Security)"
  echo -e "   • Certbot (Let's Encrypt)"
  echo -e "   • Git (deployment)"
  echo -e "   • Swap space"
  echo -e "   • Timezone + Firewall Setup"

  echo -e "\n❓ \e[1mHow do you want to proceed?\e[0m"
  print_line
  echo -e " 1) 🛠️ Run init server now     $(print_back_to_menu)"
  read_menu_choice 1

  case "$REPLY" in
    1)
      if ! prompt_and_set_timezone; then
        echo -e "\nℹ️ \e[2mYou must run \e[36minit server\e[0m before adding an app.\e[0m"
        return 1
      fi
      init_server
      check_and_offer_reboot
      return 0
      ;;
    q|Q)
      echo -e "\nℹ️ \e[2mYou must run \e[36minit server\e[0m before adding an app.\e[0m"
      return 1
      ;;
  esac
}