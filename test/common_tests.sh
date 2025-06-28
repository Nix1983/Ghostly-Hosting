#!/bin/bash
set -e

source ../lib/common.sh

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

# Run all tests
test_is_valid_ipv4
test_resolve_port_from_service_name
test_resolve_domain_from_service_name
test_resolve_domain_from_app_dir

echo -e "\n✅ All tests passed."
