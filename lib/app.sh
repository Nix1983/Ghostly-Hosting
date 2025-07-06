#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/github.sh
source ./lib/log.sh

_redeploy_blazor_app() {
  local service_name="$1"
  local commit="$2"
  local exec_dir backup_dir log_dir

  exec_dir=$(resolve_exec_dir_from_service_name "$service_name")
  backup_dir=$(resolve_backup_folder_from_service_name "$service_name")
  log_dir=$(resolve_log_folder_from_service_name "$service_name")

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

  [[ -d "$log_dir" ]] && cp -a "$log_dir" "$TMP_PUBLISH_DIR/$LOGS_DIR"
  [[ -d "$backup_dir" ]] && cp -a "$backup_dir" "$TMP_PUBLISH_DIR/$BACKUP_DIR"

  echo -e "🧹 \e[1mCleaning deployment folder...\e[0m"
  [[ -d "$exec_dir" ]] && rm -rf "${exec_dir:?}"/*

  echo -e "📁 \e[1mDeploying new version...\e[0m"
  cp -r "$TMP_PUBLISH_DIR"/. "$exec_dir"/

  save_repo_metadata "$exec_dir" "$commit"
  cleanup_temp_folders
  clean_published_output "$exec_dir" "$service_name"

  echo -e "🚀 \e[1mRestarting service:\e[0m \e[36m$service_name\e[0m"
  if systemctl start "$service_name"; then
    echo -e "\n✅ \e[1;32mUpdate completed successfully.\e[0m"
  else
    echo -e "\n❌ \e[31mUpdate deployed but service could not be started.\e[0m"
    systemctl status "$service_name" --no-pager
  fi
}

_load_dynamic_app_info() {
  local service="$1"
  local exec_dir
  exec_dir=$(resolve_exec_dir_from_service_name "$service")

  status=$(get_service_status_icon "$service")

  ram_size=$(get_service_ram_usage "$service")

  uptime=$(get_service_uptime "$service")
}

delete_app() {
  local service="$1"
  local domain 
  local exec_dir

  domain=$(resolve_domain_from_service_name "$service")
  exec_dir=$(resolve_exec_dir_from_service_name "$service")


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

  if ! confirm_action_code; then
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
  rm -f "/etc/systemd/system/multi-user.target.wants/$service"

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
  resolve_cloudflare_zone_id "$HOSTNAME_FQDN"
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

  # Remove nginx-loglink timer if no other apps exist
  if [[ -z "$(find "$APP_BASE_DIR" -type f -name '*.dll' 2>/dev/null)" ]]; then
    echo -e "\n🧹 \e[1mNo apps remaining – removing nginx log timer...\e[0m"
    systemctl disable --now nginx-loglink.timer 2>/dev/null || true
    rm -f /etc/systemd/system/nginx-loglink.timer
    rm -f /etc/systemd/system/nginx-loglink.service
    systemctl daemon-reload
  fi

  echo -e "\n✅ \e[1;32mApp $HOSTNAME_FQDN fully deleted.\e[0m"
  print_press_any_key
}

refresh_cloudflare_info_for_domain() {
  local domain="$1"

  export HOSTNAME_FQDN="$domain"

  if ! resolve_cloudflare_zone_id "$domain" >/dev/null 2>&1; then
    dns_summary="A: ❌  AAAA: ❌"
    cf_proxy="❌"
    return 1
  fi

  cf_proxy=$(get_cloudflare_proxy_status "$domain" "$ZONE_ID" "$CLOUDFLARE_API_TOKEN")
  dns_ipv4=$(has_cloudflare_dns_record "$domain" "$ZONE_ID" "$CLOUDFLARE_API_TOKEN" "A")
  dns_ipv6=$(has_cloudflare_dns_record "$domain" "$ZONE_ID" "$CLOUDFLARE_API_TOKEN" "AAAA")
  dns_summary="A: $dns_ipv4  AAAA: $dns_ipv6"
}

check_for_app_update() {
  local service_name="$1"
  local exec_dir

  exec_dir=$(resolve_exec_dir_from_service_name "$service_name")
  
  local meta_file="$exec_dir/$META_FILE_NAME"

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
      _redeploy_blazor_app "$service_name" "$latest_commit"
      return $? ;;
    *) return 9 ;;
  esac
}

restore_app_backup() {
  local exec_dir="$1"
  local service_name="$2"

  local subdomain parent domain backup_dir
  subdomain=$(basename "$exec_dir")
  parent=$(basename "$(dirname "$exec_dir")")

  if [[ "$subdomain" == "root" ]]; then
    domain="$parent"
  else
    domain="$subdomain.$parent"
  fi
  domain="${domain//-/.}"
 
  backup_dir=$(resolve_backup_folder_from_service_name "$service_name")
  mkdir -p "$backup_dir"
  if [[ ! -d "$backup_dir" ]]; then
    echo -e "\n❌ \e[31mBackup folder not found at:\e[2m $backup_dir\e[0m"
    return 1
  fi

  mapfile -t meta_files < <(find "$backup_dir" -maxdepth 1 -type f -name "meta-*.json" | sort -r)
  if (( ${#meta_files[@]} == 0 )); then
    echo -e "\n🗃️ \e[33mNo backup metadata found yet.\e[0m"
    echo -e "   A backup will be created automatically on the first app update."
    echo -e "📂 Target folder: \e[2m$backup_dir\e[0m"
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
    read_menu_choice $((i - 1))

    if [[ "$REPLY" =~ ^[Qq]$ ]]; then return 9; fi

    if [[ "$REPLY" =~ ^[0-9]+$ && -n "${map_idx[$REPLY]}" ]]; then
      local meta_file_restore="${map_idx[$REPLY]}"
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
      _redeploy_blazor_app "$service_name" "$commit"
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

  delete_app "$service"
  [[ $? -ne 1 ]] && return 0
  return 1
}

update_app_interactively() {
  local service="$1"

  check_for_app_update "$service"
  local exit_code=$?
  [[ "$exit_code" -ne 9 ]] && print_press_any_key
}

show_app_details_menu() {
  local service="$1"
  local cf_proxy="$2"
  local has_a="$3"
  local has_aaaa="$4"

  local exec_dir port disk_size main_dll ssl_status auto_renew dns_summary dns_warning fqdn
  
  fqdn=$(resolve_domain_from_service_name "$service")
  exec_dir=$(resolve_exec_dir_from_service_name "$service")
  port=$(resolve_port_from_service_name "$service")
  disk_size=$(get_dir_size "$exec_dir")
  main_dll=$(resolve_main_dll_from_service "$service")

  local cert_path="/etc/letsencrypt/live/$fqdn/fullchain.pem"
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

  dns_summary="A: $( [[ "$has_a" -eq 1 ]] && echo ✅ || echo ❌ )  AAAA: $( [[ "$has_aaaa" -eq 1 ]] && echo ✅ || echo ❌ )"

  if (( has_a == 0 && has_aaaa == 0 )); then
    dns_warning="⚠️ App is not reachable (no DNS entries found)"
  elif (( has_a == 0 )); then
    dns_warning="⚠️ App is not reachable via IPv4"
  elif (( has_aaaa == 0 )); then
    dns_warning="⚠️ App is not reachable via IPv6"
  else
    dns_warning=""
  fi

  while true; do
    _load_dynamic_app_info "$service"

    clear
    if [[ -n "$dns_warning" ]]; then
      printf "🧩 \033[1mApp Overview:\033[0m \033[36m%s\033[0m   %s   \e[1;31m%s\e[0m\n" "$fqdn" "$status" "$dns_warning"
    else
      printf "🧩 \033[1mApp Overview:\033[0m \033[36m%s\033[0m   %s\n" "$fqdn" "$status"
    fi
    print_double_line

    printf "🔌 %-18s \e[36m%-22s\e[0m   📦 %-17s \e[36m%-30s\e[0m\n" "Port:" "$port" "DLL:" "$main_dll"
    printf "💾 %-18s \e[36m%-22s\e[0m   📁 %-17s \e[2m%-30s\e[0m\n" "Disk Usage:" "$disk_size" "App Directory:" "$exec_dir"
    printf "🧠 %-18s \e[36m%-22s\e[0m   ⏱️ %-17s \e[36m%-10s\e[0m\n" "Memory Usage:" "$ram_size" "Uptime:" "$uptime"
    printf "🔒 %-18s \e[36m%-23s\e[0m   ♻️ %-17s \e[36m%-20s\e[0m\n" "SSL Certificate:" "$ssl_status" "SSL Auto Renew:" "$auto_renew"
    printf "🌩️ %-18s \e[36m%-23s\e[0m   📡 %-17s \e[36m%-20s\e[0m\n" "CF Proxy Active:" "$cf_proxy" "DNS Records:" "$dns_summary"
    printf "🌐 %-18s \e[36m%-22s\e[0m   🔗 %-17s \e[1;34mhttps://%s\e[0m\n" "HTTP Version:" "HTTP/2" "Access URL:" "$fqdn"
    printf "🛡️ %-18s \e[2m%-30s\e[0m\n" "Security Headers:" "[TODO Headers]"
    print_line

    printf "\n 1) 📜 Show Logs         2) 🔼 Update App          3) 🔄 Restart App"
    printf "\n 4) 🛑 Stop App          5) 🧨 Delete App          6) 💾 Restore Backup"
    printf "\n 7) 🔀 Toggle CF Proxy   8) ⚙️ Nginx Settings      %s$(print_back_to_menu)\n"

    read_menu_choice 8

    case "$REPLY" in
      1) show_log_menu "$service" ;;
      2) update_app_interactively "$service" ;;
      3) restart_app_service "$service" ;;
      4) stop_app_service "$service" ;;
      5)
        delete_app_interactively "$service"
        [[ $? -eq 0 ]] && return 0
        ;;
      6)
        restore_app_backup "$exec_dir" "$service"
        print_press_any_key
        ;;
      7)
        toggle_cloudflare_proxy "$fqdn"

        if resolve_cloudflare_zone_id "$fqdn"; then
          local proxy_result
          proxy_result=$(get_cloudflare_proxy_status "$fqdn" "$ZONE_ID" "$CLOUDFLARE_API_TOKEN")
          [[ "$proxy_result" == *"✅"* ]] && cf_proxy="✅" || cf_proxy="❌"
        fi
        ;;
      8)
        show_nginx_settings_menu "$fqdn"
        ;;
      q|Q) return 0 ;;
    esac
  done
}

