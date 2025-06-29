#!/bin/bash
set -e

source ../lib/common.sh
source ../lib/const.sh

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

  run_case "192.168.1.1" "valid"
  run_case "0.0.0.0" "valid"
  run_case "255.255.255.255" "valid"
  run_case "127.0.0.1" "valid"
  run_case "1.2.3.4" "valid"
  run_case "256.1.1.1" "invalid"
  run_case "192.168.1" "invalid"
  run_case "192.168.1.1.1" "invalid"
  run_case "abc.def.ghi.jkl" "invalid"
  run_case "1.2.3.-1" "invalid"
  run_case "1.2.3.256" "invalid"
}

test_get_dir_size() {
  local dir result size unit min max

  run_case() {
    dir="$1"
    min="$2"
    max="$3"

    result=$(get_dir_size "$dir")

    # Extrahiere Größe und Einheit
    size=$(awk '{print $1}' <<< "$result")
    unit=$(awk '{print $2}' <<< "$result")

    if [[ "$unit" == "Invalid" ]]; then
      if [[ "$min" == "invalid" ]]; then
        echo "✅ $dir => Invalid directory"
        return 0
      else
        echo "❌ $dir => got 'Invalid directory', expected size"
        return 1
      fi
    fi

    # Umrechnen in KB zur Bereichsprüfung
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

  head -c 512000 /dev/zero > "$tmpdir1/file1"         # ~500 KB
  head -c 3145728 /dev/zero > "$tmpdir2/file2"        # ~3 MB
  head -c 1074790400 /dev/zero > "$tmpdir3/file3"     # ~1 GB

  run_case "$tmpdir1" 480 520
  run_case "$tmpdir2" 3000 3200
  run_case "$tmpdir3" 1040000 1100000

  run_case "/non/existing/path" "invalid" "invalid"

  rm -rf "$tmpdir1" "$tmpdir2" "$tmpdir3"
}


# Run all tests
test_is_valid_ipv4
test_get_dir_size
test_is_valid_kestrel_service_name
test_resolve_url_from_service_name
test_resolve_exec_dir_from_service_name
test_resolve_port_from_service_name
test_resolve_domain_from_service_name
test_resolve_domain_from_app_dir

echo -e "\n✅ All tests passed."
