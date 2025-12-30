#!/bin/bash
# shellcheck disable=SC1091,SC2034
set -e

source ./lib/common.sh
source ./lib/print.sh
source ./lib/github.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/dotnet.sh
source ./lib/nginx.sh
source ./lib/app.sh
source ./lib/meta_data.sh
source ./lib/version.sh


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

  print_press_any_key
}

load_cloudflare_dns_info() {
  dns_map=()
  cf_proxy_map=()

  if [[ -n "$CLOUDFLARE_API_TOKEN" && -n "$CLOUDFLARE_API_BASE" ]]; then
    local zones_json zone_ids=()
    zones_json=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" "$CLOUDFLARE_API_BASE/zones")

    while IFS=$'\t' read -r name id; do
      zone_ids+=("$id")
    done < <(echo "$zones_json" | jq -r '.result[] | [.name, .id] | @tsv')

    for zone_id in "${zone_ids[@]}"; do
      local dns_json
      dns_json=$(curl -s -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        "$CLOUDFLARE_API_BASE/zones/$zone_id/dns_records?per_page=500")

      while IFS=$'\t' read -r name type proxied; do
        [[ -n "$name" && -n "$type" ]] || continue
        dns_map["$name,$type"]=1
        if [[ "$type" == "A" || "$type" == "AAAA" ]]; then
          if [[ "$proxied" == "true" ]]; then
            cf_proxy_map["${name,,}"]="✅"
          elif [[ ! ${cf_proxy_map[${name,,}]+_} ]]; then
            cf_proxy_map["${name,,}"]="❌"
          fi
        fi
      done < <(echo "$dns_json" | jq -r '.result[] | [.name, .type, (.proxied // "")] | @tsv')
    done
  fi
}

show_apps() {
  local index
  local -A app_map=()
  local -A cf_proxy_map dns_map proxy_map has_a_map has_aaaa_map

  local service_files
  mapfile -t service_files < <(find /etc/systemd/system -name "*.service" -type f | sort)

  local has_app=0
  for file in "${service_files[@]}"; do
    local name
    name="$(basename "$file")"
    if is_valid_kestrel_service_name "$name"; then
      has_app=1
      break
    fi
  done

  if (( has_app == 0 )); then
    clear
    echo -e "\n🧩  \e[1;33mNo .NET apps have been deployed yet.\e[0m"
    echo -e "\nℹ️  Use the \e[1mDeploy New App\e[0m option in the main menu"
    echo -e "    to select a Git repository and deploy your application."
    echo -e "    This will automatically set up a systemd service,"
    echo -e "    an SSL certificate, and an Nginx reverse proxy."
    print_press_any_key
    return 1
  fi

  while true; do
    index=1
    app_map=()
    proxy_map=()
    has_a_map=()
    has_aaaa_map=()

    clear
    echo -e "\n🔍 \e[1mLoading deployed apps...\e[0m \e[2mplease wait\e[0m"

    load_cloudflare_dns_info

    clear
    echo -e "\n🧩 \e[1mDeployed .NET Apps\e[0m"
    print_double_line

    for service_file in "${service_files[@]}"; do
      local service_name port fqdn exec_dir repo_name uptime
      local has_a has_aaaa dns_warning cf_proxy

      service_name="$(basename "$service_file")"
      is_valid_kestrel_service_name "$service_name" || continue

      if ! port=$(resolve_port_from_service_name "$service_name" 2>/dev/null); then
        continue
      fi

      if ! fqdn=$(resolve_domain_from_service_name "$service_name" 2>/dev/null); then
        continue
      fi

      if ! exec_dir=$(resolve_exec_dir_from_service_name "$service_name" 2>/dev/null); then
        continue
      fi
      [[ ! -d "$exec_dir" ]] && continue

      has_a="${dns_map[$fqdn,A]:-0}"
      has_aaaa="${dns_map[$fqdn,AAAA]:-0}"
      cf_proxy="${cf_proxy_map[$fqdn]:-❌}"

      if [[ "$has_a" -eq 0 && "$has_aaaa" -eq 0 ]]; then
        dns_warning="⚠️ App is not reachable (no DNS entries found)"
      elif [[ "$has_a" -eq 0 ]]; then
        dns_warning="⚠️ App is not reachable via IPv4"
      elif [[ "$has_aaaa" -eq 0 ]]; then
        dns_warning="⚠️ App is not reachable via IPv6"
      else
        dns_warning=""
      fi

      repo_name=$(get_repo_name_from_meta "$exec_dir/$META_FILE_NAME" 20)
      uptime=$(get_service_uptime "$service_name")
      ram_size=$(get_service_ram_usage "$service_name")
      disk_size="$(get_dir_size "$exec_dir")"
      status=$(get_service_status_icon "$service_name")

      local status_icon_display
      status_icon_display="${dns_warning:+⚠️}"
      status_icon_display="${status_icon_display:-$status}"

      printf "\n %2d) %s \e]8;;https://%s\e\\%-20s\e]8;;\e\\ │ ⏱️ \e[2mUptime:\e[0m %-15s │ 🌩️ \e[2mCF-Proxy:\e[0m %-3s │ 🧠 \e[2mRAM:\e[0m \e[36m%8s\e[0m │ 💾 \e[2mDisk:\e[0m \e[36m%6s\e[0m\n" \
        "$index" "$status_icon_display" "$fqdn" "$repo_name" "$uptime" "$cf_proxy" "$ram_size" "$disk_size"

      app_map["$index"]="$service_name"
      proxy_map["$index"]="$cf_proxy"
      has_a_map["$index"]="$has_a"
      has_aaaa_map["$index"]="$has_aaaa"
      ((index++))
    done

    read_menu_choice "$((index - 1))"
    if [[ "$REPLY" =~ ^[Qq]$ ]]; then
      return 0
    elif [[ -n "${app_map[$REPLY]}" ]]; then
      export SELECTED_SERVICE="${app_map[$REPLY]}"
      show_app_details_menu \
        "${app_map[$REPLY]}" \
        "${proxy_map[$REPLY]}" \
        "${has_a_map[$REPLY]}" \
        "${has_aaaa_map[$REPLY]}"

      if ! find /etc/systemd/system -name "*.service" -type f | grep -q .; then
        return 0
      fi
    fi
  done
}

show_app_manager_menu() {
  local choice
  while true; do
    clear
    if [[ -n "${SERVER_IPv4:-}" ]]; then
      echo -e "\n🧩 \e[1;34mApp Control Panel\e[0m | $SERVER_IPv4 | $(format_version_display)"
    else
      echo -e "\n🧩 \e[1;34mApp Control Panel\e[0m | $(format_version_display)"
    fi
    print_double_line

    echo -e "\n 1) 🧩 Show Apps    2) ➕ Add new App    3) 🖥️ Server Control Panel"
    echo -e "\n q) 🏃💨 \e[1;31mExit App Control\e[0m"
    
    read_menu_choice 3

    case "$REPLY" in
      1)
        show_apps 
        ;;
      2)
        add_new_app
        local exit_code=$?

        if [[ "$exit_code" -ne 0 ]]; then
          echo -e "\n❌ App deployment aborted."
          [[ "$exit_code" -eq 1 ]] && rollback_app_deployment
          print_press_any_key
        fi
        ;;
      3)
        return ;;
      q|Q) echo -e "\n🏃‍♂️💨 \e[1;31mExiting App Control Panel. Goodbye!\e[0m"; exit 0 ;;
    esac
  done
}