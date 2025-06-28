#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/print.sh
source ./lib/dotnet.sh

# Global variables to be accessed in other modules
declare -g SELECTED_REPO_NAME=""
declare -g SELECTED_REPO_OWNER=""
declare -g TMP_CLONE_DIR=""

remove_git() {
  apt-get purge -y git git-core git-man git-all git-doc >/dev/null 2>&1

  rm -f /usr/bin/git /usr/local/bin/git /snap/bin/git
  rm -rf /etc/gitconfig /usr/share/doc/git* /usr/share/man/man1/git* /var/lib/snapd/snap/git*

  echo -e "🗑️ Removed Git and all related files."
}

resolve_github_user_from_token() {
  if [[ -n "$GITHUB_API_TOKEN" ]]; then
    local user_response
    user_response=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" "$GITHUB_API_BASE/user")
    GITHUB_API_USER=$(echo "$user_response" | jq -r '.login // empty')
  fi
}

check_github_env_vars() {
  local missing=()
  [[ -z "$GITHUB_API_TOKEN" ]] && missing+=("GITHUB_API_TOKEN")
  [[ -z "$GITHUB_API_BASE" ]]  && missing+=("GITHUB_API_BASE")

  if (( ${#missing[@]} > 0 )); then
    echo -e "\n❌ \e[1;31mMissing GitHub environment variables:\e[0m"
    for var in "${missing[@]}"; do
      echo -e "   ⛔ \e[33m$var\e[0m"
    done
    echo -e "\n💡 Please ensure these are set in your .env file"
    return 1
  fi

  resolve_github_user_from_token
  if [[ -z "$GITHUB_API_USER" ]]; then
    echo -e "\n❌ \e[31mInvalid GitHub token – could not determine username.\e[0m"
    return 1
  fi

  return 0
}

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

clone_repository() {
  local commit_hash="${1:-}"

  TMP_CLONE_DIR="/$CLONE_BASE_DIR/${SELECTED_REPO_NAME}"
  export TMP_CLONE_DIR

  if [[ -d "$TMP_CLONE_DIR" ]]; then
    echo -e "\n♻️ Removing existing clone directory: \e[2m$TMP_CLONE_DIR\e[0m"
    rm -rf "$TMP_CLONE_DIR"
  fi
  echo -e "\n📦 Cloning GitHub repo: \e[36m$SELECTED_REPO_OWNER/$SELECTED_REPO_NAME\e[0m"
  local clone_url="https://${SELECTED_REPO_OWNER}:${GITHUB_API_TOKEN}@github.com/${SELECTED_REPO_OWNER}/${SELECTED_REPO_NAME}.git"

  if [[ -n "$commit_hash" ]]; then
    if ! GIT_ASKPASS=true git clone -q "$clone_url" "$TMP_CLONE_DIR" > /dev/null 2>&1; then
      echo -e "\n❌ \e[31mFailed to clone repository.\e[0m"
      sleep 5
      return 1
    fi
    if ! git -C "$TMP_CLONE_DIR" checkout -q "$commit_hash" > /dev/null 2>&1; then
      echo -e "\n❌ \e[31mFailed to checkout commit: $commit_hash\e[0m"
      sleep 5
      return 1
    fi
  elif [[ "$SELECTED_REF_TYPE" == "branch" || "$SELECTED_REF_TYPE" == "tag" ]]; then
    if ! GIT_ASKPASS=true git clone -q --branch "$SELECTED_REF_NAME" --single-branch "$clone_url" "$TMP_CLONE_DIR" > /dev/null 2>&1; then
      echo -e "\n❌ \e[31mFailed to clone selected ref: $SELECTED_REF_NAME\e[0m"
      sleep 5
      return 1
    fi
  else
    if ! GIT_ASKPASS=true git clone -q "$clone_url" "$TMP_CLONE_DIR" > /dev/null 2>&1; then
      echo -e "\n❌ \e[31mFailed to clone main repository.\e[0m"
      sleep 5
      return 1
    fi
  fi

  local -a success_modules=()
  local -a failed_modules=()

  echo -e "\n🔄 Rewriting all submodule URLs for token access..."
  find "$TMP_CLONE_DIR" -type f -name ".gitmodules" | while read -r modfile; do
    local moddir
    moddir=$(dirname "$modfile")
    sed -i -E "s#https://github.com/#https://${SELECTED_REPO_OWNER}:${GITHUB_API_TOKEN}@github.com/#g" "$modfile" 2>/dev/null
    git -C "$moddir" submodule sync >/dev/null 2>&1
  done

  echo -e "🔽 Initializing submodules...\n"
  if ! git -C "$TMP_CLONE_DIR" submodule update --init --recursive --quiet; then
    while IFS= read -r path; do
      [[ -d "$TMP_CLONE_DIR/$path" ]] && success_modules+=("$path") || failed_modules+=("$path")
    done < <(git -C "$TMP_CLONE_DIR" config --file "$TMP_CLONE_DIR/.gitmodules" --get-regexp path | awk '{print $2}')
  else
    while IFS= read -r path; do
      success_modules+=("$path")
    done < <(git -C "$TMP_CLONE_DIR" config --file "$TMP_CLONE_DIR/.gitmodules" --get-regexp path | awk '{print $2}')
  fi

  (( ${#success_modules[@]} > 0 )) && {
    echo -e "✅ \e[1mSuccessfully cloned submodules:\e[0m"
    for m in "${success_modules[@]}"; do echo -e "   ✔️  \e[36m$m\e[0m"; done
  }

  (( ${#failed_modules[@]} > 0 )) && {
    echo -e "\n❌ \e[1;31mFailed to clone submodules:\e[0m"
    for m in "${failed_modules[@]}"; do echo -e "   ❌ \e[33m$m\e[0m"; done
    return 1
  }

  echo -e "\n✅ Repo cloned to \e[2m$TMP_CLONE_DIR\e[0m (including all submodules)"

  if [[ -n "$commit_hash" ]]; then
    echo -e "🔖 \e[1mChecked out specific commit:\e[0m \e[36m$commit_hash\e[0m"
  fi

  if [[ -d "$TMP_CLONE_DIR/.git" ]]; then
    SELECTED_COMMIT_HASH=$(git -C "$TMP_CLONE_DIR" rev-parse HEAD 2>/dev/null)
    export SELECTED_COMMIT_HASH
  fi

  return 0
}

select_github_repository() {
  if ! check_github_env_vars; then return 1; fi
  if ! load_github_repositories; then return 1; fi

  if (( REPO_TOTAL == 0 )); then
    echo -e "\n❌ No repositories found for user: \e[36m$GITHUB_API_USER\e[0m"
    return 1
  fi

  local choice i index1 index2 name1 name2

  while true; do
    echo -e "\n🐙 \e[1;34mSelect a GitHub Repository\033[0m – for: \e[36m$GITHUB_API_USER\e[0m \e[2m($REPO_TOTAL repositories)\e[0m"
    print_line

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

    read_menu_choice "$REPO_TOTAL"
    [[ "$REPLY" =~ ^[Qq]$ ]] && return 1

  
    local selected_repo_json="${REPOS[$((REPLY - 1))]}"
    SELECTED_REPO_NAME=$(echo "$selected_repo_json" | jq -r '.name')
    SELECTED_REPO_OWNER=$(echo "$selected_repo_json" | jq -r '.owner.login')

    echo -e "\n✅ Selected repository: \e[36m$SELECTED_REPO_OWNER/$SELECTED_REPO_NAME\e[0m"
    return 0
  done
}

select_branch_or_tag() {
  local repo="$SELECTED_REPO_NAME"
  local owner="$SELECTED_REPO_OWNER"

  local branches_json tags_json
  branches_json=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
    "$GITHUB_API_BASE/repos/$owner/$repo/branches")
  tags_json=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
    "$GITHUB_API_BASE/repos/$owner/$repo/tags")

  local -A option_map
  local -a all_options branches sorted_branches
  local index=1

  mapfile -t branches < <(echo "$branches_json" | jq -r '.[].name')
  for branch in "${branches[@]}"; do
    [[ "$branch" == "master" ]] && sorted_branches=("master")
  done
  for branch in "${branches[@]}"; do
    [[ "$branch" != "master" ]] && sorted_branches+=("$branch")
  done

  for branch in "${sorted_branches[@]}"; do
    option_map[$index]="branch:$branch"
    all_options+=("$index|🌿 Branch:|$branch")
    ((index++))
  done

  mapfile -t tags < <(echo "$tags_json" | jq -r '.[].name')
  for tag in "${tags[@]}"; do
    option_map[$index]="tag:$tag"
    all_options+=("$index|🏷️ Tag:   |$tag")
    ((index++))
  done

  local option_count="${#all_options[@]}"
  if [[ "$option_count" -eq 1 ]]; then
    local selected_entry="${option_map[1]}"
    IFS=":" read -r type name <<< "$selected_entry"

    local type_label
    case "$type" in
      branch) type_label="Branch" ;;
      tag) type_label="Tag" ;;
      *) type_label="Reference" ;;
    esac

    SELECTED_REF_TYPE="$type"
    SELECTED_REF_NAME="$name"
    export SELECTED_REF_TYPE SELECTED_REF_NAME

    echo -e "\n✅ Only one $type_label available – automatically selected: \e[36m$name\e[0m"
    return 0
  fi

  echo -e "\n🌀 \e[1mAvailable Branches / Releases / Tags:\e[0m"
  print_line

  local i=0
  while [[ $i -lt $option_count ]]; do
    local left right
    IFS="|" read -r idx1 label1 val1 <<< "${all_options[$i]}"
    left=$(printf " %2d) %s \e[36m%-30s\e[0m" "$idx1" "$label1" "$val1")

    if (( i + 1 < option_count )); then
      IFS="|" read -r idx2 label2 val2 <<< "${all_options[$((i + 1))]}"
      right=$(printf " %2d) %s \e[36m%-30s\e[0m" "$idx2" "$label2" "$val2")
      printf "%s   %s\n" "$left" "$right"
    else
      printf "%s\n" "$left"
    fi
    ((i += 2))
  done

  read_menu_choice $((index - 1))
  [[ "$REPLY" =~ ^[Qq]$ ]] && return 1

  IFS=":" read -r type name <<< "${option_map[$REPLY]}"
  SELECTED_REF_TYPE="$type"
  SELECTED_REF_NAME="$name"
  export SELECTED_REF_TYPE SELECTED_REF_NAME

  echo -e "\n✅ Selected $type: \e[36m$name\e[0m"
  return 0
}

save_repo_metadata() {
  local target_dir="$1"
  local meta_file="$target_dir/$META_FILE_NAME"

  if [[ -z "$SELECTED_REPO_OWNER" || -z "$SELECTED_REPO_NAME" || -z "$SELECTED_REF_TYPE" || -z "$SELECTED_REF_NAME" ]]; then
    echo -e "❌ \e[31mCannot save metadata – required info missing.\e[0m"
    return 1
  fi

  local commit_to_save="$SELECTED_COMMIT_HASH"

  if [[ -z "$commit_to_save" && -d "$TMP_CLONE_DIR/.git" ]]; then
    commit_to_save=$(git -C "$TMP_CLONE_DIR" rev-parse HEAD 2>/dev/null)
    export SELECTED_COMMIT_HASH="$commit_to_save"
  fi

  if [[ -z "$commit_to_save" ]]; then
    commit_to_save=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
      "$GITHUB_API_BASE/repos/$SELECTED_REPO_OWNER/$SELECTED_REPO_NAME/commits/$SELECTED_REF_NAME" |
      jq -r '.sha // empty')
    export SELECTED_COMMIT_HASH="$commit_to_save"
  fi

  if [[ -z "$commit_to_save" ]]; then
    echo -e "⚠️ \e[33mCould not determine commit hash – continuing without.\e[0m"
  fi

  jq -n --arg owner "$SELECTED_REPO_OWNER" \
        --arg name "$SELECTED_REPO_NAME" \
        --arg type "$SELECTED_REF_TYPE" \
        --arg ref "$SELECTED_REF_NAME" \
        --arg sha "$commit_to_save" \
        '{
          repo_owner: $owner,
          repo_name: $name,
          ref_type: $type,
          ref_name: $ref,
          commit: $sha
        }' > "$meta_file"

  echo -e "📝 Metadata written to \e[2m$meta_file\e[0m"
}