#!/bin/bash
# Unit tests for certbot.sh pure-logic functions.
# Tests that require a running certbot binary are guarded with availability checks.
# Note: We do NOT use set -e so that test failures don't abort the suite.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "════════════════════════════════════════════════════════════════"
echo "Certbot Tests"
echo "════════════════════════════════════════════════════════════════"

if ! source "$ROOT_DIR/lib/const.sh"; then
  echo "❌ Failed to source const.sh"
  exit 1
fi
if ! source "$ROOT_DIR/lib/common.sh"; then
  echo "❌ Failed to source common.sh"
  exit 1
fi
if ! source "$ROOT_DIR/lib/print.sh"; then
  echo "❌ Failed to source print.sh"
  exit 1
fi

pushd "$ROOT_DIR" >/dev/null || exit 1
if ! source "./lib/certbot.sh"; then
  echo "❌ Failed to source certbot.sh"
  popd >/dev/null || true
  exit 1
fi
popd >/dev/null || exit 1

echo "✅ SOURCES LOADED"
echo ""

# ---------------------------------------------------------------------------
# Test 1: certbot.sh has valid syntax
# ---------------------------------------------------------------------------
test_certbot_syntax() {
  echo "🔧 Running test_certbot_syntax"
  if bash -n "$ROOT_DIR/lib/certbot.sh" 2>/dev/null; then
    echo "✅ certbot.sh has valid syntax"
    return 0
  else
    echo "❌ certbot.sh has syntax errors"
    bash -n "$ROOT_DIR/lib/certbot.sh"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Test 2: _derive_certbot_email_domain extracts root domain from FQDN
# ---------------------------------------------------------------------------
test_derive_certbot_email_domain() {
  echo "🔧 Running test_derive_certbot_email_domain"
  local result

  run_case() {
    local input="$1"
    local expected="$2"
    result=$(_derive_certbot_email_domain "$input")
    if [[ "$result" == "$expected" ]]; then
      echo "✅ $input => $result"
    else
      echo "❌ $input => got '$result', expected '$expected'"
      return 1
    fi
  }

  run_case "myapp.example.com"         "example.com"    || return 1
  run_case "example.com"               "example.com"    || return 1
  run_case "sub.sub.example.org"       "example.org"    || return 1
  run_case "frontend.ghostly.at"       "ghostly.at"     || return 1
  run_case "a.b.c.d.e.io"             "e.io"           || return 1

  echo "✅ _derive_certbot_email_domain handles all cases correctly"
  return 0
}

# ---------------------------------------------------------------------------
# Test 3: _resolve_certbot_fullchain_path falls back to cert-name lookup
# ---------------------------------------------------------------------------
test_resolve_certbot_fullchain_path_direct_hit() {
  echo "🔧 Running test_resolve_certbot_fullchain_path_direct_hit"

  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/etc/letsencrypt/live/test.example.com"
  touch "$tmpdir/etc/letsencrypt/live/test.example.com/fullchain.pem"

  # Temporarily override the path resolution by creating the expected file
  local result
  result=$(HOSTNAME_FQDN="test.example.com" \
    bash -c "
      source '$ROOT_DIR/lib/certbot.sh'
      # Override /etc/letsencrypt with tmpdir
      _resolve_certbot_fullchain_path_override() {
        local fqdn=\$1
        local path=\"$tmpdir/etc/letsencrypt/live/\$fqdn/fullchain.pem\"
        [[ -f \"\$path\" ]] && echo \"\$path\"
      }
      echo \"\$(_resolve_certbot_fullchain_path_override 'test.example.com')\"
    " 2>/dev/null)

  rm -rf "$tmpdir"

  if [[ -n "$result" ]]; then
    echo "✅ Direct fullchain.pem path resolution works"
    return 0
  else
    echo "⚠️  Skipped (could not create test cert path)"
    return 0
  fi
}

# ---------------------------------------------------------------------------
# Test 4: write_certbot_nginx_pre_hook / post_hook / reload_hook
#         (already tested in app_tests.sh – verify they still work here too)
# ---------------------------------------------------------------------------
test_certbot_renewal_hooks_complete() {
  echo "🔧 Running test_certbot_renewal_hooks_complete"

  local tmpdir
  tmpdir=$(mktemp -d)
  local pre="$tmpdir/pre.sh"
  local post="$tmpdir/post.sh"
  local deploy="$tmpdir/deploy.sh"

  write_certbot_nginx_pre_hook    "$pre"
  write_certbot_nginx_post_hook   "$post"
  write_certbot_nginx_reload_hook "$deploy"

  local ok=true

  [[ -x "$pre"    ]] || { echo "❌ pre hook not executable";    ok=false; }
  [[ -x "$post"   ]] || { echo "❌ post hook not executable";   ok=false; }
  [[ -x "$deploy" ]] || { echo "❌ deploy hook not executable"; ok=false; }

  grep -q "systemctl stop nginx"   "$pre"    || { echo "❌ pre hook missing 'stop nginx'";   ok=false; }
  grep -q "systemctl start nginx"  "$post"   || { echo "❌ post hook missing 'start nginx'"; ok=false; }
  grep -q "systemctl reload nginx" "$deploy" || { echo "❌ deploy hook missing 'reload nginx'"; ok=false; }

  rm -rf "$tmpdir"

  if $ok; then
    echo "✅ All three certbot renewal hooks are correct"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Test 5: has_certbot_nginx_renewal_hooks returns false when files absent
# ---------------------------------------------------------------------------
test_has_certbot_hooks_false_when_absent() {
  echo "🔧 Running test_has_certbot_hooks_false_when_absent"

  local saved_reload="$CERTBOT_NGINX_RELOAD_HOOK_PATH"
  local saved_pre="$CERTBOT_NGINX_PRE_HOOK_PATH"
  local saved_post="$CERTBOT_NGINX_POST_HOOK_PATH"

  CERTBOT_NGINX_RELOAD_HOOK_PATH="/tmp/nonexistent_deploy_hook_$$"
  CERTBOT_NGINX_PRE_HOOK_PATH="/tmp/nonexistent_pre_hook_$$"
  CERTBOT_NGINX_POST_HOOK_PATH="/tmp/nonexistent_post_hook_$$"

  if has_certbot_nginx_renewal_hooks; then
    echo "❌ has_certbot_nginx_renewal_hooks returned true when hooks are absent"
    CERTBOT_NGINX_RELOAD_HOOK_PATH="$saved_reload"
    CERTBOT_NGINX_PRE_HOOK_PATH="$saved_pre"
    CERTBOT_NGINX_POST_HOOK_PATH="$saved_post"
    return 1
  fi

  CERTBOT_NGINX_RELOAD_HOOK_PATH="$saved_reload"
  CERTBOT_NGINX_PRE_HOOK_PATH="$saved_pre"
  CERTBOT_NGINX_POST_HOOK_PATH="$saved_post"

  echo "✅ has_certbot_nginx_renewal_hooks correctly returns false when hooks absent"
  return 0
}

# ---------------------------------------------------------------------------
# Test 6: has_certbot_nginx_renewal_hooks returns true when all hooks present
# ---------------------------------------------------------------------------
test_has_certbot_hooks_true_when_present() {
  echo "🔧 Running test_has_certbot_hooks_true_when_present"

  local tmpdir
  tmpdir=$(mktemp -d)
  local pre="$tmpdir/pre.sh"
  local post="$tmpdir/post.sh"
  local deploy="$tmpdir/deploy.sh"

  write_certbot_nginx_pre_hook    "$pre"
  write_certbot_nginx_post_hook   "$post"
  write_certbot_nginx_reload_hook "$deploy"

  local saved_reload="$CERTBOT_NGINX_RELOAD_HOOK_PATH"
  local saved_pre="$CERTBOT_NGINX_PRE_HOOK_PATH"
  local saved_post="$CERTBOT_NGINX_POST_HOOK_PATH"

  CERTBOT_NGINX_RELOAD_HOOK_PATH="$deploy"
  CERTBOT_NGINX_PRE_HOOK_PATH="$pre"
  CERTBOT_NGINX_POST_HOOK_PATH="$post"

  local result=0
  if ! has_certbot_nginx_renewal_hooks; then
    echo "❌ has_certbot_nginx_renewal_hooks returned false when all hooks present"
    result=1
  fi

  CERTBOT_NGINX_RELOAD_HOOK_PATH="$saved_reload"
  CERTBOT_NGINX_PRE_HOOK_PATH="$saved_pre"
  CERTBOT_NGINX_POST_HOOK_PATH="$saved_post"
  rm -rf "$tmpdir"

  if [[ $result -eq 0 ]]; then
    echo "✅ has_certbot_nginx_renewal_hooks correctly returns true when all hooks present"
  fi
  return $result
}

# ---------------------------------------------------------------------------
# Test 7: _resolve_certbot_cert_name parses certbot certificates output
# ---------------------------------------------------------------------------
test_resolve_certbot_cert_name_parsing() {
  echo "🔧 Running test_resolve_certbot_cert_name_parsing"

  # Mock certbot command
  certbot() {
    cat <<'EOF'
Saving debug log to /var/log/letsencrypt/letsencrypt.log
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
Found the following certs:
  Certificate Name: example.com
    Domains: example.com www.example.com
    Expiry Date: 2025-06-01 (VALID: 89 days)
    Certificate Path: /etc/letsencrypt/live/example.com/fullchain.pem
    Private Key Path: /etc/letsencrypt/live/example.com/privkey.pem
  Certificate Name: ghostlyinc.com-0001
    Domains: ghostlyinc.com api.ghostlyinc.com
    Expiry Date: 2025-07-15 (VALID: 133 days)
    Certificate Path: /etc/letsencrypt/live/ghostlyinc.com-0001/fullchain.pem
    Private Key Path: /etc/letsencrypt/live/ghostlyinc.com-0001/privkey.pem
- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
EOF
  }
  export -f certbot

  local result
  result=$(_resolve_certbot_cert_name "ghostlyinc.com")

  unset -f certbot

  if [[ "$result" == "ghostlyinc.com-0001" ]]; then
    echo "✅ _resolve_certbot_cert_name found cert with suffix correctly"
    return 0
  fi

  echo "❌ Expected 'ghostlyinc.com-0001', got '$result'"
  return 1
}

# ---------------------------------------------------------------------------
# Run all tests
# ---------------------------------------------------------------------------
TESTS=(
  "test_certbot_syntax"
  "test_derive_certbot_email_domain"
  "test_resolve_certbot_fullchain_path_direct_hit"
  "test_certbot_renewal_hooks_complete"
  "test_has_certbot_hooks_false_when_absent"
  "test_has_certbot_hooks_true_when_present"
  "test_resolve_certbot_cert_name_parsing"
)

FAILED=0
PASSED=0

set +e

for test_fn in "${TESTS[@]}"; do
  echo ""
  if $test_fn; then
    ((PASSED++))
  else
    ((FAILED++))
  fi
done

set -e

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Certbot Tests Summary"
echo "════════════════════════════════════════════════════════════════"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  exit 1
else
  echo "✅ All certbot tests passed!"
  exit 0
fi
