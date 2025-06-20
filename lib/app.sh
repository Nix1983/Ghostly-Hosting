#!/bin/bash
# shellcheck disable=SC1091
set -e

# Module einbinden
source ./lib/common.sh
source ./lib/print.sh


show_app_details_menu() {
  local service="$1"

  while true; do
    local exec_dir port status domain disk_size ram_mb main_dll log_path uptime_sec uptime_readable

    exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
    port=$(systemctl show -p ExecStart "$service" | grep -oP 'http://0\.0\.0\.0:\K[0-9]+')
    status=$(systemctl is-active "$service" &>/dev/null && echo "🟢 running" || echo "🔴 stopped")
    domain=$(echo "$service" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')
    disk_size=$(du -sm "$exec_dir" 2>/dev/null | awk '{print $1 " MB"}')
    ram_kb=$(systemctl show "$service" -p MemoryCurrent | cut -d= -f2)
    [[ "$ram_kb" =~ ^[0-9]+$ && "$ram_kb" -gt 0 ]] && ram_mb="$((ram_kb / 1024 / 1024)) MB" || ram_mb="–"
    main_dll=$(find "$exec_dir" -maxdepth 1 -name "*.dll" | head -n1 | xargs basename)
    log_path="/var/log/syslog"

    uptime_sec=$(systemctl show -p ActiveEnterTimestampMonotonic "$service" | cut -d= -f2)
    if [[ "$uptime_sec" -gt 0 ]]; then
      local now
      now=$(cut -d' ' -f1 /proc/uptime | awk '{printf "%.0f", $1 * 1000000}')
      local elapsed_us=$(( now - uptime_sec ))
      local seconds=$(( elapsed_us / 1000000 ))
      uptime_readable=$(printf '%dd %02dh %02dm %02ds' $((seconds/86400)) $((seconds%86400/3600)) $((seconds%3600/60)) $((seconds%60)))
    else
      uptime_readable="–"
    fi

    clear
    echo -e "🧾 \e[1mApp Details:\e[0m \e[36m🔗\e[0m \e]8;;https://$domain\e\\$domain\e]8;;\e\\"
    echo "═══════════════════════════════════════════════════════════════════════════════════"
    printf "\n📶 %-15s %-22s     🔌 %-14s %s\n" "Status:" "$status" "Port:" "$port"
    printf "💾 %-15s %-20s     🧠 %-14s %s\n" "Disk usage:" "$disk_size" "Memory usage:" "$ram_mb"
    printf "⏱️ %-15s %s\n" "Uptime:" "$uptime_readable"
    printf "📁 %-15s %s\n" "Directory:" "$exec_dir"
    printf "📦 %-15s %s\n" "DLL:" "$main_dll"
    echo "═══════════════════════════════════════════════════════════════════════════════════"

    echo " 1) 🔄 Restart App          2) ⏹️ Stop App         3) 🧹 Delete App"
    echo " 4) 📜 Show Logs            5) 🔼 Update App       6) ⚙️ Nginx Settings"
    echo -e " q) 🔙 Back"
    echo "───────────────────────────────────────────────────────────────────────────────────"
    print_select_prompt 6

    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      1)
        systemctl restart "$service" && echo "✅ Restarted."
        sleep 1
        ;;
      2)
        echo -n "❓ Are you sure you want to stop this app? [y/N]: "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          systemctl stop "$service" && echo "⏹️ Stopped."
        else
          echo "↩️  Canceled."
        fi
        sleep 1
        ;;
      3)
        echo -e "\n❗ Are you sure you want to delete the app and its folder?"
        echo -n "Type 'yes' to confirm: "
        read -r confirm
        if [[ "$confirm" == "yes" ]]; then
          systemctl stop "$service"
          systemctl disable "$service"
          rm -f "/etc/systemd/system/$service"
          systemctl daemon-reload
          rm -rf "$exec_dir"
          echo "✅ App and service deleted."
          read -rsn1 -p "$(print_press_any_key)"
          return 0
        else
          echo "↩️  Canceled."
          sleep 1
        fi
        ;;
      4)
        journalctl -u "$service" -n 100 --no-pager | less
        ;;
      5)
        echo -e "🔼 Update placeholder – implement logic here (e.g. pull repo, republish)..."
        sleep 2
        ;;
      6)
        show_nginx_settings_menu "$domain"
        ;;
      q|Q)
        return 0
        ;;
      *)
        print_invalid_selection
        sleep 1
        ;;
    esac
  done
}


