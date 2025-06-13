#!/bin/bash
# shellcheck disable=SC1091
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh
source ./lib/print.sh
source ./lib/github.sh

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
        if select_github_repository; then
          echo ""
          read -rsn1 -p "$(print_press_any_key)"
        fi
        ;;
      2)
        echo -e "\n🔍 Listing deployed apps..."
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
