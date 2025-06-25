#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/github.sh

_show_log_file_menu() {
  local log_dir="$1"
  local title="$2"
  local domain="$3"

  if [[ ! -d "$log_dir" ]]; then
    echo -e "\n❌ No log directory found at: \e[2m$log_dir\e[0m"
    read -rsn1 -p "$(print_press_any_key)"
    return
  fi

  while true; do
    clear
    echo -e "\n$title 📁 \e[2m$log_dir\e[0m"
    print_double_line

    mapfile -t log_files < <(find "$log_dir" -maxdepth 1 -type f \( -iname "*.log" -o -iname "*.txt" -o -iname "*.log.json" \) -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)
    if (( ${#log_files[@]} == 0 )); then
      echo -e "\n  ℹ️  No log files found.\n"
    else
      local i=1 row=""
      for f in "${log_files[@]}"; do
        local size_kb name date_display
        size_kb=$(du -k "$f" | awk '{print $1}')
        name=$(basename "$f")
        if [[ "$name" =~ ([0-9]{2})-([0-9]{2})-([0-9]{4}) ]]; then
          date_display="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
        else
          date_display=$(date -r "$f" "+%d-%m-%Y")
        fi
        row+=" $(printf "%2d) 📄 %-10s \e[2m(%3s KB)\e[0m   " "$i" "$date_display" "$size_kb")"
        ((i % 3 == 0)) && { echo -e "$row"; row=""; }
        ((i++))
      done
      [[ -n "$row" ]] && echo -e "$row"
    fi

    echo -e "\n  $(print_back_to_menu)  🔗 \e[94m(https://$domain)\e[0m"
    read_menu_choice "${#log_files[@]}"
    echo ""

    if [[ "$REPLY" =~ ^[Qq]$ ]]; then
      return
    elif [[ "$REPLY" =~ ^[0-9]+$ && "$REPLY" -ge 1 && "$REPLY" -le "${#log_files[@]}" ]]; then
      local file="${log_files[$((REPLY - 1))]}"
      echo -e "\n📖 Viewing: \e[36m$(basename "$file")\e[0m"
      sed -e 's/\(err[^ ]*\)/\x1b[1;31m\1\x1b[0m/I' \
          -e 's/\(warn[^ ]*\)/\x1b[1;33m\1\x1b[0m/I' "$file" |
        less +G
    else
      print_invalid_selection
      sleep 1
    fi
  done
}

show_app_log_files() {
  local service="$1"
  local exec_dir domain log_dir
  exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
  domain=$(echo "$service" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')
  log_dir="$exec_dir/logs"
  _show_log_file_menu "$log_dir" "🧩 Application Logs:" "$domain"
}

show_webserver_access_logs() {
  local service="$1"
  local exec_dir domain log_dir
  exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
  domain=$(echo "$service" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')
  log_dir="$exec_dir/logs/webserver/access"
  _show_log_file_menu "$log_dir" "🌐 Web Server Access Logs:" "$domain"
}

show_webserver_error_logs() {
  local service="$1"
  local exec_dir domain log_dir
  exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
  domain=$(echo "$service" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')
  log_dir="$exec_dir/logs/webserver/error"
  _show_log_file_menu "$log_dir" "⚠️ Web Server Error Logs:" "$domain"
}

show_log_menu() {
  local service="$1"
  local exec_dir domain
  exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
  domain=$(echo "$service" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')

  while true; do
    clear
    echo -e "\n📊 \033[1mLog Viewer:🔗 \e[2m(https://$domain)\e[0m"
    print_double_line
    echo -e "\n 1) 🌐 Access Logs    \e[2m(Nginx access.log)\e[0m       2) ⚠️ Error Logs  \e[2m(Nginx error.log)\e[0m"
    echo -e "\n 3) 🧩 App Logs       \e[2m(Serilog, runtime etc.)\e[0m  $(print_back_to_menu)\n"
    read_menu_choice 3

    case "$REPLY" in
      1) show_webserver_access_logs "$service" ;;
      2) show_webserver_error_logs "$service" ;;
      3) show_app_log_files "$service" ;;
      q|Q) return ;;
    esac
  done
}
