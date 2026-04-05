#!/bin/bash
# shellcheck disable=SC1091,SC2001
set -e

source ./lib/common.sh
source ./lib/print.sh

_clear() {
  [[ "${DISABLE_CLEAR}" == "true" ]] || clear
}

# =============================================================================
# Digital Ocean API Communication
# =============================================================================

_digitalocean_api_request() {
  local method="$1"
  local endpoint="$2"
  local data="$3"
  local body_var="$4"
  local status_var="$5"
  local raw="" http_code="unknown" body=""
  local curl_status=0
  local -a curl_args=()

  curl_args=(
    -sS
    -w "\n%{http_code}"
    -H "Authorization: Bearer $DIGITALOCEAN_API_TOKEN"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
  )

  if [[ "$method" != "GET" ]]; then
    curl_args+=(
      -X "$method"
    )
    if [[ -n "$data" ]]; then
      curl_args+=(-d "$data")
    fi
  fi

  if ! raw=$(curl "${curl_args[@]}" "$DIGITALOCEAN_API_BASE/$endpoint" 2>&1); then
    curl_status=$?
    body="$raw"
    http_code="curl_exit_$curl_status"
    printf -v "$body_var" '%s' "$body"
    printf -v "$status_var" '%s' "$http_code"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_digitalocean_api_request" "curl transport error $curl_status for $method $endpoint: $body"
    return 1
  fi

  http_code=$(printf '%s' "$raw" | tail -n1)
  body=$(printf '%s' "$raw" | head -n -1)

  printf -v "$body_var" '%s' "$body"
  printf -v "$status_var" '%s' "$http_code"

  if [[ "$http_code" == "2"* ]]; then
    return 0
  fi

  declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_digitalocean_api_request" "API error $http_code for $method $endpoint: $body"
  return 1
}

# =============================================================================
# Token Validation
# =============================================================================

validate_digitalocean_token() {
  local token="$1"

  if [[ -z "$token" || -z "$DIGITALOCEAN_API_BASE" ]]; then
    printf "❌ Missing Digital Ocean API token or API base.\n"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "validate_digitalocean_token" "Missing token or API base"
    return 1
  fi

  declare -f _safe_log >/dev/null 2>&1 && _safe_log debug "validate_digitalocean_token" "Validating Digital Ocean API token"

  local response status body
  response=$(curl -s -w "\n%{http_code}" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/json" \
    "$DIGITALOCEAN_API_BASE/account" 2>&1)
  status=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | head -n -1)

  if [[ "$status" == "200" ]]; then
    declare -f _safe_log >/dev/null 2>&1 && _safe_log info "validate_digitalocean_token" "Digital Ocean token validated successfully"
    return 0
  else
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "validate_digitalocean_token" "Token validation failed with status $status. Response: $body"
    return 1
  fi
}

# =============================================================================
# Firewall Management
# =============================================================================

# List all firewalls for this account and return those whose names match the
# GhostlyHosting naming convention, or all firewalls if none match.
_get_digitalocean_firewall_ids() {
  local response="" http_code="unknown"

  if ! _digitalocean_api_request "GET" "firewalls" "" response http_code; then
    printf "❌ Failed to list Digital Ocean firewalls (HTTP %s).\n" "$http_code"
    return 1
  fi

  echo "$response" | jq -r '.firewalls[].id' 2>/dev/null
}

_get_digitalocean_firewall_id_by_name() {
  local name="$1"
  local response="" http_code="unknown"

  if ! _digitalocean_api_request "GET" "firewalls" "" response http_code; then
    return 1
  fi

  echo "$response" | jq -r --arg name "$name" '.firewalls[] | select(.name == $name) | .id' 2>/dev/null | head -n1
}

# Build the firewall rules JSON payload from config/desired_firewall_rules.json
_build_digitalocean_firewall_payload() {
  local rules_file="$1"

  # Parse desired_firewall_rules.json and convert UpCloud format to Digital Ocean format
  # Inbound rules: direction=in → inbound_rules
  # Outbound rules: direction=out → outbound_rules
  jq -c '
    .firewall_rules.firewall_rule as $rules |
    {
      "name": "ghostly-hosting-firewall",
      "inbound_rules": [
        $rules[] | select(.direction == "in") |
        {
          "protocol": .protocol,
          "ports": .destination_port_start,
          "sources": {
            "addresses": ["0.0.0.0/0", "::/0"]
          }
        }
      ],
      "outbound_rules": [
        $rules[] | select(.direction == "out") |
        {
          "protocol": .protocol,
          "ports": .destination_port_start,
          "destinations": {
            "addresses": ["0.0.0.0/0", "::/0"]
          }
        }
      ]
    }
  ' "$rules_file" 2>/dev/null
}

apply_digitalocean_firewall_rules() {
  set +e
  _clear
  printf "\n"
  printf "🧱 Applying firewall rules for GhostlyHosting on Digital Ocean (from config/desired_firewall_rules.json)\n"
  printf "────────────────────────────────────────────────────────────\n"

  if [[ -z "$DIGITALOCEAN_API_TOKEN" ]]; then
    printf "❌ Missing Digital Ocean API token.\n"
    return 1
  fi

  local project_root rules_file
  project_root="$(get_project_root)"
  rules_file="$project_root/config/desired_firewall_rules.json"

  if [[ ! -f "$rules_file" ]]; then
    printf "❌ Firewall rule file is missing: %s\n" "$rules_file"
    return 1
  fi

  local payload
  payload=$(_build_digitalocean_firewall_payload "$rules_file")

  if [[ -z "$payload" || "$payload" == "null" ]]; then
    printf "❌ Failed to build Digital Ocean firewall payload from rules file.\n"
    return 1
  fi

  # Check if the firewall already exists
  local existing_id
  existing_id=$(_get_digitalocean_firewall_id_by_name "ghostly-hosting-firewall")

  local response="" http_code="unknown"

  if [[ -n "$existing_id" ]]; then
    printf "🔄 Updating existing firewall (ID: %s)...\n" "$existing_id"
    if ! _digitalocean_api_request "PUT" "firewalls/$existing_id" "$payload" response http_code; then
      printf "❌ Failed to update firewall (HTTP %s).\n" "$http_code"
      echo "$response" | jq . 2>/dev/null || echo "$response"
      return 1
    fi
    printf "✅ Firewall rules updated successfully.\n"
  else
    printf "➕ Creating new firewall...\n"
    if ! _digitalocean_api_request "POST" "firewalls" "$payload" response http_code; then
      printf "❌ Failed to create firewall (HTTP %s).\n" "$http_code"
      echo "$response" | jq . 2>/dev/null || echo "$response"
      return 1
    fi
    printf "✅ Firewall created successfully.\n"
  fi

  local rule_count
  rule_count=$(echo "$payload" | jq '(.inbound_rules | length) + (.outbound_rules | length)' 2>/dev/null || echo "0")

  printf "\n📊 Summary:\n"
  printf "✅ Successfully applied: %s rules\n" "$rule_count"
  printf "────────────────────────────────────────────────────────────\n"
  return 0
}

delete_all_digitalocean_firewall_rules() {
  _clear
  printf "\n🧨 Deleting All Digital Ocean Firewalls\n"
  printf "────────────────────────────────────────────────────────────\n"

  if [[ -z "$DIGITALOCEAN_API_TOKEN" ]]; then
    printf "❌ Missing Digital Ocean API token.\n"
    return 1
  fi

  local firewall_ids
  mapfile -t firewall_ids < <(_get_digitalocean_firewall_ids 2>/dev/null)

  if [[ ${#firewall_ids[@]} -eq 0 ]]; then
    printf "ℹ️ No firewalls found – nothing to delete.\n"
    return 0
  fi

  printf "🗑️ Found %s firewall(s) to delete.\n" "${#firewall_ids[@]}"

  local failed=0
  for fid in "${firewall_ids[@]}"; do
    [[ -z "$fid" ]] && continue
    local response="" http_code="unknown"
    if _digitalocean_api_request "DELETE" "firewalls/$fid" "" response http_code; then
      printf "✅ Deleted firewall: %s\n" "$fid"
    else
      printf "❌ Failed to delete firewall %s (HTTP %s).\n" "$fid" "$http_code"
      failed=$((failed + 1))
    fi
  done

  if [[ "$failed" -gt 0 ]]; then
    printf "⚠️ %s firewall(s) could not be deleted.\n" "$failed"
    return 1
  fi

  printf "✅ All Digital Ocean firewalls deleted.\n"
  return 0
}

_show_digitalocean_firewall_status() {
  _clear
  printf "\n📊 Digital Ocean Firewall Status\n"
  printf "────────────────────────────────────────────────────────────\n"

  if [[ -z "$DIGITALOCEAN_API_TOKEN" ]]; then
    printf "❌ Missing Digital Ocean API token.\n"
    return 1
  fi

  local response="" http_code="unknown"
  if ! _digitalocean_api_request "GET" "firewalls" "" response http_code; then
    printf "❌ Failed to retrieve firewalls (HTTP %s).\n" "$http_code"
    return 1
  fi

  local count
  count=$(echo "$response" | jq '.firewalls | length' 2>/dev/null || echo "0")

  if [[ "$count" == "0" ]]; then
    printf "ℹ️ No firewalls configured.\n"
    return 0
  fi

  printf "🔒 Active firewalls: %s\n\n" "$count"

  echo "$response" | jq -r '.firewalls[] | "🌐 Name: \(.name)\n   ID:     \(.id)\n   Status: \(.status)\n   Inbound rules:  \(.inbound_rules | length)\n   Outbound rules: \(.outbound_rules | length)\n"' 2>/dev/null
  return 0
}

_enable_digitalocean_firewall() {
  printf "\nℹ️ Digital Ocean firewalls are always active when configured.\n"
  printf "   Use 'Apply Server Rules' to ensure the correct rules are applied.\n"
  return 0
}

_disable_digitalocean_firewall() {
  printf "\nℹ️ Digital Ocean firewalls cannot be temporarily disabled via API.\n"
  printf "   Use 'Delete All Rules' to remove firewall protection.\n"
  return 0
}

# =============================================================================
# Token Configuration
# =============================================================================

_configure_digitalocean_api_token() {
  _clear
  printf "\n🔑 Update Digital Ocean API Token\n"
  printf "────────────────────────────────────────────────────────────\n"
  printf "ℹ️ A personal access token from Digital Ocean is required for firewall changes.\n"
  printf "ℹ️ Enter q to cancel and keep the current token.\n\n"

  local new_token
  _read_secret_with_asterisks "🔐 Enter new Digital Ocean API Token: " new_token

  if [[ "$new_token" == "q" || "$new_token" == "Q" ]]; then
    printf "↩️ Token update cancelled.\n"
    return 0
  fi

  if [[ -z "$new_token" ]]; then
    printf "❌ Token cannot be empty.\n"
    return 1
  fi

  if ! validate_digitalocean_token "$new_token"; then
    printf "❌ Token validation failed. Token not saved.\n"
    return 1
  fi

  DIGITALOCEAN_API_TOKEN="$new_token"

  # Persist updated token to .env.secure
  local env_file="$CONFIG_DIR/.env.secure"
  if [[ -f "$env_file" ]]; then
    local tmp_file
    tmp_file=$(mktemp)
    # Rewrite env file preserving all other entries
    grep -v '^DIGITALOCEAN_API_TOKEN=' "$env_file" >"$tmp_file" 2>/dev/null || true
    printf 'DIGITALOCEAN_API_TOKEN="%s"\n' "$DIGITALOCEAN_API_TOKEN" >>"$tmp_file"
    mv "$tmp_file" "$env_file"
    chmod 600 "$env_file"
  fi

  printf "✅ Digital Ocean API token updated and saved.\n"
  return 0
}

# =============================================================================
# Admin Menu
# =============================================================================

show_digitalocean_menu() {
  while true; do
    clear
    local version_suffix=""
    if declare -f format_version_display >/dev/null 2>&1; then
      version_suffix=" | $(format_version_display)"
    fi
    echo ""
    echo -e "\n 🔵  \e[1mDigital Ocean Firewall Rules\e[0m${version_suffix}"
    echo -e "\e[1m──────────────────────────────────────────────────────\e[0m"
    echo -e "\n 1) 🔐 Enable Firewall              2) 🔓 Disable Firewall"
    echo -e "\n 3) 📊 Show Firewall Status         4) 💣 Delete All Rules"
    echo -e "\n 5) 📦 Apply Server Rules           6) 🔑 Change API Token"
    echo -e "\n $(print_back_to_menu)"
    echo -e "\n─────────────────────────────────────────────────────────────"
    print_select_prompt 6

    IFS= read -rsn1 choice
    echo

    case "$choice" in
      1)
        _enable_digitalocean_firewall
        echo ""
        print_press_any_key
        ;;
      2)
        _disable_digitalocean_firewall
        echo ""
        print_press_any_key
        ;;
      3)
        _show_digitalocean_firewall_status
        echo ""
        print_press_any_key
        ;;
      4)
        delete_all_digitalocean_firewall_rules
        echo ""
        print_press_any_key
        ;;
      5)
        apply_digitalocean_firewall_rules
        echo ""
        print_press_any_key
        ;;
      6)
        _configure_digitalocean_api_token
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
