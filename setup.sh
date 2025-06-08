#!/bin/bash
# shellcheck disable=SC1091
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh
source ./lib/cloudflare.sh

print_requirements_header() {
  clear
  printf "\n\e[1;34m🚀 Blazor Hosting Setup – Cloudflare + UpCloud\e[0m\n"
  printf "═════════════════════════════════════════════════════════════\n"

  printf "\n📋 \e[1mBefore continuing, please make sure the following are ready:\e[0m\n"
  printf "─────────────────────────────────────────────────────────────\n"

  printf "🔹 \e[1mCloudflare Domain\e[0m registered in your account\n"
  printf "   → Must be visible under: https://dash.cloudflare.com\n\n"

  printf "🔹 \e[1mCloudflare API Token\e[0m with correct permissions:\n"
  printf "   • Zone → Read\n"
  printf "   • DNS → Edit\n"
  printf "   • Zone Settings → Read (for DNSSEC)\n"
  printf "   ➤ Set in .env as: CLOUDFLARE_API_TOKEN\n\n"

  printf "🔹 \e[1mUpCloud API Credentials\e[0m:\n"
  printf "   • API user + password (username must be API-enabled)\n"
  printf "   ➤ Set in .env as: UPCLOUD_API_USER / UPCLOUD_API_PASS\n\n"

  printf "🔹 \e[1mServer Requirement:\e[0m\n"
  printf "   • Ubuntu 22.04 or higher (clean install recommended)\n"
  printf "   • Root or sudo access required\n\n"

  printf "📦 All environment variables must be configured in: \e[4m.env\e[0m\n"
  printf "─────────────────────────────────────────────────────────────\n"

  printf "\n🔐 When you're ready to begin the automated setup...\n"
  printf "➡️ Press \e[1mENTER\e[0m to continue.\n"
  read -rs
  clear
}

print_requirements_header
load_env

select_cloudflare_zone_and_domain

set_timezone_to_vienna
set_swap
update_server

setup_cloudflare_dns_for_blazor