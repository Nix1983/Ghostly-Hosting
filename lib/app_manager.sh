#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh
source ./lib/github.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/dotnet.sh
source ./lib/nginx.sh
source ./lib/app.sh


rollback_app_deployment() {
  cleanup_temp_folders
  delete_certbot_certificate
  delete_cloudflare_dns_records
}

add_new_app() {
  ensure_server_initialized || return 2
  show_app_deployment_requirements || return 2

  select_cloudflare_zone_and_domain  || return 2

  check_github_env_vars || return 2
  load_github_repositories || return 2
  while true; do
    select_github_repository || return 2
    select_branch_or_tag || continue
    break
  done
  clone_repository || return 1

  detect_required_dotnet_versions || return 1
  install_dotnet_version || return 1
  publish_dotnet_project || return 1

  setup_cloudflare_dns_for_blazor || return 1
  run_certbot_workflow || return 1

  deploy_to_domain_folder || return 1
  save_repo_metadata "$PUBLISH_DIR"
  cleanup_temp_folders || return 1

  create_kestrel_service || return 1
  setup_nginx_for_blazor_app || return 1

  read -rsn1 -p "$(print_press_any_key)"
}

show_apps() {
  local index=1
  local -A app_map=()
  local -A cf_proxy_map zone_ids

  clear
  echo -e "\n🧩 \e[1mDeployed .NET Apps\e[0m"
  print_double_line

  if [[ -n "$CLOUDFLARE_API_TOKEN" && -n "$CLOUDFLARE_API_BASE" ]]; then
    local zones_json
    zones_json=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "$CLOUDFLARE_API_BASE/zones")

    while IFS=$'\t' read -r name id; do
      zone_ids["$name"]="$id"
    done < <(echo "$zones_json" | jq -r '.result[] | [.name, .id] | @tsv')

    for domain in "${!zone_ids[@]}"; do
      local zone_id="${zone_ids[$domain]}"
      local dns_json
      dns_json=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "$CLOUDFLARE_API_BASE/zones/$zone_id/dns_records?type=A&per_page=500")

      while IFS=$'\t' read -r name proxied; do
        cf_proxy_map["$name"]=$([[ "$proxied" == "true" ]] && echo "✅" || echo "❌")
      done < <(echo "$dns_json" | jq -r '.result[] | [.name, .proxied] | @tsv')
    done
  fi

  while IFS= read -r service_file; do
    local service_name port domain exec_dir status_icon repo_name ram_kb ram_mb disk_mb uptime_readable cf_proxy

    service_name="$(basename "$service_file")"
    [[ "$service_name" != *.service ]] && continue

    local exec_line
    exec_line=$(systemctl show -p ExecStart "$service_name" 2>/dev/null | cut -d= -f2-)
    [[ "$exec_line" =~ --urls=http://0.0.0.0:([0-9]{4}) ]] || continue
    port="${BASH_REMATCH[1]}"

    exec_dir=$(systemctl show -p WorkingDirectory "$service_name" 2>/dev/null | cut -d= -f2)
    [[ -z "$exec_dir" || ! -d "$exec_dir" ]] && continue

    domain=$(echo "$service_name" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')

    if systemctl is-active --quiet "$service_name"; then
      status_icon="🟢"
    else
      status_icon="🔴"
    fi

    repo_name="–"
    if [[ -f "$exec_dir/meta.json" ]]; then
      repo_name=$(jq -r '.repo_name // "–"' "$exec_dir/meta.json")
      if [[ ${#repo_name} -gt 20 ]]; then
        repo_name="${repo_name:0:17}..."
      fi
    fi

    uptime_readable=" 0d 00h 00m 00s"
    if systemctl is-active --quiet "$service_name"; then
      local up_raw now elapsed_us sec
      up_raw=$(systemctl show -p ActiveEnterTimestampMonotonic "$service_name" | cut -d= -f2)
      if [[ "$up_raw" =~ ^[0-9]+$ ]]; then
        now=$(cut -d' ' -f1 /proc/uptime | awk '{printf "%.0f", $1 * 1000000}')
        elapsed_us=$((now - up_raw))
        sec=$((elapsed_us / 1000000))
        uptime_readable=$(printf "%2dd %02dh %02dm %02ds" $((sec/86400)) $((sec%86400/3600)) $((sec%3600/60)) $((sec%60)))
      fi
    fi

    cf_proxy="${cf_proxy_map[$domain]:-–}"

    ram_mb="0 MB"
    ram_kb=$(systemctl show "$service_name" -p MemoryCurrent | cut -d= -f2)
    if [[ "$ram_kb" =~ ^[0-9]+$ && "$ram_kb" -gt 0 ]]; then
      ram_mb="$((ram_kb / 1024 / 1024)) MB"
    fi

    disk_mb="–"
    if [[ -d "$exec_dir" ]]; then
      disk_mb="$(du -sm "$exec_dir" 2>/dev/null | awk '{print $1 " MB"}')"
    fi

    printf "\n %2d) %s \e]8;;https://%s\e\\%-20s\e]8;;\e\\ │ ⏱️ \e[2mUptime:\e[0m %-15s │ 🌩️ \e[2mCF-Proxy:\e[0m %-3s │ 🧠 \e[2mRAM:\e[0m \e[36m%6s\e[0m │ 💾 \e[2mDisk:\e[0m \e[36m%6s\e[0m\n" \
      "$index" "$status_icon" "$domain" "$repo_name" "$uptime_readable" "$cf_proxy" "$ram_mb" "$disk_mb"

    app_map["$index"]="$service_name"
    ((index++))
  done < <(find /etc/systemd/system -name "*.service" -type f | sort)

  if (( index == 1 )); then
    echo -e "\n⚠️ No .NET Apps found."
    read -rsn1 -p "$(print_press_any_key)"; return 1
  fi

  read_menu_choice "$((index - 1))"

  if [[ "$REPLY" =~ ^[Qq]$ ]]; then
    return 0
  elif [[ -n "${app_map[$REPLY]}" ]]; then
    export SELECTED_SERVICE="${app_map[$REPLY]}"
    show_app_details_menu "$SELECTED_SERVICE"
  fi
}

show_app_manager_menu() {
  local choice
  while true; do
    clear
    if [[ -n "${SERVER_IPv4:-}" ]]; then
      echo -e "\n🧩 \e[1;34mApp Control Panel\e[0m | $SERVER_IPv4"
    else
      echo -e "\n🧩 \e[1;34mApp Control Panel\e[0m"
    fi
    print_double_line

    echo -e "\n 1) ➕  Add new App    2) 🔍 Show Apps   3) 🖥️ Server Control Panel"
    echo -e "\n q) 🏃💨 \e[1;31mExit App Control\e[0m"
    
    read_menu_choice 3

    case "$REPLY" in
      1)
        add_new_app
        local exit_code=$?

        if [[ "$exit_code" -ne 0 ]]; then
          echo -e "\n❌ App deployment aborted."
          [[ "$exit_code" -eq 1 ]] && rollback_app_deployment
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      2)
        show_apps
        ;;
      3)
        return ;;
      q|Q) echo -e "\n🏃‍♂️💨 \e[1;31mExiting App Control Panel. Goodbye!\e[0m"; exit 0 ;;
    esac
  done
}

