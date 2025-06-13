#!/bin/bash
# shellcheck disable=SC1091
set -e

source ./lib/common.sh
source ./lib/dotnet.sh
source ./lib/print.sh

check_github_env() {
  local missing=()

  [[ -z "$GITHUB_API_TOKEN" ]] && missing+=("GITHUB_API_TOKEN")
  [[ -z "$GITHUB_API_USER" ]]  && missing+=("GITHUB_API_USER")
  [[ -z "$GITHUB_API_BASE" ]]  && missing+=("GITHUB_API_BASE")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo -e "\n❌ \e[1;31mMissing GitHub environment variables:\e[0m"
    for var in "${missing[@]}"; do
      echo -e "   ⛔ \e[33m$var\e[0m"
    done
    echo -e "\n💡 Please ensure these are set in your .env file and reload with 'load_env'."
    return 1
  fi
}

deploy_from_github_repo() {
  local owner="$1"
  local repo="$2"
  local project_type sdk_type sdk_version tmp_dir publish_dir

  echo -e "\n📦 \e[1mCloning GitHub repo:\e[0m $owner/$repo"

  tmp_dir="/tmp/deploy-$repo"
  rm -rf "$tmp_dir"

  # Clone with authentication (no log output)
  local clone_url="https://${GITHUB_API_USER}:${GITHUB_API_TOKEN}@github.com/${owner}/${repo}.git"
  if ! GIT_ASKPASS=true git clone -q "$clone_url" "$tmp_dir" 2>/dev/null; then
    echo "❌ Failed to clone repository. Please check your token or access rights."
    return 1
  fi

  echo "✅ Repo cloned to $tmp_dir"

  # Detect .csproj file
  local csproj
  csproj=$(find "$tmp_dir" -name '*.csproj' | head -n1)
  if [[ -z "$csproj" ]]; then
    echo "❌ No .csproj file found in the repository."
    return 1
  fi

  sdk_type=$(grep -oP '(?<=<Project Sdk=")[^"]+' "$csproj")
  sdk_version=$(grep -oP '(?<=<TargetFramework>)[^<]+' "$csproj" | head -n1)

  case "$sdk_type" in
    Microsoft.NET.Sdk.Web)
      project_type="ASP.NET Core or Blazor Server"
      ;;
    Microsoft.NET.Sdk.BlazorWebAssembly)
      project_type="Blazor WebAssembly (WASM)"
      ;;
    *)
      echo "❌ Unsupported SDK type: $sdk_type"
      return 1
      ;;
  esac

  echo -e "\n🧪 \e[1mProject Detected:\e[0m"
  echo "────────────────────────────────────────────"
  echo "🔧 SDK:       $sdk_type"
  echo "🎯 Framework: $sdk_version"
  echo "📦 Type:      $project_type"

  echo -e "\n🔍 Checking required .NET SDK..."
  if ! install_dotnet_version "$sdk_version"; then
    echo "❌ Aborting due to SDK installation failure."
    return 1
  fi

  if ! [[ -x /opt/dotnet/dotnet ]]; then
    echo "❌ .NET binary not found after installation. Aborting."
    return 1
  fi

  echo -e "\n🚀 Publishing project..."
  publish_dir="/tmp/publish-$repo"
  rm -rf "$publish_dir"
  if ! /opt/dotnet/dotnet publish "$csproj" -c Release -o "$publish_dir" > /dev/null 2>&1; then
    echo "❌ dotnet publish failed. Please check project build state."
    return 1
  fi

  echo -e "\n✅ Project successfully published to: \e[36m$publish_dir\e[0m"
}

select_github_repository() {
  load_env
  if ! check_github_env; then return 1; fi

  clear
  local response total i index1 index2 name1 name2
  response=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
    "$GITHUB_API_BASE/user/repos?per_page=100&affiliation=owner")

  mapfile -t repos < <(echo "$response" | jq -c '.[]')
  total=${#repos[@]}
  ((total == 0)) && printf "❌ No repositories found.\n" && return 1

  while true; do
    clear
    echo -e "\n🐙 \e[1;34mSelect a GitHub Repository\033[0m – for: \e[36m$GITHUB_API_USER\e[0m"
    echo "────────────────────────────────────────────────────────────"

    i=0
    while [[ $i -lt $total ]]; do
      index1=$((i+1))
      name1=$(echo "${repos[$i]}" | jq -r '.name')

      index2=$((i+2))
      if [[ $index2 -le $total ]]; then
        name2=$(echo "${repos[$i+1]}" | jq -r '.name')
        printf "%2d) 📁 \033[36m%-35s\033[0m    %2d) 📁 \033[36m%-35s\033[0m\n" "$index1" "$name1" "$index2" "$name2"
      else
        printf "%2d) 📁 \033[36m%-35s\033[0m\n" "$index1" "$name1"
      fi
      ((i+=2))
    done

    echo -e "\n─────────────────────────────────────────────────────────────"
    print_select_prompt "$total"
    read -r choice
    [[ "$choice" =~ ^[Qq]$ ]] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > total )); then
      print_invalid_selection
      sleep 1
      continue
    fi

    local repo repo_name repo_owner
    repo="${repos[$((choice-1))]}"
    repo_name=$(echo "$repo" | jq -r '.name')
    repo_owner=$(echo "$repo" | jq -r '.owner.login')

    if deploy_from_github_repo "$repo_owner" "$repo_name"; then
      local publish_dir="/tmp/publish-$repo_name"
      if dll_name=$(find_dotnet_executable_dll "$publish_dir"); then
        echo -e "\n🔍 \e[1mExecutable DLL found:\e[0m \e[36m$dll_name\e[0m"
        echo "📂 Located in: $publish_dir"
      else
        echo "⚠️  Could not determine executable DLL."
      fi
    else
      echo "❌ Deployment failed."
    fi

    print_press_any_key
    read -rsn1
    return 0
  done
}

