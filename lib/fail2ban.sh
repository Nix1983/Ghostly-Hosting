#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh

CONFIG_FILE="/etc/fail2ban/jail.local"

install_f2b() {
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo "📦 Fail2Ban not found – installing..."
    apt update && apt install -y fail2ban
  else
    echo "✅ Fail2Ban is already installed."
  fi
}

configure_f2b() {
  install_f2b

  {
    echo "[DEFAULT]"
    echo "bantime = -1"
    echo ""

    echo "[sshd]"
    echo "enabled = true"
    echo ""

    echo "[postfix]"
    echo "enabled = true"
    echo "port = smtp,ssmtp,submission"
    echo "filter = postfix"
    echo "logpath = /var/log/mail.log"
    echo "maxretry = 5"
    echo ""

    echo "[dovecot]"
    echo "enabled = true"
    echo "port = pop3,pop3s,imap,imaps,submission,465,993,995"
    echo "filter = dovecot"
    echo "logpath = /var/log/mail.log"
    echo "maxretry = 5"
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

  local jails=("dovecot" "postfix")
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
  printf "🔐 %-22s %-18s %-18s %-18s\n" "Jail:" "📥 dovecot" "📬 postfix" "🔢 Total"
  echo   "───────────────────────────────────────────────────────────────────────"
  printf "❗ %-22s %-18s %-18s %-18s\n" "Failed (active):" \
    "${values[dovecot.currently_failed]:-0}" "${values[postfix.currently_failed]:-0}" "${totals[currently_failed]}"
  printf "🔁 %-22s %-18s %-18s %-18s\n" "Failed (total):" \
    "${values[dovecot.total_failed]:-0}" "${values[postfix.total_failed]:-0}" "${totals[total_failed]}"
  printf "🔒 %-22s %-18s %-18s %-18s\n" "Currently banned:" \
    "${values[dovecot.currently_banned]:-0}" "${values[postfix.currently_banned]:-0}" "${totals[currently_banned]}"
  printf "🧾 %-22s %-18s %-18s %-18s\n" "Banned IPs (total):" \
    "${values[dovecot.total_banned]:-0}" "${values[postfix.total_banned]:-0}" "${totals[total_banned]}"
  echo "───────────────────────────────────────────────────────────────────────"

  # Funktion zur robusten Zählung von ignoreip/bannedip
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
  local wl_postfix; wl_postfix=$(count_section_ips "postfix" "ignoreip")
  local wl_dovecot; wl_dovecot=$(count_section_ips "dovecot" "ignoreip")
  local wl_total=$((wl_global + wl_postfix + wl_dovecot))
  printf "🟢 %-22s %-18s %-18s %-18s\n" "Whitelist entries:" \
    "$wl_dovecot" "$wl_postfix" "$wl_total"
  echo "──────────────────────────────────────────────────────────────────────"

  echo -e "\n🔥 \e[1mPermanently Banned IPs (bantime = -1):\e[0m"
  echo "──────────────────────────────────────────────────────────────────────"
  local bl_global; bl_global=$(count_section_ips "DEFAULT" "bannedip")
  local bl_postfix; bl_postfix=$(count_section_ips "postfix" "bannedip")
  local bl_dovecot; bl_dovecot=$(count_section_ips "dovecot" "bannedip")
  local bl_total=$((bl_global + bl_postfix + bl_dovecot))
  printf "🔴 %-22s %-18s %-18s %-18s\n" "Permanent blocklist:" \
    "$bl_dovecot" "$bl_postfix" "$bl_total"
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
  local result_map_name="$1"
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
        eval "${result_map_name}[$index]=\"$ip|$section\""
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
  local -A postfix_ips=()
  local -A dovecot_ips=()

  local -i global_idx=1 postfix_idx=1 dovecot_idx=1

  for id in $(printf "%s\n" "${!target_map[@]}" | sort -n); do
    entry="${target_map[$id]}"
    ip=$(cut -d'|' -f1 <<< "$entry")
    section=$(cut -d'|' -f2 <<< "$entry")

    case "$section" in
      postfix) postfix_ips[$postfix_idx]="$id"; ((postfix_idx++)) ;;
      dovecot) dovecot_ips[$dovecot_idx]="$id"; ((dovecot_idx++)) ;;
      *)       global_ips[$global_idx]="$id";  ((global_idx++)) ;;
    esac
  done

  local max_rows=${#global_ips[@]}
  (( ${#postfix_ips[@]} > max_rows )) && max_rows=${#postfix_ips[@]}
  (( ${#dovecot_ips[@]} > max_rows )) && max_rows=${#dovecot_ips[@]}

  local -i display_index=1

  # Überschriften exakt zentriert in 24 Zeichen breiten Spalten
  printf "\n \e[35m%-24s\e[0m \e[36m%-24s\e[0m \e[32m%-24s\e[0m\n" "🌍 Global" "  📬 postfix" "    📥 dovecot"
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

    if [[ -n "${postfix_ips[$i]}" ]]; then
      id="${postfix_ips[$i]}"
      ip=$(cut -d'|' -f1 <<< "${target_map[$id]}")
      out2="$(printf "%2d) %-17s" "$display_index" "$ip")"
      ip_index_map[$display_index]="$id"
      ((display_index++))
    else
      out2=" "
    fi

    if [[ -n "${dovecot_ips[$i]}" ]]; then
      id="${dovecot_ips[$i]}"
      ip=$(cut -d'|' -f1 <<< "${target_map[$id]}")
      out3="$(printf "%2d) %-17s" "$display_index" "$ip")"
      ip_index_map[$display_index]="$id"
      ((display_index++))
    else
      out3=" "
    fi

    # farbige IPs pro Spalte
    printf " \e[1;33m%-24s\e[0m \e[1;33m%-24s\e[0m \e[1;33m%-24s\e[0m\n" "$out1" "$out2" "$out3"
  done
}

remove_ip_from_whitelist_by_ip() {
  local ip_to_remove="$1"
  local section="$2"
  local config="$CONFIG_FILE"
  local temp_file

  temp_file=$(mktemp)

  # Sektion extrahieren & neu schreiben
  awk -v section="$section" -v ip="$ip_to_remove" '
    BEGIN { in_section=0 }
    /^\[.*\]/ {
      in_section = ($0 == "[" section "]")
    }
    {
      if (in_section && $0 ~ /^ignoreip[[:space:]]*=/) {
        # Zeile ohne zu entfernende IP neu zusammensetzen
        split($0, parts, "=")
        n = split(parts[2], ips, /[[:space:]]+/)
        new_line = "ignoreip ="
        for (i = 1; i <= n; i++) {
          if (ips[i] != "" && ips[i] != ip) {
            new_line = new_line " " ips[i]
          }
        }
        if (new_line != "ignoreip =") {
          print new_line
        }
        next
      }
    }
    { print }
  ' "$config" > "$temp_file"

  mv "$temp_file" "$config"
}

remove_ip_from_whitelist() {
  clear
  echo -e "\n🧹 \e[1mRemove Whitelist Entry for:\e[0m \e[1;34m$DOMAIN\e[0m"
  echo -e "────────────────────────────────────────────────────────────"

  declare -gA whitelist_map
  if ! load_f2b_whitelist_entries whitelist_map; then
    echo -e "\n❌ No whitelist entries found."
    return 1
  fi

  print_f2b_ip_entries whitelist_map

  print_back_to_menu
  echo -e "────────────────────────────────────────────────────────────"
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
    if sudo systemctl restart fail2ban; then
      echo -e "✅ \e[1m$ip_to_remove successfully removed and Fail2Ban restarted.\e[0m"
    else
      echo -e "❌ Fail2Ban restart failed."
    fi
    return 0
  else
    print_invalid_selection
    print_press_any_key
    read -r
    return 1
  fi
}

add_ip_to_whitelist() {
  clear
  echo -e "\n➕ \e[1mAdd IP to Fail2Ban Whitelist for:\e[0m \e[1;34m$DOMAIN\e[0m"
  echo "────────────────────────────────────────────────────────────"
  
  show_whitelist_entrys
 
  print_back_to_menu
  echo -e "────────────────────────────────────────────────────────────"
  echo -n "Enter new IP address: "
  read -rp "" IP
  if [[ "$IP" == "q" || "$IP" == "Q" ]]; then
    return 1
  fi

  if [[ -z "$IP" ]]; then
    echo "❌ No IP entered."
    return
  fi

  if ! is_valid_ipv4 "$IP"; then
    echo "❌ Invalid IPv4 address: $IP"
    return
  fi

  echo -e "\n🔧 \e[1mWhere should the IP be added?\e[0m"
  echo "────────────────────────────────────────────────────────────"
  echo -e " 1) 🌍 Global (all jails)        2) 📬 postfix (SMTP only)"
  echo -e " 3) 📥 dovecot (IMAP/POP3)       $(print_back_to_menu)"
  echo -e "────────────────────────────────────────────────────────────"
  echo -n "Choose [1–3,q]: "

  IFS= read -rsn1 scope
  echo

  case $scope in
    1) SECTION="DEFAULT" ;;
    2) SECTION="postfix" ;;
    3) SECTION="dovecot" ;;
    q|Q) return 1 ;;
    *) print_invalid_selection ; return 1 ;;
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

  # IP in Ziel-Sektion eintragen
  if grep -q "^\[$SECTION\]" "$CONFIG_FILE"; then
    if grep -A 5 "^\[$SECTION\]" "$CONFIG_FILE" | grep -q "^ignoreip"; then
      sudo sed -i "/^\[$SECTION\]/,/^\[.*\]/ s/^\(ignoreip *= *\)\(.*\)/\1\2 $IP/" "$CONFIG_FILE"
    else
      sudo sed -i "/^\[$SECTION\]/ a ignoreip = $IP" "$CONFIG_FILE"
    fi
  else
    echo -e "\n[$SECTION]\nignoreip = $IP\n" | sudo tee -a "$CONFIG_FILE" > /dev/null
  fi

  echo -e "\n🔄 Restarting Fail2Ban..."
  if sudo systemctl restart fail2ban; then
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
  echo -e "\n🧹 \e[1mClear Entire Whitelist for:\e[0m \e[1;34m$DOMAIN\e[0m"
  echo -e "────────────────────────────────────────────────────────────"

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
  if sudo systemctl restart fail2ban; then
    echo -e "✅ \e[1mWhitelist cleared successfully and Fail2Ban restarted.\e[0m"
  else
    echo -e "❌ Fail2Ban restart failed."
  fi
}

show_f2b_whitelist_menu() {
  while true; do
    clear
    echo -e "\n\e[1m🟢  Fail2Ban Whitelist Menu for Domain:\e[0m \e[1;34m$DOMAIN\e[0m"
    echo -e "\e[1m──────────────────────────────────────────────────────\e[0m"

    show_whitelist_entrys

    echo -e "\n 1) ➕ Add IP address               2) ❌ Remove IP address"
    echo -e "\n 3) 🧼 Check whitelist for errors   4) 💣 Remove all IP addresses"
    echo -e "\n $(print_back_to_menu)"
    echo -e "\n──────────────────────────────────────────────────────"
    print_select_prompt 4

    IFS= read -rsn1 subchoice
    echo

    case "$subchoice" in
      1)
        if add_ip_to_whitelist; then
          echo ""
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      2)
        if remove_ip_from_whitelist; then
          echo ""
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      3)
        if show_whitelist_raw_entrys; then
          echo ""
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      4)
        if clear_fail2ban_whitelist; then
          echo ""
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      q|Q) break ;;
      *) print_invalid_selection ; sleep 0.5 ;;
    esac
  done
}

load_f2b_blocklist_entries() {
  local result_map_name="$1"
  local index=1
  local section=""
  local found_any=false

  while IFS= read -r line; do
    local trimmed
    trimmed=$(echo "$line" | xargs)

    if [[ "$trimmed" =~ ^\[.*\]$ ]]; then
      section="${trimmed#[}"; section="${section%]}"
    elif [[ "$trimmed" =~ ^bannedip[[:space:]]*=[[:space:]]*(.*) ]]; then
      for ip in ${BASH_REMATCH[1]}; do
        [[ -n "$ip" ]] || continue
        eval "${result_map_name}[$index]=\"$ip|$section\""
        found_any=true
        ((index++))
      done
    fi
  done < "$CONFIG_FILE"

  $found_any
}

add_ip_to_blocklist() {
  clear
  echo -e "\n➕ \e[1mAdd IP to Fail2Ban Blocklist for:\e[0m \e[1;34m$DOMAIN\e[0m"
  echo "────────────────────────────────────────────────────────────"

  echo -n "Enter new IP address: "
  read -rp "" IP
  if [[ "$IP" == "q" || "$IP" == "Q" ]]; then return 1; fi
  if [[ -z "$IP" ]]; then echo "❌ No IP entered."; return; fi
  if ! is_valid_ipv4 "$IP"; then echo "❌ Invalid IPv4 address: $IP"; return; fi

  echo -e "\n🔧 \e[1mWhich jail should block this IP?\e[0m"
  echo "────────────────────────────────────────────────────────────"
  echo -e " 1) 🌍 Global (all jails)        2) 📬 postfix"
  echo -e " 3) 📥 dovecot                   $(print_back_to_menu)"
  echo -e "────────────────────────────────────────────────────────────"
  echo -n "Choose [1–3,q]: "
  IFS= read -rsn1 scope; echo
  case $scope in
    1) SECTION="DEFAULT" ;;
    2) SECTION="postfix" ;;
    3) SECTION="dovecot" ;;
    q|Q) return 1 ;;
    *) print_invalid_selection; return 1 ;;
  esac

  # Prüfen ob IP schon irgendwo eingetragen ist
  local current_section
  current_section=$(awk -v ip="$IP" 'BEGIN { section="" }
    /^\[.*\]/ { section=$0 }
    $0 ~ "bannedip" && $0 ~ ip { print section }' "$CONFIG_FILE" | head -1 | sed 's/\[//;s/\]//')

  if [[ -n "$current_section" ]]; then
    if [[ "$current_section" == "$SECTION" ]]; then
      echo -e "ℹ️  IP \e[1;33m$IP\e[0m is already in [\e[1m$SECTION\e[0m]."
      return 0
    else
      echo -e "🔁 IP \e[1;33m$IP\e[0m is currently in [\e[1m$current_section\e[0m] – moving..."
      remove_ip_from_blocklist_by_ip "$IP" "$current_section"
    fi
  fi

  if grep -q "^\[$SECTION\]" "$CONFIG_FILE"; then
    if grep -A 5 "^\[$SECTION\]" "$CONFIG_FILE" | grep -q "^bannedip"; then
      sudo sed -i "/^\[$SECTION\]/,/^\[.*\]/ s/^\(bannedip *= *\)\(.*\)/\1\2 $IP/" "$CONFIG_FILE"
    else
      sudo sed -i "/^\[$SECTION\]/ a bannedip = $IP" "$CONFIG_FILE"
    fi
  else
    echo -e "\n[$SECTION]\nbannedip = $IP\n" | sudo tee -a "$CONFIG_FILE" > /dev/null
  fi

  echo -e "\n🔄 Restarting Fail2Ban..."
  if sudo systemctl restart fail2ban; then
    echo -e "✅ \e[1mIP $IP successfully added to [\e[1m$SECTION\e[0m] blocklist.\e[0m"
  else
    echo -e "❌ Fail2Ban restart failed."
  fi
}

remove_ip_from_blocklist_by_ip() {
  local ip="$1" section="$2"
  local temp_file
  temp_file=$(mktemp)

  awk -v section="$section" -v ip="$ip" '
    BEGIN { in_section=0 }
    /^\[.*\]/ { in_section = ($0 == "[" section "]") }
    {
      if (in_section && $0 ~ /^bannedip[[:space:]]*=/) {
        split($0, parts, "=")
        n = split(parts[2], ips, /[[:space:]]+/)
        new_line = "bannedip ="
        for (i = 1; i <= n; i++) {
          if (ips[i] != "" && ips[i] != ip) {
            new_line = new_line " " ips[i]
          }
        }
        if (new_line != "bannedip =") { print new_line }
        next
      }
    }
    { print }
  ' "$CONFIG_FILE" > "$temp_file"

  mv "$temp_file" "$CONFIG_FILE"
}

remove_ip_from_blocklist() {
  clear
  echo -e "\n🧹 \e[1mRemove Blocklist Entry for:\e[0m \e[1;34m$DOMAIN\e[0m"
  echo -e "────────────────────────────────────────────────────────────"

  declare -gA blocklist_map
  if ! load_f2b_blocklist_entries blocklist_map; then
    echo -e "\n❌ No blocklist entries found."
    return 1
  fi

  print_f2b_ip_entries blocklist_map
  echo ""
   print_back_to_menu
  echo -e "────────────────────────────────────────────────────────────"
  echo -n "Select the number of the IP to remove: "
  IFS= read -r selection
  echo

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    return 1
  fi

  if [[ "$selection" =~ ^[0-9]+$ && -n "${ip_index_map[$selection]}" ]]; then
    local id="${ip_index_map[$selection]}"
    local ip_to_remove section
    ip_to_remove=$(cut -d'|' -f1 <<< "${blocklist_map[$id]}")
    section=$(cut -d'|' -f2 <<< "${blocklist_map[$id]}")

    echo -e "\n🧹 Removing \e[1;33m$ip_to_remove\e[0m from [\e[1m$section\e[0m]..."

    remove_ip_from_blocklist_by_ip "$ip_to_remove" "$section"

    echo -e "🔄 Restarting Fail2Ban..."
    if sudo systemctl restart fail2ban; then
      echo -e "✅ \e[1m$ip_to_remove successfully removed and Fail2Ban restarted.\e[0m"
    else
      echo -e "❌ Fail2Ban restart failed."
    fi
    return 0
  else
    print_invalid_selection
    print_press_any_key
    read -r
    return 1
  fi
}

clear_fail2ban_blocklist() {
  clear
  echo -e "\n🧹 \e[1mClear Entire Blocklist for:\e[0m \e[1;34m$DOMAIN\e[0m"
  declare -a entries
  get_blocklist_entry_list entries

  if [[ ${#entries[@]} -eq 0 ]]; then
    echo -e "\n⚠️  No entries found in blocklist."
    return 1
  fi

  echo -e "\n⚠️  This will remove \e[1m${#entries[@]}\e[0m entries from the blocklist."
  read -rp " ❗  Are you sure you want to proceed? [y/N]: " confirm
  [[ ! "$confirm" =~ ^[Yy]$ ]] && echo -e "\n❎ Operation cancelled." && return 1

  for entry in "${entries[@]}"; do
    ip=$(cut -d'|' -f1 <<< "$entry")
    jail=$(cut -d'|' -f2 <<< "$entry")
    echo -e "❌ Removing \e[1;33m$ip\e[0m from [\e[1m$jail\e[0m]..."
    remove_ip_from_blocklist_by_ip "$ip" "$jail"
  done

  echo -e "\n🔄 Restarting Fail2Ban..."
  if sudo systemctl restart fail2ban; then
    echo -e "✅ \e[1mBlocklist cleared successfully.\e[0m"
  else
    echo -e "❌ Fail2Ban restart failed."
  fi
}

get_blocklist_entry_list() {
  local ref_name="$1"
  declare -A map
  eval "$ref_name=()"

  if ! load_f2b_blocklist_entries map; then return 1; fi

  for i in $(printf "%s\n" "${!map[@]}" | sort -n); do
    [[ -n "${map[$i]}" ]] && eval "$ref_name+=(\"\${map[\$i]}\")"
  done
}

show_blocklist_entrys() {
  declare -A blocklist_map
  if ! load_f2b_blocklist_entries blocklist_map; then
    echo -e "\n         🚫 Blocklist is currently empty."
    return 0
  fi
  print_f2b_ip_entries blocklist_map
}

show_f2b_blocklist_menu() {
  while true; do
    clear
    echo -e "\n\e[1m🔥 Fail2Ban Blocklist Menu for Domain:\e[0m \e[1;34m$DOMAIN\e[0m"
    echo -e "\e[1m──────────────────────────────────────────────────────\e[0m"

    show_blocklist_entrys

    echo -e "\n 1) ➕ Add IP address               2) ❌ Remove IP address"
    echo -e "\n 3) 🧼 Check blocklist entries      4) 💣 Remove all IP addresses"
    echo -e "\n $(print_back_to_menu)"
    echo -e "\n──────────────────────────────────────────────────────"
    print_select_prompt 4

    IFS= read -rsn1 subchoice
    echo

    case "$subchoice" in
      1)
        if add_ip_to_blocklist; then
          echo ""
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      2)
        if remove_ip_from_blocklist; then
          echo ""
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      3)
        grep -RnE '^\s*bannedip\s*=' "$CONFIG_FILE" || echo -e "\n🚫 No bannedip entries found."
        echo ""
        read -rsn1 -p "$(print_press_any_key)"
        ;;
      4)
        if clear_fail2ban_blocklist; then
          echo ""
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      q|Q) break ;;
      *) print_invalid_selection ; sleep 0.5 ;;
    esac
  done
}

show_f2b_logs_menu() {
  while true; do
    clear
    echo -e "\n\e[1m📄 Fail2Ban Log Viewer for:\e[0m \e[1;34m$DOMAIN\e[0m"
    echo -e "\e[1m──────────────────────────────────────────────────────\e[0m"
    echo -e "\n 1) 🚫 Show all banned IPs            2) ❗ Show all failed attempts"
    echo -e "\n 3) 👀 Show all suspicious activity   4) 🧾 Show full raw log"
    echo -e "\n $(print_back_to_menu)"
    echo -e "\n──────────────────────────────────────────────────────"
    print_select_prompt 4

    IFS= read -rsn1 logopt
    echo

    case "$logopt" in
      1)
        echo -e "\n🚫 \e[1mAll Banned IPs:\e[0m"
        grep "Ban " /var/log/fail2ban.log | less +G
        ;;
      2)
        echo -e "\n❗ \e[1mAll Failed login attempts:\e[0m"
        grep "Found " /var/log/fail2ban.log | less +G
        ;;
      3)
        echo -e "\n👀 \e[1mAll suspicious activity (Found + Ban):\e[0m"
        grep -E "Found |Ban " /var/log/fail2ban.log | less +G
        ;;
      4)
        echo -e "\n🧾 \e[1mFull Fail2Ban log:\e[0m"
        less +G /var/log/fail2ban.log
        ;;
      q|Q)
        break
        ;;
      *)
        print_invalid_selection
        sleep 0.5
        ;;
    esac
  done
}

show_f2b_menu() {

  if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo -e "\n❌ \e[1;31mFail2Ban is not installed.\e[0m"
    echo -e "➤ Please install it first: \e[36mapt install fail2ban\e[0m"
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
    echo -e "\n\e[1m🛡️  Fail2Ban Management for:\e[0m \e[1;34m$DOMAIN\e[0m"
    echo -e "\e[1m──────────────────────────────────────────────────────\e[0m"
    echo -e "\n 1) 📊 Show status                2) 🟢 Manage whitelist"
    echo -e "\n 3) ℹ️ Show explanation           4) 🔥 Manage blocklist"
    echo -e "\n 5) 📄 Show log overview          $(print_back_to_menu)"
    echo -e "\n──────────────────────────────────────────────────────"
    print_select_prompt 5

    IFS= read -rsn1 subchoice
    echo

    case "$subchoice" in
      1)
        show_f2b_status
        echo ""
        read -rsn1 -p "$(print_press_any_key)"
        ;;
      2)
        show_f2b_whitelist_menu
        ;;
      3)
        show_f2b_explanation
        echo ""
        read -rsn1 -p "$(print_press_any_key)"
        ;;
      4)
        show_f2b_blocklist_menu
        echo ""
        ;;
      5)
        show_f2b_logs_menu
        echo ""
        ;;
      q|Q)
        break
        ;;
      *)
        print_invalid_selection
        sleep 0.5
        ;;
    esac
  done
}