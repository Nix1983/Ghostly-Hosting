#!/bin/bash
set -e

load_env() {
  # 🔐 Load Cloudflare and UpCloud credentials from .env file
  local ENV_FILE="./.env"

  if [[ -f "$ENV_FILE" ]]; then
    set -o allexport
    # shellcheck disable=SC1091
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +o allexport
  else
    echo "❌ Error: Environment file '$ENV_FILE' not found."
    exit 1
  fi

  # Check required variables
  local missing=0
  for var in CLOUDFLARE_API_TOKEN CLOUDFLARE_API_BASE UPCLOUD_API_USER UPCLOUD_API_PASS UPCLOUD_API_BASE; do
    if [[ -z "${!var}" ]]; then
      echo "❌ Required variable '$var' is missing or empty in .env"
      missing=1
    fi
  done

  if [[ "$missing" -eq 1 ]]; then
    exit 1
  fi
}

is_valid_ipv4() {
  local ip=$1
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

  IFS='.' read -r -a octets <<< "$ip"
  for octet in "${octets[@]}"; do
    ((octet >= 0 && octet <= 255)) || return 1
  done

  return 0
} 

get_server_ip() {
  local silent_mode=false

  if [[ "${1:-}" == "--silent" ]]; then
    silent_mode=true
  fi

  if [[ -z "${SERVER_IPv4:-}" ]]; then
    SERVER_IPv4=$(curl -s -4 https://api.ipify.org)
  fi

  if [[ -z "${SERVER_IPv6:-}" ]]; then
    SERVER_IPv6=$(curl -s -6 https://api64.ipify.org)
  fi

  if [[ "$silent_mode" == false ]]; then
    printf "\n🌐 \033[1mServer Public IP Information:\033[0m\n"
    print_line
    printf " 🌍 IPv4 Address: \033[1;36m%s\033[0m\n" "${SERVER_IPv4:-Unavailable}"
    printf " 🌐 IPv6 Address: \033[1;36m%s\033[0m\n" "${SERVER_IPv6:-Unavailable}"
  fi
}

set_swap() {
  echo -e "\n🧮 \e[1;34mChecking swap space...\e[0m"
  echo "─────────────────────────────────────────────────────────────"

  if free | grep -q "Swap: *0"; then
    echo -e "🔧 \e[33mNo active swap detected.\e[0m"
    echo -e "📦 Creating 2 GB swap file at \e[36m/swapfile\e[0m ..."

    if fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none; then
      chmod 600 /swapfile
      mkswap /swapfile >/dev/null
      swapon /swapfile
      echo '/swapfile none swap sw 0 0' >> /etc/fstab
      echo -e "✅ \e[1;32mSwap file successfully created and activated.\e[0m"
    else
      echo -e "❌ \e[1;31mFailed to create swap file.\e[0m"
    fi
  else
    echo -e "✅ \e[1;32mSwap space is already configured.\e[0m"
  fi
}

update_server() {
  echo "📦 Updating system packages (non-interactive)..."
  export DEBIAN_FRONTEND=noninteractive

  apt update
  apt -o Dpkg::Options::="--force-confdef" \
      -o Dpkg::Options::="--force-confold" \
      -y upgrade

  echo "🧹 Removing unused packages..."
  apt -y autoremove

  echo "🧼 Cleaning up cached .deb packages..."
  apt -y autoclean
}

get_project_root() {
  local i=0
  local source

  # Durchlaufe BASH_SOURCE-Stack, bis wir aus dem lib-Verzeichnis kommen
  while source="${BASH_SOURCE[$i]}"; do
    if [[ "$source" == */lib/common.sh ]]; then
      break
    fi
    ((i++)) || break
  done

  # Fallback falls nicht gefunden
  [[ -z "$source" ]] && source="${BASH_SOURCE[0]}"

  local dir
  dir="$(cd -P "$(dirname "$source")/.." >/dev/null 2>&1 && pwd)"
  echo "$dir"
}

find_free_port() {
  local base_port=5000
  local max_port=5099
  local port

  for ((port = base_port; port <= max_port; port++)); do
    if ss -tuln | grep -q ":$port\\b"; then
      continue
    fi

    if [[ -d /etc/nginx/sites-available ]] && \
       grep -r "localhost:$port" /etc/nginx/sites-available/ >/dev/null 2>&1; then
      continue
    fi

    echo "$port"
    return 0
  done

  echo "❌ No free port found between $base_port and $max_port" >&2
  return 1
}

confirm_action_code() {
  local confirm_code user_input char
  confirm_code=$((RANDOM % 90000 + 10000))
  local code_length=${#confirm_code}
  echo -e "\nTo confirm, please enter the code: \e[1;33m$confirm_code\e[0m (or type \e[36mq\e[0m to cancel)"
  echo -n $'\n🔐 Enter confirmation code: '
  
  # Clear input buffer before waiting for input
  while IFS= read -rsn1 -t 0.001; do :; done

  user_input=""
  while true; do
    IFS= read -rsn1 char

    if [[ -z "$char" || "$char" == $'\n' ]]; then
      break
    fi

    if [[ "$char" == $'\x1b' ]]; then
      IFS= read -rsn1 -t 0.01 next1
      IFS= read -rsn1 -t 0.01 next2
      if [[ "$next1$next2" == "[3" ]]; then
        read -rsn1 -t 0.01
        continue
      fi
      continue
    fi

    if [[ "$char" == $'\x7f' || "$char" == $'\x08' ]]; then
      if [[ -n "$user_input" ]]; then
        user_input="${user_input::-1}"
        echo -ne "\b \b"
      fi
      continue
    fi

    if [[ "$char" =~ [Qq] ]]; then
      echo
      return 1
    fi

    if [[ "$char" =~ [0-9] ]]; then
      if [[ "${#user_input}" -lt "$code_length" ]]; then
        user_input+="$char"
        echo -n "$char"
      fi
    fi
  done

  if [[ "$user_input" != "$confirm_code" ]]; then
    echo -e "\n❌ \e[31mAction aborted – confirmation failed.\e[0m"
    echo -e "\n↩️  \e[36mReturning to previous menu...\e[0m"
    sleep 1
    return 1
  fi

  echo
  return 0
}

read_menu_choice() {
  local max="$1"
  local input="" char
  print_line
  print_select_prompt "$max"

  # Clear input buffer before waiting for input
  while IFS= read -rsn1 -t 0.001; do :; done

  while true; do
    IFS= read -rsn1 char

    if [[ -z "$char" || "$char" == $'\n' || "$char" == $'\r' ]]; then
      if [[ "$input" =~ ^[1-9][0-9]{0,2}$ && $((10#$input)) -le $((10#$max)) ]]; then
        break
      fi
      continue
    fi

    if [[ "$char" == $'\x1b' ]]; then
      IFS= read -rsn1 -t 0.01 next1
      IFS= read -rsn1 -t 0.01 next2
      if [[ "$next1$next2" == "[3" ]]; then
        read -rsn1 -t 0.01
        continue
      fi
      continue
    fi

    if [[ "$char" == $'\x7f' || "$char" == $'\x08' ]]; then
      if [[ -n "$input" ]]; then
        input="${input::-1}"
        echo -ne "\b \b"
      fi
      continue
    fi

    if [[ "$char" =~ [Qq] ]]; then
      echo
      REPLY="q"
      return 0
    fi

    if [[ "$char" =~ [0-9] ]]; then
      if [[ -z "$input" && "$char" == "0" ]]; then
        continue
      fi

      local test_input="${input}${char}"
      if (( 10#$test_input > 10#$max )); then
        continue
      fi

      input="$test_input"
      echo -n "$char"

      if (( max < 10 )); then
        echo
        REPLY="$input"
        return 0
      fi
    fi
  done

  echo
  REPLY="$input"
  return 0
}