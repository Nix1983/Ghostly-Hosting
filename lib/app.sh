#!/bin/bash
# shellcheck disable=SC1091
set -e

# Module einbinden
source ./lib/common.sh
source ./lib/print.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/github.sh

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
    return 1
  fi
  
 export HOSTNAME_FQDN="$domain"
 _domain_part=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
 export DOMAIN="$_domain_part"

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

  echo -e "\n⚙️ \e[1mRemoving Nginx config:\e[0m \e[36m$HOSTNAME_FQDN\e[0m"
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

  echo -e "\n☁️ \e[1mDeleting Cloudflare DNS records...\e[0m"
  load_env
  resolve_cloudflare_zone_id
  if [[ -n "$CLOUDFLARE_API_TOKEN" && -n "$CLOUDFLARE_API_BASE" && -n "$ZONE_ID" && -n "$HOSTNAME_FQDN" ]]; then
    if delete_cloudflare_dns_records; then
      echo "✅ DNS records successfully removed."
    else
      echo -e "⚠️ \e[33mCloudflare DNS deletion failed for $HOSTNAME_FQDN.\e[0m"
      echo -e "💡 Please check manually in the Cloudflare dashboard."
    fi
  else
    echo -e "⚠️ \e[33mMissing CLOUDFLARE_API_TOKEN, ZONE_ID or HOSTNAME_FQDN – cannot delete DNS.\e[0m"
    echo -e "🔎 Please delete DNS records manually for: \e[36m$HOSTNAME_FQDN\e[0m"
  fi

  echo -e "\n✅ \e[1;32mApp $HOSTNAME_FQDN fully deleted.\e[0m"
  read -rsn1 -p "$(print_press_any_key)"
}

show_app_log_files() {
  local service="$1"
  local exec_dir
  exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
  local log_dir="$exec_dir/logs"

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

    mapfile -t log_files < <(find "$log_dir" -maxdepth 1 -type f -name "*.log" -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)
    if (( ${#log_files[@]} == 0 )); then
      echo -e "ℹ️  No log files found."
    else
      local i=1
      local row=""
      for f in "${log_files[@]}"; do
        local size
        size=$(du -k "$f" | cut -f1)
        local name
        name=$(basename "$f")
        row+=" $(printf "%2d) 📄 %-20s \e[2m%4s KB\e[0m   " "$i" "$name" "$size")"
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
        rm -f "$log_dir"/*.log
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
      sed -e 's/\\(err[^ ]*\\)/\\x1b[1;31m\\1\\x1b[0m/I' \
          -e 's/\\(warn[^ ]*\\)/\\x1b[1;33m\\1\\x1b[0m/I' "$file" |
        less +G
    else
      print_invalid_selection
      sleep 1
    fi
  done
}

check_for_app_update() {
  local exec_dir="$1"
  local service_name="$2"
  local meta_file="$exec_dir/meta.json"
  local backup_dir="$exec_dir/backup"
  local log_dir="$exec_dir/logs"

  clear
  echo -e "\n🔍 \e[1mChecking for App Updates\e[0m"
  echo "═════════════════════════════════════════════════════════════"

  if [[ -z "$exec_dir" || -z "$service_name" ]]; then
    echo -e "❌ \e[31mMissing parameters: execution directory or service name.\e[0m"
    return 1
  fi

  if [[ ! -f "$meta_file" ]]; then
    echo -e "❌ \e[31mNo metadata found at:\e[2m $meta_file\e[0m"
    echo -e "💡 App was likely deployed manually or with an old script version."
    return 1
  fi

  local repo_owner repo_name ref_type ref_name current_commit
  repo_owner=$(jq -r '.repo_owner // empty' "$meta_file")
  repo_name=$(jq -r '.repo_name // empty' "$meta_file")
  ref_type=$(jq -r '.ref_type // empty' "$meta_file")
  ref_name=$(jq -r '.ref_name // empty' "$meta_file")
  current_commit=$(jq -r '.commit // empty' "$meta_file")

  if [[ -z "$repo_owner" || -z "$repo_name" || -z "$ref_type" || -z "$ref_name" ]]; then
    echo -e "❌ \e[31mMetadata file is incomplete or malformed.\e[0m"
    return 1
  fi

  echo -e "📦 \e[1mRepository:\e[0m  \e[36m$repo_owner/$repo_name\e[0m"
  echo -e "🔗 \e[1mReference:\e[0m   \e[36m$ref_type → $ref_name\e[0m"
  echo -e "🔖 \e[1mCurrent commit:\e[0m \e[2m$current_commit\e[0m"

  if [[ "$ref_type" == "tag" ]]; then
    echo -e "\n⚠️  \e[33mThis app was deployed from a Git tag.\e[0m"
    echo -e "📌 Tags are fixed and cannot receive updates."
    return 0
  fi

  local latest_commit
  latest_commit=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
    "$GITHUB_API_BASE/repos/$repo_owner/$repo_name/commits/$ref_name" |
    jq -r '.sha // empty')

  if [[ -z "$latest_commit" ]]; then
    echo -e "\n❌ \e[31mFailed to retrieve latest commit from GitHub API.\e[0m"
    return 1
  fi

  echo -e "📥 \e[1mLatest commit:\e[0m  \e[2m$latest_commit\e[0m"

  if [[ "$current_commit" == "$latest_commit" ]]; then
    echo -e "\n✅ \e[1mThis app is already up to date.\e[0m"
    return 0
  fi

  echo -e "\n🆕 \e[1;32mA newer version is available!\e[0m"
  echo -e "   👉 Deployed: \e[2m$current_commit\e[0m"
  echo -e "   👉 Latest:   \e[2m$latest_commit\e[0m"

  echo -e "\n❓ \e[1mWould you like to update this app now?\e[0m"
  echo -e " \n1) 🔄 Yes, update now        q) 🔙 No, return to menu"
  echo "─────────────────────────────────────────────────────────────"
  echo -n "Select [1,q]: "
  IFS= read -rsn1 choice
  echo ""

  case "$choice" in
    1)
      echo -e "🔄 \e[1mUpdating app from GitHub...\e[0m"
      export SELECTED_REPO_OWNER="$repo_owner"
      export SELECTED_REPO_NAME="$repo_name"
      export SELECTED_REF_TYPE="$ref_type"
      export SELECTED_REF_NAME="$ref_name"

      clone_repository || return 1
      detect_required_dotnet_versions || return 1
      install_dotnet_version || return 1
      publish_dotnet_project || {
        echo -e "❌ \e[31mPublish failed – update aborted.\e[0m"
        cleanup_temp_folders
        return 1
      }

      echo -e "\n⏹️ \e[1mStopping service:\e[0m \e[36m$service_name\e[0m"
      systemctl stop "$service_name" 2>/dev/null || echo "⚠️ Could not stop service."

      # Ensure backup folder exists
      mkdir -p "$backup_dir"

      # Backup meta.json with timestamp BEFORE deletion
      if [[ -f "$meta_file" ]]; then
        local timestamp
        timestamp=$(date +"%Y%m%dT%H%M%S")
        local backup_path="$backup_dir/meta-${timestamp}.json"
        cp "$meta_file" "$backup_path" && echo "✅ Backup saved to $backup_path" || echo "❌ Failed to copy meta.json"
      else
        echo "❌ meta.json not found – cannot back up"
      fi

      # Preserve logs and backup in TMP_PUBLISH_DIR
      [[ -d "$log_dir" ]] && cp -a "$log_dir" "$TMP_PUBLISH_DIR/logs"
      [[ -d "$backup_dir" ]] && cp -a "$backup_dir" "$TMP_PUBLISH_DIR/backup"

      echo -e "🧹 \e[1mCleaning deployment folder...\e[0m"
      if [[ -d "$exec_dir" ]]; then
        rm -rf "${exec_dir:?}"/*
      fi

      echo -e "📁 \e[1mDeploying new version...\e[0m"
      cp -r "$TMP_PUBLISH_DIR"/. "$exec_dir"/

      save_repo_metadata "$exec_dir"
      cleanup_temp_folders

      echo -e "🚀 \e[1mRestarting service:\e[0m \e[36m$service_name\e[0m"
      if systemctl start "$service_name"; then
        echo -e "\n✅ \e[1;32mUpdate completed successfully.\e[0m"
      else
        echo -e "\n❌ \e[31mUpdate deployed but service could not be started.\e[0m"
        systemctl status "$service_name" --no-pager
      fi

      return 0
      ;;
    *)
      return 9
      ;;
  esac
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

    echo -e " 1) 📜 Show Logs             2) 📁 Show App Folder    3) 🔼 Update App"
    echo -e " 4) 🔄 Restart App           5) 🛑 Stop App           6) 🧹 Delete App"
    echo -e " 7) ⚙️ Nginx Settings        $(print_back_to_menu)"
    echo "───────────────────────────────────────────────────────────────────────────────────"
    print_select_prompt 7

    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      1)
        show_app_log_files "$service"
        ;;
      2)
        echo -n "Show folder"
        ;;
      3)
        check_for_app_update "$exec_dir" "$service"
        exit_code=$?
        if [[ "$exit_code" -ne 9 ]]; then
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      4)
        systemctl restart "$service" && echo "✅ Restarted."
        sleep 1
        ;;
      5)
        echo -n "❓ Are you sure you want to stop this app? [y/N]: "
        read -r confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
          systemctl stop "$service" && echo "⏹️ Stopped."
        fi
        ;;
      6)
        delete_blazor_app "$service" "$domain" "$exec_dir"
        return 0
        ;;
      7)
        show_nginx_settings_menu "$domain"
        ;;
      *)
        return 0
        ;;
    esac
  done
}