#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/github.sh

_redeploy_blazor_app() {
  local exec_dir="$1"
  local service_name="$2"
  local commit="$3"
  local backup_dir="$exec_dir/backup"
  local log_dir="$exec_dir/logs"
  local meta_file="$exec_dir/meta.json"

  detect_required_dotnet_versions || return 1
  install_dotnet_version || return 1
  publish_dotnet_project || {
    echo -e "❌ \e[31mPublish failed – update aborted.\e[0m"
    cleanup_temp_folders
    return 1
  }

  echo -e "\n⏹️ \e[1mStopping service:\e[0m \e[36m$service_name\e[0m"
  systemctl stop "$service_name" 2>/dev/null || echo "⚠️ Could not stop service."

  backup_app_metadata "$exec_dir"

  [[ -d "$log_dir" ]] && cp -a "$log_dir" "$TMP_PUBLISH_DIR/logs"
  [[ -d "$backup_dir" ]] && cp -a "$backup_dir" "$TMP_PUBLISH_DIR/backup"

  echo -e "🧹 \e[1mCleaning deployment folder...\e[0m"
  [[ -d "$exec_dir" ]] && rm -rf "${exec_dir:?}"/*

  echo -e "📁 \e[1mDeploying new version...\e[0m"
  cp -r "$TMP_PUBLISH_DIR"/. "$exec_dir"/

  save_repo_metadata "$exec_dir" "$commit"
  cleanup_temp_folders

  echo -e "🚀 \e[1mRestarting service:\e[0m \e[36m$service_name\e[0m"
  if systemctl start "$service_name"; then
    echo -e "\n✅ \e[1;32mUpdate completed successfully.\e[0m"
  else
    echo -e "\n❌ \e[31mUpdate deployed but service could not be started.\e[0m"
    systemctl status "$service_name" --no-pager
  fi
}


delete_blazor_app() {
  local service="$1"
  local domain="$2"
  local exec_dir="$3"

  if [[ -z "$service" || -z "$domain" || -z "$exec_dir" ]]; then
    echo -e "❌ \e[31mMissing required parameters: service, domain or exec_dir.\e[0m"
    return 1
  fi

  clear
  echo -e "\n🧨 \e[1;31mApp Deletion Warning\e[0m"
  echo "────────────────────────────────────────────────────────────"
  echo -e "You are about to permanently delete:\n"
  echo " 🧩 Systemd service:       $service"
  echo " 📁 App folder:            $exec_dir"
  echo " 🌐 Nginx config for:      $domain"
  echo " 🔒 SSL certificate for:   $domain"
  echo " ☁️ Cloudflare DNS entry:  $domain"
  echo -e "\n⚠️ This includes all logs and backups inside the app folder!"
  echo -e "💣 \e[1mThis action cannot be undone.\e[0m"

  local confirm_code user_input
  confirm_code=$((RANDOM % 90000 + 10000))
  echo -e "\nTo confirm, please enter the code: \e[1;33m$confirm_code\e[0m (or type \e[36mq\e[0m to cancel)"
  read -rp $'\n🔐 Enter confirmation code: ' user_input

  if [[ "$user_input" == "q" || "$user_input" == "Q" ]]; then
    echo -e "\n↩️  \e[36mApp deletion cancelled.\e[0m"
    sleep 1
    return 1
  fi

  if [[ "$user_input" != "$confirm_code" ]]; then
    echo -e "\n❌ \e[31mDeletion aborted – confirmation failed.\e[0m"
    sleep 1
    return 1
  fi

  export HOSTNAME_FQDN="$domain"
  local _domain_part
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
    echo -e "🧹 \e[1mDeleting app folder (incl. logs & backups):\e[0m \e[2m$exec_dir\e[0m"
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

refresh_cloudflare_info_for_domain() {
  local domain="$1"

  export HOSTNAME_FQDN="$domain"
  load_env >/dev/null 2>&1

  local _domain_part
  _domain_part=$(echo "$domain" | awk -F. '{print $(NF-1)"."$NF}')
  export DOMAIN="$_domain_part"
  resolve_cloudflare_zone_id >/dev/null 2>&1

  cf_proxy=$(get_cloudflare_proxy_status "$domain" "$ZONE_ID" "$CLOUDFLARE_API_TOKEN")
  dns_ipv4=$(has_cloudflare_dns_record "$domain" "$ZONE_ID" "$CLOUDFLARE_API_TOKEN" "A")
  dns_ipv6=$(has_cloudflare_dns_record "$domain" "$ZONE_ID" "$CLOUDFLARE_API_TOKEN" "AAAA")
  dns_summary="A: $dns_ipv4  AAAA: $dns_ipv6"
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

backup_app_metadata() {
  local exec_dir="$1"
  local meta_file="$exec_dir/meta.json"
  local backup_dir="$exec_dir/backup"

  mkdir -p "$backup_dir"

  if [[ ! -f "$meta_file" ]]; then
    echo -e "❌ \e[31mmeta.json not found – cannot back up.\e[0m"
    return 1
  fi

  local commit
  commit=$(jq -r '.commit // empty' "$meta_file")
  if [[ -z "$commit" ]]; then
    echo -e "❌ \e[31mCommit hash not found in meta.json – aborting.\e[0m"
    return 1
  fi

  local timestamp
  timestamp=$(date +"%Y%m%dT%H%M%S")
  local new_backup="$backup_dir/meta-${timestamp}.json"

  if cp "$meta_file" "$new_backup"; then
    echo "✅ Backup saved to $new_backup"
  else
    echo -e "❌ \e[31mFailed to copy meta.json\e[0m"
    return 1
  fi

  mapfile -t matching_files < <(
    find "$backup_dir" -maxdepth 1 -type f -name "meta-*.json" \
    -exec jq -r '.commit // empty' {} \; -exec printf "%s\n" {} \; |
    paste - - | awk -v hash="$commit" '$1 == hash {print $2}'
  )

  if (( ${#matching_files[@]} > 1 )); then
    mapfile -t sorted < <(printf "%s\n" "${matching_files[@]}" | sort -r)
    local keep="${sorted[0]}"
    echo -e "\n🧹 Found multiple backups for commit \e[36m$commit\e[0m"
    echo -e "   ➕ Keeping latest: \e[2m$keep\e[0m"

    for f in "${sorted[@]:1}"; do
      rm -f "$f"
      echo -e "   ❌ Removed old duplicate: \e[2m$f\e[0m"
    done
  fi

  return 0
}

check_for_app_update() {
  local exec_dir="$1"
  local service_name="$2"
  local meta_file="$exec_dir/meta.json"

  clear
  echo -e "\n🔍 \e[1mChecking for App Updates\e[0m"
  echo "═════════════════════════════════════════════════════════════"

  if [[ -z "$exec_dir" || -z "$service_name" ]]; then
    echo -e "❌ \e[31mMissing parameters: execution directory or service name.\e[0m"
    return 1
  fi

  if [[ ! -f "$meta_file" ]]; then
    echo -e "❌ \e[31mNo metadata found at:\e[2m $meta_file\e[0m"
    return 1
  fi

  local repo_owner repo_name ref_type ref_name current_commit latest_commit
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
      export SELECTED_REPO_OWNER="$repo_owner"
      export SELECTED_REPO_NAME="$repo_name"
      export SELECTED_REF_TYPE="$ref_type"
      export SELECTED_REF_NAME="$ref_name"
      clone_repository || return 1
      _redeploy_blazor_app "$exec_dir" "$service_name" "$latest_commit"
      return $? ;;
    *) return 9 ;;
  esac
}


restore_app_backup() {
  local exec_dir="$1"
  local service_name="$2"
  local backup_dir="$exec_dir/backup"

  local subdomain parent domain
  subdomain=$(basename "$exec_dir")
  parent=$(basename "$(dirname "$exec_dir")")

  if [[ "$subdomain" == "root" ]]; then
    domain="$parent"
  else
    domain="$subdomain.$parent"
  fi
  domain="${domain//-/.}"

  if [[ ! -d "$backup_dir" ]]; then
    echo -e "\n❌ \e[31mBackup folder not found at:\e[2m $backup_dir\e[0m"
    return 1
  fi

  mapfile -t meta_files < <(find "$backup_dir" -maxdepth 1 -type f -name "meta-*.json" | sort -r)
  if (( ${#meta_files[@]} == 0 )); then
    echo -e "\n❌ \e[31mNo backup metadata files found.\e[0m"
    return 1
  fi

  local options=()
  local -A map_idx
  local i=1

  for file in "${meta_files[@]}"; do
    local filename timestamp datetime ref commit
    filename=$(basename "$file")
    timestamp="${filename//meta-/}"
    timestamp="${timestamp//.json/}"
    timestamp="${timestamp//T/}"
    datetime=$(date -d "${timestamp:0:8} ${timestamp:8:2}:${timestamp:10:2}:${timestamp:12:2}" "+%H:%M:%S %d-%m-%Y" 2>/dev/null || echo "$timestamp")
    ref=$(jq -r '.ref_name // "-" ' "$file")
    commit=$(jq -r '.commit // ""' "$file")
    options+=("$(printf " %2d) 🕒 %s  |  🌿 %s \e[2m(%s)\e[0m" "$i" "$datetime" "$ref" "${commit:0:7}")")
    map_idx["$i"]="$file"
    ((i++))
  done

  while true; do
    clear
    echo -e "\n♻️   Restore App from Backup | 🌐 \e[36m$domain\e[0m"
    echo -e "─────────────────────────────────────────────────────────────"
    printf "%s\n" "${options[@]}"
    echo -e "\n  $(print_back_to_menu)"
    echo "─────────────────────────────────────────────────────────────"
    print_select_prompt $((i - 1))
    read -r choice
    echo ""

    if [[ "$choice" =~ ^[Qq]$ ]]; then return 9; fi

    if [[ "$choice" =~ ^[0-9]+$ && -n "${map_idx[$choice]}" ]]; then
      local meta_file_restore="${map_idx[$choice]}"
      echo -e "\n✅ Selected Backup: \e[36m$meta_file_restore\e[0m"

      local owner repo ref_type ref_name commit
      owner=$(jq -r '.repo_owner // empty' "$meta_file_restore")
      repo=$(jq -r '.repo_name // empty' "$meta_file_restore")
      ref_type=$(jq -r '.ref_type // empty' "$meta_file_restore")
      ref_name=$(jq -r '.ref_name // empty' "$meta_file_restore")
      commit=$(jq -r '.commit // empty' "$meta_file_restore")

      if [[ -z "$owner" || -z "$repo" || -z "$ref_type" || -z "$ref_name" || -z "$commit" ]]; then
        echo -e "❌ \e[31mInvalid or incomplete metadata in: $meta_file_restore\e[0m"
        return 1
      fi

      export SELECTED_REPO_OWNER="$owner"
      export SELECTED_REPO_NAME="$repo"
      export SELECTED_REF_TYPE="$ref_type"
      export SELECTED_REF_NAME="$ref_name"

      echo -e "\n📦 Restoring from:\n - Repo: \e[36m$owner/$repo\e[0m\n - Ref:  \e[36m$ref_type → $ref_name\e[0m\n - Commit: \e[2m$commit\e[0m"

      clone_repository "$commit" || return 1
      _redeploy_blazor_app "$exec_dir" "$service_name" "$commit"
      return $?
    else
      print_invalid_selection
      sleep 1
    fi
  done
}

restart_app_service() {
  local service="$1"
  if systemctl restart "$service"; then
    echo "✅ Restarted."
  else
    echo -e "❌ \e[31mFailed to restart service.\e[0m"
  fi
  sleep 1
}

stop_app_service() {
  local service="$1"
  printf "❓ Are you sure you want to stop this app? [y/N]: "
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    systemctl stop "$service" && echo "⏹️ Stopped." || echo -e "❌ \e[31mFailed to stop.\e[0m"
    sleep 1
  fi
}

delete_app_interactively() {
  local service="$1"
  local domain="$2"
  local exec_dir="$3"

  delete_blazor_app "$service" "$domain" "$exec_dir"
  [[ $? -ne 1 ]] && return 0
  return 1
}

update_app_interactively() {
  local exec_dir="$1"
  local service="$2"

  check_for_app_update "$exec_dir" "$service"
  local exit_code=$?
  [[ "$exit_code" -ne 9 ]] && read -rsn1 -p "$(print_press_any_key)"
}

_load_dynamic_app_info() {
  local service="$1"
  local exec_dir="$2"

  status=$(systemctl is-active "$service" &>/dev/null && printf "\e[32m🟢 running\e[0m" || printf "\e[31m🔴 stopped\e[0m")

  local ram_kb
  ram_kb=$(systemctl show "$service" -p MemoryCurrent | cut -d= -f2)
  if [[ "$ram_kb" =~ ^[0-9]+$ && "$ram_kb" -gt 0 ]]; then
    ram_mb="$((ram_kb / 1024 / 1024)) MB"
  else
    ram_mb="0 MB"
  fi

  main_dll=$(find "$exec_dir" -maxdepth 1 -name "*.dll" | head -n1 | xargs basename 2>/dev/null)

  local uptime_monotonic
  uptime_monotonic=$(systemctl show -p ActiveEnterTimestampMonotonic "$service" | cut -d= -f2)
  if [[ "$uptime_monotonic" -gt 0 ]]; then
    local now elapsed_us seconds
    now=$(cut -d' ' -f1 /proc/uptime | awk '{printf "%.0f", $1 * 1000000}')
    elapsed_us=$((now - uptime_monotonic))
    seconds=$((elapsed_us / 1000000))
    uptime_readable=$(printf '%02dd %02dh %02dm %02ds' $((seconds/86400)) $((seconds%86400/3600)) $((seconds%3600/60)) $((seconds%60)))
  else
    uptime_readable="–"
  fi
}

show_app_details_menu() {
  local service="$1"

  local exec_dir port domain disk_size ram_mb main_dll uptime_readable ssl_status auto_renew
  local cf_proxy dns_ipv4 dns_ipv6 dns_summary

  exec_dir=$(systemctl show -p WorkingDirectory "$service" | cut -d= -f2)
  port=$(systemctl show -p ExecStart "$service" | grep -oP 'http://0\.0\.0\.0:\K[0-9]+')
  domain=$(echo "$service" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')
  disk_size=$(du -sm "$exec_dir" 2>/dev/null | awk '{print $1 " MB"}')

  local cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
  if [[ -f "$cert_path" ]]; then
    local expiry_raw expiry_date expiry_ts now_ts days_left
    expiry_raw=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
    if [[ -n "$expiry_raw" ]]; then
      expiry_date=$(date -d "$expiry_raw" '+%Y-%m-%d')
      expiry_ts=$(date -d "$expiry_raw" +%s)
      now_ts=$(date +%s)
      days_left=$(( (expiry_ts - now_ts) / 86400 ))
      ssl_status=$([[ "$days_left" -ge 0 ]] && echo "$expiry_date (${days_left}d) ✅" || echo "expired ❌")
    else
      ssl_status="Unknown ⚠️"
    fi
  else
    ssl_status="Not found ❌"
  fi

  if systemctl list-timers --all | grep -q certbot.timer; then
    auto_renew="systemd ✅"
  elif crontab -l 2>/dev/null | grep -q certbot; then
    auto_renew="via cron ⚠️"
  else
    auto_renew="none ❌"
  fi

  refresh_cloudflare_info_for_domain "$domain"


  while true; do
    _load_dynamic_app_info "$service" "$exec_dir"
    clear
    printf "🧾 \033[1mApp Overview:\033[0m \033[36m%s\033[0m   %s\n" "$domain" "$status"
    printf "══════════════════════════════════════════════════════════════════════════════\n"
    printf "🔌 %-18s \e[36m%-22s\e[0m   📦 %-17s \e[36m%-30s\e[0m\n" "Port:" "$port" "DLL:" "$main_dll"
    printf "💾 %-18s \e[36m%-22s\e[0m   📁 %-17s \e[2m%-30s\e[0m\n" "Disk Usage:" "$disk_size" "App Directory:" "$exec_dir"
    printf "🧠 %-18s \e[36m%-22s\e[0m   ⏱️ %-17s \e[36m%-10s\e[0m\n" "Memory Usage:" "$ram_mb" "Uptime:" "$uptime_readable"
    printf "🔒 %-18s \e[36m%-23s\e[0m   ♻️ %-17s \e[36m%-20s\e[0m\n" "SSL Certificate:" "$ssl_status" "Auto Renew:" "$auto_renew"
    printf "🌩️ %-18s \e[36m%-23s\e[0m   📡 %-17s \e[36m%-20s\e[0m\n" "CF Proxy Active:" "$cf_proxy" "DNS Records:" "$dns_summary"
    printf "🌐 %-18s \e[36m%-22s\e[0m   🔗 %-17s \e[1;34mhttps://%s\e[0m\n" "HTTP Version:" "HTTP/2" "Access URL:" "$domain"
    printf "🛡️ %-18s \e[2m%-30s\e[0m\n" "Security Headers:" "[TODO Headers]"
    printf "══════════════════════════════════════════════════════════════════════════════\n"
    printf "\n 1) 📜 Show Logs         2) 🔼 Update App          3) 🔄 Restart App"
    printf "\n 4) 🛑 Stop App          5) 🧨 Delete App          6) 💾 Restore Backup"
    printf "\n 7) 🔀 Toggle CF Proxy   8) ⚙️ Nginx Settings      %s$(print_back_to_menu)"
    printf "\n──────────────────────────────────────────────────────────────────────────────\n"
    print_select_prompt 8

    IFS= read -rsn1 choice
    printf "\n"

    case "$choice" in
      1) show_app_log_files "$service" ;;
      2) update_app_interactively "$exec_dir" "$service" ;;
      3) restart_app_service "$service" ;;
      4) stop_app_service "$service" ;;
      5)
        delete_app_interactively "$service" "$domain" "$exec_dir"
        [[ $? -eq 0 ]] && return 0
        ;;
      6) restore_app_backup "$exec_dir" "$service" 
         read -rsn1 -p "$(print_press_any_key)"
         ;;
      7) toggle_cloudflare_proxy 
         refresh_cloudflare_info_for_domain "$domain"
         ;;
      8) show_nginx_settings_menu "$domain" ;;
      *) return 0 ;;
    esac
  done
}

