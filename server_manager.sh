#!/bin/bash
# shellcheck disable=SC1091
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh
source ./lib/print.sh
source ./lib/fail2ban.sh


# 📦 Dummy-Funktionen
admin_upcloud() { echo -e "\n☁️  Managing UpCloud..."; sleep 1; }
install_dotnet_versions() { echo -e "\n🧰  Installing .NET SDKs..."; sleep 1; }
show_all_blazor_apps() { echo -e "\n📦  Listing Blazor apps..."; sleep 1; }
update_system() { echo -e "\n🔄  Updating system..."; sleep 1; }
init_server() { echo -e "\n🚀  Initializing server..."; sleep 1; }
reset_server() { echo -e "\n🧨  Resetting server..."; sleep 1; }

show_server_manager_menu() {

  if [[ -z "$SERVER_IPv4" ]]; then
    echo -e "\n❌ \e[1;31mSERVER_IPv4 is not set.\e[0m"
    exit 1
  fi

  local choice
  while true; do
    clear
    echo -e "\n📦 \e[1;34mBlazor Server Control Panel\e[0m | $SERVER_IPv4"
    echo "═════════════════════════════════════════════════════════════"

    echo -e "\n 1) 🩺  Show Health        2) 🛡️  Fail2Ban           3) ☁️  UpCloud Admin"
    echo -e "\n 4) 🧰  Install .NET       5) 📦  List Apps          6) 🔄  Update Server"
    echo -e "\n 7) 🚀  Init Server        8) 🧨  Reset Server"
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
      3) admin_upcloud ;;
      4) install_dotnet_versions ;;
      5) show_all_blazor_apps ;;
      6) update_system ;;
      7) init_server ;;
      8) reset_server ;;
      q|Q) echo -e "\n🏃‍♂️💨 \e[1;31mExiting Mail Control Panel. Goodbye!\e[0m"; break ;;
      *) print_invalid_selection ;;
    esac
  done
}

load_env
get_server_ip --silent

show_server_manager_menu
