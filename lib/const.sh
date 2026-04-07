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

# Guard: prevent re-sourcing
[[ -n "${__CONSTANTS_SH_LOADED:-}" ]] && return 0
__CONSTANTS_SH_LOADED=1

# ======================
# ⚙️ Global Constants
# ======================

# API Base URLs
[[ -z "${CLOUDFLARE_API_BASE+x}" ]]    && declare -gr CLOUDFLARE_API_BASE="https://api.cloudflare.com/client/v4"
[[ -z "${GITHUB_API_BASE+x}" ]]        && declare -gr GITHUB_API_BASE="https://api.github.com"
[[ -z "${UPCLOUD_API_BASE+x}" ]]       && declare -gr UPCLOUD_API_BASE="https://api.upcloud.com/1.3"
[[ -z "${DIGITALOCEAN_API_BASE+x}" ]] && declare -gr DIGITALOCEAN_API_BASE="https://api.digitalocean.com/v2"

# .NET Support
# Baseline versions for display in menus - dynamically extended by get_available_dotnet_versions()
[[ -z "${BASELINE_DOTNET_VERSIONS+x}" ]] && declare -agr BASELINE_DOTNET_VERSIONS=("6.0" "7.0" "8.0" "9.0")
# Minimum supported .NET version
[[ -z "${MIN_DOTNET_VERSION+x}" ]] && declare -gr MIN_DOTNET_VERSION="6.0"

# Base directory for all deployed apps
[[ -z "${APP_BASE_DIR+x}" ]] && declare -gr APP_BASE_DIR="/var/www"

# Default subfolder structure for app-specific logs (used in Blazor deployment)
[[ -z "${LOGS_DIR+x}" ]]             && declare -gr LOGS_DIR="logs"
[[ -z "${WEB_LOGS_ACCESS_DIR+x}" ]]  && declare -gr WEB_LOGS_ACCESS_DIR="webserver/access"
[[ -z "${WEB_LOGS_ERROR_DIR+x}" ]]   && declare -gr WEB_LOGS_ERROR_DIR="webserver/error"

# Default common folders
[[ -z "${CLONE_BASE_DIR+x}" ]]  && declare -gr CLONE_BASE_DIR="tmp-clone"
[[ -z "${BACKUP_DIR+x}" ]]      && declare -gr BACKUP_DIR="backups"

# Default File names
[[ -z "${META_FILE_NAME+x}" ]]  && declare -gr META_FILE_NAME="meta.json"

# ======================
# 🔓 Optional Environment Variables
# ======================

[[ -z "${CLOUDFLARE_API_TOKEN+x}" ]]    && declare -g CLOUDFLARE_API_TOKEN
[[ -z "${UPCLOUD_API_TOKEN+x}" ]]       && declare -g UPCLOUD_API_TOKEN
[[ -z "${DIGITALOCEAN_API_TOKEN+x}" ]] && declare -g DIGITALOCEAN_API_TOKEN
[[ -z "${GITHUB_API_TOKEN+x}" ]]        && declare -g GITHUB_API_TOKEN
[[ -z "${SERVER_IPv4+x}" ]]             && declare -g SERVER_IPv4
[[ -z "${SERVER_IPv6+x}" ]]             && declare -g SERVER_IPv6
[[ -z "${CLOUD_PROVIDER+x}" ]]          && declare -g CLOUD_PROVIDER
