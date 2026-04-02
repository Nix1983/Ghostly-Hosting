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
source ./lib/nginx.sh
source ./lib/dotnet.sh
source ./lib/git.sh

remove_snapd() {
  apt-get purge -y snapd >/dev/null 2>&1
  rm -rf ~/snap /snap /var/snap /var/lib/snapd \
         /etc/systemd/system/snap* \
         /etc/systemd/system/multi-user.target.wants/snap* >/dev/null 2>&1
  echo -e "🗑️ Removed Snapd and all residual files."
}

remove_swap() {
  if [[ -f /swapfile ]]; then
    swapoff /swapfile
    rm -f /swapfile
    sed -i '/\/swapfile/d' /etc/fstab
    echo -e "🗑️ Removed swap file."
  fi
}

remove_ufw() {
  systemctl stop ufw 2>/dev/null || true
  systemctl disable ufw 2>/dev/null || true
  systemctl reset-failed ufw 2>/dev/null || true
  apt-get purge -y ufw >/dev/null 2>&1
  rm -rf /etc/ufw /var/log/ufw.log /lib/ufw /var/lib/ufw 2>/dev/null
  echo -e "🗑️ Removed UFW and all firewall configurations."
}

resolve_status_binary_path() {
  local binary_name="$1"
  shift || true

  if command -v "$binary_name" >/dev/null 2>&1; then
    command -v "$binary_name"
    return 0
  fi

  local candidate
  for candidate in "$@"; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

find_installed_package_name_from_status_lines() {
  local requested_package="$1"
  local status_lines="$2"
  local package_name package_status

  while IFS=$'\t' read -r package_name package_status; do
    [[ -z "$package_name" ]] && continue
    [[ "$package_status" != "install ok installed" ]] && continue

    case "$requested_package" in
      nginx)
        case "$package_name" in
          nginx|nginx-common|nginx-core|nginx-full|nginx-light|nginx-extras)
            echo "$package_name"
            return 0
            ;;
        esac
        ;;
      *)
        if [[ "$package_name" == "$requested_package" ]]; then
          echo "$package_name"
          return 0
        fi
        ;;
    esac
  done <<< "$status_lines"

  return 1
}

get_installed_status_package_name() {
  local requested_package="$1"
  local query_output

  case "$requested_package" in
    nginx)
      query_output=$(dpkg-query -W -f=$'${Package}\t${Status}\n' \
        nginx nginx-common nginx-core nginx-full nginx-light nginx-extras 2>/dev/null || true)
      ;;
    *)
      query_output=$(dpkg-query -W -f=$'${Package}\t${Status}\n' "$requested_package" 2>/dev/null || true)
      ;;
  esac

  find_installed_package_name_from_status_lines "$requested_package" "$query_output"
}

pending_updates_include_package() {
  local pending_updates="$1"
  shift || true

  local package_name
  for package_name in "$@"; do
    [[ -z "$package_name" ]] && continue
    if grep -q "^${package_name}/" <<< "$pending_updates"; then
      return 0
    fi
  done

  return 1
}

systemd_unit_exists() {
  local unit_name="$1"
  local unit_type="${2:-service}"

  if ! command -v systemctl >/dev/null 2>&1; then
    return 1
  fi

  systemctl list-unit-files --type="$unit_type" 2>/dev/null | grep -q "^${unit_name}\.${unit_type}"
}

is_server_component_available() {
  local component="$1"
  local installed_pkg=""

  case "$component" in
    nginx)
      installed_pkg=$(get_installed_status_package_name nginx || true)
      [[ -n "$installed_pkg" ]] && return 0
      resolve_status_binary_path nginx /usr/sbin/nginx /usr/bin/nginx >/dev/null 2>&1 && return 0
      systemd_unit_exists nginx service && return 0
      ;;
    fail2ban)
      installed_pkg=$(get_installed_status_package_name fail2ban || true)
      [[ -n "$installed_pkg" ]] && return 0
      resolve_status_binary_path fail2ban-client /usr/bin/fail2ban-client >/dev/null 2>&1 && return 0
      systemd_unit_exists fail2ban service && return 0
      ;;
    certbot)
      installed_pkg=$(get_installed_status_package_name certbot || true)
      [[ -n "$installed_pkg" ]] && return 0
      resolve_status_binary_path certbot /usr/bin/certbot /snap/bin/certbot >/dev/null 2>&1 && return 0
      systemd_unit_exists certbot.timer timer && return 0
      ;;
    git)
      installed_pkg=$(get_installed_status_package_name git || true)
      [[ -n "$installed_pkg" ]] && return 0
      resolve_status_binary_path git /usr/bin/git /usr/lib/git-core/git >/dev/null 2>&1 && return 0
      ;;
    swapfile)
      [[ -f /swapfile ]] && return 0
      ;;
  esac

  return 1
}

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

  # Disk (in GB with 2 decimal places)
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

  echo -ne "\n🛰️ \e[1mUpdating APT sources...\e[0m "
  if apt-get update -y >/dev/null 2>&1; then
    echo -e "✅ Done"
  else
    echo -e "❌ Failed"
  fi

  echo -e "\n📦 \e[1mUpgrading installed packages (this may take a while)...\e[0m"
  echo -e "   ➤ Running: \e[2mapt-get upgrade\e[0m"
  echo ""

  if DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" -y upgrade; then
    echo -e "\n   ✅ Packages upgraded successfully."
  else
    echo -e "\n   ❌ Upgrade failed. Check manually."
  fi

  echo -e "\n🧼 \e[1mCleaning up system ...\e[0m"
  echo -ne "   ➤ Removing unused packages... "
  apt-get -y autoremove >/dev/null 2>&1 && echo "✅ Done"
  echo -ne "   ➤ Cleaning package cache... "
  apt-get -y autoclean >/dev/null 2>&1 && echo "✅ Done"

  echo -e "\n🧠 \e[1mSystem Status\e[0m"
  print_line

  local kernel version
  kernel=$(uname -r)
  version=$(lsb_release -ds 2>/dev/null || echo "Unknown")

  printf "💻 %-17s %s\n" "OS Version:" "$version"
  printf "🧬 %-17s %s\n" "Kernel:" "$kernel"

  local pending_updates
  pending_updates=$(apt list --upgradable 2>/dev/null || true)

  check_package_status() {
    local pkg_name="$1"
    local label="$2"
    local emoji="$3"
    local check_bin="${4:-}"
    local service_name="${5:-}"
    local status
    local binary_path=""
    local installed_pkg=""
    local service_detected=false

    if [[ -n "$check_bin" ]]; then
      case "$check_bin" in
        nginx)
          binary_path=$(resolve_status_binary_path nginx /usr/sbin/nginx /usr/bin/nginx || true)
          ;;
        *)
          binary_path=$(command -v "$check_bin" 2>/dev/null || true)
          ;;
      esac
    fi

    if [[ -n "$service_name" ]] && command -v systemctl >/dev/null 2>&1; then
      if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${service_name}\.service"; then
        service_detected=true
      fi
    fi

    installed_pkg=$(get_installed_status_package_name "$pkg_name" || true)

    if [[ -n "$installed_pkg" ]]; then
      if pending_updates_include_package "$pending_updates" "$installed_pkg" "$pkg_name"; then
        status="\e[33mUpdate available\e[0m"
      else
        status="\e[32mUp to date\e[0m"
      fi
    elif [[ -n "$binary_path" || "$service_detected" == true ]]; then
      status="\e[32mInstalled\e[0m"
    else
      status="\e[2mNot installed\e[0m"
    fi

    printf "%s %-17s %b\n" "$emoji" "$label:" "$status"
  }

  echo ""
  check_package_status nginx    "Nginx"     "🌐" nginx nginx
  check_package_status fail2ban "Fail2Ban"  "🛡️" "" fail2ban
  check_package_status git      "Git"       "🔧" git

  echo -e "\n✅ \e[1mSystem update completed.\e[0m"
  print_line
  read -rsn1 -p $'\nPress any key to return to menu...'
}

show_init_server_prompt() {
  clear
  echo -e "\n🚀 \e[1;34mInitialize Server for GhostlyHosting\e[0m"
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

  install_nginx
  intsall_fail2ban
  install_certbot
  install_git


  export DISABLE_CLEAR=true
  set_swap
  apply_upcloud_firewall_rules
  configure_f2b
  update_server

  echo -e "\n🧩 \e[1mSystemd ready for .NET apps\e[0m"
  echo -e "   ➤ Apps will run as individual system services with unique port assignments"
  echo -e "   ➤ You can add new apps anytime via:"
  echo -e "      ➕ \e[1mOption 2) Add new App\e[0m in the App Manager"

  echo -e "\n✅ \e[1mServer initialization completed.\e[0m"
  print_double_line
  print_press_any_key
}

remove_all_kestrel_services() {
  echo -e "\n🧹 \e[1mRemoving all .NET (Kestrel) systemd services...\e[0m"

  local services
  mapfile -t services < <(find /etc/systemd/system -type f -name "*@*:*[5-9][0-9][0-9][0-9].service")

  if [[ ${#services[@]} -eq 0 ]]; then
    echo -e "ℹ️ No Kestrel services found."
    return 0
  fi

  for service_path in "${services[@]}"; do
    local service_name
    service_name=$(basename "$service_path")

    if systemctl list-units --all --type=service | grep -qF -- "$service_name"; then
      echo -e "\n⏹️ Stopping: \e[36m$service_name\e[0m"
      systemctl stop "$service_name" || true
      echo -e "❌ Disabling: \e[36m$service_name\e[0m"
      systemctl disable "$service_name" &>/dev/null || true
    fi

    echo -e "🧽 Removing file: \e[2m$service_path\e[0m"
    rm -f "$service_path"
  done

  systemctl daemon-reexec
  systemctl daemon-reload
  echo -e "\n✅ \e[32mAll Kestrel services removed.\e[0m"
}

reset_server() {
  clear
  echo -e "\n🧨 \e[1;31mWARNING: FULL SERVER RESET\e[0m"
  print_double_line
  echo -e "\nThis operation will completely wipe all installed services and data:"
  print_line
  echo -e "🔸 Remove \e[36mNGINX\e[0m and its configs"
  echo -e "🔸 Remove \e[36mCertbot\e[0m and all certificates"
  echo -e "🔸 Remove \e[36mFail2Ban\e[0m and blocklists"
  echo -e "🔸 Remove \e[36mGit\e[0m and all related binaries"
  echo -e "🔸 Remove \e[36m/opt/dotnet\e[0m and installed .NET SDKs"
  echo -e "🔸 Remove \e[36mSnapd\e[0m and related core services"
  echo -e "🔸 Remove \e[36mufw\e[0m and all firewall rules"
  echo -e "🔸 Remove all .NET apps in \e[36m$APP_BASE_DIR/\e[0m"
  echo -e "🔸 Remove all systemd services for hosted .NET apps"
  echo -e "🔸 Remove \e[36m/swapfile\e[0m"
  echo -e "🔸 Remove all \e[36mUpCloud firewall rules\e[0m (via API)"
  echo -e "🔸 Reset timezone to \e[36mUTC\e[0m"
  print_line
  echo -e "⚠️ \e[1mThis cannot be undone.\e[0m"

  if ! confirm_action_code; then return 1; fi

  echo -e "\n🚧 \e[1mResetting server – please wait...\e[0m"
  print_line

  remove_nginx_log_timer
  remove_all_kestrel_services
  remove_nginx
  remove_certbot
  remove_fail2ban
  remove_git
  remove_dotnet
  remove_snapd
  remove_ufw
  remove_swap

  rm -rf "${APP_BASE_DIR:?}/"* "/var/${CLONE_BASE_DIR:?}"

  echo -e "\n🌐 \e[1mResetting system timezone...\e[0m"
  timedatectl set-timezone UTC
  echo -e "🌐 Timezone reset to UTC."

  echo -e "\n🧱 \e[1mDeleting UpCloud firewall rules...\e[0m"
  export DISABLE_CLEAR=true
  delete_all_upcloud_firewall_rules

  echo -e "\n✅ \e[1;32mServer reset completed.\e[0m"
  print_double_line
  read -rsn1 -p $'\n↩️  Press any key to return to menu...'
}

ensure_server_initialized() {
  local missing=()

  # 🔍 Check for required system components
  is_server_component_available nginx         || missing+=("🌐 Nginx (Reverse Proxy)")
  is_server_component_available fail2ban      || missing+=("🛡️ Fail2Ban (SSH protection)")
  is_server_component_available certbot       || missing+=("🔒 Certbot (HTTPS / Let's Encrypt)")
  is_server_component_available git           || missing+=("🔧 Git (for deployments)")
  is_server_component_available swapfile      || missing+=("📦 Swap file")

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
