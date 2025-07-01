#!/bin/bash
# shellcheck disable=SC1091
set -e

get_repo_name_from_meta() {
  local dir="$1"
  local maxlen="$2"
  local meta_file repo_name

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "–"
    return 1
  fi

  if [[ -z "$maxlen" || ! "$maxlen" =~ ^[0-9]+$ || "$maxlen" -lt 4 ]]; then
    echo "❌ Invalid or missing max length parameter (must be ≥ 4)." >&2
    return 1
  fi

  meta_file="$dir/$META_FILE_NAME"

  if [[ -f "$meta_file" ]]; then
    repo_name=$(jq -r '.repo_name // "–"' "$meta_file")

    if [[ "$repo_name" != "–" && ${#repo_name} -gt "$maxlen" ]]; then
      local cutoff=$((maxlen - 3))
      repo_name="${repo_name:0:cutoff}..."
    fi

    echo "$repo_name"
  else
    echo "–"
    return 1
  fi
}

get_repo_owner_from_meta() {
  local dir="$1"
  local meta_file repo_owner

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "–"
    return 1
  fi

  meta_file="$dir/$META_FILE_NAME"

  if [[ -f "$meta_file" ]]; then
    repo_owner=$(jq -r '.repo_owner // "–"' "$meta_file")
    echo "$repo_owner"
  else
    echo "–"
    return 1
  fi
}

get_ref_type_from_meta() {
  local dir="$1"
  local meta_file ref_type

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "–"
    return 1
  fi

  meta_file="$dir/$META_FILE_NAME"

  if [[ -f "$meta_file" ]]; then
    ref_type=$(jq -r '.ref_type // "–"' "$meta_file")
    echo "$ref_type"
  else
    echo "–"
    return 1
  fi
}

get_ref_name_from_meta() {
  local dir="$1"
  local meta_file ref_name

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "–"
    return 1
  fi

  meta_file="$dir/$META_FILE_NAME"

  if [[ -f "$meta_file" ]]; then
    ref_name=$(jq -r '.ref_name // "–"' "$meta_file")
    echo "$ref_name"
  else
    echo "–"
    return 1
  fi
}

get_commit_from_meta() {
  local dir="$1"
  local meta_file commit

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "–"
    return 1
  fi

  meta_file="$dir/$META_FILE_NAME"

  if [[ -f "$meta_file" ]]; then
    commit=$(jq -r '.commit // "–"' "$meta_file")
    echo "$commit"
  else
    echo "–"
    return 1
  fi
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
