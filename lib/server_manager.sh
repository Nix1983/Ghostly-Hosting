#!/bin/bash
# shellcheck disable=SC1091,SC2034
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh
source ./lib/print.sh
source ./lib/fail2ban.sh
source ./lib/upcloud.sh
source ./lib/digitalocean.sh
source ./lib/firewall_provider.sh
source ./lib/dotnet.sh
source ./lib/server.sh
source ./lib/version.sh

export DISABLE_CLEAR=true


show_manual_firewall_info() {
  clear
  echo -e "\n⚙️  \e[1;33mManual Firewall Configuration\e[0m"
  print_double_line
  echo -e "\nYour server is configured with \e[1mmanual\e[0m firewall management."
  echo -e "No cloud provider API is used to manage firewall rules.\n"
  echo -e "\e[1mRequired open ports for Blazor hosting:\e[0m\n"
  echo -e "   🔐  Port \e[1m22\e[0m    (SSH)     – Remote server access"
  echo -e "   🌐  Port \e[1m80\e[0m    (HTTP)    – Web traffic & Let's Encrypt validation"
  echo -e "   🔒  Port \e[1m443\e[0m   (HTTPS)   – Secure web traffic (TLS/SSL)"
  echo -e "   📡  Port \e[1m53\e[0m    (DNS)     – Outbound DNS resolution\n"
  print_line
  echo -e "\n\e[1mRecommended firewall setup:\e[0m\n"
  echo -e "   • \e[2mDeny all incoming traffic by default\e[0m"
  echo -e "   • \e[2mAllow incoming on ports 22, 80, 443\e[0m"
  echo -e "   • \e[2mAllow outbound DNS (port 53 UDP/TCP)\e[0m"
  echo -e "   • \e[2mAllow all outbound traffic (for package updates, API calls)\e[0m\n"
  print_line
  echo -e "\n💡 \e[2mTo switch to a managed cloud provider, update CLOUD_PROVIDER in your .env file.\e[0m\n"
  print_press_any_key
}


show_server_manager_menu() {
  if [[ -z "$SERVER_IPv4" ]]; then
    echo -e "\n❌ \e[1;31mSERVER_IPv4 is not set.\e[0m"
    exit 1
  fi

  local choice
  while true; do
    clear
    echo -e "\n🖥️ \e[1;34mServer Control Panel\e[0m | $SERVER_IPv4 | $(format_version_display)"
    print_double_line

    local provider_menu_text=""
    if [[ "${CLOUD_PROVIDER:-}" == "other" ]]; then
      provider_menu_text="6) ⚙️  Firewall Info (Manual)"
    elif [[ -n "${CLOUD_PROVIDER:-}" ]]; then
      local provider_name
      provider_name=$(get_provider_display_name)
      provider_menu_text="6) ☁️  ${provider_name} Admin"
    fi

    echo -e "\n 1) 🩺  Show Server Health   2) 🛡️  Fail2Ban Admin     3) 🧩  App Control Panel"
    echo -e "\n 4) 🧰  Show .NET Versions   5) 🪛  Init Server        ${provider_menu_text}"
    echo -e "\n 7) 🌐  Reset Cloudlfare     8) 🔄  Update Server      9) 🧨  Reset Server "
    echo -e "\n q) 🏃💨 \e[1;31mExit Server Control\e[0m"

    read_menu_choice 9

    case "$REPLY" in
      1) show_server_health
         echo ""
         print_press_any_key
         ;;
      2) show_f2b_menu ;;
      3) return ;;
      4) show_dotnet_version_menu ;;
      5)
         if show_init_server_prompt; then
           if prompt_and_set_timezone; then
             init_server
             check_and_offer_reboot
           fi
         fi
         ;;
      6)
         if [[ "${CLOUD_PROVIDER:-}" == "other" ]]; then
           show_manual_firewall_info
         elif [[ -n "${CLOUD_PROVIDER:-}" ]]; then
           show_provider_menu
         fi
         ;;
      7) delete_all_cloudflare_dns_records_for_server ;;
      8) update_server_and_show_status
         check_and_offer_reboot ;;
      9) reset_server ;;
      q|Q) echo -e "\n🏃‍♂️💨 \e[1;31mExiting Server Control Panel. Goodbye!\e[0m"; exit 0 ;;
    esac
  done
}

