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


add_new_app() {
  show_app_deployment_requirements || return 1

  get_server_ip
  load_env || return 1

  select_cloudflare_zone_and_domain || return 1
  setup_cloudflare_dns_for_blazor || return 1
  run_certbot_workflow || return 1

  check_github_env_vars || return 1
  load_github_repositories || return 1
  select_github_repository || return 1
  clone_repository || return 1

  detect_required_dotnet_versions || return 1
  install_dotnet_version || return 1
  publish_dotnet_project || return 1

  deploy_to_domain_folder || return 1
  cleanup_temp_folders || return 1

  create_kestrel_service || return 1

  setup_nginx_for_blazor_app || return 1

  read -rsn1 -p "$(print_press_any_key)"
}



list_blazor_apps_clean() {
  local index=1
  local -A app_map=()
  local -A seen_services=()
  clear
  echo -e "\n📋 \e[1mDeployed Blazor Apps\e[0m"
  echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────"

  while IFS= read -r -d '' service_path; do
    local service_name raw domain exec_dir status ram_kb ram_mb disk_mb
    service_name="$(basename "$service_path")"
    [[ -n "${seen_services[$service_name]}" ]] && continue
    seen_services["$service_name"]=1

    # ➤ Domain-Korrektur
    raw="${service_name#blazor-}"
    raw="${raw%.service}"
    domain="$(echo "$raw" | awk -F'-' '{for(i=1;i<NF-1;i++) printf "%s.", $i; print $(NF-1) "." $NF}')"

    # Working directory
    exec_dir=$(systemctl show -p WorkingDirectory "$service_name" 2>/dev/null | cut -d= -f2)

    # Status
    if systemctl is-active --quiet "$service_name"; then
      status="🟢 running"
    else
      status="🔴 stopped"
    fi

    # RAM
    ram_mb="–"
    ram_kb=$(systemctl show "$service_name" -p MemoryCurrent | cut -d= -f2)
    if [[ "$ram_kb" =~ ^[0-9]+$ && "$ram_kb" -gt 0 ]]; then
      ram_mb="$((ram_kb / 1024 / 1024)) MB"
    fi

    # Disk
    disk_mb="–"
    if [[ -n "$exec_dir" && -d "$exec_dir" ]]; then
      disk_mb="$(du -sm "$exec_dir" 2>/dev/null | awk '{print $1 " MB"}')"
    fi

    [[ "$ram_mb" == "–" ]] && ram_mb="  –   "
    [[ "$disk_mb" == "–" ]] && disk_mb="  –   "
    # Ausgabe
    printf "\n %2d) 🌐 \e]8;;https://%s\e\\%-50s\e]8;;\e\\ │ %s │ 🧠 RAM: \e[36m%6s\e[0m │ 💾 Disk: \e[2m%6s\e[0m\n" \
      "$index" "$domain" "$domain" "$status" "$ram_mb" "$disk_mb"

    app_map["$index"]="$service_name"
    ((index++))
  done < <(find /etc/systemd/system -name "blazor-*.service" -print0 | sort -z)

  if (( index == 1 )); then
    echo -e "\n⚠️  No Blazor apps found."
    return 1
  fi

  echo -e "\n────────────────────────────────────────────────────────────────────────────────────────────────────────────"
  print_select_prompt "$((index-1))"
  read -r selection

  if [[ "$selection" =~ ^[Qq]$ ]]; then
    return 0
  elif [[ -n "${app_map[$selection]}" ]]; then
    export SELECTED_SERVICE="${app_map[$selection]}"
    echo "📂 Selected: $SELECTED_SERVICE"
  else
    print_invalid_selection
    return 1
  fi
}

show_app_manager_menu() {
  local choice

  while true; do
    clear
    echo -e "\n📦 \e[1;34mBlazor App Manager\e[0m"
    echo "═════════════════════════════════════════════════════════════"

    echo -e "\n 1) ➕  Add new App         2) 🔍  Show deployed Apps      3) 🚀  Deploy update"
    echo -e "\n 4) 📤  Backup App          5) ❌  Remove App              q) 🔙  Back to Menu"

    echo -e "\n─────────────────────────────────────────────────────────────"
    print_select_prompt 5

    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      1)
        if ! add_new_app; then
          echo -e "\n❌ App deployment aborted."
          cleanup_temp_folders
          delete_certbot_certificate
          delete_cloudflare_dns_records
          read -rsn1 -p "$(print_press_any_key)"
        fi
        echo ""
        ;;
      2)
        list_blazor_apps_clean
        sleep 1
        read -rsn1 -p "$(print_press_any_key)"
        ;;
      3)
        echo -e "\n🚀 Deploying app update..."
        sleep 1
        read -rsn1 -p "$(print_press_any_key)"
        ;;
      4)
        echo -e "\n📤 Creating app backup..."
        sleep 1
        read -rsn1 -p "$(print_press_any_key)"
        ;;
      5)
        echo -e "\n❌ Removing app..."
        sleep 1
        read -rsn1 -p "$(print_press_any_key)"
        ;;
      q|Q)
        break
        ;;
      *)
        print_invalid_selection
        sleep 0.5
        ;;
    esac
  done
}

show_app_manager_menu
