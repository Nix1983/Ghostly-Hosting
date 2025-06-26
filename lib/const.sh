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
