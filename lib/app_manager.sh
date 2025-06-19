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

  ensure_server_initialized || return 2
  show_app_deployment_requirements || return 2
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

list_hosted_apps() {
  local index=1
  local -A app_map=()
  clear
  echo -e "\n📋 \e[1mDeployed Kestrel Apps\e[0m"
  echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"

  while IFS= read -r service_file; do
    local service_name port domain exec_dir status ram_kb ram_mb disk_mb

    service_name="$(basename "$service_file")"
    [[ "$service_name" != *.service ]] && continue

    # Port aus ExecStart extrahieren
    local exec_line
    exec_line=$(systemctl show -p ExecStart "$service_name" 2>/dev/null | cut -d= -f2-)
    [[ "$exec_line" =~ --urls=http://0.0.0.0:([0-9]{4}) ]] || continue
    port="${BASH_REMATCH[1]}"

    # WorkingDirectory prüfen
    exec_dir=$(systemctl show -p WorkingDirectory "$service_name" 2>/dev/null | cut -d= -f2)
    [[ -z "$exec_dir" || ! -d "$exec_dir" ]] && continue

    # Domain korrekt aus dem Servicenamen extrahieren (z. B. 1-ghostlypick-com-5002 → 1.ghostlypick.com)
    domain=$(echo "$service_name" | sed -E 's/\.service$//' | sed -E 's/(.*)-([0-9]{4})$/\1/' | sed 's/-/\./g')

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
    if [[ -d "$exec_dir" ]]; then
      disk_mb="$(du -sm "$exec_dir" 2>/dev/null | awk '{print $1 " MB"}')"
    fi

    [[ "$ram_mb" == "–" ]] && ram_mb="  –   "
    [[ "$disk_mb" == "–" ]] && disk_mb="  –   "

    printf "\n %2d) 🌐 \e]8;;https://%s\e\\%-45s\e]8;;\e\\ │ %s │ 📦 Port: \e[36m%-5s\e[0m │ 🧠 RAM: \e[36m%6s\e[0m │ 💾 Disk: \e[2m%6s\e[0m\n" \
      "$index" "$domain" "$domain" "$status" "$port" "$ram_mb" "$disk_mb"

    app_map["$index"]="$service_name"
    ((index++))
  done < <(find /etc/systemd/system -name "*.service" -type f | sort)

  if (( index == 1 )); then
    echo -e "\n⚠️  No Kestrel-hosted apps found."
    return 1
  fi

  echo -e "\n────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
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
    echo -e "\n📦 \e[1;34mApp Control Panel\e[0m | $SERVER_IPv4"
    echo "═════════════════════════════════════════════════════════════"

    echo -e "\n 1) ➕  Add new App         2) 🔍  Show deployed Apps      3) 🚀  Deploy update"
    echo -e "\n 4) 📤  Backup App          5) ❌  Remove App              6) 🖥️  Server Control Panel"
    echo -e "\n q) 🏃💨 \e[1;31mExit Server Control\e[0m"

    echo -e "\n─────────────────────────────────────────────────────────────"
    print_select_prompt 6

    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      1)
        if ! add_new_app; then
          local exit_code=$?

          echo -e "\n❌ App deployment aborted."
          if [[ "$exit_code" -eq 1 ]]; then
            cleanup_temp_folders
            delete_certbot_certificate
            delete_cloudflare_dns_records
          fi

          read -rsn1 -p "$(print_press_any_key)"
        fi
        echo ""
        ;;
      2)
        list_hosted_apps
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
      6)
        return ;;
      q|Q) echo -e "\n🏃‍♂️💨 \e[1;31mExiting App Control Panel. Goodbye!\e[0m"; exit 0 ;;
      *)
        print_invalid_selection
        sleep 0.5
        ;;
    esac
  done
}

