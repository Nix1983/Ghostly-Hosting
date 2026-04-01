#!/bin/bash
# shellcheck disable=SC1091

set -e

source ./lib/common.sh
source ./lib/print.sh

_clear() {
  [[ "${DISABLE_CLEAR}" == "true" ]] || clear
}

_get_upcloud_server_uuid_by_ip() {
  if [[ -v SERVER_UUID && -n "$SERVER_UUID" && "$SERVER_UUID" != "null" ]]; then
    declare -f _safe_log >/dev/null 2>&1 && _safe_log debug "_get_upcloud_server_uuid_by_ip" "SERVER_UUID already set: $SERVER_UUID"
    return 0
  fi

  if [[ -z "$SERVER_IPv4" ]]; then
    printf "❌ SERVER_IPv4 is not set.\n"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "SERVER_IPv4 is not set"
    return 1
  fi

  if [[ -z "$UPCLOUD_API_TOKEN" || -z "$UPCLOUD_API_BASE" ]]; then
    printf "❌ Missing API credentials.\n"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "Missing UPCLOUD_API_TOKEN or UPCLOUD_API_BASE"
    return 1
  fi

  printf "🔍 Searching for server UUID using IP: \033[36m%s\033[0m ...\n" "$SERVER_IPv4"
  declare -f _safe_log >/dev/null 2>&1 && _safe_log info "_get_upcloud_server_uuid_by_ip" "Looking up server UUID for IP: $SERVER_IPv4"

  # Get list of all servers
  local response servers_json uuid
  if ! response=$(_upcloud_api_get "server" 2>&1); then
    printf "❌ Failed to query UpCloud API (server list). Response: %s\n" "$response"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "API query failed: $response"
    return 1
  fi

  servers_json=$(echo "$response" | jq -r '.servers.server // []' 2>/dev/null)

  if [[ -z "$servers_json" || "$servers_json" == "[]" ]]; then
    printf "❌ No servers found in account. Raw API response: %s\n" "$response"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "No servers returned from API. Response: $response"
    return 1
  fi

  # Search through all servers for matching IP
  uuid=$(echo "$servers_json" | jq -r --arg ip "$SERVER_IPv4" '
    .[] |
    select((.ip_addresses.ip_address // [])[] | .address == $ip) |
    .uuid // empty
  ' | head -n1)

  if [[ -n "$uuid" && "$uuid" != "null" ]]; then
    SERVER_UUID="$uuid"
    printf "✅ SERVER_UUID detected and set: %s\n" "$SERVER_UUID"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log info "_get_upcloud_server_uuid_by_ip" "Successfully resolved SERVER_UUID: $SERVER_UUID"
    return 0
  else
    printf "❌ No server found with IP address: %s\n" "$SERVER_IPv4"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "Could not find server with IP $SERVER_IPv4. Available UUIDs: $(echo "$servers_json" | jq -r '.[].uuid' | tr '\n' ' ')"
    return 1
  fi
}

_verify_upcloud_context() {
  if [[ -z "$UPCLOUD_API_TOKEN" || -z "$UPCLOUD_API_BASE" ]]; then
    printf "❌ Missing API credentials.\n"
    return 1
  fi

  if [[ -z "$SERVER_IPv4" && -z "$SERVER_IPv6" ]]; then
    printf "❌ Neither SERVER_IPv4 nor SERVER_IPv6 is set.\n"
    return 1
  fi

  if [[ -z "$SERVER_IPv4" ]]; then
    printf "⚠️  Only IPv6 is set – server UUID cannot be resolved automatically.\n"
    printf "   ➜ Please set SERVER_UUID manually.\n"
    return 1
  fi

  if ! _get_upcloud_server_uuid_by_ip; then
    printf "❌ Could not resolve server UUID – aborting.\n"
    return 1
  fi

  return 0
}

_upcloud_api_get() {
  local endpoint="$1"
  local raw http_code body
  raw=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $UPCLOUD_API_TOKEN" \
    -H "Accept: application/json" \
    "$UPCLOUD_API_BASE/$endpoint")
  http_code=$(printf '%s' "$raw" | tail -n1)
  body=$(printf '%s' "$raw" | head -n -1)
  printf '%s' "$body"
  if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
    return 0
  else
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_upcloud_api_get" "HTTP $http_code from $endpoint: $body"
    return 1
  fi
}

_upcloud_api_put() {
  local endpoint="$1"
  local data="$2"
  local raw http_code body
  raw=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $UPCLOUD_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$data" \
    -X PUT "$UPCLOUD_API_BASE/$endpoint")
  http_code=$(printf '%s' "$raw" | tail -n1)
  body=$(printf '%s' "$raw" | head -n -1)
  printf '%s' "$body"
  if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
    return 0
  else
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_upcloud_api_put" "HTTP $http_code from $endpoint: $body"
    return 1
  fi
}

_upcloud_firewall_rules_match_desired() {
  local project_root desired_file desired_json current_json
  project_root="$(get_project_root)"
  desired_file="$project_root/config/desired_firewall_rules.json"

  if [[ ! -f "$desired_file" ]]; then
    printf "❌ Desired firewall rules file not found: %s\n" "$desired_file"
    return 1
  fi

  printf "🔍 Comparing current UpCloud rules with desired state...\n"

  # Normalize desired rules
  desired_json=$(jq -S '
    .firewall_rules.firewall_rule
    | map(
        del(.position)
        | with_entries(select(.value != null and .value != ""))
        | with_entries({key: .key, value: .value})
      )
    | sort_by(
        .direction,
        .family,
        .protocol,
        .action,
        .destination_port_start,
        .destination_port_end,
        .comment
      )
  ' "$desired_file")

  local current_response
  current_response=$(_upcloud_api_get "server/$SERVER_UUID/firewall_rule")

  if ! echo "$current_response" | jq -e '.firewall_rules.firewall_rule' >/dev/null 2>&1; then
    printf "❌ Could not load current firewall rules from API.\n"
    return 1
  fi

  current_json=$(echo "$current_response" | jq -S '
    .firewall_rules.firewall_rule
    | map(
        del(.position)
        | with_entries(select(.value != null and .value != ""))
        | with_entries({key: .key, value: .value})
      )
    | sort_by(
        .direction,
        .family,
        .protocol,
        .action,
        .destination_port_start,
        .destination_port_end,
        .comment
      )
  ')

  local tmp_desired tmp_current
  tmp_desired=$(mktemp)
  tmp_current=$(mktemp)

  echo "$desired_json" > "$tmp_desired"
  echo "$current_json" > "$tmp_current"

  if diff -q "$tmp_desired" "$tmp_current" >/dev/null; then
    printf "✅ Firewall rules match desired configuration.\n"
    rm -f "$tmp_desired" "$tmp_current"
    return 0
  else
    printf "❌ Firewall rules differ. Here's the diff:\n"
    diff -u "$tmp_desired" "$tmp_current" || true
    rm -f "$tmp_desired" "$tmp_current"
    return 1
  fi
}

_print_firewall_rule() {
  local rule="$1"

  local family action protocol src_ip dst_ip src_port dst_port comment

  family=$(echo "$rule" | jq -r '.family // "-"')
  action=$(echo "$rule" | jq -r '.action // "-"')
  protocol=$(echo "$rule" | jq -r '.protocol // ""')
  src_ip=$(echo "$rule" | jq -r '.source_address_start // ""')
  dst_ip=$(echo "$rule" | jq -r '.destination_address_start // ""')
  src_port=$(echo "$rule" | jq -r '.source_port_start // ""')
  dst_port=$(echo "$rule" | jq -r '.destination_port_start // ""')
  comment=$(echo "$rule" | jq -r '.comment // ""')

  [[ -z "$src_ip" || "$src_ip" == "null" ]] && src_ip="Any"
  [[ -z "$dst_ip" || "$dst_ip" == "null" ]] && dst_ip="Any"
  [[ -z "$src_port" || "$src_port" == "null" ]] && src_port="Any"
  [[ -z "$dst_port" || "$dst_port" == "null" ]] && dst_port="Any"
  [[ -z "$protocol" || "$protocol" == "null" ]] && protocol="–"
  [[ -z "$comment" || "$comment" == "null" ]] && comment="No comment found."

  local action_color="\e[33m"
  local family_color="\e[36m"

  case "$action" in
    accept) action_color="\e[32m" ;;
    drop)   action_color="\e[31m" ;;
  esac

  # Main rule line without comment
  printf "🔸 ${family_color}%-5s\e[0m │ ${action_color}%-6s\e[0m │ \e[36m%-6s\e[0m │ Src: %-17s Port: %-8s │ Dst: %-17s Port: %-8s\n" \
    "$family" "$action" "$protocol" "$src_ip" "$src_port" "$dst_ip" "$dst_port"

  # Separate comment line
  printf "📝 \e[2m%s\e[0m\n" "$comment"
  printf "\n"
}

delete_all_upcloud_firewall_rules() {
  _clear
  printf "\n🧨 Deleting All UpCloud Firewall Rules\n"
  printf "────────────────────────────────────────────────────────────\n"

  if [[ -z "$UPCLOUD_API_TOKEN" ]]; then
    printf "❌ Missing UpCloud API credentials.\n"
    return 1
  fi

  if [[ -z "$SERVER_IPv4" ]]; then
    printf "❌ SERVER_IPv4 is not set.\n"
    return 1
  fi

  if ! _get_upcloud_server_uuid_by_ip; then
    printf "❌ Could not resolve server UUID – aborting.\n"
    return 1
  fi

  local server_info firewall_enabled
  server_info=$(_upcloud_api_get "server/$SERVER_UUID")
  firewall_enabled=$(echo "$server_info" | jq -r '.server.firewall // ""')

  if [[ "$firewall_enabled" != "on" && "$firewall_enabled" != "true" ]]; then
    printf "⚠️ Firewall is currently disabled – enabling now...\n"
    local enable_response
    enable_response=$(_upcloud_api_put "server/$SERVER_UUID" '{"server": { "firewall": "on" }}')
    firewall_enabled=$(echo "$enable_response" | jq -r '.server.firewall // ""')
    if [[ "$firewall_enabled" != "on" && "$firewall_enabled" != "true" ]]; then
      printf "❌ Failed to enable firewall:\n"
      echo "$enable_response" | jq -r '.error.message // "Unknown error"'
      return 1
    fi
    printf "✅ Firewall successfully \e[32menabled\e[0m.\n"
  else
    printf "✅ Firewall is already \e[32menabled\e[0m – loading rules...\n"
  fi

  local response
  response=$(_upcloud_api_get "server/$SERVER_UUID/firewall_rule")

  if ! echo "$response" | jq -e '.firewall_rules.firewall_rule' >/dev/null 2>&1; then
    printf "ℹ️ No firewall rules found or API returned no data.\n"
    return 0
  fi

  mapfile -t rules < <(echo "$response" | jq -c '.firewall_rules.firewall_rule[]')

  if [[ ${#rules[@]} -eq 0 ]]; then
    printf "ℹ️ No firewall rules present.\n"
    return 0
  fi

  printf "📋 %d firewall rules found – starting deletion...\n\n" "${#rules[@]}"

  for ((i=${#rules[@]}-1; i>=0; i--)); do
    local rule="${rules[$i]}"
    local position
    position=$(echo "$rule" | jq -r '.position')

    printf "❌ Deleting rule at position %s:\n" "$position"
    _print_firewall_rule "$rule"

    local del_response
    del_response=$(curl -s \
      -H "Authorization: Bearer $UPCLOUD_API_TOKEN" \
      -X DELETE "$UPCLOUD_API_BASE/server/$SERVER_UUID/firewall_rule/$position")

    if [[ -z "$del_response" ]]; then
      printf "✅ Rule deleted (no response, assumed success).\n"
    elif echo "$del_response" | jq -e '.error?' >/dev/null 2>&1; then
      printf "⚠️ Failed to delete rule:\n"
      echo "$del_response" | jq -r '.error.message // .error // .'
    else
      printf "✅ Rule deleted successfully.\n"
    fi
   printf "────────────────────────────────────────────────────────────\n"

  done

  printf "\n✅ All rules deleted (unless errors occurred).\n"
  printf "═════════════════════════════════════════════════════════════\n"
}

_enable_upcloud_firewall() {
  _clear
  printf "\n🔒 Enabling UpCloud Firewall\n"
  printf "────────────────────────────────────────────────────────────\n"

  _verify_upcloud_context || return 1

  local response new_status
  response=$(_upcloud_api_put "server/$SERVER_UUID" '{"server": { "firewall": "on" }}')
  new_status=$(echo "$response" | jq -r '.server.firewall // ""')

  if [[ "$new_status" == "on" || "$new_status" == "true" ]]; then
    printf "✅ Firewall was successfully \e[32menabled\e[0m.\n"
    return 0
  else
    printf "❌ Failed to enable firewall:\n"
    echo "$response" | jq -r '.error.message // "Unknown error"'
    return 1
  fi
}

_disable_upcloud_firewall() {
  _clear
  printf "\n🔓 Disabling UpCloud Firewall\n"
  printf "────────────────────────────────────────────────────────────\n"

  _verify_upcloud_context || return 1

  local response new_status
  response=$(_upcloud_api_put "server/$SERVER_UUID" '{"server": { "firewall": "off" }}')
  new_status=$(echo "$response" | jq -r '.server.firewall // ""')

  if [[ "$new_status" == "off" || "$new_status" == "false" ]]; then
    printf "✅ Firewall was successfully \e[33mdisabled\e[0m.\n"
    return 0
  else
    printf "❌ Failed to disable firewall:\n"
    echo "$response" | jq -r '.error.message // "Unknown error"'
    return 1
  fi
}

_show_upcloud_firewall_status() {
  _clear
  printf "\n🔎 UpCloud Firewall Status Overview\n"
  printf "────────────────────────────────────────────────────────────\n"

  _verify_upcloud_context || return 1

  local server_info firewall_enabled
  server_info=$(_upcloud_api_get "server/$SERVER_UUID")
  firewall_enabled=$(echo "$server_info" | jq -r '.server.firewall // ""')

  if [[ "$firewall_enabled" != "on" && "$firewall_enabled" != "true" ]]; then
    printf "ℹ️  Firewall is currently \e[33mdisabled\e[0m (Status: '%s')\n" "$firewall_enabled"
    printf "────────────────────────────────────────────────────────────\n"
    return 0
  fi

  printf "✅ Firewall is \e[32menabled\e[0m\n\n"

  local response rules
  response=$(_upcloud_api_get "server/$SERVER_UUID/firewall_rule")

  if [[ -z "$response" ]]; then
    echo "❌ No response from API (response is empty)."
    return 1
  fi

  if ! echo "$response" | jq -e '.firewall_rules.firewall_rule' >/dev/null 2>&1; then
    echo "❌ Structure 'firewall_rules.firewall_rule' not found – API format may differ:"
    echo "$response"
    return 1
  fi

  rules=$(echo "$response" | jq -c '.firewall_rules.firewall_rule // [] | .[]')
  [[ -z "$rules" ]] && {
    echo "ℹ️  No firewall rules defined."
    return 0
  }

  echo "📥 Incoming Rules"
  echo "────────────────────────────────────────────────────────────"
  while IFS= read -r rule; do
    [[ "$(echo "$rule" | jq -r '.direction')" == "in" ]] && _print_firewall_rule "$rule"
  done <<< "$rules"

  echo ""
  echo "📤 Outgoing Rules"
  echo "────────────────────────────────────────────────────────────"
  while IFS= read -r rule; do
    [[ "$(echo "$rule" | jq -r '.direction')" == "out" ]] && _print_firewall_rule "$rule"
  done <<< "$rules"

  echo ""
  echo "═════════════════════════════════════════════════════════════"
}

apply_upcloud_firewall_rules() {
  set +e  # Handle errors manually
  set -u  # Treat unset variables as errors
  _clear
  printf "\n"

  printf "🧱 Applying firewall rules for GhostlyHosting on UpCloud (from config/desired_firewall_rules.json)\n"
  printf "────────────────────────────────────────────────────────────\n"

  local project_root rules_file
  project_root="$(get_project_root)"
  rules_file="$project_root/config/desired_firewall_rules.json"

  if [[ ! -f "$rules_file" ]]; then
    printf "❌ Firewall rule file is missing: %s\n" "$rules_file"
    return 1
  fi

  # Verify context and enable firewall
  if ! _verify_upcloud_context; then
    printf "❌ API context invalid or SERVER_UUID missing.\n"
    return 1
  fi

  if ! _enable_upcloud_firewall; then
    printf "❌ Failed to enable firewall.\n"
    return 1
  fi

  if _upcloud_firewall_rules_match_desired; then
  printf "✅ Existing firewall rules already match desired configuration – nothing to do.\n"
  return 0
  else
    printf "🔄 Existing rules do not match desired state – resetting...\n"
    if ! delete_all_upcloud_firewall_rules; then
      printf "⚠️  Warning: Could not delete existing firewall rules.\n"
    fi
  fi

  printf "➕ Loading new rules from: %s\n" "$rules_file"
  mapfile -t new_rules < <(jq -c '.firewall_rules.firewall_rule[]' "$rules_file" 2>/dev/null)

  if [[ ${#new_rules[@]} -eq 0 ]]; then
    printf "❌ No firewall rules found in JSON or syntax is invalid.\n"
    jq . "$rules_file" || cat "$rules_file"
    return 1
  fi

  printf "📦 %d rules found. Starting to apply...\n\n" "${#new_rules[@]}"

  local success_count=0
  local fail_count=0
  local index=0

  for rule in "${new_rules[@]}"; do
    ((index++))
    printf "────────────────────────────────────────────────────────────\n"
    printf "➕ Adding rule [%d/%d]\n" "$index" "${#new_rules[@]}"

    if [[ -z "$rule" ]]; then
      printf "⚠️  Empty rule – skipped.\n"
      ((fail_count++))
      continue
    fi

    # Send rule using API helper
    local add_response status body
    add_response=$(curl -s -w "\n%{http_code}" \
      -H "Authorization: Bearer $UPCLOUD_API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"firewall_rule\": $rule}" \
      "$UPCLOUD_API_BASE/server/$SERVER_UUID/firewall_rule")

    body=$(echo "$add_response" | head -n -1)
    status=$(echo "$add_response" | tail -n1)

    if [[ "$status" == "201" && "$body" == *"firewall_rule"* ]]; then
      _print_firewall_rule "$rule"
      printf "✅ Rule added successfully.\n"
      ((success_count++))
    else
      printf "❌ Failed to add rule.\n"
      printf "🔸 HTTP status: %s\n" "$status"
      printf "🔸 Sent rule:\n"
      _print_firewall_rule "$rule"
      printf "🔸 API response:\n"
      echo "$body" | jq . || echo "$body"
      ((fail_count++))
    fi
  done

  printf "\n📊 Summary:\n"
  printf "✅ Successfully added: %d\n" "$success_count"
  printf "❌ Failed to add:      %d\n" "$fail_count"
  printf "────────────────────────────────────────────────────────────\n"
}

validate_upcloud_token() {
  local token="$1"

  if [[ -z "$token" || -z "$UPCLOUD_API_BASE" ]]; then
    printf "❌ Missing API token or API base.\n"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "validate_upcloud_token" "Missing token or API base"
    return 1
  fi

  declare -f _safe_log >/dev/null 2>&1 && _safe_log debug "validate_upcloud_token" "Validating UpCloud API token"
  
  local response status body
  response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/json" \
    "$UPCLOUD_API_BASE/account" 2>&1)
  status=$(echo "$response" | tail -n1)
  body=$(echo "$response" | head -n -1)

  if [[ "$status" == "200" ]]; then
    declare -f _safe_log >/dev/null 2>&1 && _safe_log info "validate_upcloud_token" "UpCloud token validated successfully"
    return 0
  else
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "validate_upcloud_token" "Token validation failed with status $status. Response: $body"
    return 1
  fi
}


show_upcloud_menu() {
  while true; do
    clear
    echo ""
    echo -e "\n 🌩️  \e[1mUpCloud Firewall Rules\e[0m"
    echo -e "\e[1m──────────────────────────────────────────────────────\e[0m"
    echo -e "\n 1) 🔐 Enable Firewall              2) 🔓 Disable Firewall"
    echo -e "\n 3) 📊 Show Firewall Status         4) 💣 Delete All Rules"
    echo -e "\n 5) 📦 Apply Server Rules           $(print_back_to_menu)"
    echo -e "\n─────────────────────────────────────────────────────────────"
    print_select_prompt 5

    IFS= read -rsn1 choice
    echo

    case "$choice" in
      1)
        _enable_upcloud_firewall
        echo ""
        print_press_any_key
        ;;
      2)
        _disable_upcloud_firewall
        echo ""
        print_press_any_key
        ;;
      3)
        _show_upcloud_firewall_status
        echo ""
        print_press_any_key
        ;;
      4)
        delete_all_upcloud_firewall_rules
        echo ""
        print_press_any_key
        ;;
      5)
        apply_upcloud_firewall_rules
        echo ""
        print_press_any_key
        ;;
      q|Q)
        break
        ;;
      *)
        print_invalid_selection
        ;;
    esac
  done
}