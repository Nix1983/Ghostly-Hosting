#!/bin/bash
# shellcheck disable=SC1091

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/print.sh"
source "$SCRIPT_DIR/common.sh"

get_repo_name_from_meta() {
  local file="$1"
  local maxlen="$2"
  local repo_name

  [[ -f "$file" ]] || { echo "–"; return 1; }

  repo_name=$(jq -r '.repo_name // "–"' "$file")

  if [[ "$repo_name" != "–" && -n "$maxlen" ]]; then
    if [[ "$maxlen" =~ ^[0-9]+$ && "$maxlen" -ge 4 ]]; then
      if [[ ${#repo_name} -gt "$maxlen" ]]; then
        local cutoff=$((maxlen - 3))
        repo_name="${repo_name:0:cutoff}..."
      fi
    else
      echo "❌ Invalid max length parameter (must be ≥ 4)." >&2
      return 1
    fi
  fi

  echo "$repo_name"
}

get_repo_owner_from_meta() {
  local file="$1"
  [[ -f "$file" ]] || { echo "–"; return 1; }
  jq -r '.repo_owner // "–"' "$file"
}

get_ref_type_from_meta() {
  local file="$1"
  [[ -f "$file" ]] || { echo "–"; return 1; }
  jq -r '.ref_type // "–"' "$file"
}

get_ref_name_from_meta() {
  local file="$1"
  [[ -f "$file" ]] || { echo "–"; return 1; }
  jq -r '.ref_name // "–"' "$file"
}

get_commit_from_meta() {
  local file="$1"
  [[ -f "$file" ]] || { echo "–"; return 1; }
  jq -r '.commit // "–"' "$file"
}

backup_app_metadata() {
  local exec_dir="$1"
  local meta_file="$exec_dir/$META_FILE_NAME"
  local backup_dir="$exec_dir/$BACKUP_DIR"

  mkdir -p "$backup_dir"

  if [[ ! -f "$meta_file" ]]; then
    echo -e "❌ \e[31m$META_FILE_NAME not found – cannot back up.\e[0m"
    return 1
  fi

  local commit
  commit=$(jq -r '.commit // empty' "$meta_file")
  if [[ -z "$commit" ]]; then
    echo -e "❌ \e[31mCommit hash not found in $META_FILE_NAME – aborting.\e[0m"
    return 1
  fi

  local timestamp
  timestamp=$(date +"%Y%m%dT%H%M%S")
  local new_backup="$backup_dir/meta-${timestamp}.json"

  if cp "$meta_file" "$new_backup"; then
    echo "✅ Backup saved to $new_backup"
  else
    echo -e "❌ \e[31mFailed to copy $META_FILE_NAME\e[0m"
    return 1
  fi

  mapfile -t matching_files < <(
    find "$backup_dir" -maxdepth 1 -type f -name "meta-*.json" \
    -exec jq -r '.commit // empty' {} \; -exec printf "%s\n" {} \; |
    paste - - | awk -v hash="$commit" '$1 == hash {print $2}'
  )

  if (( ${#matching_files[@]} > 1 )); then
    mapfile -t sorted < <(printf "%s\n" "${matching_files[@]}" | sort -r)
    local keep="${sorted[0]}"
    echo -e "\n🧹 Found multiple backups for commit \e[36m$commit\e[0m"
    echo -e "   ➕ Keeping latest: \e[2m$keep\e[0m"

    for f in "${sorted[@]:1}"; do
      rm -f "$f"
      echo -e "   ❌ Removed old duplicate: \e[2m$f\e[0m"
    done
  fi

  return 0
}

restore_app_meta_data() {
  local service_name="$1"
  local subdomain parent domain backup_dir exec_dir

  exec_dir=$(resolve_exec_dir_from_service_name "$service_name")
  subdomain=$(basename "$exec_dir")
  parent=$(basename "$(dirname "$exec_dir")")

  if [[ "$subdomain" == "root" ]]; then
    domain="$parent"
  else
    domain="$subdomain.$parent"
  fi
  domain="${domain//-/.}"

  backup_dir=$(resolve_backup_folder_from_service_name "$service_name")
  mkdir -p "$backup_dir"
  if [[ ! -d "$backup_dir" ]]; then
    echo -e "\n❌ \e[31mBackup folder not found at:\e[2m $backup_dir\e[0m"
    return 1
  fi

  mapfile -t meta_files < <(find "$backup_dir" -maxdepth 1 -type f -name "meta-*.json" | sort -r)
  if (( ${#meta_files[@]} == 0 )); then
    echo -e "\n🗃️ \e[33mNo backup metadata found yet.\e[0m"
    echo -e "   A backup will be created automatically on the first app update."
    echo -e "📂 Target folder: \e[2m$backup_dir\e[0m"
    print_press_any_key
    return 1
  fi

  local current_meta_file="$exec_dir/$META_FILE_NAME"
  local current_commit=""
  if [[ -f "$current_meta_file" ]]; then
    current_commit=$(get_commit_from_meta "$current_meta_file")
  fi

  local options=()
  local -A map_idx
  local i=1

  for file in "${meta_files[@]}"; do
    local filename timestamp datetime ref commit

    commit=$(get_commit_from_meta "$file")
    [[ "$commit" == "$current_commit" ]] && continue  # identisches Build → überspringen

    filename=$(basename "$file")
    timestamp="${filename//meta-/}"
    timestamp="${timestamp//.json/}"
    timestamp="${timestamp//T/}"
    datetime=$(date -d "${timestamp:0:8} ${timestamp:8:2}:${timestamp:10:2}:${timestamp:12:2}" "+%H:%M:%S %d-%m-%Y" 2>/dev/null || echo "$timestamp")
    ref=$(get_ref_name_from_meta "$file")

    options+=("$(printf " %2d) 🕒 %s  |  🌿 %s \e[2m(%s)\e[0m" "$i" "$datetime" "$ref" "${commit:0:7}")")
    map_idx["$i"]="$file"
    ((i++))
  done

  if (( ${#options[@]} == 0 )); then
    echo -e "\n🛑 \e[33mNo other backups available (only same commit as current).\e[0m"
    return 1
  fi

  while true; do
    clear
    echo -e "\n♻️   Restore App from Backup | 🌐 \e[36m$domain\e[0m"
    echo -e "─────────────────────────────────────────────────────────────"
    printf "%s\n" "${options[@]}"
    echo -e "\n  $(print_back_to_menu)"
    read_menu_choice $((i - 1))

    if [[ "$REPLY" =~ ^[Qq]$ ]]; then return 9; fi

    if [[ "$REPLY" =~ ^[0-9]+$ && -n "${map_idx[$REPLY]}" ]]; then
      local meta_file_restore="${map_idx[$REPLY]}"

      echo -e "\n✅ Selected Backup: \e[36m$meta_file_restore\e[0m"

      export SELECTED_REPO_OWNER
      export SELECTED_REPO_NAME
      export SELECTED_REF_TYPE
      export SELECTED_REF_NAME
      export SELECTED_COMMIT

      SELECTED_REPO_OWNER=$(get_repo_owner_from_meta "$meta_file_restore")
      SELECTED_REPO_NAME=$(get_repo_name_from_meta "$meta_file_restore")
      SELECTED_REF_TYPE=$(get_ref_type_from_meta "$meta_file_restore")
      SELECTED_REF_NAME=$(get_ref_name_from_meta "$meta_file_restore")
      SELECTED_COMMIT=$(get_commit_from_meta "$meta_file_restore")

      if [[ "$SELECTED_REPO_OWNER" == "–" || "$SELECTED_REPO_NAME" == "–" || "$SELECTED_REF_TYPE" == "–" || "$SELECTED_REF_NAME" == "–" || "$SELECTED_COMMIT" == "–" ]]; then
        echo -e "❌ \e[31mInvalid or incomplete metadata in: $meta_file_restore\e[0m"
        return 1
      fi

      return 0
    else
      print_invalid_selection
      sleep 1
    fi
  done
}
