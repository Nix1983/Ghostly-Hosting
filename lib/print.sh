#!/bin/bash
set -e

source ./lib/error_logging.sh
initialize_error_logging_for_script "${BASH_SOURCE[0]}" "$0"

print_cancel(){
    echo -e "\n q) ❌ \e[1mCancel\e[0m"
}

print_press_any_key() {
  echo "↩️ Press any key to continue..."
  read -rsn1
}


print_invalid_selection() {
    echo "❗ Invalid selection."
}

print_back_to_menu() {
  echo "q) 🔙 Back to menu"
}

print_select_prompt() {
  local max="$1"
  if [[ "$max" -eq 0 ]]; then
    echo -n "Please select [q]: "
  else
    echo -n "Please select [1–$max, q]: "
  fi
}

print_line(){
  echo "──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
}

print_double_line(){
  echo "══════════════════════════════════════════════════════════════════════════════════════════════════════════════════════"
}