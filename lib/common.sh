#!/bin/bash
set -e


load_env_once() {
  if [[ -n "${__ENV_LOADED_ALREADY:-}" ]]; then
    return 0
  fi

  local env_file="./.env"
  if [[ ! -f "$env_file" ]]; then
    return 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  __ENV_LOADED_ALREADY=1
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

load_server_ip_once() {
  if [[ -n "${__SERVER_IP_LOADED:-}" ]]; then
    return 0
  fi

  SERVER_IPv4=$(curl -s -4 https://api.ipify.org || true)
  SERVER_IPv6=$(curl -s -6 https://api64.ipify.org || true)

  if [[ -z "$SERVER_IPv4" && -z "$SERVER_IPv6" ]]; then
    echo -e "\n❌ \e[1;31mUnable to retrieve public IP address.\e[0m"
    echo -e "💡 Please check your internet connection or firewall settings."
    exit 1
  fi

  __SERVER_IP_LOADED=1
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

resolve_domain_from_app_dir() {
  local app_dir="$1"
  local subdir domain

  subdir=$(basename "$app_dir")
  domain=$(basename "$(dirname "$app_dir")")

  if [[ "$subdir" == "root" ]]; then
    printf "%s" "$domain" #return value
  else
    printf "%s.%s" "$subdir" "$domain" #return value
  fi
}

resolve_domain_from_service_name() {
  local service="$1"
  local base sub root fqdn

  base="${service%.service}"

  if [[ "$base" == *"@"*":"* ]]; then
    sub="${base%%@*}"
    root="${base#*@}"
    root="${root%%:*}"
    if [[ -z "$root" ]]; then
      return 1
    fi
    if [[ -z "$sub" ]]; then
      fqdn="$root"
    else
      fqdn="${sub}.${root}"
    fi
  elif [[ "$base" == *":"* ]]; then
    root="${base%%:*}"
    if [[ -z "$root" ]]; then
      return 1
    fi
    fqdn="$root"
  else
    return 1
  fi

  printf "%s" "$fqdn"
}

resolve_port_from_service_name() {
  local service="$1"
  local base port

  base="${service%.service}"

  if [[ "$base" == *":"* ]]; then
    port="${base##*:}"
    printf "%s" "$port"
  else
    echo "❌ Invalid service name: missing port → $service" >&2
    return 1
  fi
}

resolve_exec_dir_from_service_name() {
  local service="$1"
  local base sub root

  base="${service%.service}"

  if [[ "$base" == *"@"*":"* ]]; then
    sub="${base%%@*}"
    root="${base#*@}"
    root="${root%%:*}"
    if [[ -z "$sub" ]]; then
      printf "$APP_BASE_DIR/%s/root/" "$root"
    else
      printf "$APP_BASE_DIR/%s/%s/" "$root" "$sub"
    fi
  elif [[ "$base" == *":"* ]]; then
    root="${base%%:*}"
    printf "$APP_BASE_DIR/%s/root/" "$root"
  else
    echo "❌ Invalid service name: missing domain and port → $service" >&2
    return 1
  fi
}

resolve_url_from_service_name() {
  local service="$1"
  local fqdn

  if ! fqdn=$(resolve_domain_from_service_name "$service" 2>/dev/null); then
    echo "❌ Failed to resolve FQDN from service name: $service" >&2
    return 1
  fi

  printf "https://%s" "$fqdn"
}

is_valid_kestrel_service_name() {
  local service="$1"
  local base domain port

  [[ "$service" != *.service ]] && return 1

  base="${service%.service}"

  if [[ "$base" == *":"* ]]; then
    domain="${base%%:*}"
    port="${base##*:}"
    [[ -n "$domain" && "$port" =~ ^[0-9]+$ ]] || return 1
    return 0
  fi

  return 1
}

resolve_main_dll_from_service() {
  local service="$1"
  local exec_line dll_path dll_name

  if [[ -z "$service" ]]; then
    echo ""
    return 1
  fi

  exec_line=$(systemctl show -p ExecStart "$service" 2>/dev/null)
  if [[ -z "$exec_line" ]]; then
    echo ""
    return 1
  fi

  dll_path=$(grep -oP '\s/[^ ]+\.dll' <<< "$exec_line" | tr -d '[:space:]')
  if [[ -z "$dll_path" ]]; then
    echo ""
    return 1
  fi

  dll_name=$(basename "$dll_path")
  echo "$dll_name"
}

resolve_log_folder_from_service_name() {
  local service="$1"
  local base sub root

  base="${service%.service}"

  if [[ "$base" == *"@"*":"* ]]; then
    sub="${base%%@*}"
    root="${base#*@}"
    root="${root%%:*}"
    [[ -z "$sub" ]] && sub="root"
    printf "%s/%s/%s/%s/" "$APP_BASE_DIR" "$root" "$sub" "$LOGS_DIR"
  elif [[ "$base" == *":"* ]]; then
    root="${base%%:*}"
    printf "%s/%s/root/%s/" "$APP_BASE_DIR" "$root" "$LOGS_DIR"
  else
    echo "❌ Invalid service name: missing domain and port → $service" >&2
    return 1
  fi
}

resolve_backup_folder_from_service_name() {
  local service="$1"
  local base sub root

  base="${service%.service}"

  if [[ "$base" == *"@"*":"* ]]; then
    sub="${base%%@*}"
    root="${base#*@}"
    root="${root%%:*}"
    [[ -z "$sub" ]] && sub="root"
    printf "%s/%s/%s/%s/" "$APP_BASE_DIR" "$root" "$sub" "$BACKUP_DIR"
  elif [[ "$base" == *":"* ]]; then
    root="${base%%:*}"
    printf "%s/%s/root/%s/" "$APP_BASE_DIR" "$root" "$BACKUP_DIR"
  else
    echo "❌ Invalid service name: missing domain and port → $service" >&2
    return 1
  fi
}

get_dir_size() {
  local dir="$1"
  local size_kb size_human

  if [[ -z "$dir" || ! -d "$dir" ]]; then
    echo "Invalid"
    return 1
  fi

  size_kb=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
  if [[ -z "$size_kb" || "$size_kb" == *[!0-9]* ]]; then
    echo "Invalid"
    return 1
  fi

  if (( size_kb < 1024 )); then
    size_human="${size_kb} KB"
  elif (( size_kb < 1048576 )); then
    size_human="$(awk "BEGIN {printf \"%.1f MB\", $size_kb/1024}")"
  else
    size_human="$(awk "BEGIN {printf \"%.2f GB\", $size_kb/1048576}")"
  fi

  echo "$size_human"
}


get_service_ram_usage() {
  local service="$1"
  local ram_kb ram_human

  if [[ -z "$service" || ! "$service" =~ \.service$ ]]; then
    echo "Invalid service name"
    return 1
  fi

  ram_kb=$(systemctl show "$service" -p MemoryCurrent 2>/dev/null | cut -d= -f2)

  if [[ ! "$ram_kb" =~ ^[0-9]+$ || "$ram_kb" -eq 0 ]]; then
    echo "0 KB"
    return 0
  fi

  ram_kb=$((ram_kb / 1024))

  if (( ram_kb < 1024 )); then
    ram_human="${ram_kb} KB"
  elif (( ram_kb < 1048576 )); then
    ram_human="$(awk "BEGIN {printf \"%.1f MB\", $ram_kb/1024}")"
  else
    ram_human="$(awk "BEGIN {printf \"%.2f GB\", $ram_kb/1048576}")"
  fi

  echo "$ram_human"
}

get_service_uptime() {
  local service="$1"
  local uptime_readable="000d 00h 00m 00s"

  if [[ -z "$service" || ! "$service" =~ \.service$ ]]; then
    echo "Invalid service name"
    return 1
  fi

  if systemctl is-active --quiet "$service"; then
    local up_raw now elapsed_us sec
    up_raw=$(systemctl show -p ActiveEnterTimestampMonotonic "$service" 2>/dev/null | cut -d= -f2)
    if [[ "$up_raw" =~ ^[0-9]+$ ]]; then
      now=$(awk '{printf "%.0f", $1 * 1000000}' /proc/uptime)
      elapsed_us=$((now - up_raw))
      sec=$((elapsed_us / 1000000))
      uptime_readable=$(printf "%03dd %02dh %02dm %02ds" $((sec/86400)) $((sec%86400/3600)) $((sec%3600/60)) $((sec%60)))
    fi
  fi

  echo "$uptime_readable"
}

get_service_status_icon() {
  local service="$1"

  if [[ -z "$service" || ! "$service" =~ \.service$ ]]; then
    echo "Invalid service name"
    return 1
  fi

  if systemctl is-active --quiet "$service"; then
    printf '🟢'
  else
    printf '🔴'
  fi
}