#!/bin/bash
# shellcheck disable=SC1091
set -e

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

validate_cloudflare_token() {
  local token="$1"
  local response status body

  response=$(curl -s -w "\n%{http_code}" -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    "https://api.cloudflare.com/client/v4/user/tokens/verify")

  status=$(echo "$response" | tail -n1)
  body=$(echo "$response" | head -n -1)

  if [[ "$status" != "200" ]]; then
    return 1
  fi

  if echo "$body" | jq -e '.success == true' >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

resolve_cloudflare_zone_id() {
  local input_domain="$1"

  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" || -z "$input_domain" ]]; then
    echo "❌ Missing required variables: CLOUDFLARE_API_TOKEN, CLOUDFLARE_API_BASE or domain."
    return 1
  fi

  local response zone_list
  response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

  if ! echo "$response" | jq -e '.success == true and (.result | type == "array")' >/dev/null 2>&1; then
    echo "❌ Failed to retrieve Cloudflare zones:"
    echo "$response" | jq -C . 2>/dev/null || echo "$response"
    return 1
  fi

  zone_list=$(echo "$response" | jq -r '.result[].name')

  for zone in $zone_list; do
    if [[ "$input_domain" == "$zone" || "$input_domain" == *."$zone" ]]; then
      ZONE_ID=$(echo "$response" | jq -r --arg zone "$zone" '.result[] | select(.name == $zone) | .id')
      break
    fi
  done

  if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
    echo "❌ Zone ID could not be resolved for: $input_domain"
    echo "ℹ️  Available zones:"
    echo "$zone_list" | sed 's/^/ → /'
    return 1
  fi

  export ZONE_ID
  return 0
}

get_cloudflare_proxy_status() {
  local domain="$1"
  local zone_id="$2"
  local token="$3"

  if [[ -z "$domain" || -z "$zone_id" || -z "$token" || -z "$CLOUDFLARE_API_BASE" ]]; then
    echo "❌"
    return 1
  fi

  local response proxy_flag
  response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$zone_id/dns_records?type=A&name=$domain" \
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

  if [[ -z "$domain" || -z "$zone_id" || -z "$token" || -z "$type" || -z "$CLOUDFLARE_API_BASE" ]]; then
    echo "❌"
    return 1
  fi

  local response count
  response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$zone_id/dns_records?type=$type&name=$domain" \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json")

  count=$(echo "$response" | jq '.result | length')
  [[ "$count" -gt 0 ]] && echo "✅" || echo "❌"
}

toggle_cloudflare_proxy() {
  local fqdn="$1"

  if [[ -z "$fqdn" ]]; then
    echo -e "❌ \e[31mDomain name (FQDN) not provided.\e[0m"
    print_press_any_key
    return 1
  fi

  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" ]]; then
    echo -e "❌ \e[31mMissing required variables: CLOUDFLARE_API_TOKEN or CLOUDFLARE_API_BASE.\e[0m"
    print_press_any_key
    return 1
  fi

  if ! resolve_cloudflare_zone_id "$fqdn"; then
    echo -e "❌ \e[31mUnable to resolve Zone ID for domain:\e[0m \e[36m$fqdn\e[0m"
    print_press_any_key
    return 1
  fi

  local types=("A" "AAAA")
  local has_change=false
  local desired_status=""

  echo -e "\n🔄 \e[1mToggling Cloudflare Proxy for:\e[0m \e[36m$fqdn\e[0m"

  for record_type in "${types[@]}"; do
    local response record_id current_status new_status ip_var update_payload

    response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?type=$record_type&name=$fqdn" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    if ! echo "$response" | jq -e '.result | length > 0' >/dev/null 2>&1; then
      echo -e "⚠️  No $record_type record found or invalid response."
      continue
    fi

    record_id=$(echo "$response" | jq -r '.result[0].id // empty')
    current_status=$(echo "$response" | jq -r '.result[0].proxied // empty')
    ip_var=$(echo "$response" | jq -r '.result[0].content // empty')

    [[ -z "$record_id" ]] && continue

    new_status=$([[ "$current_status" == "true" ]] && echo "false" || echo "true")
    desired_status="$new_status"

    update_payload=$(jq -n \
      --arg type "$record_type" \
      --arg name "$fqdn" \
      --arg content "$ip_var" \
      --argjson proxied "$new_status" \
      '{type: $type, name: $name, content: $content, proxied: $proxied}')

    curl -s -X PUT "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records/$record_id" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "$update_payload" >/dev/null

    echo -e " → $record_type updated: \e[1m$fqdn\e[0m → \e[32m$([[ "$new_status" == "true" ]] && echo "✅ ON" || echo "❌ OFF")\e[0m"
    has_change=true
  done

  if [[ "$has_change" != true ]]; then
    echo -e "⚠️  \e[33mNo records updated – nothing toggled.\e[0m"
    return 1
  fi

  if [[ -n "$desired_status" ]]; then
    local alias_candidate="www.$fqdn"
    local cname_response cname_id cname_status cname_target
    cname_response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?type=CNAME&name=$alias_candidate" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    if echo "$cname_response" | jq -e '.result | length > 0' >/dev/null 2>&1; then
      cname_id=$(echo "$cname_response" | jq -r '.result[0].id // empty')
      cname_target=$(echo "$cname_response" | jq -r '.result[0].content // empty')
      cname_status=$(echo "$cname_response" | jq -r '.result[0].proxied // "false"')

      if [[ -n "$cname_id" && "${cname_target,,}" == "${fqdn,,}" ]]; then
        if [[ "$cname_status" != "$desired_status" ]]; then
          local cname_payload
          cname_payload=$(jq -n \
            --arg type "CNAME" \
            --arg name "$alias_candidate" \
            --arg content "$cname_target" \
            --argjson proxied "$desired_status" \
            '{type: $type, name: $name, content: $content, proxied: $proxied}')

          curl -s -X PUT "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records/$cname_id" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "$cname_payload" >/dev/null

          echo -e " → CNAME updated: \e[1m$alias_candidate\e[0m → \e[32m$([[ "$desired_status" == "true" ]] && echo "✅ ON" || echo "❌ OFF")\e[0m"
        fi
      fi
    fi
  fi

  return 0
}

delete_cloudflare_dns_records() {
  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" || -z "$ZONE_ID" || -z "$HOSTNAME_FQDN" ]]; then
    echo -e "❌ \e[31mCannot delete DNS records – required variables missing (CLOUDFLARE_API_TOKEN, ZONE_ID, HOSTNAME_FQDN).\e[0m"
    return 1
  fi

  echo -e "\n🧹 \e[1;31mCleaning up Cloudflare DNS entries:\e[0m \e[36m$HOSTNAME_FQDN\e[0m"

  local -a types=("A" "AAAA")
  local -a names=("$HOSTNAME_FQDN" "$HOSTNAME_FQDN")
  local found_any=false

  if [[ -n "${WWW_HOSTNAME_FQDN:-}" ]]; then
    types+=("CNAME")
    names+=("$WWW_HOSTNAME_FQDN")
  fi

  for idx in "${!types[@]}"; do
    local record_type="${types[$idx]}"
    local record_name="${names[$idx]}"
    local dns_response
    dns_response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?type=$record_type&name=$record_name" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    if [[ -z "$dns_response" || "$dns_response" == "null" ]]; then
      echo -e "❌ \e[31mFailed to fetch $record_type records for $record_name\033[0m"
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

      printf "❌ Deleting %-5s %-35s → \033[36m%-39s\033[0m ... " "$record_type" "$record_name" "$record_content"

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
    local targets="$HOSTNAME_FQDN"
    [[ -n "${WWW_HOSTNAME_FQDN:-}" ]] && targets+=" / ${WWW_HOSTNAME_FQDN}"
    echo -e "ℹ️ No managed DNS records found for \e[2m$targets\e[0m — skipping."
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

  export WWW_HOSTNAME_FQDN=""
  export CLOUDFLARE_WWW_ENABLED=false

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

  local wants_www=false
  local www_candidate="www.$HOSTNAME_FQDN"

  if [[ "$HOSTNAME_FQDN" != www.* ]]; then
    printf "\n🌍 \033[1mwww-Weiterleitung\033[0m\n"
    printf "   ➤   \033[36m%s\033[0m → Besucher von \033[2mhttps://www.%s\033[0m werden auf die Hauptdomain umgeleitet.\n" "$HOSTNAME_FQDN" "$HOSTNAME_FQDN"
    printf "   ➤   Für Subdomains (z. B. home.example.com) wird optional \033[36mwww.%s\033[0m eingerichtet.\n" "$HOSTNAME_FQDN"
    printf "❓ Soll eine www-Weiterleitung eingerichtet werden? [y/N]: "
    IFS= read -rsn1 www_choice
    printf "\n"
    if [[ "$www_choice" =~ ^[Yy]$ ]]; then
      wants_www=true
    fi
  fi

  if [[ "$wants_www" == true ]]; then
    local www_lookup existing_type
    www_lookup=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?name=$www_candidate" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")
    existing_type=$(echo "$www_lookup" | jq -r '.result[0].type // empty')
    if [[ -n "$existing_type" && "$existing_type" != "CNAME" ]]; then
      echo -e "⚠️  \e[33mwww-Hostname bereits durch $existing_type-Eintrag belegt – Überspringe www-Weiterleitung.\e[0m"
      wants_www=false
    fi
  fi

  if [[ "$wants_www" == true ]]; then
    export WWW_HOSTNAME_FQDN="$www_candidate"
    export CLOUDFLARE_WWW_ENABLED=true
  fi

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

  if [[ "$wants_www" == true ]]; then
    echo ""
    echo -e "🔁 Creating www-alias \e[36m$WWW_HOSTNAME_FQDN\e[0m → \e[36m$HOSTNAME_FQDN\e[0m"
    _upsert_dns_record "CNAME" "$WWW_HOSTNAME_FQDN" "$HOSTNAME_FQDN" "Blazor Hosting www alias" "$use_proxy"
  fi

  # DNS Result Übersicht
  printf "\n🔎 \033[1mVerifying DNS records...\033[0m\n"
  local response name type content proxied proxy_icon
  local -a record_pairs=("A:$HOSTNAME_FQDN" "AAAA:$HOSTNAME_FQDN")

  if [[ "$wants_www" == true ]]; then
    record_pairs+=("CNAME:$WWW_HOSTNAME_FQDN")
  fi

  for pair in "${record_pairs[@]}"; do
    local record_type="${pair%%:*}"
    local record_name="${pair##*:}"

    response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$ZONE_ID/dns_records?type=$record_type&name=$record_name" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    if [[ -z "$response" || "$response" == "null" ]]; then
      printf "❌ \033[31mCould not fetch %s record for %s\033[0m\n" "$record_type" "$record_name"
      continue
    fi

    if ! echo "$response" | jq -e '.result | length > 0' >/dev/null; then
      printf "❌ \033[31mNo %s record found for %s\033[0m\n" "$record_type" "$record_name"
      continue
    fi

    echo "$response" | jq -c '.result[]' | while read -r record; do
      name=$(echo "$record" | jq -r '.name')
      content=$(echo "$record" | jq -r '.content')
      proxied=$(echo "$record" | jq -r '.proxied // "false"')
      [[ "$proxied" == "true" ]] && proxy_icon="🔒 via CF" || proxy_icon="➡️ direct"
      printf "✅ %-5s %-35s → \033[36m%-39s\033[0m [%s]\n" "$record_type" "$name" "$content" "$proxy_icon"
    done
  done
}

delete_all_cloudflare_dns_records_for_server() {
  if [[ -z "$CLOUDFLARE_API_TOKEN" || -z "$CLOUDFLARE_API_BASE" || -z "$SERVER_IPv4" ]]; then
    echo -e "❌ \e[31mRequired environment variables are missing.\e[0m"
    print_press_any_key
    return 1
  fi

  local ip4_lc ip6_lc
  ip4_lc=$(echo "$SERVER_IPv4" | tr '[:upper:]' '[:lower:]')
  ip6_lc=$(echo "$SERVER_IPv6" | tr '[:upper:]' '[:lower:]')

  clear
  echo -e "\n🧨 \e[1;31mDNS Record Deletion Warning – All Zones\e[0m"
  print_double_line
  echo -e "You are about to remove \e[1mALL A/AAAA DNS records\e[0m from Cloudflare\nthat match your current server's public IP addresses:"
  echo -e "\n 🔹 IPv4: \e[36m$ip4_lc\e[0m"
  [[ -n "$ip6_lc" ]] && echo -e " 🔹 IPv6: \e[36m$ip6_lc\e[0m"

  echo -e "\n⚠️ \e[1mImpact:\e[0m"
  echo -e "   ➤ Apps, mail servers, or services using these DNS entries will stop working."
  echo -e "   ➤ Affects all domains/subdomains pointing to this server."
  echo -e "\n💣 \e[1mThis action is irreversible.\e[0m"

  echo -e "\n🔍 Fetching zones from Cloudflare..."
  print_line
  local zone_response
  zone_response=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones?per_page=100" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

  if [[ -z "$zone_response" || "$zone_response" == "null" ]]; then
    echo -e "❌ \e[31mFailed to fetch zones.\e[0m"
    print_press_any_key
    return 1
  fi

  local zone_count deleted=0
  zone_count=$(echo "$zone_response" | jq '.result | length')
  if [[ "$zone_count" -eq 0 ]]; then
    echo -e "ℹ️ No zones found in your Cloudflare account."
    print_press_any_key
    return 0
  fi

  mapfile -t zones < <(echo "$zone_response" | jq -r '.result[] | "\(.id)|\(.name)"')
  declare -a records_to_delete=()

  for zone in "${zones[@]}"; do
    local zone_id domain dns_response_a dns_response_aaaa dns_response
    zone_id="${zone%%|*}"
    domain="${zone##*|}"

    dns_response_a=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$zone_id/dns_records?per_page=500&type=A" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    dns_response_aaaa=$(curl -s -X GET "$CLOUDFLARE_API_BASE/zones/$zone_id/dns_records?per_page=500&type=AAAA" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json")

    dns_response=$(jq -s '[.[][]]' <(echo "$dns_response_a" | jq '.result') <(echo "$dns_response_aaaa" | jq '.result'))

    mapfile -t records < <(echo "$dns_response" | jq -c '.[]')

    for record in "${records[@]}"; do
      local id type name content content_lc
      id=$(echo "$record" | jq -r '.id')
      type=$(echo "$record" | jq -r '.type')
      name=$(echo "$record" | jq -r '.name')
      content=$(echo "$record" | jq -r '.content')
      content_lc=$(echo "$content" | tr '[:upper:]' '[:lower:]')

      if [[ "$content_lc" == "$ip4_lc" || "$content_lc" == "$ip6_lc" ]]; then
        printf "📡 \e[36m%s\e[0m (%s) → %s\n" "$name" "$type" "$content"
        records_to_delete+=("$zone_id|$id|$type|$name|$content")
      fi
    done
  done

  if [[ "${#records_to_delete[@]}" -eq 0 ]]; then
    echo -e "\n✅ \e[32mNo matching A/AAAA records found for this server.\e[0m"
    print_press_any_key
    return 0
  fi

  echo -e "\n💥 \e[1;31m${#records_to_delete[@]} DNS record(s) will be deleted if you confirm.\e[0m"
  if ! confirm_action_code; then
    return 1
  fi

  for entry in "${records_to_delete[@]}"; do
    local zone_id id type name content rest
    zone_id="${entry%%|*}"
    rest="${entry#*|}"
    id="${rest%%|*}"
    rest="${rest#*|}"
    type="${rest%%|*}"
    rest="${rest#*|}"
    name="${rest%%|*}"
    content="${rest#*|}"

    printf "❌ Deleting %-4s → \e[36m%-39s\e[0m ... " "$type" "$name"
    if curl -s -X DELETE "$CLOUDFLARE_API_BASE/zones/$zone_id/dns_records/$id" \
      -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
      -H "Content-Type: application/json" >/dev/null; then
      echo -e "\e[32m✅ done\e[0m"
      ((deleted++))
    else
      echo -e "\e[31m❌ failed\e[0m"
    fi
  done

  echo -e "\n✅ \e[1;32m$deleted DNS record(s) deleted across all zones.\e[0m"
  print_press_any_key
}
