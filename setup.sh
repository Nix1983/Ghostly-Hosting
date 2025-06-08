#!/bin/bash
# shellcheck disable=SC1091
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh

# Ask user for domain and subdomain configuration (ShellCheck compliant)
prompt_domain_and_subdomain() {
  clear
  echo -e "\n\e[1m🌐 Configure domain for your Blazor Server App\e[0m"
  echo -e "────────────────────────────────────────────────────────────"

  read -rp "📛 Enter your root domain (e.g. ghostlypick.com): " domain_input
  domain_input="${domain_input,,}"

  if [[ -z "$domain_input" ]]; then
    echo -e "\n❌ Domain must not be empty. Aborting."
    exit 1
  fi

  echo -e "\n🌍 \e[1mHow should your app be accessible?\e[0m"
  echo "────────────────────────────────────────────────────────────"
  echo " 1) Use a subdomain  (e.g. app.$domain_input)"
  echo " 2) Use root domain  ($domain_input)"
  echo -e "────────────────────────────────────────────────────────────"
  read -rp "❓ Your choice [1–2]: " sub_choice

  case "$sub_choice" in
    1)
      echo ""
      read -rp "✏️  Enter subdomain (only the sub part, e.g. 'app'): " sub_input
      sub_input="${sub_input,,}"

      # Strip full domain suffix if user enters full FQDN
      if [[ "$sub_input" == *".${domain_input}" ]]; then
        sub_input="${sub_input%."$domain_input"}"
      fi

      if [[ -z "$sub_input" ]]; then
        echo -e "\n❌ Subdomain must not be empty. Aborting."
        exit 1
      fi

      fqdn="${sub_input}.${domain_input}"
      ;;
    2)
      fqdn="$domain_input"
      ;;
    *)
      echo -e "\n❌ Invalid selection. Aborting."
      exit 1
      ;;
  esac

  export HOSTNAME_FQDN="$fqdn"

  echo -e "\n📌 Your app will be hosted at: \e[1;34mhttps://$HOSTNAME_FQDN\e[0m"
}

prompt_domain_and_subdomain
load_env

