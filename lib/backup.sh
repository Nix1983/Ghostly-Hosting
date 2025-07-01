#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/print.sh
source ./lib/common.sh

restore_app_backup() {
  local exec_dir="$1"
  local service_name="$2"
  local backup_dir="$exec_dir/$BACKUP_DIR"

  local subdomain parent domain
  subdomain=$(basename "$exec_dir")
  parent=$(basename "$(dirname "$exec_dir")")

  if [[ "$subdomain" == "root" ]]; then
    domain="$parent"
  else
    domain="$subdomain.$parent"
  fi
  domain="${domain//-/.}"

  if [[ ! -d "$backup_dir" ]]; then
    echo -e "\n❌ \e[31mBackup folder not found at:\e[2m $backup_dir\e[0m"
    return 1
  fi

  mapfile -t meta_files < <(find "$backup_dir" -maxdepth 1 -type f -name "meta-*.json" | sort -r)
  if (( ${#meta_files[@]} == 0 )); then
    echo -e "\n❌ \e[31mNo backup metadata files found.\e[0m"
    return 1
  fi

  local options=()
  local -A map_idx
  local i=1

  for file in "${meta_files[@]}"; do
    local filename timestamp datetime ref commit
    filename=$(basename "$file")
    timestamp="${filename//meta-/}"
    timestamp="${timestamp//.json/}"
    timestamp="${timestamp//T/}"
    datetime=$(date -d "${timestamp:0:8} ${timestamp:8:2}:${timestamp:10:2}:${timestamp:12:2}" "+%H:%M:%S %d-%m-%Y" 2>/dev/null || echo "$timestamp")
    ref=$(jq -r '.ref_name // "-" ' "$file")
    commit=$(jq -r '.commit // ""' "$file")
    options+=("$(printf " %2d) 🕒 %s  |  🌿 %s \e[2m(%s)\e[0m" "$i" "$datetime" "$ref" "${commit:0:7}")")
    map_idx["$i"]="$file"
    ((i++))
  done

  while true; do
    clear
    echo -e "\n♻️   Restore App from Backup | 🌐 \e[36m$domain\e[0m"
    echo -e "─────────────────────────────────────────────────────────────"
    printf "%s\n" "${options[@]}"
    echo -e "\n  $(print_back_to_menu)"
    echo "─────────────────────────────────────────────────────────────"
    print_select_prompt $((i - 1))
    read -r choice
    echo ""

    if [[ "$choice" =~ ^[Qq]$ ]]; then return 9; fi

    if [[ "$choice" =~ ^[0-9]+$ && -n "${map_idx[$choice]}" ]]; then
      local meta_file_restore="${map_idx[$choice]}"
      echo -e "\n✅ Selected Backup: \e[36m$meta_file_restore\e[0m"

      local owner repo ref_type ref_name commit
      owner=$(jq -r '.repo_owner // empty' "$meta_file_restore")
      repo=$(jq -r '.repo_name // empty' "$meta_file_restore")
      ref_type=$(jq -r '.ref_type // empty' "$meta_file_restore")
      ref_name=$(jq -r '.ref_name // empty' "$meta_file_restore")
      commit=$(jq -r '.commit // empty' "$meta_file_restore")

      if [[ -z "$owner" || -z "$repo" || -z "$ref_type" || -z "$ref_name" || -z "$commit" ]]; then
        echo -e "❌ \e[31mInvalid or incomplete metadata in: $meta_file_restore\e[0m"
        return 1
      fi

      export SELECTED_REPO_OWNER="$owner"
      export SELECTED_REPO_NAME="$repo"
      export SELECTED_REF_TYPE="$ref_type"
      export SELECTED_REF_NAME="$ref_name"

      echo -e "\n📦 Restoring from:\n - Repo: \e[36m$owner/$repo\e[0m\n - Ref:  \e[36m$ref_type → $ref_name\e[0m\n - Commit: \e[2m$commit\e[0m"

      clone_repository "$commit" || return 1
      _redeploy_blazor_app "$exec_dir" "$service_name" "$commit"
      return $?
    else
      print_invalid_selection
      sleep 1
    fi
  done
}