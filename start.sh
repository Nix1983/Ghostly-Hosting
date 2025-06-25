#!/bin/bash
# shellcheck disable=SC1091

source ./lib/constants.sh
source ./lib/common.sh
source ./lib/server_manager.sh
source ./lib/app_manager.sh

load_env
get_server_ip --silent

main_menu() {
  local current="app" 
  while true; do
    if [[ "$current" == "server" ]]; then
      show_server_manager_menu || exit 0
      current="app"
    else
      show_app_manager_menu || exit 0
      current="server"
    fi
  done
}

main_menu
