#!/bin/bash

# Ensures that error logging is only initialized once per shell session.
__ERROR_LOGGING_INITIALIZED=""
__ERROR_LOGGING_FD=""

__log_error_handler() {
  local exit_code="$1"
  local failed_command="$2"

  if [[ -z "$__ERROR_LOGGING_INITIALIZED" || -z "$__ERROR_LOGGING_FD" ]]; then
    return
  fi

  if [[ "$exit_code" -eq 0 ]]; then
    return
  fi

  printf '%s [ERROR] Command failed (exit %s): %s\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" \
    "$exit_code" \
    "$failed_command" \
    >&${__ERROR_LOGGING_FD}
}

__activate_error_logging() {
  local source_path="$1"
  local absolute_dir log_file

  if [[ -n "$__ERROR_LOGGING_INITIALIZED" ]]; then
    return
  fi

  absolute_dir=$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && pwd)
  log_file="$absolute_dir/$(basename "$source_path").error.log"

  touch "$log_file"
  chmod 600 "$log_file"

  exec {__ERROR_LOGGING_FD}>>"$log_file"

  exec 2> >(while IFS= read -r line; do
    printf '%s [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$line" >&${__ERROR_LOGGING_FD}
  done)

  trap '__log_error_handler $? "$BASH_COMMAND"' ERR
  set -E

  __ERROR_LOGGING_INITIALIZED=1
}

initialize_error_logging_for_script() {
  local source_path="$1"
  local entry_point="$2"

  if [[ -z "$source_path" ]]; then
    return
  fi

  if [[ -z "$entry_point" || "$source_path" == "$entry_point" ]]; then
    __activate_error_logging "$source_path"
    return
  fi

  if [[ "$entry_point" == */* || "$source_path" == */* ]]; then
    local normalized_source normalized_entry

    normalized_source=$(cd -P "$(dirname "$source_path")" >/dev/null 2>&1 && printf '%s/%s' "$(pwd)" "$(basename "$source_path")")
    normalized_entry=$(cd -P "$(dirname "$entry_point")" >/dev/null 2>&1 && printf '%s/%s' "$(pwd)" "$(basename "$entry_point")")

    if [[ "$normalized_source" == "$normalized_entry" ]]; then
      __activate_error_logging "$source_path"
    fi
  fi
}
