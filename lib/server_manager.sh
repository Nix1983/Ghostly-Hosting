#!/bin/bash
# shellcheck disable=SC1091
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh
source ./lib/print.sh
source ./lib/fail2ban.sh
source ./lib/upcloud.sh
source ./lib/dotnet.sh
source ./lib/server.sh

export DISABLE_CLEAR=true


show_server_manager_menu() {
  if [[ -z "$SERVER_IPv4" ]]; then
    echo -e "\n❌ \e[1;31mSERVER_IPv4 is not set.\e[0m"
    exit 1
  fi

  local choice
  while true; do
    clear
    echo -e "\n🖥️ \e[1;34mServer Control Panel\e[0m | $SERVER_IPv4"
    echo "═════════════════════════════════════════════════════════════"

    echo -e "\n 1) 🩺  Show Server Health   2) 🛡️  Fail2Ban Admin     3) 📦  App Control Panel"
    echo -e "\n 4) 🧰  Show .NET Versions   5) 🪛  Init Server        6) ☁️  UpCloud Admin"
    echo -e "\n 7) 🧨  Reset Server         8) 🔄  Update Server"
    echo -e "\n q) 🏃💨 \e[1;31mExit Server Control\e[0m"

    echo -e "\n─────────────────────────────────────────────────────────────"
    print_select_prompt 8

    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      1) show_server_health
         echo ""
         read -rsn1 -p "$(print_press_any_key)"
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
      6) show_upcloud_menu  ;;
      7) reset_server ;;
      8) update_server_and_show_status
         check_and_offer_reboot ;;
      q|Q) echo -e "\n🏃‍♂️💨 \e[1;31mExiting Server Control Panel. Goodbye!\e[0m"; exit 0 ;;
      *) print_invalid_selection ;;
    esac
  done
}

