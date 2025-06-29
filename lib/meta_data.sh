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
