#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/dotnet.sh
source ./lib/print.sh

check_github_env_vars() {
  local missing=()

  [[ -z "$GITHUB_API_TOKEN" ]] && missing+=("GITHUB_API_TOKEN")
  [[ -z "$GITHUB_API_USER" ]]  && missing+=("GITHUB_API_USER")
  [[ -z "$GITHUB_API_BASE" ]]  && missing+=("GITHUB_API_BASE")

  if (( ${#missing[@]} > 0 )); then
    echo -e "\n❌ \e[1;31mMissing GitHub environment variables:\e[0m"
    for var in "${missing[@]}"; do
      echo -e "   ⛔ \e[33m$var\e[0m"
    done
    echo -e "\n💡 Please ensure these are set in your .env file and reload with 'load_env'."
    return 1
  fi
  return 0
}

load_github_repositories() {
  local response
  response=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
    "$GITHUB_API_BASE/user/repos?per_page=100&affiliation=owner")

  mapfile -t REPOS < <(echo "$response" | jq -c '.[]')
  REPO_TOTAL=${#REPOS[@]}
  return 0
}

# 🧭 Show repo selection menu
select_repo_from_list() {
  local choice i index1 index2 name1 name2

  while true; do
    clear
    echo -e "\n🐙 \e[1;34mSelect a GitHub Repository\033[0m – for: \e[36m$GITHUB_API_USER\e[0m"
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
    [[ "$choice" =~ ^[Qq]$ ]] && return 1
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > REPO_TOTAL )); then
      print_invalid_selection
      sleep 1
      continue
    fi

    SELECTED_REPO_JSON="${REPOS[$((choice - 1))]}"
    SELECTED_REPO_NAME=$(echo "$SELECTED_REPO_JSON" | jq -r '.name')
    SELECTED_REPO_OWNER=$(echo "$SELECTED_REPO_JSON" | jq -r '.owner.login')
    export SELECTED_REPO_NAME SELECTED_REPO_OWNER
    return 0
  done
}

# 🔄 Clone selected GitHub repo into TMP_CLONE_DIR
clone_selected_repo() {
  TMP_CLONE_DIR="/tmp/deploy-${SELECTED_REPO_NAME}"
  export TMP_CLONE_DIR

  rm -rf "$TMP_CLONE_DIR"

  echo -e "\n📦 Cloning GitHub repo: $SELECTED_REPO_OWNER/$SELECTED_REPO_NAME"
  local clone_url="https://${GITHUB_API_USER}:${GITHUB_API_TOKEN}@github.com/${SELECTED_REPO_OWNER}/${SELECTED_REPO_NAME}.git"
  if ! GIT_ASKPASS=true git clone -q "$clone_url" "$TMP_CLONE_DIR"; then
    echo "❌ Failed to clone repository. Please check your access/token."
    return 1
  fi
  echo "✅ Repo cloned to $TMP_CLONE_DIR"
  return 0
}

publish_selected_repo() {
  TMP_PUBLISH_DIR="/tmp/publish-${SELECTED_REPO_NAME}"
  export TMP_PUBLISH_DIR

  rm -rf "$TMP_PUBLISH_DIR"

  local csproj raw_framework
  csproj=$(find "$TMP_CLONE_DIR" -name '*.csproj' | head -n1)
  [[ -z "$csproj" ]] && echo "❌ No .csproj file found." && return 1

  raw_framework=$(grep -oP '(?<=<TargetFramework>)[^<]+' "$csproj" | head -n1)
  DOTNET_Version=$(resolve_dotnet_channel "$raw_framework") || return 1
  export DOTNET_Version

  echo -e "\n🔧 Detected Target Framework: $raw_framework → Channel: $DOTNET_Version"
  install_dotnet_version "$DOTNET_Version" || return 1

  echo -e "\n🚀 Publishing project..."
  if ! /opt/dotnet/dotnet publish "$csproj" -c Release -o "$TMP_PUBLISH_DIR"; then
    echo "❌ Publish failed."
    return 1
  fi
  echo "✅ Published to $TMP_PUBLISH_DIR"
  return 0
}

# 🔍 Find DLL in published folder and export
find_and_set_executable_dll() {
  if dll_name=$(find_dotnet_executable_dll "$TMP_PUBLISH_DIR"); then
    DLL_NAME="$dll_name"
    export DLL_NAME
    echo -e "\n🔍 Executable DLL found: \e[36m$DLL_NAME\e[0m"
    return 0
  else
    echo "⚠️  Could not determine executable DLL."
    return 1
  fi
}

# 🌐 Entry point for full GitHub repo selection + publish
select_github_repository_and_clone() {
  load_env
  check_github_env_vars || return 1
  load_github_repositories

  if (( REPO_TOTAL == 0 )); then
    echo -e "\n❌ No repositories found for user: \e[36m$GITHUB_API_USER\e[0m"
    echo -e "\n↩️  Press any key to return..."
    read -r
    return 1
  fi

  if ! select_repo_from_list; then return 1; fi
  if ! clone_selected_repo; then return 1; fi
  if ! publish_selected_repo; then return 1; fi
  find_and_set_executable_dll || return 1
}
