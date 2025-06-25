#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/github.sh


show_app_log_files() {
  local service="$1"
  local exec_dir log_dir
  exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
  log_dir="$exec_dir/logs"

  if [[ ! -d "$log_dir" ]]; then
    echo -e "\n❌ No log directory found at: \e[2m$log_dir\e[0m"
    read -rsn1 -p "$(print_press_any_key)"
    return
  fi

  while true; do
    clear
    echo -e "\n📂 \e[1mAvailable App Log Files:\e[0m \e[36m$service\e[0m"
    echo -e "📁 Folder: \e[2m$log_dir\e[0m"
    echo "─────────────────────────────────────────────────────────────"

    mapfile -t log_files < <(find "$log_dir" -maxdepth 1 -type f \( -iname "*.log" -o -iname "*.txt" -o -iname "*.log.json" \) -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)
    if (( ${#log_files[@]} == 0 )); then
      echo -e "ℹ️  No log files found."
    else
      local i=1 row=""
      for f in "${log_files[@]}"; do
        local size_kb name date_display
        size_kb=$(du -k "$f" | awk '{print $1}')
        name=$(basename "$f")

        # Datum aus dem Dateinamen extrahieren, fallback auf date +%d-%m-%Y
        if [[ "$name" =~ ([0-9]{4})([0-9]{2})([0-9]{2}) ]]; then
          local y="${BASH_REMATCH[1]}" m="${BASH_REMATCH[2]}" d="${BASH_REMATCH[3]}"
          date_display="$d-$m-$y"
        else
          date_display=$(date -r "$f" "+%d-%m-%Y")
        fi

        row+=" $(printf "%2d) 📄 %-20s \e[2m(%3s KB)\e[0m   " "$i" "$date_display" "$size_kb")"
        ((i % 3 == 0)) && { echo -e "$row"; row=""; }
        ((i++))
      done
      [[ -n "$row" ]] && echo -e "$row"
    fi

    echo -e "\n d) 🧹 Delete all log files"
    echo -e " q) 🔙 Back to menu"
    echo "─────────────────────────────────────────────────────────────"
    print_select_prompt "${#log_files[@]}"
    read -r choice
    echo ""

    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
      return
    elif [[ "$choice" == "d" || "$choice" == "D" ]]; then
      echo -n "❓ Really delete ALL log files? [y/N]: "
      read -r confirm
      if [[ "$confirm" =~ ^[Yy]$ ]]; then
        find "$log_dir" -type f \( -iname "*.log" -o -iname "*.txt" -o -iname "*.log.json" \) -delete
        echo -e "✅ Deleted."
        sleep 1
      else
        echo "↩️ Cancelled."
        sleep 1
      fi
      continue
    elif [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#log_files[@]}" ]]; then
      local file="${log_files[$((choice - 1))]}"
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
