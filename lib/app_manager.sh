#!/bin/bash
# shellcheck disable=SC1091
set -e

# Module einbinden
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

  get_server_ip --silent
  load_env || return 1

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
  clear
  echo -e "\n📋 \e[1mDeployed .NET Apps\e[0m"
  print_double_line

  while IFS= read -r service_file; do
    local service_name port domain exec_dir status ram_kb ram_mb disk_mb

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
      status="🟢 running"
    else
      status="🔴 stopped"
    fi

    ram_mb="0 MB"
    ram_kb=$(systemctl show "$service_name" -p MemoryCurrent | cut -d= -f2)
    if [[ "$ram_kb" =~ ^[0-9]+$ && "$ram_kb" -gt 0 ]]; then
      ram_mb="$((ram_kb / 1024 / 1024)) MB"
    fi

    disk_mb="–"
    if [[ -d "$exec_dir" ]]; then
      disk_mb="$(du -sm "$exec_dir" 2>/dev/null | awk '{print $1 " MB"}')"
    fi

    printf "\n %2d) 🌐 \e]8;;https://%s\e\\%-40s\e]8;;\e\\ │ %s │ 📦 Port: \e[36m%-5s\e[0m │ 🧠 RAM: \e[36m%6s\e[0m │ 💾 Disk: \e[2m%6s\e[0m\n" \
      "$index" "$domain" "$domain" "$status" "$port" "$ram_mb" "$disk_mb"

    app_map["$index"]="$service_name"
    ((index++))
  done < <(find /etc/systemd/system -name "*.service" -type f | sort)

  if (( index == 1 )); then
    echo -e "\n⚠️ No .NET Apps found."
    read -rsn1 -p "$(print_press_any_key)"
    return 1
  fi
  
  read_menu_choice "$((index-1))"


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
      echo -e "\n📦 \e[1;34mApp Control Panel\e[0m | $SERVER_IPv4"
    else
      echo -e "\n📦 \e[1;34mApp Control Panel\e[0m"
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

