#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh

CONFIG_FILE="/etc/fail2ban/jail.local"

remove_fail2ban() {
  systemctl stop fail2ban 2>/dev/null || true
  systemctl disable fail2ban 2>/dev/null || true
  systemctl reset-failed fail2ban 2>/dev/null || true

  apt-get purge -y fail2ban fail2ban-py* >/dev/null 2>&1
  dpkg --purge fail2ban >/dev/null 2>&1 || true

  rm -rf /etc/fail2ban /var/lib/fail2ban /var/log/fail2ban*
  rm -f /usr/bin/fail2ban-client /usr/bin/fail2ban-server /usr/bin/fail2ban-regex \
        /usr/bin/fail2ban-testcases /usr/bin/fail2ban-python3
  rm -rf /usr/lib/python3*/dist-packages/fail2ban* /usr/local/bin/fail2ban*

  echo -e "🗑️ Removed Fail2Ban configuration, binaries and Python modules."
}

install_fail2ban(){
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

  if [[ ! -d /etc/fail2ban ]]; then
    echo -e "⚠️ \e[33mFail2Ban config missing – repairing broken installation (Ubuntu 20 workaround)...\e[0m"
    apt-get purge -y fail2ban >/dev/null 2>&1
    rm -rf /etc/fail2ban /var/lib/fail2ban /var/log/fail2ban*
    if apt-get install -y fail2ban >/dev/null 2>&1; then
      echo "✅ Fail2Ban reinstalled and fixed."
    else
      echo -e "❌ \e[31mRepair failed – aborting.\e[0m"
      exit 1
    fi
  fi

  echo -e "\n🔐 \e[1mEnabling and starting Fail2Ban...\e[0m"
  if ! systemctl enable fail2ban >/dev/null 2>&1; then
    echo -e "❌ \e[31mFailed to enable Fail2Ban service.\e[0m"
    exit 1
  fi
  if ! systemctl start fail2ban >/dev/null 2>&1; then
    echo -e "❌ \e[31mFailed to start Fail2Ban service.\e[0m"
    exit 1
  fi
  if ! systemctl is-active --quiet fail2ban; then
    echo -e "❌ \e[31mFail2Ban service is not running after start.\e[0m"
    exit 1
  fi
  echo "✅ Fail2Ban service is running."
}

configure_f2b() {

  {
    echo "[DEFAULT]"
    echo "bantime = -1"
    echo ""

    echo "[sshd]"
    echo "enabled = true"
    echo "port = ssh"
    echo "logpath = /var/log/auth.log"
    echo "maxretry = 3"
    echo ""

    # Note: nginx-http-auth is only useful when nginx is exposed directly to the
    # internet. If you use Cloudflare as a proxy, all traffic comes through
    # Cloudflare IPs and this jail will not trigger on real attacker IPs.
    echo "[nginx-http-auth]"
    echo "enabled = true"
    echo "filter = nginx-http-auth"
    echo "logpath = /var/log/nginx/error.log"
    echo "maxretry = 3"
  } > "$CONFIG_FILE"

  systemctl restart fail2ban
}

show_f2b_explanation() {
  clear
  echo -e "\n🛡️  Fail2Ban Overview"
  echo "────────────────────────────────────────"
  echo -e "\nℹ️  Meaning:"
  echo "   ❗ Failed attempts (active) = Current number of failed login attempts"
  echo "   🔁 Failed attempts (total) = Total detected failed attempts"
  echo "   🔒 Currently banned = Number of IPs currently banned"
  echo "   🧾 Banned IPs (total) = Total number of all ever banned IPs"
  echo "   🚫 Banned IPs = List of currently banned IP addresses"
  echo "   ✅ Recent offenders = Recently suspicious IPs (not necessarily banned)"
  echo "   ⏱️ Last ban = Timestamp and age of the last ban"
  echo "   ⚙️ Settings = Jail config like bantime, maxretry etc."
  echo "   📭 Whitelist = IPs that should never be banned (ignoreip)"
  echo ""
}

show_f2b_status() {
  clear

  local jails=("sshd" "nginx-http-auth")
  declare -A values
  local metrics=("currently_failed" "total_failed" "currently_banned" "total_banned")
  declare -A totals
  for metric in "${metrics[@]}"; do totals[$metric]=0; done

  for jail in "${jails[@]}"; do
    if output=$(fail2ban-client status "$jail" 2>/dev/null); then
      while IFS= read -r line; do
        case "$line" in
          *"Currently failed"*)   values["$jail.currently_failed"]=$(cut -d: -f2 <<< "$line" | xargs) ;;
          *"Total failed"*)       values["$jail.total_failed"]=$(cut -d: -f2 <<< "$line" | xargs) ;;
          *"Currently banned"*)   values["$jail.currently_banned"]=$(cut -d: -f2 <<< "$line" | xargs) ;;
          *"Total banned"*)       values["$jail.total_banned"]=$(cut -d: -f2 <<< "$line" | xargs) ;;
        esac
      done <<< "$output"

      for metric in "${metrics[@]}"; do
        val=${values["$jail.$metric"]:-0}
        totals[$metric]=$(( totals[$metric] + val ))
      done
    fi
  done

  echo -e "\n📊 \e[1mFail2Ban Jail Comparison:\e[0m"
  echo "───────────────────────────────────────────────────────────────────────"
  printf "🔐 %-22s %-18s %-18s %-18s\n" "Jail:" "🔐 sshd" "🌐 nginx" "🔢 Total"
  echo   "───────────────────────────────────────────────────────────────────────"
  printf "❗ %-22s %-18s %-18s %-18s\n" "Failed (active):" \
    "${values[sshd.currently_failed]:-0}" "${values[nginx-http-auth.currently_failed]:-0}" "${totals[currently_failed]}"
  printf "🔁 %-22s %-18s %-18s %-18s\n" "Failed (total):" \
    "${values[sshd.total_failed]:-0}" "${values[nginx-http-auth.total_failed]:-0}" "${totals[total_failed]}"
  printf "🔒 %-22s %-18s %-18s %-18s\n" "Currently banned:" \
    "${values[sshd.currently_banned]:-0}" "${values[nginx-http-auth.currently_banned]:-0}" "${totals[currently_banned]}"
  printf "🧾 %-22s %-18s %-18s %-18s\n" "Banned IPs (total):" \
    "${values[sshd.total_banned]:-0}" "${values[nginx-http-auth.total_banned]:-0}" "${totals[total_banned]}"
  echo "───────────────────────────────────────────────────────────────────────"

  count_section_ips() {
    local section="$1"
    local key="$2"
    awk -v section="[$section]" -v key="$key" '
      BEGIN { in_section=0; count=0 }
      /^\[.*\]/ { in_section = ($0 == section); next }
      in_section && $0 ~ "^"key"[[:space:]]*=" {
        gsub(/.*=/, "", $0)
        n = split($0, ips, /[[:space:]]+/)
        for (i = 1; i <= n; i++) if (ips[i] != "") count++
      }
      END { print count }
    ' "$CONFIG_FILE"
  }

  echo -e "\n📄 \e[1mWhitelist IP Counts (ignoreip):\e[0m"
  echo "──────────────────────────────────────────────────────────────────────"
  local wl_global; wl_global=$(count_section_ips "DEFAULT" "ignoreip")
  local wl_sshd; wl_sshd=$(count_section_ips "sshd" "ignoreip")
  local wl_nginx; wl_nginx=$(count_section_ips "nginx-http-auth" "ignoreip")
  local wl_total=$((wl_global + wl_sshd + wl_nginx))
  printf "🟢 %-22s %-18s %-18s %-18s\n" "Whitelist entries:" \
    "$wl_sshd" "$wl_nginx" "$wl_total"
  echo "──────────────────────────────────────────────────────────────────────"

  echo -e "\n🔥 \e[1mManually Banned IPs (via fail2ban-client):\e[0m"
  echo "──────────────────────────────────────────────────────────────────────"
  local bl_sshd=0 bl_nginx=0
  if command -v fail2ban-client >/dev/null 2>&1; then
    bl_sshd=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned:" | awk '{print $NF}' || echo 0)
    bl_nginx=$(fail2ban-client status nginx-http-auth 2>/dev/null | grep "Currently banned:" | awk '{print $NF}' || echo 0)
  fi
  local bl_total=$(( ${bl_sshd:-0} + ${bl_nginx:-0} ))
  printf "🔴 %-22s %-18s %-18s %-18s\n" "Currently banned:" \
    "${bl_sshd:-0}" "${bl_nginx:-0}" "$bl_total"
  echo "──────────────────────────────────────────────────────────────────────"
}

show_whitelist_entrys() {
 declare -A whitelist_map
    if ! load_f2b_whitelist_entries whitelist_map; then
      echo ""
      echo -e "\n         🧾 Whitelist is currently empty."
      echo ""
      return 0
    fi

    print_f2b_ip_entries whitelist_map
}

load_f2b_whitelist_entries() {
  declare -n _result_map="$1"
  local index=1
  local section=""
  local found_any=false

  while IFS= read -r line; do
    local trimmed
    trimmed=$(echo "$line" | xargs)

    if [[ "$trimmed" =~ ^\[.*\]$ ]]; then
      section="${trimmed#[}"
      section="${section%]}"
    elif [[ "$trimmed" =~ ^ignoreip[[:space:]]*=[[:space:]]*(.*) ]]; then
      for ip in ${BASH_REMATCH[1]}; do
        [[ -n "$ip" ]] || continue
        _result_map[$index]="$ip|$section"
        found_any=true
        ((index++))
      done
    fi
  done < "$CONFIG_FILE"

  $found_any
}

get_whitelist_entry_list() {
  declare -n result_array=$1
  declare -A map
  result_array=()

  if ! load_f2b_whitelist_entries map; then
    return 1
  fi

  for i in $(printf "%s\n" "${!map[@]}" | sort -n); do
    [[ -n "${map[$i]}" ]] && result_array+=("${map[$i]}")
  done
}

print_f2b_ip_entries() {
  declare -n target_map=$1
  declare -gA ip_index_map=()

  local -A global_ips=()
  local -A sshd_ips=()
  local -A nginx_ips=()

  local -i global_idx=1 sshd_idx=1 nginx_idx=1

  for id in $(printf "%s\n" "${!target_map[@]}" | sort -n); do
    entry="${target_map[$id]}"
    ip=$(cut -d'|' -f1 <<< "$entry")
    section=$(cut -d'|' -f2 <<< "$entry")

    case "$section" in
      sshd)               sshd_ips[$sshd_idx]="$id";   ((sshd_idx++)) ;;
      nginx-http-auth)    nginx_ips[$nginx_idx]="$id"; ((nginx_idx++)) ;;
      *)                  global_ips[$global_idx]="$id"; ((global_idx++)) ;;
    esac
  done

  local max_rows=${#global_ips[@]}
  (( ${#sshd_ips[@]} > max_rows )) && max_rows=${#sshd_ips[@]}
  (( ${#nginx_ips[@]} > max_rows )) && max_rows=${#nginx_ips[@]}

  local -i display_index=1

  # Column header
  printf "\n \e[35m%-24s\e[0m \e[36m%-24s\e[0m \e[32m%-24s\e[0m\n" "🌍 Global" "🔐 sshd" "🌐 nginx"
  echo    " ──────────────────────── ──────────────────────── ────────────────────────"

  for ((i = 1; i <= max_rows; i++)); do
    local out1="" out2="" out3=""

    if [[ -n "${global_ips[$i]}" ]]; then
      id="${global_ips[$i]}"
      ip=$(cut -d'|' -f1 <<< "${target_map[$id]}")
      out1="$(printf "%2d) %-17s" "$display_index" "$ip")"
      ip_index_map[$display_index]="$id"
      ((display_index++))
    else
      out1=" "
    fi

    if [[ -n "${sshd_ips[$i]}" ]]; then
      id="${sshd_ips[$i]}"
      ip=$(cut -d'|' -f1 <<< "${target_map[$id]}")
      out2="$(printf "%2d) %-17s" "$display_index" "$ip")"
      ip_index_map[$display_index]="$id"
      ((display_index++))
    else
      out2=" "
    fi

    if [[ -n "${nginx_ips[$i]}" ]]; then
      id="${nginx_ips[$i]}"
      ip=$(cut -d'|' -f1 <<< "${target_map[$id]}")
      out3="$(printf "%2d) %-17s" "$display_index" "$ip")"
      ip_index_map[$display_index]="$id"
      ((display_index++))
    else
      out3=" "
    fi

    printf " \e[1;33m%-24s\e[0m \e[1;33m%-24s\e[0m \e[1;33m%-24s\e[0m\n" "$out1" "$out2" "$out3"
  done
}

remove_ip_from_whitelist_by_ip() {
  local ip_to_remove="$1"
  local section="$2"
  local temp_file

  temp_file=$(mktemp)

  awk -v section="$section" -v ip="$ip_to_remove" '
    BEGIN { in_section=0 }
    /^\[.*\]/ { in_section = ($0 == "[" section "]") }
    {
      if (in_section && $0 ~ /^ignoreip[[:space:]]*=/) {
        split($0, parts, "=")
        n = split(parts[2], ips, /[[:space:]]+/)
        new_line = "ignoreip ="
        for (i = 1; i <= n; i++) {
          if (ips[i] != "" && ips[i] != ip) {
            new_line = new_line " " ips[i]
          }
        }
        if (new_line != "ignoreip =") print new_line
        next
      }
    }
    { print }
  ' "$CONFIG_FILE" > "$temp_file"

  mv "$temp_file" "$CONFIG_FILE"
}

remove_ip_from_whitelist() {
  clear
  echo -e "\n🧹 \e[1mRemove Whitelist Entry"
  echo "────────────────────────────────────────────────────────────"

  declare -A whitelist_map
  if ! load_f2b_whitelist_entries whitelist_map; then
    echo -e "\n❌ No whitelist entries found."
    return 1
  fi

  print_f2b_ip_entries whitelist_map

  print_back_to_menu
  echo "────────────────────────────────────────────────────────────"
  echo -n "Select the number of the IP to remove: "
  IFS= read -r selection
  echo

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    return 1
  fi

  if [[ "$selection" =~ ^[0-9]+$ && -n "${ip_index_map[$selection]}" ]]; then
    local id="${ip_index_map[$selection]}"
    local ip_to_remove section
    ip_to_remove=$(cut -d'|' -f1 <<< "${whitelist_map[$id]}")
    section=$(cut -d'|' -f2 <<< "${whitelist_map[$id]}")

    echo -e "\n🧹 Removing \e[1;33m$ip_to_remove\e[0m from [\e[1m$section\e[0m]..."

    remove_ip_from_whitelist_by_ip "$ip_to_remove" "$section"

    echo -e "🔄 Restarting Fail2Ban..."
    if systemctl restart fail2ban; then
      echo -e "✅ \e[1m$ip_to_remove successfully removed and Fail2Ban restarted.\e[0m"
    else
      echo -e "❌ Fail2Ban restart failed."
    fi
    return 0
  else
    print_invalid_selection
    print_press_any_key
    return 1
  fi
}

add_ip_to_whitelist() {
  clear
  echo -e "\n➕ \e[1mAdd IP to Fail2Ban Whitelist"
  echo "────────────────────────────────────────────────────────────"

  show_whitelist_entrys

  print_back_to_menu
  echo "────────────────────────────────────────────────────────────"
  echo -n "Enter new IP address: "
  read -rp "" IP

  if [[ "$IP" == "q" || "$IP" == "Q" ]]; then return 1; fi
  if [[ -z "$IP" ]]; then echo "❌ No IP entered."; return; fi
  if ! is_valid_ipv4 "$IP"; then echo "❌ Invalid IPv4 address: $IP"; return; fi

  echo -e "\n🔧 \e[1mWhere should the IP be added?\e[0m"
  echo "────────────────────────────────────────────────────────────"
  echo -e " 1) 🌍 Global (all jails)        2) 🔐 sshd"
  echo -e " 3) 🌐 nginx-http-auth           $(print_back_to_menu)"
  echo "────────────────────────────────────────────────────────────"
  echo -n "Choose [1–3,q]: "
  IFS= read -rsn1 scope
  echo

  case $scope in
    1) SECTION="DEFAULT" ;;
    2) SECTION="sshd" ;;
    3) SECTION="nginx-http-auth" ;;
    q|Q) return 1 ;;
    *) print_invalid_selection; return 1 ;;
  esac

  local current_section
  current_section=$(awk -v ip="$IP" 'BEGIN { section="" }
    /^\[.*\]/ { section=$0 }
    $0 ~ "ignoreip" && $0 ~ ip { print section }' "$CONFIG_FILE" | head -1 | sed 's/\[//;s/\]//')

  if [[ -n "$current_section" ]]; then
    if [[ "$current_section" == "$SECTION" ]]; then
      echo -e "ℹ️  IP \e[1;33m$IP\e[0m is already in [\e[1m$SECTION\e[0m]."
      return 0
    else
      echo -e "🔁 IP \e[1;33m$IP\e[0m is currently in [\e[1m$current_section\e[0m] – moving..."
      remove_ip_from_whitelist_by_ip "$IP" "$current_section"
    fi
  fi

  if grep -q "^\[$SECTION\]" "$CONFIG_FILE"; then
    if grep -A 5 "^\[$SECTION\]" "$CONFIG_FILE" | grep -q "^ignoreip"; then
      sed -i "/^\[$SECTION\]/,/^\[.*\]/ s/^\(ignoreip *= *\)\(.*\)/\1\2 $IP/" "$CONFIG_FILE"
    else
      sed -i "/^\[$SECTION\]/ a ignoreip = $IP" "$CONFIG_FILE"
    fi
  else
    echo -e "\n[$SECTION]\nignoreip = $IP\n" | tee -a "$CONFIG_FILE" > /dev/null
  fi

  echo -e "\n🔄 Restarting Fail2Ban..."
  if systemctl restart fail2ban; then
    echo -e "✅ \e[1mIP $IP successfully added to [\e[1m$SECTION\e[0m] whitelist.\e[0m"
  else
    echo -e "❌ Fail2Ban restart failed."
  fi

  return 0
}

show_whitelist_raw_entrys() {
  clear
  grep -RnE '^\s*ignoreip\s*=' /etc/fail2ban/
}

clear_fail2ban_whitelist() {
  clear
  echo -e "\n🧹 \e[1mClear Entire Whitelist"
  echo "────────────────────────────────────────────────────────────"

  declare -a entries
  get_whitelist_entry_list entries

  if [[ ${#entries[@]} -eq 0 ]]; then
    echo -e "\n⚠️  No entries found in whitelist."
    return 1
  fi

  echo -e "\n⚠️  This will remove \e[1m${#entries[@]}\e[0m entries from the whitelist."
  read -rp " ❗  Are you sure you want to proceed? [y/N]: " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\n❎ Operation cancelled."
    return 1
  fi

  for entry in "${entries[@]}"; do
    ip=$(cut -d'|' -f1 <<< "$entry")
    jail=$(cut -d'|' -f2 <<< "$entry")
    echo -e "❌ Removing \e[1;33m$ip\e[0m from [\e[1m$jail\e[0m]..."
    remove_ip_from_whitelist_by_ip "$ip" "$jail"
  done

  echo -e "\n🔄 Restarting Fail2Ban..."
  if systemctl restart fail2ban; then
    echo -e "✅ \e[1mWhitelist cleared successfully and Fail2Ban restarted.\e[0m"
  else
    echo -e "❌ Fail2Ban restart failed."
  fi
}

show_f2b_whitelist_menu() {
  while true; do
    clear
    echo -e "\n\e[1m🟢  Fail2Ban Whitelist Menu"
    echo "────────────────────────────────────────────────────────────"

    show_whitelist_entrys

    echo -e "\n 1) ➕ Add IP address               2) ❌ Remove IP address"
    echo -e "\n 3) 🧼 Show raw whitelist entries   4) 💣 Clear entire whitelist"
    echo -e "\n $(print_back_to_menu)"

    read_menu_choice 4

    case "$REPLY" in
      1)
        if add_ip_to_whitelist; then
          echo ""
          print_press_any_key
        fi
        ;;
      2)
        if remove_ip_from_whitelist; then
          echo ""
          print_press_any_key
        fi
        ;;
      3)
        show_whitelist_raw_entrys
        echo ""
        print_press_any_key
        ;;
      4)
        if clear_fail2ban_whitelist; then
          echo ""
          print_press_any_key
        fi
        ;;
      q|Q)
        break
        ;;
    esac
  done
}

load_f2b_blocklist_entries() {
  # Reads currently banned IPs from fail2ban-client (live data from the daemon).
  # This replaces the old approach of writing a non-standard "bannedip" key
  # to jail.local, which fail2ban silently ignored.
  declare -n _result_map="$1"
  local index=1
  local found_any=false
  local jails=("sshd" "nginx-http-auth")

  for jail in "${jails[@]}"; do
    local jail_status banned_list
    if ! jail_status=$(fail2ban-client status "$jail" 2>/dev/null); then
      continue
    fi
    banned_list=$(echo "$jail_status" | grep "Banned IP list:" | sed 's/.*Banned IP list:[[:space:]]*//')
    for ip in $banned_list; do
      [[ -n "$ip" ]] || continue
      _result_map[$index]="$ip|$jail"
      found_any=true
      ((index++))
    done
  done

  $found_any
}

add_ip_to_blocklist() {
  clear
  echo -e "\n➕ \e[1mManually Ban IP via Fail2Ban"
  echo "────────────────────────────────────────────────────────────"

  echo -n "Enter IP address to ban: "
  read -rp "" IP

  if [[ "$IP" == "q" || "$IP" == "Q" ]]; then return 1; fi
  if [[ -z "$IP" ]]; then echo "❌ No IP entered."; return; fi
  if ! is_valid_ipv4 "$IP"; then echo "❌ Invalid IPv4 address: $IP"; return; fi

  echo -e "\n🔧 \e[1mWhich jail should ban this IP?\e[0m"
  echo "────────────────────────────────────────────────────────────"
  echo -e " 1) 🔐 sshd                      2) 🌐 nginx-http-auth"
  echo -e " 3) 🌍 All jails                 $(print_back_to_menu)"
  echo "────────────────────────────────────────────────────────────"
  echo -n "Choose [1–3,q]: "
  IFS= read -rsn1 scope; echo

  local jails_to_ban=()
  case $scope in
    1) jails_to_ban=("sshd") ;;
    2) jails_to_ban=("nginx-http-auth") ;;
    3) jails_to_ban=("sshd" "nginx-http-auth") ;;
    q|Q) return 1 ;;
    *) print_invalid_selection; return 1 ;;
  esac

  local any_success=false
  for jail in "${jails_to_ban[@]}"; do
    if fail2ban-client set "$jail" banip "$IP" >/dev/null 2>&1; then
      echo -e "✅ \e[1mIP $IP banned in [$jail].\e[0m"
      any_success=true
    else
      echo -e "❌ Failed to ban $IP in [$jail]."
    fi
  done

  $any_success
}

remove_ip_from_blocklist_by_ip() {
  local ip="$1"
  local jail="$2"
  if fail2ban-client set "$jail" unbanip "$ip" >/dev/null 2>&1; then
    return 0
  else
    echo -e "⚠️  Could not unban \e[1;33m$ip\e[0m from [$jail] – may not be actively banned."
    return 1
  fi
}

remove_ip_from_blocklist() {
  clear
  echo -e "\n🧹 \e[1mUnban IP via Fail2Ban"
  echo "────────────────────────────────────────────────────────────"

  declare -A blocklist_map
  if ! load_f2b_blocklist_entries blocklist_map; then
    echo -e "\n❌ No actively banned IPs found."
    return 1
  fi

  print_f2b_ip_entries blocklist_map
  echo ""
  print_back_to_menu
  echo "────────────────────────────────────────────────────────────"
  echo -n "Select the number of the IP to unban: "
  IFS= read -r selection
  echo

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    return 1
  fi

  if [[ "$selection" =~ ^[0-9]+$ && -n "${ip_index_map[$selection]}" ]]; then
    local id="${ip_index_map[$selection]}"
    local ip_to_remove jail
    ip_to_remove=$(cut -d'|' -f1 <<< "${blocklist_map[$id]}")
    jail=$(cut -d'|' -f2 <<< "${blocklist_map[$id]}")

    echo -e "\n🧹 Unbanning \e[1;33m$ip_to_remove\e[0m from [\e[1m$jail\e[0m]..."

    if remove_ip_from_blocklist_by_ip "$ip_to_remove" "$jail"; then
      echo -e "✅ \e[1m$ip_to_remove successfully unbanned from [$jail].\e[0m"
    fi
    return 0
  else
    print_invalid_selection
    print_press_any_key
    return 1
  fi
}

clear_fail2ban_blocklist() {
  clear
  echo -e "\n🧹 \e[1mUnban All Manually Banned IPs"
  echo "────────────────────────────────────────────────────────────"

  declare -a entries
  get_blocklist_entry_list entries

  if [[ ${#entries[@]} -eq 0 ]]; then
    echo -e "\n⚠️  No actively banned IPs found."
    return 1
  fi

  echo -e "\n⚠️  This will unban \e[1m${#entries[@]}\e[0m IPs from Fail2Ban."
  read -rp " ❗  Are you sure you want to proceed? [y/N]: " confirm

  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo -e "\n❎ Operation cancelled."
    return 1
  fi

  for entry in "${entries[@]}"; do
    ip=$(cut -d'|' -f1 <<< "$entry")
    jail=$(cut -d'|' -f2 <<< "$entry")
    echo -e "🧹 Unbanning \e[1;33m$ip\e[0m from [\e[1m$jail\e[0m]..."
    remove_ip_from_blocklist_by_ip "$ip" "$jail" || true
  done

  echo -e "\n✅ \e[1mAll manually banned IPs have been removed.\e[0m"
}

get_blocklist_entry_list() {
  declare -n _bl_array="$1"
  declare -A map
  _bl_array=()

  if ! load_f2b_blocklist_entries map; then
    return 1
  fi

  for i in $(printf "%s\n" "${!map[@]}" | sort -n); do
    [[ -n "${map[$i]}" ]] && _bl_array+=("${map[$i]}")
  done
}

show_blocklist_entrys() {
  declare -A blocklist_map
  if ! load_f2b_blocklist_entries blocklist_map; then
    echo -e "\n         🚫 No actively banned IPs found."
    return 0
  fi

  print_f2b_ip_entries blocklist_map
}

show_f2b_blocklist_menu() {
  while true; do
    clear
    echo -e "\n\e[1m🔥 Fail2Ban Blocklist (Active Bans)"
    echo "────────────────────────────────────────────────────────────"

    show_blocklist_entrys

    echo -e "\n 1) ➕ Ban IP address               2) ❌ Unban IP address"
    echo -e "\n 3) 🧾 Show live ban status         4) 💣 Unban all IPs"
    echo -e "\n $(print_back_to_menu)"

    read_menu_choice 4

    case "$REPLY" in
      1)
        if add_ip_to_blocklist; then
          echo ""
          print_press_any_key
        fi
        ;;
      2)
        if remove_ip_from_blocklist; then
          echo ""
          print_press_any_key
        fi
        ;;
      3)
        echo -e "\n🧾 \e[1mLive Fail2Ban Ban Status:\e[0m"
        for jail in "sshd" "nginx-http-auth"; do
          echo -e "\n[$jail]:"
          fail2ban-client status "$jail" 2>/dev/null | grep "Banned IP list:" || echo "  (none)"
        done
        echo ""
        print_press_any_key
        ;;
      4)
        if clear_fail2ban_blocklist; then
          echo ""
          print_press_any_key
        fi
        ;;
      q|Q)
        break
        ;;
    esac
  done
}

show_f2b_logs_menu() {
  while true; do
    clear
    echo -e "\n\e[1m📄 Fail2Ban Log Viewer"
    echo "────────────────────────────────────────────────────────────"

    echo -e "\n 1) 🚫 Show all banned IPs            2) ❗ Show all failed attempts"
    echo -e "\n 3) 👀 Show all suspicious activity   4) 🧾 Show full raw log"
    echo -e "\n $(print_back_to_menu)"

    read_menu_choice 4

    case "$REPLY" in
      1)
        echo -e "\n🚫 \e[1mAll Banned IPs:\e[0m"
        grep "Ban " /var/log/fail2ban.log | less +G
        ;;
      2)
        echo -e "\n❗ \e[1mAll Failed Login Attempts:\e[0m"
        grep "Found " /var/log/fail2ban.log | less +G
        ;;
      3)
        echo -e "\n👀 \e[1mAll Suspicious Activity (Found + Ban):\e[0m"
        grep -E "Found |Ban " /var/log/fail2ban.log | less +G
        ;;
      4)
        echo -e "\n🧾 \e[1mFull Raw Fail2Ban Log:\e[0m"
        less +G /var/log/fail2ban.log
        ;;
      q|Q)
        break
        ;;
    esac
  done
}

show_f2b_menu() {
    if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo -e "➤ Please run the 🪛 \e[36mInit server\e[0m option first to install and configure Fail2Ban."
    sleep 2
    return
  fi

  if ! systemctl is-active --quiet fail2ban; then
    echo -e "\n⚠️  \e[1;33mFail2Ban is installed but not running.\e[0m"
    echo -e "➤ Start it with: \e[36msystemctl start fail2ban\e[0m"
    sleep 2
    return
  fi

  while true; do
    clear
    echo -e "\n\e[1m🛡️  Fail2Ban Management"
    echo    "────────────────────────────────────────────────────────────"

    echo -e "\n 1) 📊 Show status                2) 🟢 Manage whitelist"
    echo -e "\n 3) ℹ️ Show explanation           4) 🔥 Manage blocklist"
    echo -e "\n 5) 📄 Show log overview          $(print_back_to_menu)"
    
    read_menu_choice 5

    case "$REPLY" in
      1)
        show_f2b_status
        echo ""
        print_press_any_key
        ;;
      2)
        show_f2b_whitelist_menu
        ;;
      3)
        show_f2b_explanation
        echo ""
        print_press_any_key
        ;;
      4)
        show_f2b_blocklist_menu
        ;;
      5)
        show_f2b_logs_menu
        ;;
      q|Q)
        break
        ;;
    esac
  done
}
