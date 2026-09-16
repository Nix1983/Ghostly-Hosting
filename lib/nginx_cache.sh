#!/bin/bash

nginx_cache_fallback_variable() {
  local digest
  digest=$(printf '%s' "$1" | sha256sum) || return 1
  printf 'ghostly_cache_fallback_%s' "${digest:0:16}"
}

write_nginx_cache_fallback_map() {
  local variable="$1"
  # An empty add_header value emits no header; upstream policies pass through.
  printf 'map $upstream_http_cache_control $%s {\n' "$variable"
  printf '    default "";\n    "" "no-store";\n}\n\n'
}

write_nginx_cache_fallback_header() {
  # Keep a location-level directive to preserve existing security-header inheritance.
  printf '        add_header Cache-Control $%s always;\n' "$1"
}
