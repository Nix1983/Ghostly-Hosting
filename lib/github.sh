#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh
source ./lib/dotnet.sh

# Default GitHub API base URL
GITHUB_API_BASE="https://api.github.com"

# Global variables to be accessed in other modules
declare -g SELECTED_REPO_NAME=""
declare -g SELECTED_REPO_OWNER=""
declare -g TMP_CLONE_DIR=""

# Resolves the GitHub username from the token using the GitHub API
resolve_github_user_from_token() {
  if [[ -n "$GITHUB_API_TOKEN" ]]; then
    local user_response
    user_response=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" "$GITHUB_API_BASE/user")
    GITHUB_API_USER=$(echo "$user_response" | jq -r '.login // empty')
  fi
}

# Validates required GitHub environment variables and resolves username
check_github_env_vars() {
  local missing=()
  [[ -z "$GITHUB_API_TOKEN" ]] && missing+=("GITHUB_API_TOKEN")
  [[ -z "$GITHUB_API_BASE" ]]  && missing+=("GITHUB_API_BASE")

  if (( ${#missing[@]} > 0 )); then
    echo -e "\n❌ \e[1;31mMissing GitHub environment variables:\e[0m"
    for var in "${missing[@]}"; do
      echo -e "   ⛔ \e[33m$var\e[0m"
    done
    echo -e "\n💡 Please ensure these are set in your .env file and reload with 'load_env'."
    return 1
  fi

  resolve_github_user_from_token
  if [[ -z "$GITHUB_API_USER" ]]; then
    echo -e "\n❌ \e[31mInvalid GitHub token – could not determine username.\e[0m"
    return 1
  fi

  return 0
}

# Loads repositories and fills REPOS array
load_github_repositories() {
  local response
  response=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
    "$GITHUB_API_BASE/user/repos?per_page=100&affiliation=owner")

  if ! echo "$response" | jq -e '.[0]' >/dev/null 2>&1; then
    echo -e "\n❌ \e[31mFailed to load repositories.\e[0m"
    echo -e "🔍 Possible reason: invalid token, rate limit or API error."
    read -r
    return 1
  fi

  mapfile -t REPOS < <(echo "$response" | jq -c '.[]')
  REPO_TOTAL=${#REPOS[@]}
  return 0
}

# Clones the selected GitHub repository into a temporary folder
clone_repository() {
  TMP_CLONE_DIR="/tmp/clone-${SELECTED_REPO_NAME}"
  export TMP_CLONE_DIR

  # Remove existing clone directory if it exists
  if [[ -d "$TMP_CLONE_DIR" ]]; then
    echo -e "\n♻️ Removing existing clone directory: \e[2m$TMP_CLONE_DIR\e[0m"
    rm -rf "$TMP_CLONE_DIR"
  fi

  echo -e "\n📦 Cloning GitHub repo: \e[36m$SELECTED_REPO_OWNER/$SELECTED_REPO_NAME\e[0m"

  local clone_url="https://${SELECTED_REPO_OWNER}:${GITHUB_API_TOKEN}@github.com/${SELECTED_REPO_OWNER}/${SELECTED_REPO_NAME}.git"

  if ! GIT_ASKPASS=true git clone -q "$clone_url" "$TMP_CLONE_DIR"; then
    echo -e "\n❌ \e[31mFailed to clone repository.\e[0m"
    echo -e "🔍 Please check your token, access rights, or repository visibility."
    return 1
  fi

  echo -e "✅ Repo cloned to \e[2m$TMP_CLONE_DIR\e[0m"
  return 0
}

# Displays a list of repositories and lets the user select one
select_github_repository() {
  if ! check_github_env_vars; then return 1; fi
  if ! load_github_repositories; then return 1; fi

  if (( REPO_TOTAL == 0 )); then
    echo -e "\n❌ No repositories found for user: \e[36m$GITHUB_API_USER\e[0m"
    return 1
  fi

  local choice i index1 index2 name1 name2

  while true; do
    clear
    echo -e "\n🐙 \e[1;34mSelect a GitHub Repository\033[0m – for: \e[36m$GITHUB_API_USER\e[0m \e[2m($REPO_TOTAL repositories)\e[0m"
    echo "────────────────────────────────────────────────────────────"

    i=0
    while [[ $i -lt $REPO_TOTAL ]]; do
      index1=$((i + 1))
      name1=$(echo "${REPOS[$i]}" | jq -r '.name')

      index2=$((i + 2))
      if [[ $index2 -le $REPO_TOTAL ]]; then
        name2=$(echo "${REPOS[$i+1]}" | jq -r '.name')
        printf "%2d) 📁 \033[36m%-35s\033[0m    %2d) 📁 \033[36m%-35s\033[0m\n" "$index1" "$name1" "$index2" "$name2"
      else
        printf "%2d) 📁 \033[36m%-35s\033[0m\n" "$index1" "$name1"
      fi
      ((i += 2))
    done

    echo -e "\n─────────────────────────────────────────────────────────────"
    print_select_prompt "$REPO_TOTAL"
    read -r choice
    [[ "$choice" =~ ^[Qq]$ ]] && return 0

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > REPO_TOTAL )); then
      print_invalid_selection
      sleep 1
      continue
    fi

    local selected_repo_json="${REPOS[$((choice - 1))]}"
    SELECTED_REPO_NAME=$(echo "$selected_repo_json" | jq -r '.name')
    SELECTED_REPO_OWNER=$(echo "$selected_repo_json" | jq -r '.owner.login')

    echo -e "\n✅ Selected repository: \e[36m$SELECTED_REPO_OWNER/$SELECTED_REPO_NAME\e[0m"
    return 0
  done
}
