#!/bin/bash
# shellcheck disable=SC1091
set -e

# Note: log.sh should NOT source common.sh to avoid circular dependency
# log.sh provides logging functions that can be used by any module
source ./lib/print.sh
source ./lib/cloudflare.sh
source ./lib/certbot.sh
source ./lib/github.sh

# Centralized error logging configuration
declare -g ERROR_LOG_DIR="${ERROR_LOG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ghostly-hosting/logs}"
declare -g ERROR_LOG_FILE="${ERROR_LOG_DIR}/error.log"
declare -g DEBUG_MODE="${DEBUG_MODE:-false}"

# Initialize error logging
_init_error_logging() {
  mkdir -p "$ERROR_LOG_DIR" 2>/dev/null || true
  if [[ ! -w "$ERROR_LOG_DIR" ]]; then
    ERROR_LOG_DIR="/tmp/ghostly-hosting-logs"
    mkdir -p "$ERROR_LOG_DIR" 2>/dev/null || true
    ERROR_LOG_FILE="${ERROR_LOG_DIR}/error.log"
  fi
}

# Log error message with context
# Usage: log_error "context" "message" ["exit_code"]
log_error() {
  local context="${1:-unknown}"
  local message="${2:-no message provided}"
  local exit_code="${3:-1}"
  local timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  _init_error_logging
  
  # Log to file
  {
    echo "[$timestamp] [ERROR] [$context] $message"
    [[ "$exit_code" != "0" ]] && echo "[$timestamp] [ERROR] [$context] Exit code: $exit_code"
  } >> "$ERROR_LOG_FILE" 2>/dev/null || true
  
  # Also log to stderr if debug mode
  if [[ "$DEBUG_MODE" == "true" ]]; then
    echo " [$context] $message" >&2
  fi
}

# Log warning message
# Usage: log_warning "context" "message"
log_warning() {
  local context="${1:-unknown}"
  local message="${2:-no message provided}"
  local timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  _init_error_logging
  
  echo "[$timestamp] [WARNING] [$context] $message" >> "$ERROR_LOG_FILE" 2>/dev/null || true
  
  if [[ "$DEBUG_MODE" == "true" ]]; then
    echo "  [$context] $message" >&2
  fi
}

# Log info message (for audit trail)
# Usage: log_info "context" "message"
log_info() {
  local context="${1:-unknown}"
  local message="${2:-no message provided}"
  local timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  _init_error_logging
  
  echo "[$timestamp] [INFO] [$context] $message" >> "$ERROR_LOG_FILE" 2>/dev/null || true
  
  if [[ "$DEBUG_MODE" == "true" ]]; then
    echo "  [$context] $message" >&2
  fi
}

# Log debug message (only when DEBUG_MODE=true)
# Usage: log_debug "context" "message"
log_debug() {
  [[ "$DEBUG_MODE" != "true" ]] && return 0
  
  local context="${1:-unknown}"
  local message="${2:-no message provided}"
  local timestamp
  timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  _init_error_logging
  
  echo "[$timestamp] [DEBUG] [$context] $message" >> "$ERROR_LOG_FILE" 2>/dev/null || true
  echo " [$context] $message" >&2
}


_strip_ansi() {
  sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g'
}

_view_log_file_filtered() {
  local file="$1"

  grep -a -Eiv 'googlebot|bingbot|ahrefsbot|yandex|semrush|baiduspider' "$file" |
  grep -a -Ev 'HEAD /| 301 | 302 | 304 | 403 ' |
  _strip_ansi |
  sed -E \
    -e 's/\[ERR.*?\]/\x1b[1;31m&\x1b[0m/gI' \
    -e 's/\[FATAL.*?\]/\x1b[1;31m&\x1b[0m/gI' \
    -e 's/\[WARN.*?\]/\x1b[1;33m&\x1b[0m/gI' \
    -e 's/\[INF.*?\]/\x1b[1;36m&\x1b[0m/gI' \
    -e 's/\[DBG.*?\]/\x1b[2m&\x1b[0m/gI' |
  less -R +G
}


_show_log_file_menu() {
  local log_dir="$1"
  local title="$2"
  local domain="$3"

  if [[ ! -d "$log_dir" ]]; then
    echo -e "\n No log directory found at: \e[2m$log_dir\e[0m"
    print_press_any_key
    return
  fi

  while true; do
    clear
    echo -e "\n$title  \e[2m$log_dir\e[0m"
    print_double_line

    mapfile -t log_files < <(find "$log_dir" -maxdepth 1 -type f \( -iname "*.log" -o -iname "*.txt" -o -iname "*.log.json" \) -size +0c -printf "%T@ %p\n" | sort -nr | cut -d' ' -f2-)
    if (( ${#log_files[@]} == 0 )); then
      echo -e "\n    No non-empty log files found.\n"
    else
      local i=1 row=""
      for f in "${log_files[@]}"; do
        local size_kb name date_display
        size_kb=$(du -k "$f" | awk '{print $1}')
        name=$(basename "$f")
        if [[ "$name" =~ ([0-9]{2})-([0-9]{2})-([0-9]{4}) ]]; then
          date_display="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}"
        else
          date_display=$(date -r "$f" "+%d-%m-%Y")
        fi
        row+=" $(printf "%2d)  %-10s \e[2m(%3s KB)\e[0m   " "$i" "$date_display" "$size_kb")"
        ((i % 3 == 0)) && { echo -e "$row"; row=""; }
        ((i++))
      done
      [[ -n "$row" ]] && echo -e "$row"
    fi

    echo -e "\n  $(print_back_to_menu)   \e[94m(https://$domain)\e[0m"
    read_menu_choice "${#log_files[@]}"
    echo ""

    if [[ "$REPLY" =~ ^[Qq]$ ]]; then
      return
    elif [[ "$REPLY" =~ ^[0-9]+$ && "$REPLY" -ge 1 && "$REPLY" -le "${#log_files[@]}" ]]; then
      local file="${log_files[$((REPLY - 1))]}"
      echo -e "\n Viewing: \e[36m$(basename "$file")\e[0m"
      _view_log_file_filtered "$file"
    else
      print_invalid_selection
      sleep 1
    fi
  done
}

show_app_log_files() {
  local service="$1"
  local domain log_dir
  log_dir=$(resolve_log_folder_from_service_name "$service")
  domain=$(resolve_domain_from_service_name "$service")
  _show_log_file_menu "$log_dir" " Application Logs:" "$domain"
}

show_webserver_access_logs() {
  local service="$1"
  local domain log_dir
  log_dir=$(resolve_log_folder_from_service_name "$service")
  domain=$(resolve_domain_from_service_name "$service")
  log_dir="$log_dir$WEB_LOGS_ACCESS_DIR"
  _show_log_file_menu "$log_dir" " Web Server Access Logs:" "$domain"
}

show_webserver_error_logs() {
  local service="$1"
  local domain log_dir
  log_dir=$(resolve_log_folder_from_service_name "$service")
  domain=$(resolve_domain_from_service_name "$service")
  log_dir="$log_dir$WEB_LOGS_ERROR_DIR"
  _show_log_file_menu "$log_dir" " Web Server Error Logs:" "$domain"
}

show_log_menu() {
  local service="$1"
  local url
  url=$(resolve_url_from_service_name "$service")

  while true; do
    clear
    echo -e "\n \033[1mLog Viewer: \e[94m($url)\e[0m"
    print_double_line
    echo -e "\n 1)  Access Logs    \e[2m(Nginx access.log)\e[0m       2)  Error Logs  \e[2m(Nginx error.log)\e[0m"
    echo -e "\n 3)  App Logs       \e[2m(Serilog, runtime etc.)\e[0m  $(print_back_to_menu)\n"
    read_menu_choice 3

    case "$REPLY" in
      1) show_webserver_access_logs "$service" ;;
      2) show_webserver_error_logs "$service" ;;
      3) show_app_log_files "$service" ;;
      q|Q) return ;;
    esac
  done
}
