#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh

_restart_timezone_services() {
  echo -e "\n🔄 \e[1mRestarting affected services...\e[0m"

  local services=("rsyslog" "fail2ban" "systemd-journald")
  for svc in "${services[@]}"; do
    if systemctl is-active --quiet "$svc"; then
      echo -e "↻ Restarting \e[36m$svc\e[0m..."
      systemctl restart "$svc"
    else
      echo -e "⚠️ \e[33m$svc is not running – skipping restart.\e[0m"
    fi
  done

  echo -e "✅ \e[1;32mAll relevant services refreshed.\e[0m"
}

prompt_and_set_timezone() {
  while true; do
    clear
    echo -e "\n🕒 \e[1mTimezone Setup\e[0m"
    print_double_line
    echo -e "How would you like to set the server timezone?\n"
    echo -e " 1) 🧠 Detect timezone from your current local time"
    echo -e " 2) 📚 Manually select from common timezones"
    echo -e " 3) 🌍 Use UTC (Coordinated Universal Time)"
    echo -e " $(print_back_to_menu)"

    read_menu_choice 3

    case "$REPLY" in
      1)
        if detect_timezone_from_input; then
          set_timezone "$SELECTED_TIMEZONE"
          return 0
        fi
        ;;
      2)
        if prompt_for_common_timezone; then
          set_timezone "$SELECTED_TIMEZONE"
          return 0
        fi
        ;;
      3)
        set_timezone "UTC"
        return 0
        ;;
      q|Q)
        return 1
        ;;
    esac
  done
}

detect_timezone_from_input() {
  local user_time offset_hours

  # Loop until valid time is entered
  while true; do
    clear
    echo -e "\n⌛ \e[1mTimezone Detection via Local Time\e[0m"
    print_double_line
    echo -e "Please enter your \e[36mcurrent local time\e[0m (24h format, e.g. \e[36m14:30\e[0m):"
    read -rp "> " user_time

    if [[ "$user_time" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]]; then
      break
    fi

    echo -e "\n❌ \e[31mInvalid time format. Please use HH:MM (e.g. 09:45 or 17:30).\e[0m"
    sleep 2
  done

  local user_hour=${user_time%:*}
  local user_minute=${user_time#*:}

  local utc_now
  utc_now=$(TZ=UTC date +%H:%M)
  local utc_hour=${utc_now%:*}
  local utc_minute=${utc_now#*:}

  local user_total=$((10#$user_hour * 60 + 10#$user_minute))
  local utc_total=$((10#$utc_hour * 60 + 10#$utc_minute))
  local diff=$((user_total - utc_total))

  [[ $diff -gt 720 ]] && diff=$((diff - 1440))
  [[ $diff -lt -720 ]] && diff=$((diff + 1440))

  offset_hours=$((diff / 60))
  local offset_str
  offset_str=$(printf "%+d" "$offset_hours")

  clear
  echo -e "\n🔍 Detected UTC offset: \e[36mUTC$offset_str\e[0m"
  echo -e "🔎 Searching matching timezones..."

  mapfile -t zone_candidates < <(
    timedatectl list-timezones | while read -r tz; do
      local zone_offset
      zone_offset=$(TZ="$tz" date +%z | sed 's/00$//;s/^\([+-]\)0/\1/')
      [[ "$zone_offset" == "$offset_str" ]] && echo "$tz"
    done | sort | head -n 10
  )

  # Add typical fallback European zones
  local fallback_zones=("Europe/Vienna" "Europe/Berlin" "Europe/Zurich" "Europe/Paris" "Europe/Rome")
  for fallback in "${fallback_zones[@]}"; do
    if [[ ! " ${zone_candidates[*]} " =~ $fallback ]]; then
      zone_candidates+=("$fallback")
    fi
  done

  # Loop until valid selection is made
  while true; do
    clear
    echo -e "\n📋 \e[1mSelect a matching timezone for:\e[0m \e[36mUTC$offset_str\e[0m"
    print_double_line

    local columns=3
    local width=30
    for i in "${!zone_candidates[@]}"; do
      local index=$((i + 1))
      printf " %2d) 🌍 \e[36m%-*s\e[0m" "$index" "$width" "${zone_candidates[$i]}"
      (( index % columns == 0 || index == ${#zone_candidates[@]} )) && echo ""
    done
    print_line
    echo "  $(print_back_to_menu)"
    read_menu_choice "${#zone_candidates[@]}"


    if [[ "$REPLY" =~ ^[Qq]$ ]]; then
      return 1
    fi
    
    if [[ "$REPLY" =~ ^[1-9][0-9]*$ ]] && (( REPLY <= ${#zone_candidates[@]} )); then
      SELECTED_TIMEZONE="${zone_candidates[REPLY-1]}"
      return 0
    fi

  done
}

prompt_for_common_timezone() {
  local zones=("Europe/Vienna" "Europe/Berlin" "Europe/Zurich" "UTC" "America/New_York" "Asia/Tokyo" "Asia/Dubai" "Australia/Sydney")

  while true; do
    clear
    echo -e "\n📚 \e[1mManual Timezone Selection\e[0m"
    print_double_line

    local columns=3
    local width=20
    for i in "${!zones[@]}"; do
      local index=$((i + 1))
      printf " %2d) 🌍 \e[36m%-*s\e[0m" "$index" "$width" "${zones[$i]}"
      (( index % columns == 0 || index == ${#zones[@]} )) && echo ""
    done

    print_line
    echo "  $(print_back_to_menu)"
    read_menu_choice "${#zones[@]}"

    if [[ "$REPLY" == "q" || "$REPLY" == "Q" ]]; then
      return 1
    elif [[ "$REPLY" =~ ^[1-9][0-9]*$ ]] && (( REPLY >= 1 && REPLY <= ${#zones[@]} )); then
      SELECTED_TIMEZONE="${zones[$((REPLY - 1))]}"
      return 0
    fi
  done
}

set_timezone() {
  local desired_tz="$1"
  echo -e "\n🕒 \e[1mConfiguring timezone to:\e[0m \e[36m$desired_tz\e[0m"

  local current_tz
  current_tz=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "unknown")

  if [[ "$current_tz" == "$desired_tz" ]]; then
    echo -e "✅ Timezone already set correctly: \e[1;32m$desired_tz\e[0m"
  else
    echo -e "🔄 Current timezone: \e[33m$current_tz\e[0m"
    echo -e "⚙️ Changing timezone to: \e[1;34m$desired_tz\e[0m"
    timedatectl set-timezone "$desired_tz"
    echo -e "✅ Timezone successfully updated: \e[1;32m$desired_tz\e[0m"
    _restart_timezone_services
  fi

  echo -e "🕒 Current system time: \e[36m$(date)\e[0m"
  sleep 2
}
