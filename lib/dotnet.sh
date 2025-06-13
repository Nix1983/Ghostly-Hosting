#!/bin/bash
# shellcheck disable=SC1091
set -e

install_dotnet_version() {
  local version="$1"
  local install_dir="/opt/dotnet"

  # Normalize netX.Y to SDK version (e.g. net9.0 → 9.0.100)
  local sdk_version=""
  if [[ "$version" =~ ^net([0-9]+)\.([0-9]+)$ ]]; then
    sdk_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.100"
  else
    sdk_version="$version"
  fi

  if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^${sdk_version%.*}"; then
    echo "✅ .NET SDK ${sdk_version%.*} is already installed."
    return 0
  fi

  echo "⬇️  Installing .NET SDK $sdk_version..."
  curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  chmod +x /tmp/dotnet-install.sh

  if ! /tmp/dotnet-install.sh --version "$sdk_version" --install-dir "$install_dir" --no-path > /dev/null 2>&1; then
    echo "❌ Failed to install .NET SDK version: $sdk_version"
    return 1
  fi

  if [[ ! -x "$install_dir/dotnet" ]]; then
    echo "❌ Installation failed – dotnet binary missing in $install_dir"
    return 1
  fi

  echo "✅ .NET SDK $sdk_version installed to $install_dir"
}

delete_dotnet_version() {
  local version="$1"
  local install_dir="/opt/dotnet/sdk"

  mapfile -t matching_versions < <(find "$install_dir" -maxdepth 1 -type d -printf "%f\n" | grep -E "^$version")
  if (( ${#matching_versions[@]} == 0 )); then
    echo "⚠️  No SDKs matching version $version found."
    return 1
  fi

  echo ""
  echo "🗑️  The following .NET SDK versions will be removed:"
  echo "──────────────────────────────────────────────────────"
  for ver in "${matching_versions[@]}"; do
    printf " • .NET %s\n" "$ver"
  done
  echo "──────────────────────────────────────────────────────"

  for ver in "${matching_versions[@]}"; do
    rm -rf -- "$install_dir/${ver:?}"
  done

  echo "✅ .NET SDK $version removed successfully."
}

check_apps_using_sdk() {
  local version="$1"
  local root="/var/www"
  grep -r "\"$version\"" "$root" 2>/dev/null | grep global.json | cut -d: -f1 | uniq
}

find_dotnet_executable_dll() {
  local publish_dir="$1"

  if [[ -z "$publish_dir" || ! -d "$publish_dir" ]]; then
    echo "❌ Invalid or missing publish directory: $publish_dir" >&2
    return 1
  fi

  local dll
  dll=$(find "$publish_dir" -maxdepth 1 -type f -name '*.dll' | while read -r f; do
    local base="${f%.dll}"
    if [[ -f "$base.runtimeconfig.json" ]]; then
      basename "$f"
      return 0
    fi
  done)

  if [[ -z "$dll" ]]; then
    echo "❌ No executable DLL found in $publish_dir" >&2
    return 1
  fi

  echo "$dll"
  return 0
}



show_dotnet_version_menu() {
  local install_dir="/opt/dotnet"
  local versions=("5.0" "6.0" "7.0" "8.0" "9.0")

  while true; do
    clear
    echo -e "\n🧰 \e[1;34m.NET SDK Management\e[0m"
    echo "═════════════════════════════════════════════════════════════════════════════════"

    for i in "${!versions[@]}"; do
      local ver="${versions[$i]}"
      local status="➕  Not installed"
      local usage="0"
      local disk="–       "
      local realver="–"

      if [[ -x "$install_dir/dotnet" ]] && "$install_dir/dotnet" --list-sdks | grep -q "^$ver"; then
        status="✅  Installed"
        realver=$("$install_dir/dotnet" --list-sdks | grep "^$ver" | awk '{print $1}')
        usage=$(check_apps_using_sdk "$ver" | wc -l)
        disk=$(du -sh "$install_dir/sdk"/* 2>/dev/null | grep "$ver" | awk '{sum+=$1} END{print sum " MB"}')
      fi

      printf " %d) .NET %-4s │ %-20s │ 📦 Apps: %-4s │ 💾 Size: %-8s │ 🔢 Version: %-15s\n" \
        $((i + 1)) "$ver" "$status" "$usage" "$disk" "$realver"
    done

    echo -e "\n d) 🗑️  Delete version     q) 🔙 Back to main menu"
    echo "───────────────────────────────────────────────────────────────────────────────"
    printf "Install version [1–%d], delete [d], or quit [q]: " "${#versions[@]}"
    IFS= read -rsn1 choice
    echo ""

    case "$choice" in
      q|Q) return ;;
      d|D)
        while true; do
          clear
          echo -e "\n🗑️  \e[1;31mDelete installed .NET SDK\e[0m"
          echo "═════════════════════════════════════════════════════════════"
          local index=1
          declare -A deletable
          for dir in "$install_dir/sdk"/*; do
            [[ -d "$dir" ]] || continue
            local name
            name=$(basename "$dir")
            local basever=${name%%.*}.${name#*.}
            printf " %d) .NET %s\n" "$index" "$name"
            deletable[$index]="$basever"
            ((index++))
          done

          if [[ "${#deletable[@]}" -eq 0 ]]; then
            echo "⚠️  No installed SDKs found."
            read -rsn1 -p $'\nPress any key to return...' _
            break
          fi

          echo -e " q) 🔙 Cancel"
          echo "─────────────────────────────────────────────────────────────"
          printf "Select version number to delete: "
          IFS= read -rsn1 delsel
          echo ""

          if [[ "$delsel" == "q" || "$delsel" == "Q" ]]; then
            break
          elif [[ "$delsel" =~ ^[0-9]+$ ]] && [[ -n "${deletable[$delsel]}" ]]; then
            delete_dotnet_version "${deletable[$delsel]}"
            read -rsn1 -p $'\n✅ Deleted. Press any key to return...' _
            break
          else
            echo "❌ Invalid selection. Returning..."
            sleep 1
            break
          fi
        done
        ;;
      [1-9])
        if (( choice >= 1 && choice <= ${#versions[@]} )); then
          local version="net${versions[$((choice - 1))]}"
          install_dotnet_version "$version"
          read -rsn1 -p $'\n✅ Done. Press any key to return...' _
        fi
        ;;
      *)
        echo "❌ Invalid selection."
        sleep 1
        ;;
    esac
  done
}
