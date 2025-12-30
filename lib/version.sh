#!/bin/bash
set -e

# Version management functions

get_app_version() {
  local version_file
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  version_file="$script_dir/VERSION"

  if [[ -f "$version_file" ]]; then
    tr -d '[:space:]' < "$version_file"
  else
    echo "unknown"
  fi
}

format_version_display() {
  local version
  version=$(get_app_version)
  echo "v$version"
}
