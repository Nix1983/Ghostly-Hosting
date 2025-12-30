#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! source "$ROOT_DIR/lib/common.sh"; then
  echo "❌ Failed to source common.sh"
  exit 1
fi

if ! source "$ROOT_DIR/lib/const.sh"; then
  echo "❌ Failed to source const.sh"
  exit 1
fi

echo "✅ SOURCES LOADED"


test_resolve_domain_from_app_dir() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    result=$(resolve_domain_from_app_dir "$input")
    if [[ "$result" == "$expected" ]]; then
      echo "✅ $input => $result"
    else
      echo "❌ $input => got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "/var/www/example.com/root" "example.com"
  run_case "/var/www/example.com/myapp" "myapp.example.com"
  run_case "/var/www/ghostly.at/frontend" "frontend.ghostly.at"
  run_case "/var/www/ghostly.at/root" "ghostly.at"
  run_case "/var/www/test.dev/web" "web.test.dev"
  run_case "/var/www/test.dev/root" "test.dev"
  run_case "/var/www/blog.org/admin-panel" "admin-panel.blog.org"
  run_case "/var/www/blog.org/root" "blog.org"
}

test_resolve_domain_from_service_name() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    result=$(resolve_domain_from_service_name "$input")
    if [[ "$result" == "$expected" ]]; then
      echo "✅ $input => $result"
    else
      echo "❌ $input => got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "myapp@ghostlypick.com:5000.service" "myapp.ghostlypick.com"
  run_case "@ghostlypick.com:5001.service" "ghostlypick.com"
  run_case "ghostly.at:5002.service" "ghostly.at"
  run_case "admin-panel@blog.ghostly.at:5011.service" "admin-panel.blog.ghostly.at"
  run_case "@example.org:5022.service" "example.org"
}

test_resolve_port_from_service_name() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    if result=$(resolve_port_from_service_name "$input" 2>/dev/null); then
      if [[ "$result" == "$expected" ]]; then
        echo "✅ $input => $result"
      else
        echo "❌ $input => got '$result', expected '$expected'"
        return 1
      fi
    else
      if [[ -z "$expected" ]]; then
        echo "✅ $input => failed as expected"
      else
        echo "❌ $input => unexpected failure"
        return 1
      fi
    fi
  }

  run_case "myapp@ghostlypick.com:5000.service" "5000"
  run_case "@ghostlypick.com:5001.service" "5001"
  run_case "ghostly.at:5002.service" "5002"
  run_case "admin-panel@blog.ghostly.at:5011.service" "5011"
  run_case "@example.org:5099.service" "5099"
  run_case "invalid-service-name.service" ""
}

test_resolve_exec_dir_from_service_name() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    if result=$(resolve_exec_dir_from_service_name "$input" 2>/dev/null); then
      if [[ "$result" == "$expected" ]]; then
        echo "✅ $input => $result"
      else
        echo "❌ $input => got '$result', expected '$expected'"
        return 1
      fi
    else
      if [[ -z "$expected" ]]; then
        echo "✅ $input => failed as expected"
      else
        echo "❌ $input => unexpected failure"
        return 1
      fi
    fi
  }

  run_case "myapp@ghostlypick.com:5000.service" "/var/www/ghostlypick.com/myapp/"
  run_case "@ghostlypick.com:5001.service" "/var/www/ghostlypick.com/root/"
  run_case "ghostly.at:5002.service" "/var/www/ghostly.at/root/"
  run_case "admin-panel@blog.ghostly.at:5011.service" "/var/www/blog.ghostly.at/admin-panel/"
  run_case "@example.org:5099.service" "/var/www/example.org/root/"
  run_case "invalid-service-name.service" ""
}

test_resolve_url_from_service_name() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    if result=$(resolve_url_from_service_name "$input" 2>/dev/null); then
      if [[ "$result" == "$expected" ]]; then
        echo "✅ $input => $result"
      else
        echo "❌ $input => got '$result', expected '$expected'"
        return 1
      fi
    else
      if [[ -z "$expected" ]]; then
        echo "✅ $input => failed as expected"
      else
        echo "❌ $input => unexpected failure"
        return 1
      fi
    fi
  }

  run_case "myapp@ghostlypick.com:5000.service" "https://myapp.ghostlypick.com"
  run_case "@ghostlypick.com:5001.service" "https://ghostlypick.com"
  run_case "ghostly.at:5002.service" "https://ghostly.at"
  run_case "admin-panel@blog.ghostly.at:5011.service" "https://admin-panel.blog.ghostly.at"
  run_case "@example.org:5099.service" "https://example.org"
  run_case "invalid-service-name.service" ""
}

test_resolve_log_folder_from_service_name() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    if result=$(resolve_log_folder_from_service_name "$input" 2>/dev/null); then
      if [[ "$result" == "$expected" ]]; then
        echo "✅ $input => $result"
      else
        echo "❌ $input => got '$result', expected '$expected'"
        return 1
      fi
    else
      if [[ -z "$expected" ]]; then
        echo "✅ $input => failed as expected"
      else
        echo "❌ $input => unexpected failure"
        return 1
      fi
    fi
  }

  run_case "myapp@ghostlypick.com:5000.service" "/var/www/ghostlypick.com/myapp/logs/"
  run_case "@ghostlypick.com:5001.service" "/var/www/ghostlypick.com/root/logs/"
  run_case "ghostly.at:5002.service" "/var/www/ghostly.at/root/logs/"
  run_case "admin-panel@blog.ghostly.at:5011.service" "/var/www/blog.ghostly.at/admin-panel/logs/"
  run_case "@example.org:5099.service" "/var/www/example.org/root/logs/"
  run_case "invalid.service" ""
}

test_resolve_backup_folder_from_service_name() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"
    if result=$(resolve_backup_folder_from_service_name "$input" 2>/dev/null); then
      if [[ "$result" == "$expected" ]]; then
        echo "✅ $input => $result"
      else
        echo "❌ $input => got '$result', expected '$expected'"
        return 1
      fi
    else
      if [[ -z "$expected" ]]; then
        echo "✅ $input => failed as expected"
      else
        echo "❌ $input => unexpected failure"
        return 1
      fi
    fi
  }

  run_case "myapp@ghostlypick.com:5000.service" "/var/www/ghostlypick.com/myapp/backups/"
  run_case "@ghostlypick.com:5001.service" "/var/www/ghostlypick.com/root/backups/"
  run_case "ghostly.at:5002.service" "/var/www/ghostly.at/root/backups/"
  run_case "admin-panel@blog.ghostly.at:5011.service" "/var/www/blog.ghostly.at/admin-panel/backups/"
  run_case "@example.org:5099.service" "/var/www/example.org/root/backups/"
  run_case "invalid" ""
}

test_is_valid_kestrel_service_name() {
  local input expected result

  run_case() {
    input="$1"
    expected="$2"

    if is_valid_kestrel_service_name "$input"; then
      result="true"
    else
      result="false"
    fi

    if [[ "$result" == "$expected" ]]; then
      echo "✅ $input => $result"
    else
      echo "❌ $input => got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "myapp@ghostlypick.com:5000.service" "true"
  run_case "@ghostlypick.com:5001.service" "true"
  run_case "ghostly.at:5002.service" "true"
  run_case "admin-panel@blog.ghostly.at:5011.service" "true"
  run_case "@example.org:5099.service" "true"
  run_case "invalid-service-name.service" "false"
  run_case "test@domain.com.service" "false"
  run_case "justtext" "false"
  run_case "file.txt" "false"
  run_case "webapp@ghostlypick.com:notaport.service" "false"
}

test_is_valid_ipv4() {
  local ip expected result

  run_case() {
    ip="$1"
    expected="$2"
    if is_valid_ipv4 "$ip"; then
      result="valid"
    else
      result="invalid"
    fi

    if [[ "$result" == "$expected" ]]; then
      echo "✅ $ip => $result"
    else
      echo "❌ $ip => got $result, expected $expected"
      return 1
    fi
  }

  # Valid IPs
  run_case "192.168.1.1" "valid"
  run_case "0.0.0.0" "valid"
  run_case "255.255.255.255" "valid"
  run_case "127.0.0.1" "valid"
  run_case "1.2.3.4" "valid"
  run_case "10.0.0.1" "valid"
  run_case "172.16.0.1" "valid"
  
  # Invalid IPs - out of range
  run_case "256.1.1.1" "invalid"
  run_case "1.256.1.1" "invalid"
  run_case "1.1.256.1" "invalid"
  run_case "1.1.1.256" "invalid"
  run_case "1.2.3.300" "invalid"
  
  # Invalid IPs - wrong format
  run_case "192.168.1" "invalid"
  run_case "192.168.1.1.1" "invalid"
  run_case "abc.def.ghi.jkl" "invalid"
  run_case "1.2.3.-1" "invalid"
  
  # Invalid IPs - empty or special cases
  run_case "" "invalid"
  run_case "..." "invalid"
  run_case "1..1.1" "invalid"
  
  # Invalid IPs - leading zeros (security consideration)
  run_case "192.168.001.1" "invalid"
  run_case "192.168.1.01" "invalid"
}

test_get_dir_size() {
  local dir result size unit size_kb min max

  run_case() {
    dir="$1"
    min="$2"
    max="$3"

    result=$(get_dir_size "$dir")

    read -r size unit <<< "$result"

    if [[ "$unit" == "Invalid" || "$size" == "Invalid" ]]; then
      if [[ "$min" == "invalid" ]]; then
        echo "✅ $dir => Invalid directory"
        return 0
      else
        echo "❌ $dir => got 'Invalid directory', expected size"
        return 1
      fi
    fi

    if [[ -z "$unit" || -z "$size" ]]; then
      echo "❌ Malformed result: '$result'"
      return 1
    fi

    case "$unit" in
      KB) size_kb=$(awk "BEGIN {print $size}") ;;
      MB) size_kb=$(awk "BEGIN {print $size * 1024}") ;;
      GB) size_kb=$(awk "BEGIN {print $size * 1048576}") ;;
      *) echo "❌ Unknown unit: $unit"; return 1 ;;
    esac

    if awk "BEGIN {exit !($size_kb >= $min && $size_kb <= $max)}"; then
      echo "✅ $dir => $result (OK: $min–$max KB)"
    else
      echo "❌ $dir => got '$result', expected between $min–$max KB"
      return 1
    fi
  }

  tmpdir1=$(mktemp -d)
  tmpdir2=$(mktemp -d)
  tmpdir3=$(mktemp -d)

  head -c 512000 /dev/zero > "$tmpdir1/file1"
  head -c 3145728 /dev/zero > "$tmpdir2/file2"
  head -c 1074790400 /dev/zero > "$tmpdir3/file3"

  run_case "$tmpdir1" 480 520
  run_case "$tmpdir2" 3000 3200
  run_case "$tmpdir3" 1040000 1100000
  run_case "/non/existing/path" "invalid" "invalid"
  run_case "/dev/null" "invalid" "invalid"

  rm -rf "$tmpdir1" "$tmpdir2" "$tmpdir3"
}


run_test() {
  echo -e "\n🔧 Running $1"
  if ! "$1"; then
    echo "❌ Test '$1' failed"
  fi
}

run_test test_is_valid_ipv4
run_test test_get_dir_size
run_test test_is_valid_kestrel_service_name
run_test test_resolve_url_from_service_name
run_test test_resolve_exec_dir_from_service_name
run_test test_resolve_port_from_service_name
run_test test_resolve_domain_from_service_name
run_test test_resolve_domain_from_app_dir
run_test test_resolve_log_folder_from_service_name
run_test test_resolve_backup_folder_from_service_name

echo -e "\n✅ All tests finished (some may have failed)"

