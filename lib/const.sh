#!/bin/bash
# shellcheck disable=SC2034

# ==============================================================================
# ⚠️ WARNING: Do not source this file multiple times!
# ------------------------------------------------------------------------------
# This file defines global readonly variables (declare -gr / -agr).
# Bash does NOT allow re-declaring readonly variables during a session.
#
# ➤ Always ensure this file is sourced only ONCE per session.
# ➤ Never set these variables elsewhere (e.g. via `.env`, export, etc.)
# ➤ Use guard check: [[ -z "${__CONSTANTS_SH_LOADED:-}" ]] && source ./lib/constants.sh
# ==============================================================================

__CONSTANTS_SH_LOADED=1

# API Base URLs
declare -gr CLOUDFLARE_API_BASE="https://api.cloudflare.com/client/v4"
declare -gr GITHUB_API_BASE="https://api.github.com"
declare -gr UPCLOUD_API_BASE="https://api.upcloud.com/1.2"

# .NET Support
declare -agr SUPPORTED_DOTNET_VERSIONS=("6.0" "7.0" "8.0" "9.0")

# Base directory for all deployed apps
declare -gr APP_BASE_DIR="/var/www"

# Default subfolder structure for app-specific logs (used in Blazor deployment)
declare -gr LOGS_DIR="logs"
declare -gr WEB_LOGS_ACCESS_DIR="webserver/access"
declare -gr WEB_LOGS_ERROR_DIR="webserver/error"

# Default common folders
declare -gr CLONE_BASE_DIR="tmp-clone"
declare -gr BACKUP_DIR="backups"

# Default File names
declare -gr META_FILE_NAME="meta.json"

# Environment Variables (placeholders)
declare -g CLOUDFLARE_API_TOKEN=""
declare -g UPCLOUD_API_USER=""
declare -g UPCLOUD_API_PASS=""
declare -g GITHUB_API_TOKEN=""

# Server Info
declare -g SERVER_IPv4=""
declare -g SERVER_IPv6=""

