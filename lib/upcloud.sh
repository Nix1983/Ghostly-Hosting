#!/bin/bash
# shellcheck disable=SC1091

set -e

source ./lib/common.sh
source ./lib/print.sh

_clear() {
  [[ "${DISABLE_CLEAR}" == "true" ]] || clear
}

_upcloud_print_error() {
  local method="${1:-REQUEST}"
  local endpoint="${2:-unknown}"
  local http_code="${3:-unknown}"
  local body="${4:-}"
  local error_code error_type

  error_code=$(echo "$body" | jq -r '.error.error_code // .errors.error_code // .status // empty' 2>/dev/null)
  error_type=$(echo "$body" | jq -r '.type // empty' 2>/dev/null)

  if [[ "$http_code" == "unknown" ]]; then
    case "$error_code" in
      SERVER_FORBIDDEN|IP_ADDRESS_FORBIDDEN) http_code="403" ;;
      SERVER_NOT_FOUND|IP_ADDRESS_NOT_FOUND) http_code="404" ;;
      AUTHENTICATION_FAILED|ERROR_ACCESS_DENIED) http_code="401" ;;
    esac
  fi

  printf "🔸 UpCloud API %s %s returned HTTP %s\n" "$method" "$endpoint" "$http_code"

  if [[ -n "$error_code" && "$error_code" != "null" ]]; then
    printf "🔸 API error code: %s\n" "$error_code"
  elif [[ -n "$error_type" && "$error_type" != "null" ]]; then
    printf "🔸 API error type: %s\n" "$error_type"
  fi

  case "$http_code" in
    401)
      printf "💡 UpCloud rejected the token. Common causes: token expired, token typo, or allowed IP ranges do not include this server.\n"
      ;;
    403)
      printf "💡 Token is valid but lacks access to the requested UpCloud resource.\n"
      ;;
    404)
      printf "💡 UpCloud did not find the requested resource or endpoint.\n"
      ;;
  esac

  case "$error_code" in
    SERVER_FORBIDDEN)
      printf "💡 UpCloud reports this server is owned by another account. Use a token from the account that owns the server, or grant the subaccount access to this server.\n"
      ;;
    IP_ADDRESS_FORBIDDEN)
      printf "💡 UpCloud does not allow this token to inspect that IP resource directly. The script already falls back to metadata/server lookups where possible.\n"
      ;;
  esac
}

_upcloud_api_request() {
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
    -H "Authorization: Bearer $UPCLOUD_API_TOKEN"
    -H "Accept: application/json"
  )

  if [[ "$method" != "GET" ]]; then
    curl_args+=(
      -H "Content-Type: application/json"
      -X "$method"
      -d "$data"
    )
  fi

  if ! raw=$(curl "${curl_args[@]}" "$UPCLOUD_API_BASE/$endpoint" 2>&1); then
    curl_status=$?
    body="$raw"
    http_code="curl_exit_$curl_status"
    printf -v "$body_var" '%s' "$body"
    printf -v "$status_var" '%s' "$http_code"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_upcloud_api_request" "curl transport error $curl_status for $method $endpoint: $body"
    return 1
  fi

  http_code=$(printf '%s' "$raw" | tail -n1)
  body=$(printf '%s' "$raw" | head -n -1)

  printf -v "$body_var" '%s' "$body"
  printf -v "$status_var" '%s' "$http_code"

  if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
    return 0
  fi

  declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_upcloud_api_request" "HTTP $http_code from $method $endpoint: $body"
  return 1
}

_upcloud_urlencode() {
  local value="$1"
  jq -rn --arg value "$value" '$value | @uri'
}

_is_valid_upcloud_uuid() {
  local value="${1:-}"
  [[ "$value" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

_set_upcloud_server_uuid() {
  local uuid="$1"
  local strategy="$2"

  SERVER_UUID="$uuid"
  printf "✅ SERVER_UUID detected and set: %s\n" "$SERVER_UUID"
  declare -f _safe_log >/dev/null 2>&1 && _safe_log info "_get_upcloud_server_uuid_by_ip" "Successfully resolved SERVER_UUID via $strategy: $SERVER_UUID"
}

_extract_server_uuid_from_server_details() {
  local server_json="$1"
  local lookup_ip="$2"

  echo "$server_json" | jq -r --arg ip "$lookup_ip" '
    def has_ip($list):
      any(($list // [])[]?; .address == $ip);

    def has_ip_in_interfaces($interfaces):
      any(($interfaces // [])[]?;
        has_ip(.ip_addresses.ip_address)
      );

    .server as $server
    | select(
        has_ip($server.ip_addresses.ip_address)
        or has_ip_in_interfaces($server.networking.interfaces.interface)
      )
    | $server.uuid // empty
  ' 2>/dev/null
}

_get_upcloud_server_uuid_via_metadata_service() {
  local metadata_uuid=""

  metadata_uuid=$(curl -fsS --max-time 2 http://169.254.169.254/metadata/v1/instance_id 2>/dev/null | tr -d '[:space:]') || true

  if _is_valid_upcloud_uuid "$metadata_uuid"; then
    printf "ℹ️ Resolved server UUID via UpCloud metadata service.\n"
    _set_upcloud_server_uuid "$metadata_uuid" "metadata service"
    return 0
  fi

  declare -f _safe_log >/dev/null 2>&1 && _safe_log debug "_get_upcloud_server_uuid_by_ip" "Metadata service did not return a valid server UUID"
  return 1
}

_get_upcloud_server_uuid_via_server_search() {
  local lookup_ip="$1"
  # shellcheck disable=SC2034
  local encoded_ip search_response search_status candidate_uuid server_detail detail_status uuid
  local -a candidate_uuids=()

  encoded_ip=$(_upcloud_urlencode "$lookup_ip")

  if ! _upcloud_api_request "GET" "server?search=$encoded_ip" "" search_response search_status; then
    declare -f _safe_log >/dev/null 2>&1 && _safe_log warning "_get_upcloud_server_uuid_by_ip" "Server search failed for IP: $lookup_ip"
    return 1
  fi

  mapfile -t candidate_uuids < <(echo "$search_response" | jq -r '.servers.server[]?.uuid // empty' 2>/dev/null)

  if [[ ${#candidate_uuids[@]} -eq 0 ]]; then
    declare -f _safe_log >/dev/null 2>&1 && _safe_log warning "_get_upcloud_server_uuid_by_ip" "Server search returned no candidates for IP: $lookup_ip"
    return 1
  fi

  for candidate_uuid in "${candidate_uuids[@]}"; do
    _upcloud_api_request "GET" "server/$candidate_uuid" "" server_detail detail_status || continue
    uuid=$(_extract_server_uuid_from_server_details "$server_detail" "$lookup_ip")

    if [[ -n "$uuid" && "$uuid" != "null" ]]; then
      printf "ℹ️ Resolved server UUID via server search + details lookup.\n"
      _set_upcloud_server_uuid "$uuid" "server search"
      return 0
    fi
  done

  declare -f _safe_log >/dev/null 2>&1 && _safe_log warning "_get_upcloud_server_uuid_by_ip" "Server search found candidates but no exact IP match for: $lookup_ip"
  return 1
}

_get_upcloud_server_uuid_via_server_list() {
  local lookup_ip="$1"
  # shellcheck disable=SC2034
  local list_response list_status candidate_uuid server_detail detail_status uuid
  local -a candidate_uuids=()

  if ! _upcloud_api_request "GET" "server" "" list_response list_status; then
    declare -f _safe_log >/dev/null 2>&1 && _safe_log warning "_get_upcloud_server_uuid_by_ip" "Server list lookup failed for IP: $lookup_ip"
    return 1
  fi

  mapfile -t candidate_uuids < <(echo "$list_response" | jq -r '.servers.server[]?.uuid // empty' 2>/dev/null)

  if [[ ${#candidate_uuids[@]} -eq 0 ]]; then
    declare -f _safe_log >/dev/null 2>&1 && _safe_log warning "_get_upcloud_server_uuid_by_ip" "Server list returned no servers for IP lookup: $lookup_ip"
    return 1
  fi

  for candidate_uuid in "${candidate_uuids[@]}"; do
    _upcloud_api_request "GET" "server/$candidate_uuid" "" server_detail detail_status || continue
    uuid=$(_extract_server_uuid_from_server_details "$server_detail" "$lookup_ip")

    if [[ -n "$uuid" && "$uuid" != "null" ]]; then
      printf "ℹ️ Resolved server UUID via full server inventory lookup.\n"
      _set_upcloud_server_uuid "$uuid" "server list"
      return 0
    fi
  done

  declare -f _safe_log >/dev/null 2>&1 && _safe_log warning "_get_upcloud_server_uuid_by_ip" "Full server inventory lookup found no exact IP match for: $lookup_ip"
  return 1
}

_get_upcloud_server_uuid_by_ip() {
  if [[ -v SERVER_UUID && -n "$SERVER_UUID" && "$SERVER_UUID" != "null" ]]; then
    declare -f _safe_log >/dev/null 2>&1 && _safe_log debug "_get_upcloud_server_uuid_by_ip" "SERVER_UUID already set: $SERVER_UUID"
    return 0
  fi

  local lookup_ip="${SERVER_IPv4:-${SERVER_IPv6:-}}"

  if [[ -z "$lookup_ip" ]]; then
    printf "❌ Neither SERVER_IPv4 nor SERVER_IPv6 is set.\n"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "Neither SERVER_IPv4 nor SERVER_IPv6 is set"
    return 1
  fi

  if [[ -z "$UPCLOUD_API_TOKEN" || -z "$UPCLOUD_API_BASE" ]]; then
    printf "❌ Missing API credentials.\n"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "Missing UPCLOUD_API_TOKEN or UPCLOUD_API_BASE"
    return 1
  fi

  printf "🔍 Searching for server UUID using IP: \033[36m%s\033[0m ...\n" "$lookup_ip"
  declare -f _safe_log >/dev/null 2>&1 && _safe_log info "_get_upcloud_server_uuid_by_ip" "Looking up server UUID for IP: $lookup_ip"

  if _get_upcloud_server_uuid_via_metadata_service; then
    return 0
  fi

  if _get_upcloud_server_uuid_via_server_search "$lookup_ip"; then
    return 0
  fi

  if _get_upcloud_server_uuid_via_server_list "$lookup_ip"; then
    return 0
  fi

  local response="" http_code="unknown" uuid encoded_ip
  encoded_ip=$(_upcloud_urlencode "$lookup_ip")

  if ! _upcloud_api_request "GET" "ip_address/$encoded_ip" "" response http_code; then
    printf "❌ Failed to query UpCloud API\n"
    _upcloud_print_error "GET" "ip_address/$encoded_ip" "$http_code" "$response"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "API query failed for IP: $lookup_ip"
    return 1
  fi

  uuid=$(echo "$response" | jq -r '.ip_address.server // empty' 2>/dev/null)

  if [[ -n "$uuid" && "$uuid" != "null" ]]; then
    printf "ℹ️ Resolved server UUID via IP address endpoint fallback.\n"
    _set_upcloud_server_uuid "$uuid" "ip_address endpoint"
    return 0
  else
    printf "❌ IP not directly associated with a server (possibly floating IP or error)\n"
    declare -f _safe_log >/dev/null 2>&1 && _safe_log error "_get_upcloud_server_uuid_by_ip" "Could not resolve server UUID from IP $lookup_ip. Response: $response"
    return 1
  fi
}

_verify_upcloud_context() {
  if [[ -z "$UPCLOUD_API_TOKEN" || -z "$UPCLOUD_API_BASE" ]]; then
    printf "❌ Missing API credentials.\n"
    return 1
  fi

  if [[ -n "${SERVER_UUID:-}" && "$SERVER_UUID" != "null" ]]; then
    return 0
  fi

  if [[ -z "$SERVER_IPv4" && -z "$SERVER_IPv6" ]]; then
    printf "❌ Neither SERVER_IPv4 nor SERVER_IPv6 is set.\n"
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
  local http_code="unknown" body=""
  if ! _upcloud_api_request "GET" "$endpoint" "" body http_code; then
    printf '%s' "$body"
    return 1
  fi
  printf '%s' "$body"
  return 0
}

_upcloud_api_put() {
  local endpoint="$1"
  local data="$2"
  local http_code="unknown" body=""
  if ! _upcloud_api_request "PUT" "$endpoint" "$data" body http_code; then
    printf '%s' "$body"
    return 1
  fi
  printf '%s' "$body"
  return 0
}

_get_upcloud_firewall_enabled_state() {
  local server_info="" http_code="unknown" firewall_enabled=""
  local rules_response=""

  if _upcloud_api_request "GET" "server/$SERVER_UUID" "" server_info http_code; then
    firewall_enabled=$(echo "$server_info" | jq -r '.server.firewall // empty' 2>/dev/null)
    case "$firewall_enabled" in
      on|true)
        printf 'enabled\n'
        return 0
        ;;
      off|false)
        printf 'disabled\n'
        return 0
        ;;
    esac
  fi

  if _upcloud_api_request "GET" "server/$SERVER_UUID/firewall_rule" "" rules_response _; then
    if echo "$rules_response" | jq -e '.firewall_rules.firewall_rule' >/dev/null 2>&1; then
      printf 'enabled\n'
      return 0
    fi
  fi

  printf 'unknown\n'
  return 1
}

_get_upcloud_firewall_rules_response() {
  local body_var="$1"
  local status_var="$2"
  local api_response="" api_http_code="unknown"

  if ! _upcloud_api_request "GET" "server/$SERVER_UUID/firewall_rule" "" api_response api_http_code; then
    printf -v "$body_var" '%s' "$api_response"
    printf -v "$status_var" '%s' "$api_http_code"
    return 1
  fi

  if ! echo "$api_response" | jq -e '.firewall_rules.firewall_rule' >/dev/null 2>&1; then
    printf -v "$body_var" '%s' "$api_response"
    printf -v "$status_var" '%s' "$api_http_code"
    return 1
  fi

  printf -v "$body_var" '%s' "$api_response"
  printf -v "$status_var" '%s' "$api_http_code"
  return 0
}

_read_secret_with_asterisks() {
  local prompt="$1"
  local result_var="$2"
  local input="" char

  printf '%s' "$prompt"

  while IFS= read -rsn1 char; do
    if [[ -z "$char" || "$char" == $'\n' ]]; then
      printf '\n'
      break
    fi

    if [[ "$char" == $'\x7f' || "$char" == $'\x08' ]]; then
      if [[ -n "$input" ]]; then
        input="${input%?}"
        printf '\b \b'
      fi
      continue
    fi

    input+="$char"
    printf '*'
  done

  printf -v "$result_var" '%s' "$input"
}

_normalize_upcloud_firewall_rules_array() {
  jq -c '
    [
      .. | objects
      | select(
          has("direction")
          and has("action")
          and (
            has("protocol")
            or has("family")
            or has("position")
            or has("destination_port_start")
            or has("source_port_start")
          )
        )
    ]
  ' 2>/dev/null
}

_get_upcloud_normalized_firewall_rules_json() {
  local response="$1"
  printf '%s' "$response" | _normalize_upcloud_firewall_rules_array
}

_get_upcloud_normalized_firewall_rule_count() {
  local response="$1"
  local count
  count=$(printf '%s' "$response" | _normalize_upcloud_firewall_rules_array | jq -r 'length' 2>/dev/null || true)

  if [[ -z "$count" || "$count" == "null" ]]; then
    printf '0\n'
    return 0
  fi

  printf '%s\n' "$count"
}

_get_upcloud_firewall_rule_lines_from_response() {
  local response="$1"

  if printf '%s' "$response" | jq -e '.firewall_rules.firewall_rule | type == "array"' >/dev/null 2>&1; then
    printf '%s' "$response" | jq -c '.firewall_rules.firewall_rule[]?' 2>/dev/null
    return 0
  fi

  printf '%s' "$response" | _normalize_upcloud_firewall_rules_array | jq -c '.[]?' 2>/dev/null
}

_get_upcloud_firewall_rule_count_from_response() {
  local response="$1"
  local count=""

  if printf '%s' "$response" | jq -e '.firewall_rules.firewall_rule | type == "array"' >/dev/null 2>&1; then
    count=$(printf '%s' "$response" | jq -r '.firewall_rules.firewall_rule | length' 2>/dev/null || true)
  else
    count=$(_get_upcloud_normalized_firewall_rule_count "$response")
  fi

  if [[ -z "$count" || "$count" == "null" ]]; then
    printf '0\n'
    return 0
  fi

  printf '%s\n' "$count"
}

_count_nonempty_lines() {
  awk 'NF { count++ } END { print count + 0 }'
}

_get_upcloud_firewall_rule_count_for_runtime() {
  local response="$1"

  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$response" | python3 -c '
import json, sys
try:
    payload = json.load(sys.stdin)
except Exception:
    print(0)
    raise SystemExit(0)
rules = payload.get("firewall_rules", {}).get("firewall_rule", [])
if isinstance(rules, dict):
    rules = rules.get("firewall_rule", [])
print(len(rules) if isinstance(rules, list) else 0)
' 2>/dev/null
    return 0
  fi

  printf '%s' "$response" | jq -r '(.firewall_rules.firewall_rule | if type == "array" then length else 0 end) // 0' 2>/dev/null || printf '0\n'
}

_emit_upcloud_firewall_rule_lines_for_runtime() {
  local response="$1"
  local direction="${2:-}"
  local order="${3:-normal}"

  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$response" | python3 -c '
import json, sys
direction = sys.argv[1]
order = sys.argv[2]
try:
    payload = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
rules = payload.get("firewall_rules", {}).get("firewall_rule", [])
if isinstance(rules, dict):
    rules = rules.get("firewall_rule", [])
if not isinstance(rules, list):
    rules = []
if direction:
    rules = [rule for rule in rules if isinstance(rule, dict) and rule.get("direction") == direction]
if order == "reverse":
    rules = list(reversed(rules))
for rule in rules:
    print(json.dumps(rule, separators=(",", ":"), ensure_ascii=False))
' "$direction" "$order" 2>/dev/null
    return 0
  fi

  local filter='.firewall_rules.firewall_rule[]?'
  if [[ "$order" == "reverse" ]]; then
    filter='.firewall_rules.firewall_rule | reverse[]?'
  fi
  if [[ -n "$direction" ]]; then
    filter="$filter | select(.direction == \"$direction\")"
  fi

  printf '%s' "$response" | jq -c "$filter" 2>/dev/null
}

_print_json_or_raw() {
  local payload="${1:-}"

  if [[ -z "$payload" ]]; then
    printf "(empty)\n"
    return 0
  fi

  if printf '%s' "$payload" | jq . >/dev/null 2>&1; then
    printf '%s' "$payload" | jq .
  else
    printf '%s\n' "$payload"
  fi
}

_print_upcloud_runtime_parse_diagnostics() {
  local response="$1"
  local context_label="${2:-Runtime}"
  local tmp_normalized exact_count normalized_count file_count
  local incoming_preview outgoing_preview reverse_preview
  local python_path jq_path

  tmp_normalized=$(mktemp)
  _get_upcloud_normalized_firewall_rules_json "$response" >"$tmp_normalized"

  exact_count=$(printf '%s' "$response" | jq -r '.firewall_rules.firewall_rule | length' 2>/dev/null || printf 'jq_failed')
  normalized_count=$(_get_upcloud_normalized_firewall_rule_count "$response" 2>/dev/null || printf 'helper_failed')
  file_count=$(jq -r 'length' "$tmp_normalized" 2>/dev/null || printf 'file_failed')
  incoming_preview=$(jq -c '.[] | select(.direction == "in")' "$tmp_normalized" 2>/dev/null | head -n 1)
  outgoing_preview=$(jq -c '.[] | select(.direction == "out")' "$tmp_normalized" 2>/dev/null | head -n 1)
  reverse_preview=$(jq -c 'reverse[]?' "$tmp_normalized" 2>/dev/null | head -n 1)
  python_path=$(command -v python3 2>/dev/null || printf 'missing')
  jq_path=$(command -v jq 2>/dev/null || printf 'missing')

  printf "\n🧪 %s Parse Diagnostics\n" "$context_label"
  printf "────────────────────────────────────────────────────────────\n"
  printf "response_bytes: %s\n" "$(printf '%s' "$response" | wc -c | tr -d ' ')"
  printf "python3: %s\n" "$python_path"
  printf "jq: %s\n" "$jq_path"
  printf "exact_jq_count: %s\n" "$exact_count"
  printf "normalized_helper_count: %s\n" "$normalized_count"
  printf "normalized_file_count: %s\n" "$file_count"
  printf "normalized_file_bytes: %s\n" "$(wc -c <"$tmp_normalized" | tr -d ' ')"
  printf "first_incoming_rule: %s\n" "${incoming_preview:-<empty>}"
  printf "first_outgoing_rule: %s\n" "${outgoing_preview:-<empty>}"
  printf "first_reverse_rule: %s\n" "${reverse_preview:-<empty>}"
  printf "normalized_preview:\n"
  head -c 400 "$tmp_normalized"
  printf "\n"

  rm -f "$tmp_normalized"
}

_debug_upcloud_firewall_api() {
  _clear
  printf "\n🧪 UpCloud Firewall API Debug\n"
  printf "────────────────────────────────────────────────────────────\n"

  _verify_upcloud_context || return 1

  local server_response="" server_status="unknown"
  local rules_response="" rules_status="unknown"
  local normalized_rules="[]" normalized_count="0"
  local exact_node_type="missing" recursive_rule_like_count="0"

  if _upcloud_api_request "GET" "server/$SERVER_UUID" "" server_response server_status; then
    printf "✅ GET server/%s succeeded (HTTP %s)\n" "$SERVER_UUID" "$server_status"
  else
    printf "❌ GET server/%s failed\n" "$SERVER_UUID"
    _upcloud_print_error "GET" "server/$SERVER_UUID" "$server_status" "$server_response"
  fi

  if _upcloud_api_request "GET" "server/$SERVER_UUID/firewall_rule" "" rules_response rules_status; then
    printf "✅ GET server/%s/firewall_rule succeeded (HTTP %s)\n" "$SERVER_UUID" "$rules_status"
  else
    printf "❌ GET server/%s/firewall_rule failed\n" "$SERVER_UUID"
    _upcloud_print_error "GET" "server/$SERVER_UUID/firewall_rule" "$rules_status" "$rules_response"
  fi

  normalized_rules=$(_get_upcloud_normalized_firewall_rules_json "$rules_response")
  normalized_count=$(_get_upcloud_normalized_firewall_rule_count "$rules_response")
  exact_node_type=$(printf '%s' "$rules_response" | jq -r '(.firewall_rules.firewall_rule | type) // "missing"' 2>/dev/null || printf 'invalid')
  recursive_rule_like_count=$(printf '%s' "$rules_response" | jq -r '
    [
      .. | objects
      | select(
          has("direction")
          and has("action")
          and (
            has("protocol")
            or has("family")
            or has("position")
            or has("destination_port_start")
            or has("source_port_start")
          )
        )
    ] | length
  ' 2>/dev/null || printf '0')

  printf "\n📊 Parser Summary\n"
  printf "────────────────────────────────────────────────────────────\n"
  printf "SERVER_UUID: %s\n" "$SERVER_UUID"
  printf "Exact node type at .firewall_rules.firewall_rule: %s\n" "$exact_node_type"
  printf "Recursive rule-like object count: %s\n" "$recursive_rule_like_count"
  printf "Normalized firewall rule count: %s\n" "$normalized_count"

  printf "\n🛰️ Raw server response\n"
  printf "────────────────────────────────────────────────────────────\n"
  _print_json_or_raw "$server_response"

  printf "\n🧱 Raw firewall_rule response\n"
  printf "────────────────────────────────────────────────────────────\n"
  _print_json_or_raw "$rules_response"

  printf "\n🧰 Normalized firewall rules\n"
  printf "────────────────────────────────────────────────────────────\n"
  _print_json_or_raw "$normalized_rules"

  _print_upcloud_runtime_parse_diagnostics "$rules_response" "Debug"

  printf "═════════════════════════════════════════════════════════════\n"
}

_upcloud_firewall_rules_match_desired() {
  local project_root desired_file desired_json current_json
  project_root="$(get_project_root)"
  desired_file="$project_root/config/upcloud_firewall_rules.json"

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

  local current_response=""
  if ! _get_upcloud_firewall_rules_response current_response _; then
    printf "❌ Could not load current firewall rules from API.\n"
    return 1
  fi

  current_json=$(_get_upcloud_normalized_firewall_rules_json "$current_response" | jq -S '
    .
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

  if ! _verify_upcloud_context; then
    return 1
  fi

  local firewall_state response=""
  firewall_state=$(_get_upcloud_firewall_enabled_state)
  case "$firewall_state" in
    enabled) printf "✅ Firewall is already \e[32menabled\e[0m – loading rules...\n" ;;
    disabled) printf "ℹ️ Firewall is disabled, but stored rules can still be managed.\n" ;;
    *) printf "ℹ️ Firewall state could not be determined exactly – trying to load rules directly.\n" ;;
  esac

  if ! _get_upcloud_firewall_rules_response response _; then
    printf "ℹ️ No firewall rules found or API returned no data.\n"
    return 0
  fi

  local rule_count normalized_rules_file
  normalized_rules_file=$(mktemp)
  _get_upcloud_normalized_firewall_rules_json "$response" >"$normalized_rules_file"

  rule_count=$(jq -r 'length' "$normalized_rules_file" 2>/dev/null || printf '0')

  if [[ -z "$rule_count" || "$rule_count" == "null" ]]; then
    rule_count="0"
  fi

  if [[ "$rule_count" == "0" ]]; then
    printf "ℹ️ No firewall rules present.\n"
    rm -f "$normalized_rules_file"
    return 0
  fi

  printf "📋 %s firewall rules found.\n" "$rule_count"
  printf "⚡ Trying fast bulk reset via UpCloud ruleset replacement...\n"

  local clear_payload clear_response="" clear_status="unknown" remaining_response=""
  clear_payload='{"firewall_rules":{"firewall_rule":[]}}'

  if _upcloud_api_request "PUT" "server/$SERVER_UUID/firewall_rule" "$clear_payload" clear_response clear_status; then
    sleep 1
    if _get_upcloud_firewall_rules_response remaining_response _; then
      local remaining_count
      remaining_count=$(_get_upcloud_normalized_firewall_rule_count "$remaining_response")
      if [[ "$remaining_count" == "0" ]]; then
        rm -f "$normalized_rules_file"
        printf "✅ All firewall rules removed using fast bulk reset.\n"
        printf "═════════════════════════════════════════════════════════════\n"
        return 0
      fi
      printf "⚠️ Bulk reset completed, but %s rules are still reported. Falling back to individual delete...\n\n" "$remaining_count"
    else
      rm -f "$normalized_rules_file"
      printf "✅ Bulk reset request accepted by UpCloud.\n"
      printf "═════════════════════════════════════════════════════════════\n"
      return 0
    fi
  else
    printf "⚠️ Fast bulk reset was rejected by UpCloud. Falling back to individual delete...\n"
    _upcloud_print_error "PUT" "server/$SERVER_UUID/firewall_rule" "$clear_status" "$clear_response"
    printf "\n"
  fi

  printf "🪓 Deleting rules one by one as fallback...\n\n"

  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
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
  done < <(jq -c 'reverse[]?' "$normalized_rules_file" 2>/dev/null)
  rm -f "$normalized_rules_file"

  printf "\n✅ All rules deleted (unless errors occurred).\n"
  printf "═════════════════════════════════════════════════════════════\n"
}

_enable_upcloud_firewall() {
  _clear
  printf "\n🔒 Enabling UpCloud Firewall\n"
  printf "────────────────────────────────────────────────────────────\n"

  _verify_upcloud_context || return 1

  local response="" http_code="unknown" new_status
  if ! _upcloud_api_request "PUT" "server/$SERVER_UUID" '{"server": { "firewall": "on" }}' response http_code; then
    printf "❌ Failed to enable firewall:\n"
    _upcloud_print_error "PUT" "server/$SERVER_UUID" "$http_code" "$response"
    echo "$response" | jq -r '.error.message // .errors.error_message // .message // empty' 2>/dev/null
    return 1
  fi
  new_status=$(echo "$response" | jq -r '.server.firewall // ""')

  if [[ -z "$new_status" ]]; then
    new_status=$(_get_upcloud_firewall_enabled_state 2>/dev/null || true)
  fi

  if [[ "$new_status" == "on" || "$new_status" == "true" || "$new_status" == "enabled" ]]; then
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

  local response="" http_code="unknown" new_status
  if ! _upcloud_api_request "PUT" "server/$SERVER_UUID" '{"server": { "firewall": "off" }}' response http_code; then
    printf "❌ Failed to disable firewall:\n"
    _upcloud_print_error "PUT" "server/$SERVER_UUID" "$http_code" "$response"
    echo "$response" | jq -r '.error.message // .errors.error_message // .message // empty' 2>/dev/null
    return 1
  fi
  new_status=$(echo "$response" | jq -r '.server.firewall // ""')

  if [[ -z "$new_status" ]]; then
    new_status=$(_get_upcloud_firewall_enabled_state 2>/dev/null || true)
  fi

  if [[ "$new_status" == "off" || "$new_status" == "false" || "$new_status" == "disabled" ]]; then
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

  local firewall_enabled
  firewall_enabled=$(_get_upcloud_firewall_enabled_state 2>/dev/null || true)

  if [[ "$firewall_enabled" == "disabled" ]]; then
    printf "ℹ️  Firewall is currently \e[33mdisabled\e[0m (Status: '%s')\n" "$firewall_enabled"
    printf "────────────────────────────────────────────────────────────\n"
    return 0
  fi

  if [[ "$firewall_enabled" == "enabled" ]]; then
    printf "✅ Firewall is \e[32menabled\e[0m\n\n"
  else
    printf "ℹ️ Firewall status could not be read directly, but rules are available.\n\n"
  fi

  local response="" rule_count normalized_rules_file
  if ! _get_upcloud_firewall_rules_response response _; then
    echo "❌ Could not load firewall rules from API."
    return 1
  fi

  normalized_rules_file=$(mktemp)
  _get_upcloud_normalized_firewall_rules_json "$response" >"$normalized_rules_file"
  rule_count=$(jq -r 'length' "$normalized_rules_file" 2>/dev/null || printf '0')

  if [[ -z "$rule_count" || "$rule_count" == "null" ]]; then
    rule_count="0"
  fi
  [[ "$rule_count" == "0" ]] && {
    echo "ℹ️ No firewall rules defined."
    rm -f "$normalized_rules_file"
    return 0
  }

  echo "📥 Incoming Rules"
  echo "────────────────────────────────────────────────────────────"
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    [[ "$(echo "$rule" | jq -r '.direction')" == "in" ]] && _print_firewall_rule "$rule"
  done < <(jq -c '.[] | select(.direction == "in")' "$normalized_rules_file" 2>/dev/null)

  echo ""
  echo "📤 Outgoing Rules"
  echo "────────────────────────────────────────────────────────────"
  while IFS= read -r rule; do
    [[ -z "$rule" ]] && continue
    [[ "$(echo "$rule" | jq -r '.direction')" == "out" ]] && _print_firewall_rule "$rule"
  done < <(jq -c '.[] | select(.direction == "out")' "$normalized_rules_file" 2>/dev/null)
  rm -f "$normalized_rules_file"

  echo ""
  echo "═════════════════════════════════════════════════════════════"
}

apply_upcloud_firewall_rules() {
  set +e  # Handle errors manually
  set -u  # Treat unset variables as errors
  _clear
  printf "\n"

  printf "🧱 Applying firewall rules for GhostlyHosting on UpCloud (from config/upcloud_firewall_rules.json)\n"
  printf "────────────────────────────────────────────────────────────\n"

  local project_root rules_file
  project_root="$(get_project_root)"
  rules_file="$project_root/config/upcloud_firewall_rules.json"

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
  fi

  printf "🔄 Existing rules do not match desired state – overwriting rule set...\n"
  printf "➕ Loading new rules from: %s\n" "$rules_file"

  local rules_payload rule_count response="" http_code="unknown"
  rules_payload=$(jq -c '.firewall_rules.firewall_rule |= map(del(.position)) | .' "$rules_file" 2>/dev/null)

  if [[ -z "$rules_payload" || "$rules_payload" == "null" ]]; then
    printf "❌ No firewall rules found in JSON or syntax is invalid.\n"
    jq . "$rules_file" || cat "$rules_file"
    return 1
  fi

  rule_count=$(echo "$rules_payload" | jq -r '.firewall_rules.firewall_rule | length' 2>/dev/null)
  printf "📦 %s rules found. Applying complete ruleset...\n\n" "$rule_count"

  if ! _upcloud_api_request "PUT" "server/$SERVER_UUID/firewall_rule" "$rules_payload" response http_code; then
    printf "❌ Failed to apply firewall ruleset.\n"
    _upcloud_print_error "PUT" "server/$SERVER_UUID/firewall_rule" "$http_code" "$response"
    echo "$response" | jq . 2>/dev/null || echo "$response"
    return 1
  fi

  printf "✅ Firewall ruleset successfully applied.\n"
  printf "\n📊 Summary:\n"
  printf "✅ Successfully applied: %s\n" "$rule_count"
  printf "❌ Failed to add:      0\n"
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

_get_upcloud_current_server_uuid_for_token_check() {
  if _is_valid_upcloud_uuid "${SERVER_UUID:-}"; then
    printf '%s\n' "$SERVER_UUID"
    return 0
  fi

  local metadata_uuid=""
  metadata_uuid=$(curl -fsS --max-time 2 http://169.254.169.254/metadata/v1/instance_id 2>/dev/null | tr -d '[:space:]') || true

  if _is_valid_upcloud_uuid "$metadata_uuid"; then
    printf '%s\n' "$metadata_uuid"
    return 0
  fi

  return 1
}

_get_upcloud_token_server_access_status() {
  local token="$1"
  local server_uuid="" response="" status="" body="" error_code=""
  local scope_status="unknown"

  if [[ -z "$token" || -z "$UPCLOUD_API_BASE" ]]; then
    printf '%s\n' "$scope_status"
    return 0
  fi

  if ! server_uuid=$(_get_upcloud_current_server_uuid_for_token_check); then
    printf '%s\n' "$scope_status"
    return 0
  fi

  response=$(curl -sS -w "\n%{http_code}" \
    -H "Authorization: Bearer $token" \
    -H "Accept: application/json" \
    "$UPCLOUD_API_BASE/server/$server_uuid" 2>&1) || true
  status=$(printf '%s' "$response" | tail -n1)
  body=$(printf '%s' "$response" | head -n -1)
  error_code=$(printf '%s' "$body" | jq -r '.error.error_code // .errors.error_code // empty' 2>/dev/null || true)

  if [[ "$status" == "200" ]]; then
    scope_status="ok"
  elif [[ "$status" == "403" || "$error_code" == "SERVER_FORBIDDEN" || "$error_code" == "ACTION_FORBIDDEN" ]]; then
    scope_status="forbidden"
  elif [[ "$status" == "404" && "$error_code" == "SERVER_NOT_FOUND" ]]; then
    scope_status="forbidden"
  fi

  printf '%s\n' "$scope_status"
  return 0
}

_print_upcloud_wrong_account_hint() {
  printf "💡 Token is valid, but it cannot access this server.\n"
  printf "💡 UpCloud API tokens inherit the permissions of the account or subaccount that created them.\n"
  printf "💡 The server does not need to be created after the token. What matters is that the token comes from the owning account, or from a subaccount with explicit permission to this server.\n"
  printf "💡 If a subaccount created this server, that same subaccount automatically has access to it. Otherwise the main account must grant server permission first.\n"
}

_get_ghostly_env_file() {
  if [[ -n "${ENV_FILE:-}" ]]; then
    printf '%s\n' "$ENV_FILE"
    return 0
  fi

  local config_dir
  config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/ghostly-hosting"
  printf '%s/.env.secure\n' "$config_dir"
}

_persist_secure_tokens() {
  local env_file tmp_file
  env_file="$(_get_ghostly_env_file)"

  mkdir -p "$(dirname "$env_file")"
  tmp_file=$(mktemp)

  {
    printf 'CLOUDFLARE_API_TOKEN="%s"\n' "${CLOUDFLARE_API_TOKEN:-}"
    printf 'UPCLOUD_API_TOKEN="%s"\n' "${UPCLOUD_API_TOKEN:-}"
    printf 'GITHUB_API_TOKEN="%s"\n' "${GITHUB_API_TOKEN:-}"
  } >"$tmp_file"

  mv "$tmp_file" "$env_file"
  chmod 600 "$env_file"
}

_configure_upcloud_api_token() {
  _clear
  printf "\n🔑 Update UpCloud API Token\n"
  printf "────────────────────────────────────────────────────────────\n"
  printf "ℹ️ A token from the owning UpCloud account is required for firewall changes.\n"
  printf "ℹ️ Enter q to cancel and keep the current token.\n\n"

  local new_token scope_status="unknown"
  _read_secret_with_asterisks "🔐 Enter new UpCloud API Token: " new_token

  if [[ "$new_token" == "q" || "$new_token" == "Q" ]]; then
    printf "↩️ Token update cancelled.\n"
    return 0
  fi

  if [[ -z "$new_token" ]]; then
    printf "❌ No token entered.\n"
    return 1
  fi

  if ! validate_upcloud_token "$new_token"; then
    printf "❌ Token validation failed. Token was not saved.\n"
    return 1
  fi

  scope_status=$(_get_upcloud_token_server_access_status "$new_token")
  if [[ "$scope_status" == "forbidden" ]]; then
    printf "❌ Token is valid, but it does not have access to this server.\n"
    _print_upcloud_wrong_account_hint
    printf "❌ Token was not saved.\n"
    return 1
  fi

  UPCLOUD_API_TOKEN="$new_token"
  SERVER_UUID=""
  _persist_secure_tokens

  printf "✅ UpCloud API token saved successfully.\n"
  printf "📁 Stored at: %s\n" "$(_get_ghostly_env_file)"
  printf "ℹ️ SERVER_UUID cache cleared. The next request will resolve it again.\n"
  if [[ "$scope_status" == "unknown" ]]; then
    printf "ℹ️ The token was validated, but server ownership could not be verified from this environment.\n"
  fi
  return 0
}


show_upcloud_menu() {
  while true; do
    clear
    local version_suffix=""
    if declare -f format_version_display >/dev/null 2>&1; then
      version_suffix=" | $(format_version_display)"
    fi
    echo ""
    echo -e "\n 🌩️  \e[1mUpCloud Firewall Rules\e[0m${version_suffix}"
    echo -e "\e[1m──────────────────────────────────────────────────────\e[0m"
    echo -e "\n 1) 🔐 Enable Firewall              2) 🔓 Disable Firewall"
    echo -e "\n 3) 📊 Show Firewall Status         4) 💣 Delete All Rules"
    echo -e "\n 5) 📦 Apply Server Rules           6) 🔑 Change API Token"
    echo -e "\n 7) 🧪 Debug API"
    echo -e "\n $(print_back_to_menu)"
    echo -e "\n─────────────────────────────────────────────────────────────"
    print_select_prompt 7

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
      6)
        _configure_upcloud_api_token
        echo ""
        print_press_any_key
        ;;
      7)
        _debug_upcloud_firewall_api
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
