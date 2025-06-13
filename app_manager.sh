#!/bin/bash
# shellcheck disable=SC1091
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh
source ./lib/print.sh
source ./lib/github.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/dotnet.sh
source ./lib/nginx.sh


add_new_app() {
  select_github_repository || return 1

  echo -e "\n↩️  Press Enter to continue with Cloudflare setup..."
  read -r

  select_cloudflare_zone_and_domain || return 1
  setup_cloudflare_dns_for_blazor || return 1
  run_certbot_workflow || return 1
  setup_nginx_for_blazor_app "$HOSTNAME_FQDN" || return 1
  finalize_blazor_deployment || return 1
  create_and_start_blazor_service || return 1
}

list_blazor_apps_clean() {
  local index=1
  local -A app_map=()

  echo -e "\n📋 \e[1mDeployed Blazor Apps\e[0m"
  echo "────────────────────────────────────────────────────────────────────────────────────────────"
  printf "%3s │ %-30s │ %-15s │ %-8s │ %-10s │ %s\n" "#" "Domain" "App Name" ".NET" "Status" "Size"
  echo "────┼────────────────────────────────┼─────────────────┼──────────┼────────────┼────────────"

  while IFS= read -r -d '' service_path; do
    local service_name appname domain dll_name version size status exec_dir

    service_name="$(basename "$service_path")"
    appname="${service_name#blazor-}"
    appname="${appname%.service}"

    # Reverse domain-like (z. B. app-ghostlypick-com)
    domain="$(echo "$appname" | awk -F'-' '{for(i=NF;i>=2;i--) printf "%s.", $i; print $1}')"
    appname="$(systemctl show -p ExecStart "$service_name" 2>/dev/null | cut -d= -f2 | sed -E 's|.*/([^/]+)\.dll.*|\1|' | xargs)"

    exec_dir="$(systemctl show -p WorkingDirectory "$service_name" | cut -d= -f2)"

    dll_name=$(find "$exec_dir" -maxdepth 1 -name "*.dll" | head -n1)
    if [[ -n "$dll_name" ]]; then
      local runtimeconfig="${dll_name%.dll}.runtimeconfig.json"
      if [[ -f "$runtimeconfig" ]]; then
        version=$(jq -r '.runtimeOptions.framework.version // empty' "$runtimeconfig")
      fi
    fi
    [[ -z "$version" ]] && version="–"

    if systemctl is-active --quiet "$service_name"; then
      status="🟢 running"
    else
      status="🔴 stopped"
    fi

    size=$(du -sm "$exec_dir" 2>/dev/null | awk '{print $1 " MB"}')
    [[ -z "$size" ]] && size="–"

    printf "%3d │ %-30s │ %-15s │ %-8s │ %-10s │ %s\n" "$index" "$domain" "$appname" "$version" "$status" "$size"
    app_map["$index"]="$service_name"
    ((index++))
  done < <(find /etc/systemd/system -name "blazor-*.service" -print0 | sort -z)

  if (( index == 1 )); then
    echo "⚠️  No Blazor apps found."
    return 1
  fi

  echo "────────────────────────────────────────────────────────────────────────────────────────────"
  echo -n "❓ Select an app [1–$((index-1)), q]: "
  read -r selection

  if [[ "$selection" =~ ^[Qq]$ ]]; then
    return 0
  elif [[ -n "${app_map[$selection]}" ]]; then
    export SELECTED_SERVICE="${app_map[$selection]}"
    echo "📂 Selected: $SELECTED_SERVICE"
  else
    echo "❌ Invalid selection."
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
        add_new_app
        echo ""
        read -rsn1 -p "$(print_press_any_key)"
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
