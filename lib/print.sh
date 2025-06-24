#!/bin/bash
set -e

print_cancel(){
    echo -e "\n q) ❌ \e[1mCancel\e[0m"
}

print_press_any_key() {
   echo "↩️ Press any key to continue..."
}

print_invalid_selection() {
    echo "❗ Invalid selection."
}

print_back_to_menu() {
  echo "q) 🔙 Back to menu"
}

print_select_prompt() {
  local max="$1"
  echo -n "Please select [1–$max, q]: "
}

print_line(){
  echo "──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
}

print_double_line(){
  echo "══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════"
}