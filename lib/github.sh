#!/bin/bash
# shellcheck disable=SC1091
set -e

# Load environment values
source ./lib/common.sh

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


analyze_dotnet_project() {
  clear
  local owner="$1"
  local repo="$2"

  printf "\n📦 \033[1m.NET Web App Analysis for:\033[0m \033[1;34m%s\033[0m\n" "$repo"
  echo "────────────────────────────────────────────────────────────────────────────"

  local result
  if ! result=$(is_dotnet_web_repo "$owner" "$repo"); then
    IFS="|" read -r reason sdk framework <<< "$result"
    printf "❌ \033[1m%s\033[0m is \033[31mnot a supported web project\033[0m\n" "$repo"

    case "$reason" in
      unsupported)
        printf "⚠️  Project uses unsupported .NET version: \033[33m%s\033[0m\n" "$framework"
        ;;
      not-hostable)
        printf "ℹ️  No Web SDK detected in .csproj, or missing Program.cs\n"
        ;;
      *)
        printf "ℹ️  Reason: %s\n" "$reason"
        ;;
    esac

    printf "\n✅ \033[1mSupported project types:\033[0m\n"
    echo   "────────────────────────────────────────────────────────────"
    printf "   🔹 \033[32mASP.NET Core API\033[0m (SDK: Microsoft.NET.Sdk.Web)\n"
    printf "   🔹 \033[32mBlazor Server\033[0m     (SDK: Microsoft.NET.Sdk.Web)\n"
    printf "   🔹 \033[33mBlazor WebAssembly\033[0m (SDK: Microsoft.NET.Sdk.BlazorWebAssembly)\n"
    printf "   🔸 Supported frameworks: \033[36mnet7.0, net8.0, net9.0\033[0m\n"
    printf "\n↩️  Press any key to return to selection..."
    read -rsn1
    return 1
  else
    IFS="|" read -r type sdk framework <<< "$result"
    printf "✅ \033[1m%s\033[0m is a supported web project\n" "$repo"
    printf "📦 Type:      \033[1;32m%s\033[0m\n" "$type"
    printf "🔧 SDK:       \033[36m%s\033[0m\n" "$sdk"
    printf "🎯 Framework: \033[35m%s\033[0m\n" "$framework"
    return 0
  fi
}


check_github_workflow_valid() {
  local owner="$1"
  local repo="$2"

  printf "\n🛠️  \033[1mGitHub Workflow Check for:\033[0m \033[1;34m%s\033[0m\n" "$repo"
  echo "────────────────────────────────────────────────────────────────────────────"

  local api_url="$GITHUB_API_BASE/repos/$owner/$repo/contents/.github/workflows"
  local response files file_path content

  response=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" "$api_url")

  if ! jq -e 'type == "array"' <<< "$response" > /dev/null 2>&1; then
    printf "❌ No \033[33m.github/workflows/\033[0m folder found.\n"
  else
    mapfile -t files < <(echo "$response" | jq -r '.[].path')
    if [[ ${#files[@]} -eq 0 ]]; then
      printf "❌ No workflow files found in \033[33m.github/workflows/\033[0m\n"
    else
      for file_path in "${files[@]}"; do
        content=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
          "$GITHUB_API_BASE/repos/$owner/$repo/contents/$file_path" \
          | jq -r '.content' | base64 -d 2>/dev/null)

        if grep -q "runs-on: ubuntu" <<< "$content" &&
           grep -q "actions/setup-dotnet" <<< "$content" &&
           grep -E -q "dotnet (build|publish)" <<< "$content"; then
          printf "✅ Valid deployment workflow found: \033[36m%s\033[0m\n" "$file_path"
          return 0
        fi
      done

      printf "❌ No valid deployment workflow found in \033[33m.github/workflows/\033[0m\n"
    fi
  fi

  printf "\n📝 Workflow must meet these requirements:\n"
  echo   "────────────────────────────────────────────────────────────"
  printf "  • 🐧 runs on: \033[32mubuntu-latest\033[0m (or similar Linux runner)\n"
  printf "  • ⚙️ uses: \033[36mactions/setup-dotnet\033[0m\n"
  printf "  • 🚀 runs: \033[33mdotnet build\033[0m or \033[33mdotnet publish\033[0m\n"
  printf "  • 💡 Suggested path: \033[36m.github/workflows/deploy.yml\033[0m\n"

  printf "\n↩️  Press any key to return to selection..."
  read -rsn1
  return 1
}


select_github_repository() {
  load_env
  if ! check_github_env; then return 1; fi
  clear

  while true; do
    clear
    printf "\n🐙 \033[1;34mSelect a GitHub Repository\033[0m – for: \033[36m%s\033[0m\n" "$GITHUB_API_USER"
    echo "────────────────────────────────────────────────────────────────────────────"

    local response total i index1 index2 name1 name2
    response=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
      "$GITHUB_API_BASE/user/repos?per_page=100&affiliation=owner")

    mapfile -t repos < <(echo "$response" | jq -c '.[]')
    total=${#repos[@]}
    ((total == 0)) && printf "❌ No repositories found.\n" && return 1

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

    printf "\n🔢 Total: \033[1m%d\033[0m repositories\n" "$total"
    printf "\n📌 Select a repository [1–%d, q]: " "$total"
    read -r choice

    [[ "$choice" =~ ^[Qq]$ ]] && return 0
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > total )); then
      continue
    fi

    local repo repo_name repo_owner
    repo="${repos[$((choice-1))]}"
    repo_name=$(echo "$repo" | jq -r '.name')
    repo_owner=$(echo "$repo" | jq -r '.owner.login')

    if analyze_dotnet_project "$repo_owner" "$repo_name"; then
      if check_github_workflow_valid "$repo_owner" "$repo_name"; then
        break
      else
        printf "\n↩️  Press any key to return to selection..."
        read -rsn1
        continue
      fi
    else
      continue
    fi

  done
}


is_dotnet_web_repo() {
  local owner="$1"
  local repo="$2"
  local contents sdk_type sdk_version framework files project_type

  contents=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
    "$GITHUB_API_BASE/repos/$owner/$repo/git/trees/HEAD?recursive=1")

  mapfile -t files < <(echo "$contents" | jq -r '.tree[].path')

  for f in "${files[@]}"; do
    if [[ "$f" == *.csproj ]]; then
      local csproj
      csproj=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
        "$GITHUB_API_BASE/repos/$owner/$repo/contents/$f" \
        | jq -r '.content' | base64 -d 2>/dev/null)

      sdk_type=$(grep -oP '(?<=<Project Sdk=")[^"]+' <<< "$csproj")
      framework=$(grep -oP '(?<=<TargetFramework>)[^<]+' <<< "$csproj" | head -n1)

      if [[ "$framework" =~ net[0-9]+ ]]; then
        sdk_version="$framework"
      else
        sdk_version="unknown"
      fi

      if [[ "$sdk_version" =~ net[1-6]\. ]]; then
        echo "unsupported|$sdk_type|$sdk_version"
        return 1
      fi

      case "$sdk_type" in
        Microsoft.NET.Sdk.Web)
          project_type="ASP.NET Core or Blazor Server"
          ;;
        Microsoft.NET.Sdk.BlazorWebAssembly)
          project_type="Blazor WebAssembly (WASM)"
          ;;
        *)
          continue
          ;;
      esac

      # Zusätzliche Analyse von Program.cs (wenn existiert)
      for file in "${files[@]}"; do
        if [[ "$file" == *Program.cs ]]; then
          program_file=$(curl -s -H "Authorization: Bearer $GITHUB_API_TOKEN" \
            "$GITHUB_API_BASE/repos/$owner/$repo/contents/$file" \
            | jq -r '.content' | base64 -d 2>/dev/null)

          if grep -q "AddServerSideBlazor" <<< "$program_file"; then
            project_type="Blazor Server"
          elif grep -q "MapControllers" <<< "$program_file"; then
            project_type="ASP.NET Core API"
          elif grep -q "RootComponents" <<< "$program_file"; then
            project_type="Blazor WebAssembly (WASM)"
          fi
        fi
      done

      echo "$project_type|$sdk_type|$sdk_version"
      return 0
    fi
  done

  echo "not-hostable|unknown|unknown"
  return 1
}








