#!/bin/bash
# shellcheck disable=SC1091
set -e

# ✨ Funktionen einbinden
source ./lib/common.sh

_check_cloudflare_env_vars() {
  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" ]]; then
    echo "❌ CLOUDFLARE_API_TOKEN or CLOUDFLARE_API_BASE is not set."
    exit 1
  fi
}

_upsert_dns_record() {
  local type="$1"
  local name="$2"
  local content="$3"
  local comment="$4"
  local proxied="$5"

  local response id current
  response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?type=$type&name=$name" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

  id=$(echo "$response" | jq -r '.result[0].id // empty')
  current=$(echo "$response" | jq -r '.result[0].content // empty')

  if [[ "$current" == "$content" ]]; then
    printf "✅ %s-record is already up to date: \033[36m%s → %s\033[0m\n" "$type" "$name" "$content"
    return
  fi

  local method url
  if [[ -n "$id" ]]; then
    method="PUT"
    url="$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records/$id"
    printf "♻️  Updating %s-record: \033[36m%s → %s\033[0m\n" "$type" "$name" "$content"
  else
    method="POST"
    url="$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records"
    printf "➕ Creating %s-record: \033[36m%s → %s\033[0m\n" "$type" "$name" "$content"
  fi

  curl -s -X "$method" "$url" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "$(jq -n \
      --arg type "$type" \
      --arg name "$name" \
      --arg content "$content" \
      --arg comment "$comment" \
      --argjson proxied "$proxied" \
      '{type: $type, name: $name, content: $content, ttl: 120, proxied: $proxied, comment: $comment}')" > /dev/null

  printf "✅ %s-record %s.\n" "$type" "$( [[ -n "$id" ]] && echo "updated" || echo "created" )"
}

select_cloudflare_zone_and_domain() {
  _check_cloudflare_env_vars

  local response zones
  local -A zone_map=()

  while true; do
    clear
    get_server_ip
    printf "\n☁️  \033[1mRetrieving Cloudflare zones...\033[0m\n"
    printf "────────────────────────────────────────────────────────────\n"

    response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    zones=$(echo "$response" | jq -r '.result[] | [.name, .id] | @tsv')

    if [[ -z "$zones" ]]; then
      printf "\n❌ \033[31mNo zones found in your Cloudflare account.\033[0m\n"
      printf "   ➤ Please add a domain at: \033[4mhttps://dash.cloudflare.com\033[0m\n"
      exit 1
    fi

    printf "\n🌐 \033[1mAvailable Cloudflare Zones:\033[0m\n"
    printf "────────────────────────────────────────────────────────────\n"
    local index=1
    zone_map=()
    while IFS=$'\t' read -r name id; do
      printf " %2d) \033[1;36m%-30s\033[0m\n" "$index" "$name"
      zone_map[$index]="$name:$id"
      ((index++))
    done <<< "$zones"

    printf "────────────────────────────────────────────────────────────\n"
    printf "❓ Select a domain by number: "
    read -r selection
    printf "\n"

    local selected="${zone_map[$selection]}"
    if [[ -z "$selected" ]]; then
      printf "⚠️  \033[33mInvalid selection.\033[0m Please try again.\n"
      sleep 1
      continue
    fi

    DOMAIN="${selected%%:*}"
    ZONE_ID="${selected##*:}"
    export DOMAIN ZONE_ID
    printf "✅ Selected Zone: \033[1;34m%s\033[0m\n" "$DOMAIN"

    # 🔍 Get all existing A/AAAA records
    local dns_response used_names root_taken=false
    dns_response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?per_page=500&type=A&type=AAAA" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    used_names=$(echo "$dns_response" | jq -r '.result[] | .name' | sort -u)

    printf "\n📄 \033[1mUsed DNS Records in this zone:\033[0m\n"
    printf "────────────────────────────────────────────────────────────\n"
    echo "$dns_response" | jq -r '.result[] | select(.type=="A" or .type=="AAAA") | "\(.name)\t\(.content)"' | sort -u | while IFS=$'\t' read -r name ip; do
    printf "🔒 %-35s → \033[36m%s\033[0m\n" "$name" "$ip"
    done
    printf "🔒 These hostnames are already in use and \033[31mcannot be selected\033[0m.\n"

    if grep -q -Fx "$DOMAIN" <<< "$used_names"; then
      root_taken=true
    fi

    # 🧭 Auswahlmenü
    while true; do
      printf "\n🌍 \033[1mHow should your app be accessible?\033[0m\n"
      printf "────────────────────────────────────────────────────────────\n"
      printf " 1) Use a subdomain  (e.g. \033[36mapp.%s\033[0m)\n" "$DOMAIN"
      if [[ "$root_taken" != true ]]; then
        printf " 2) Use root domain  (\033[36m%s\033[0m)\n" "$DOMAIN"
        printf " 3) ⬅️  Go back to zone selection\n"
        printf "────────────────────────────────────────────────────────────\n"
        printf "❓ Your choice [1–3]: "
      else
        printf " 2) ⬅️  Go back to zone selection\n"
        printf "────────────────────────────────────────────────────────────\n"
        printf "❓ Your choice [1–2]: "
      fi

      IFS= read -rsn1 sub_choice
      printf "\n"

      if [[ "$root_taken" == true && "$sub_choice" == "2" ]]; then
        sub_choice="3"
      fi

      case "$sub_choice" in
        1)
          while true; do
            printf "✏️  Enter subdomain (e.g. \033[36mapp\033[0m): "
            read -r subname
            subname=${subname,,}
            if ! [[ "$subname" =~ ^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$ ]]; then
              printf "❌ Invalid subdomain. Only lowercase letters, digits, and hyphens allowed.\n"
              sleep 1
              continue
            fi
            local full_fqdn="$subname.$DOMAIN"
            if grep -q -Fx "$full_fqdn" <<< "$used_names"; then
              local ip
              ip=$(echo "$dns_response" | jq -r --arg fqdn "$full_fqdn" '.result[] | select(.name == $fqdn) | .content' | head -n 1)
              printf "⚠️  \033[33mSubdomain already in use:\033[0m \033[36m%s → \033[36m%s\033[0m\n" "$full_fqdn" "$ip"
              printf "   ➤ Please choose another name.\n"
              sleep 1
              continue
            fi
            HOSTNAME_FQDN="$full_fqdn"
            export HOSTNAME_FQDN
            printf "\n📌 Your app will be hosted at: \033[1;34mhttps://%s\033[0m\n" "$HOSTNAME_FQDN"
            return 0
          done
          ;;
        2)
          HOSTNAME_FQDN="$DOMAIN"
          export HOSTNAME_FQDN
          printf "\n📌 Your app will be hosted at: \033[1;34mhttps://%s\033[0m\n" "$HOSTNAME_FQDN"
          return 0
          ;;
        3)
          break
          ;;
        *)
          printf "❌ Invalid selection. Please try again.\n"
          sleep 1
          ;;
      esac
    done
  done
}

setup_cloudflare_dns_for_blazor() {
  for var in CLOUDFLARE_API_TOKEN CLOUDFLARE_API_BASE ZONE_ID DOMAIN HOSTNAME_FQDN SERVER_IPv4; do
    if [[ -z "${!var}" ]]; then
      printf "\n❌ \033[31mMissing required environment variable: %s\033[0m\n" "$var"
      exit 1
    fi
  done

  if [[ -z "$SERVER_IPv4" ]]; then
    SERVER_IPv4=$(curl -s -4 https://api.ipify.org)
    [[ -n "$SERVER_IPv4" ]] && printf "📡 Detected IPv4: \033[36m%s\033[0m\n" "$SERVER_IPv4"
  fi

  if [[ -z "$SERVER_IPv6" ]]; then
    SERVER_IPv6=$(curl -s -6 https://api64.ipify.org)
    [[ -n "$SERVER_IPv6" ]] && printf "📡 Detected IPv6: \033[35m%s\033[0m\n" "$SERVER_IPv6"
  fi


  printf "\n☁️  \033[1mCloudflare DNS Setup for Blazor Hosting\033[0m\n"
  printf "────────────────────────────────────────────────────────────\n"

  # Ask about proxy usage
  printf "\n🌐 \033[1mCloudflare Proxy-Modus\033[0m\n"
  printf "   ➤ \033[32mEnabled\033[0m: Traffic is routed via Cloudflare (faster, safer, hides server IP)\n"
  printf "   ➤ \033[33mDisabled\033[0m: Direct traffic to your server (better for debugging or testing)\n"
  printf "   ℹ️  For development, it's recommended to \033[33mdisable\033[0m the proxy.\n"
  printf "❓ Enable Cloudflare proxy for A/AAAA records? [Y/n]: "
  IFS= read -rsn1 proxy_choice
  printf "\n"
  local use_proxy=true
  [[ "$proxy_choice" =~ ^[Nn]$ ]] && use_proxy=false

  # A record
  _upsert_dns_record "A" "$HOSTNAME_FQDN" "$SERVER_IPv4" "Blazor Hosting A-record" "$use_proxy"

  # Ask about IPv6
  printf "\n🌍 \033[1mOptional IPv6 Support (AAAA record)\033[0m\n"
  printf "   ➤ Enables visitors from IPv6-only networks (common in mobile and Asia)\n"
  printf "   ➤ Makes your app more globally reachable and future-proof\n"
  printf "   ➤ Needs working public IPv6 on your server\n"
  printf "   Detected IPv6: \033[35m%s\033[0m\n" "${SERVER_IPv6:-Unavailable}"
  printf "❓ Add AAAA record with this address? [y/N]: "
  IFS= read -rsn1 ipv6_choice
  printf "\n"

  if [[ "$ipv6_choice" =~ ^[Yy]$ && -n "$SERVER_IPv6" ]]; then
    _upsert_dns_record "AAAA" "$HOSTNAME_FQDN" "$SERVER_IPv6" "Blazor Hosting AAAA-record" "$use_proxy"
    export CLOUDFLARE_IPV6_ENABLED=true
  else
    printf "↪️  Skipped AAAA-record.\n"
  fi
}