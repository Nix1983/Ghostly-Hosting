#!/bin/bash
# shellcheck disable=SC1091

set -e

# ✨ Funktionen einbinden
source ./lib/common.sh

_clear() {
  [[ "${DISABLE_CLEAR}" == "true" ]] || clear
}

_get_upcloud_server_uuid_by_ip() {
  if [[ -v SERVER_UUID && -n "$SERVER_UUID" && "$SERVER_UUID" != "null" ]]; then
    return 0
  fi

  if [[ -z "$SERVER_IPv4" ]]; then
    printf "❌ SERVER_IPv4 is not set.\n"
    return 1
  fi

  if [[ -z "$UPCLOUD_API_USER" || -z "$UPCLOUD_API_PASS" || -z "$UPCLOUD_API_BASE" ]]; then
    printf "❌ Missing API credentials.\n"
    return 1
  fi

  printf "🔍 Searching for server UUID using IP: \033[36m%s\033[0m ...\n" "$SERVER_IPv4"
  local response uuid
  response=$(_upcloud_api_get "ip_address/$SERVER_IPv4")
  uuid=$(echo "$response" | jq -r '.ip_address.server // empty')

  if [[ -n "$uuid" && "$uuid" != "null" ]]; then
    SERVER_UUID="$uuid"
    printf "✅ SERVER_UUID detected and set: %s\n" "$SERVER_UUID"
    return 0
  else
    printf "❌ IP not directly associated with a server (possibly floating IP or error)\n"
    return 1
  fi
}

_verify_upcloud_context() {
  if [[ -z "$UPCLOUD_API_USER" || -z "$UPCLOUD_API_PASS" || -z "$UPCLOUD_API_BASE" ]]; then
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
  curl -s -u "$UPCLOUD_API_USER:$UPCLOUD_API_PASS" \
    -H "Accept: application/json" \
    "$UPCLOUD_API_BASE/$endpoint"
}

_upcloud_api_put() {
  local endpoint="$1"
  local data="$2"
  curl -s -u "$UPCLOUD_API_USER:$UPCLOUD_API_PASS" \
    -H "Content-Type: application/json" \
    -d "$data" \
    -X PUT "$UPCLOUD_API_BASE/$endpoint"
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
}

_delete_all_upcloud_firewall_rules() {
  _clear
  printf "\n🧨 Deleting all UpCloud firewall rules\n"
  printf "────────────────────────────────────────────────────────────\n"

  if [[ -z "$UPCLOUD_API_USER" || -z "$UPCLOUD_API_PASS" ]]; then
    printf "❌ Missing API credentials.\n"
    return 1
  fi

  if [[ -z "$SERVER_IPv4" ]]; then
    printf "❌ SERVER_IPv4 is not set.\n"
    return 1
  fi

  # Fetch server UUID
  if ! _get_upcloud_server_uuid_by_ip; then
    printf "❌ Could not resolve server UUID – aborting.\n"
    return 1
  fi

  # Check firewall status
  local server_info firewall_enabled
  server_info=$(_upcloud_api_get "server/$SERVER_UUID")
  firewall_enabled=$(echo "$server_info" | jq -r '.server.firewall // ""')

  if [[ "$firewall_enabled" != "on" && "$firewall_enabled" != "true" ]]; then
    printf "⚠️  Firewall is NOT active – enabling now ...\n"
    local enable_response
    enable_response=$(_upcloud_api_put "server/$SERVER_UUID" '{"server": { "firewall": "on" }}')
    firewall_enabled=$(echo "$enable_response" | jq -r '.server.firewall // ""')
    if [[ "$firewall_enabled" != "on" && "$firewall_enabled" != "true" ]]; then
      printf "❌ Failed to enable firewall:\n"
      echo "$enable_response" | jq -r '.error.message // "Unknown error"'
      return 1
    fi
    printf "✅ Firewall successfully enabled.\n"
  else
    printf "✅ Firewall is already active – loading rules ...\n"
  fi

  # Load rules
  local response
  response=$(_upcloud_api_get "server/$SERVER_UUID/firewall_rule")

  if ! echo "$response" | jq -e '.firewall_rules.firewall_rule' >/dev/null 2>&1; then
    printf "ℹ️  No firewall rules found or API error.\n"
    return 0
  fi

  mapfile -t rules < <(echo "$response" | jq -c '.firewall_rules.firewall_rule[]')

  if [[ ${#rules[@]} -eq 0 ]]; then
    printf "ℹ️  No firewall rules present.\n"
    return 0
  fi

  printf "📋 %d rules found – starting deletion ...\n\n" "${#rules[@]}"

  # Delete rules in reverse order
  for ((i=${#rules[@]}-1; i>=0; i--)); do
    local rule="${rules[$i]}"
    local position
    position=$(echo "$rule" | jq -r '.position')

    printf "❌ Deleting rule at position %s:\n" "$position"
    _print_firewall_rule "$rule"

    local del_response
    del_response=$(curl -s -u "$UPCLOUD_API_USER:$UPCLOUD_API_PASS" -X DELETE \
      "$UPCLOUD_API_BASE/server/$SERVER_UUID/firewall_rule/$position")

    if echo "$del_response" | jq -e '.error' >/dev/null 2>&1; then
      printf "⚠️  Failed to delete rule:\n"
      echo "$del_response" | jq -r '.error.message // .error // .'
    else
      printf "✅ Rule successfully deleted.\n"
      printf "────────────────────────────────────────────────────────────\n"
    fi
  done

  printf "✅ All rules deleted (unless errors occurred).\n"
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
    printf "✅ Firewall successfully enabled.\n"
    return 0
  else
    printf "❌ Failed to enable firewall:\n"
    echo "$response" | jq -r '.error.message // "Unknown error"'
    return 1
  fi
}

apply_upcloud_firewall_rules() {
  set +e  # Handle errors manually
  set -u  # Treat unset variables as errors
  _clear
  printf "\n"

  printf "🧱 Applying firewall rules for Blazor Hosting on UpCloud (from config/desired_firewall_rules.json)\n"
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

  if ! _delete_all_upcloud_firewall_rules; then
    printf "⚠️  Warning: Could not delete existing firewall rules.\n"
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
    add_response=$(curl -s -w "\n%{http_code}" -u "$UPCLOUD_API_USER:$UPCLOUD_API_PASS" \
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