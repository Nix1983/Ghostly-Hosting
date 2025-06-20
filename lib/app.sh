#!/bin/bash
# shellcheck disable=SC1091
set -e

# Module einbinden
source ./lib/common.sh
source ./lib/print.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh

delete_blazor_app() {
  local service="$1"
  local domain="$2"
  local exec_dir="$3"

  if [[ -z "$service" || -z "$domain" || -z "$exec_dir" ]]; then
    echo -e "❌ \e[31mMissing required parameters: service, domain or exec_dir.\e[0m"
    return 1
  fi

  echo -e "\n🧨 \e[1;31mApp Deletion Warning\e[0m"
  echo "────────────────────────────────────────────────────────────"
  echo -e "You are about to permanently delete:\n"
  echo " 🧩 Systemd service:       $service"
  echo " 📁 App folder:            $exec_dir"
  echo " 🌐 Nginx config for:      $domain"
  echo " 🔒 SSL certificate for:   $domain"
  echo " ☁️ Cloudflare DNS entry:  $domain"
  echo -e "\nThis action cannot be undone."
  echo -n "Type 'yes' to confirm: "
  read -r confirm
  if [[ "$confirm" != "yes" ]]; then
    print_cancel
    sleep 0.5
    return 1
  fi
  
  export HOSTNAME_FQDN="$domain"
  load_env
  echo -e "\n⏹️ \e[1mStopping and disabling service:\e[0m \e[36m$service\e[0m"
  systemctl stop "$service" 2>/dev/null || true
  systemctl disable "$service" 2>/dev/null || true
  rm -f "/etc/systemd/system/$service"

  echo "🔄 Reloading systemd..."
  systemctl daemon-reexec
  systemctl daemon-reload

  if [[ -d "$exec_dir" ]]; then
    echo -e "🧹 \e[1mDeleting app folder:\e[0m \e[2m$exec_dir\e[0m"
    rm -rf "$exec_dir"
  else
    echo -e "ℹ️  App folder not found: \e[2m$exec_dir\e[0m"
  fi

  echo -e "\n⚙️  \e[1mRemoving Nginx config:\e[0m \e[36m$HOSTNAME_FQDN\e[0m"
  rm -f "/etc/nginx/sites-available/$HOSTNAME_FQDN"
  rm -f "/etc/nginx/sites-enabled/$HOSTNAME_FQDN"
  if nginx -t &>/dev/null; then
    systemctl reload nginx
    echo "✅ Nginx reloaded."
  else
    echo -e "⚠️  \e[33mNginx config test failed – please check manually.\e[0m"
  fi

  echo -e "\n🔐 \e[1mDeleting SSL certificate (Certbot)...\e[0m"
  delete_certbot_certificate

  echo -e "\n☁️  \e[1mDeleting Cloudflare DNS records...\e[0m"
  if [[ -n "$CLOUDFLARE_API_TOKEN" && -n "$CLOUDFLARE_API_BASE" && -n "$ZONE_ID" && -n "$HOSTNAME_FQDN" ]]; then
    if delete_cloudflare_dns_records; then
      echo "✅ DNS records successfully removed."
    else
      echo -e "⚠️  \e[33mCloudflare DNS deletion failed for $HOSTNAME_FQDN.\e[0m"
      echo -e "💡 Please check manually in the Cloudflare dashboard."
    fi
  else
    echo -e "⚠️  \e[33mMissing CLOUDFLARE_API_TOKEN, ZONE_ID or HOSTNAME_FQDN – cannot delete DNS.\e[0m"
    echo -e "🔎 Please delete DNS records manually for: \e[36m$HOSTNAME_FQDN\e[0m"
  fi

  echo -e "\n✅ \e[1;32mApp $HOSTNAME_FQDN fully deleted.\e[0m"
  read -rsn1 -p "$(print_press_any_key)"
}


show_app_details_menu() {
  local service="$1"

  while true; do
    local exec_dir port status domain disk_size ram_mb main_dll uptime_sec uptime_readable

    exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
    port=$(systemctl show -p ExecStart "$service" | grep -oP 'http://0\.0\.0\.0:\K[0-9]+')
    status=$(systemctl is-active "$service" &>/dev/null && echo "🟢 running" || echo "🔴 stopped")
    domain=$(echo "$service" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')
    disk_size=$(du -sm "$exec_dir" 2>/dev/null | awk '{print $1 " MB"}')
    ram_kb=$(systemctl show "$service" -p MemoryCurrent | cut -d= -f2)
    [[ "$ram_kb" =~ ^[0-9]+$ && "$ram_kb" -gt 0 ]] && ram_mb="$((ram_kb / 1024 / 1024)) MB" || ram_mb="–"
    main_dll=$(find "$exec_dir" -maxdepth 1 -name "*.dll" | head -n1 | xargs basename)

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
    echo -e " $(print_back_to_menu)"
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
        delete_blazor_app "$service" "$domain" "$exec_dir"
        return 0
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
