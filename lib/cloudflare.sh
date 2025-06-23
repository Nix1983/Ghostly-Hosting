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

resolve_cloudflare_zone_id() {
  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" || -z "$DOMAIN" ]]; then
    echo "❌ CLOUDFLARE_API_TOKEN, CLOUDFLARE_API_BASE oder DOMAIN fehlt."
    return 1
  fi

  local response
  response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

  ZONE_ID=$(echo "$response" | jq -r --arg domain "$DOMAIN" '.result[] | select(.name == $domain) | .id')

  if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
    echo "❌ Zone ID für $DOMAIN konnte nicht gefunden werden."
    return 1
  fi

  export ZONE_ID
  return 0
}

get_cloudflare_proxy_status() {
  local domain="$1"
  local zone_id="$2"
  local token="$3"
  local api_base="${4:-$CLOUDFLARE_API_BASE}"

  if [[ -z "$domain" || -z "$zone_id" || -z "$token" ]]; then
    echo "❌"
    return 1
  fi

  local response proxy_flag
  response=$(curl -s -X GET "$api_base/zones/$zone_id/dns_records?type=A&name=$domain" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json")

  proxy_flag=$(echo "$response" | jq -r '.result[0].proxied // empty')
  [[ "$proxy_flag" == "true" ]] && echo "Enabled ✅" || echo "Disabled ❌"
}

has_cloudflare_dns_record() {
  local domain="$1"
  local zone_id="$2"
  local token="$3"
  local type="$4"
  local api_base="${5:-$CLOUDFLARE_API_BASE}"

  if [[ -z "$domain" || -z "$zone_id" || -z "$token" || -z "$type" ]]; then
    echo "❌"
    return 1
  fi

  local response count
  response=$(curl -s -X GET "$api_base/zones/$zone_id/dns_records?type=$type&name=$domain" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json")

  count=$(echo "$response" | jq '.result | length')
  [[ "$count" -gt 0 ]] && echo "✅" || echo "❌"
}

toggle_cloudflare_proxy() {
  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" || -z "$ZONE_ID" || -z "$HOSTNAME_FQDN" ]]; then
    echo -e "❌ \e[31mMissing required variables: CLOUDFLARE_API_TOKEN, ZONE_ID, or HOSTNAME_FQDN.\e[0m"
    return 1
  fi

  local types=("A" "AAAA")
  local has_change=false

  echo -e "\n🔄 \e[1mToggling Cloudflare Proxy for:\e[0m \e[36m$HOSTNAME_FQDN\e[0m"

  for record_type in "${types[@]}"; do
    local response record_id current_status new_status ip_var update_payload

    response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?type=$record_type&name=$HOSTNAME_FQDN" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    record_id=$(echo "$response" | jq -r '.result[0].id // empty')
    current_status=$(echo "$response" | jq -r '.result[0].proxied // empty')
    ip_var=$(echo "$response" | jq -r '.result[0].content // empty')

    if [[ -z "$record_id" ]]; then
      echo -e "⚠️  No $record_type-record found."
      continue
    fi

    # Toggle proxy status
    new_status=$([[ "$current_status" == "true" ]] && echo "false" || echo "true")

    update_payload=$(jq -n \
      --arg type "$record_type" \
      --arg name "$HOSTNAME_FQDN" \
      --arg content "$ip_var" \
      --argjson proxied "$new_status" \
      '{type: $type, name: $name, content: $content, proxied: $proxied}')

    curl -s -X PUT "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records/$record_id" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$update_payload" >/dev/null

    echo -e " → $record_type updated: \e[1m$HOSTNAME_FQDN\e[0m → \e[32m$([[ "$new_status" == "true" ]] && echo "✅ ON" || echo "❌ OFF")\e[0m"
    has_change=true
  done

  if [[ "$has_change" != true ]]; then
    echo -e "⚠️  \e[33mNo records updated – nothing toggled.\e[0m"
    return 1
  fi

  return 0
}

delete_cloudflare_dns_records() {
  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" || -z "$ZONE_ID" || -z "$HOSTNAME_FQDN" ]]; then
    echo -e "❌ \e[31mCannot delete DNS records – required variables missing (CLOUDFLARE_API_TOKEN, ZONE_ID, HOSTNAME_FQDN).\e[0m"
    return 1
  fi

  echo -e "\n🧹 \e[1;31mCleaning up Cloudflare DNS entries:\e[0m \e[36m$HOSTNAME_FQDN\e[0m"

  local types=("A" "AAAA")
  local found_any=false

  for record_type in "${types[@]}"; do
    local dns_response
    dns_response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?type=$record_type&name=$HOSTNAME_FQDN" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    if [[ -z "$dns_response" || "$dns_response" == "null" ]]; then
      echo -e "❌ \e[31mFailed to fetch $record_type records for $HOSTNAME_FQDN\033[0m"
      continue
    fi

    local count; count=$(echo "$dns_response" | jq '.result | length')
    if [[ "$count" == "0" ]]; then
      continue
    fi

    found_any=true

    echo "$dns_response" | jq -c '.result[]' | while read -r record; do
      local record_id record_content
      record_id=$(echo "$record" | jq -r '.id')
      record_content=$(echo "$record" | jq -r '.content')

      printf "❌ Deleting %-4s → \033[36m%-39s\033[0m ... " "$record_type" "$record_content"

     if curl -s -X DELETE "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records/$record_id" \
       -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
       -H "Content-Type: application/json" > /dev/null; then
       echo -e "\e[32m✅ done\e[0m"
     else
       echo -e "\e[31m❌ failed\e[0m"
     fi
    done
  done

  if [[ "$found_any" == false ]]; then
    echo -e "ℹ️ No A/AAAA DNS records found for \e[2m$HOSTNAME_FQDN\e[0m — skipping."
  else
    echo -e "✅ \e[1;32mCloudflare DNS cleanup completed.\e[0m"
  fi
}

select_cloudflare_zone_and_domain() {
  _check_cloudflare_env_vars
  local response zones
  local -A zone_map=()

  while true; do
    clear
    get_server_ip "$@"

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
    print_line
    local index=1
    zone_map=()
    while IFS=$'\t' read -r name id; do
      printf " %2d) \033[1;36m%-30s\033[0m\n" "$index" "$name"
      zone_map[$index]="$name:$id"
      ((index++))
    done <<< "$zones"

    read_menu_choice $((index - 1))

    if [[ "$REPLY" =~ ^[Qq]$ ]]; then
      return 1
    fi

    local selected="${zone_map[$REPLY]}"

    DOMAIN="${selected%%:*}"
    ZONE_ID="${selected##*:}"
    export DOMAIN ZONE_ID
    printf "\n✅ Selected Zone: \033[1;34m%s\033[0m\n" "$DOMAIN"

    local dns_response used_names root_taken=false
    dns_response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?per_page=500&type=A&type=AAAA" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    used_names=$(echo "$dns_response" | jq -r '.result[] | .name' | sort -u)

    printf "\n📄 \033[1mUsed DNS Records in this zone:\033[0m\n"
    print_line
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
      print_line
      printf " 1) Use a subdomain  (e.g. \033[36mapp.%s\033[0m)\n" "$DOMAIN"
      if [[ "$root_taken" != true ]]; then
        printf " 2) Use root domain  (\033[36m%s\033[0m)\n" "$DOMAIN"
        printf " 3) ⬅️  Go back to zone selection\n"
        print_line
        printf "❓ Your choice [1–3]: "
      else
        printf " 2) ⬅️  Go back to zone selection\n"
        print_line
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
            export HOSTNAME_FQDN DOMAIN
            printf "\n📌 Your app will be hosted at: \033[1;34mhttps://%s\033[0m\n" "$HOSTNAME_FQDN"
            return 0
          done
          ;;
        2)
          HOSTNAME_FQDN="$DOMAIN"
          export HOSTNAME_FQDN DOMAIN
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

  printf "\n☁️  \033[1mCloudflare DNS Setup for Blazor Hosting\033[0m\n"
  printf "────────────────────────────────────────────────────────────\n"

  # Ask about proxy usage
  printf "\n🌐 \033[1mCloudflare Proxy-Modus\033[0m\n"
  printf "   ➤   \033[32mEnabled\033[0m: Traffic is routed via Cloudflare (faster, safer, hides server IP)\n"
  printf "   ➤   \033[33mDisabled\033[0m: Direct traffic to your server (better for debugging or testing)\n"
  printf "   ℹ️  For development, it's recommended to \033[33mdisable\033[0m the proxy.\n"
  printf "❓ Enable Cloudflare proxy for A/AAAA records? [Y/n]: "
  IFS= read -rsn1 proxy_choice
  printf "\n"
  local use_proxy=true
  [[ "$proxy_choice" =~ ^[Nn]$ ]] && use_proxy=false

  echo ""
  echo -e "📤 Setting DNS records for \e[36m$HOSTNAME_FQDN\e[0m"

  # A record
  if [[ -n "${SERVER_IPv4:-}" ]]; then
    _upsert_dns_record "A" "$HOSTNAME_FQDN" "$SERVER_IPv4" "Blazor Hosting A-record" "$use_proxy"
  else
    echo -e "❌ \e[31mSERVER_IPv4 is not set – skipping A record creation.\e[0m"
  fi


  # AAAA record (optional)
  if [[ -n "$SERVER_IPv6" ]]; then
    _upsert_dns_record "AAAA" "$HOSTNAME_FQDN" "$SERVER_IPv6" "Blazor Hosting AAAA-record" "$use_proxy"
    export CLOUDFLARE_IPV6_ENABLED=true
  else
    echo -e "↪️  \033[2mNo IPv6 detected – skipping AAAA record.\033[0m"
  fi

  # DNS Result Übersicht
  printf "\n🔎 \033[1mVerifying DNS records...\033[0m\n"
  local response name type content proxied proxy_icon

  for record_type in A AAAA; do
    response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?type=$record_type&name=$HOSTNAME_FQDN" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    if [[ -z "$response" || "$response" == "null" ]]; then
      printf "❌ \033[31mCould not fetch %s record for %s\033[0m\n" "$record_type" "$HOSTNAME_FQDN"
      continue
    fi

    if ! echo "$response" | jq -e '.result | length > 0' >/dev/null; then
      printf "❌ \033[31mNo %s record found for %s\033[0m\n" "$record_type" "$HOSTNAME_FQDN"
      continue
    fi

    echo "$response" | jq -c '.result[]' | while read -r record; do
      name=$(echo "$record" | jq -r '.name')
      content=$(echo "$record" | jq -r '.content')
      proxied=$(echo "$record" | jq -r '.proxied')
      [[ "$proxied" == "true" ]] && proxy_icon="🔒 via CF" || proxy_icon="➡️ direct"
      printf "✅ %-5s %-35s → \033[36m%-39s\033[0m [%s]\n" "$record_type" "$name" "$content" "$proxy_icon"
    done
  done
}