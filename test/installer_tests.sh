#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_INSTALLER_FILE="$ROOT_DIR/build_installer.sh"

echo "✅ INSTALLER TESTS READY"

test_installer_prompts_for_self_deletion_after_success() {
  if grep -Fq 'read -rp "Delete this installer now? [y/N] " delete_installer_response' "$BUILD_INSTALLER_FILE"; then
    echo "✅ build_installer.sh: Installer prompts for self-deletion after success"
    return 0
  fi

  echo "❌ build_installer.sh: Missing self-deletion prompt after successful installation"
  return 1
}

test_installer_deletes_current_script_when_confirmed() {
  if grep -Fq 'rm -f -- "$SELF_PATH"' "$BUILD_INSTALLER_FILE"; then
    echo "✅ build_installer.sh: Installer removes its own script when deletion is confirmed"
    return 0
  fi

  echo "❌ build_installer.sh: Missing self-delete command for installer script"
  return 1
}

test_installer_deletion_prompt_is_after_success_message() {
  local success_line delete_prompt_line
  success_line=$(grep -n 'Installation Complete!' "$BUILD_INSTALLER_FILE" | head -n1 | cut -d: -f1)
  delete_prompt_line=$(grep -n 'Delete this installer now\?' "$BUILD_INSTALLER_FILE" | head -n1 | cut -d: -f1)

  if [[ -n "$success_line" && -n "$delete_prompt_line" && "$delete_prompt_line" -gt "$success_line" ]]; then
    echo "✅ build_installer.sh: Self-deletion prompt is placed after the success flow"
    return 0
  fi

  echo "❌ build_installer.sh: Self-deletion prompt is not positioned after the success flow"
  return 1
}

FAILED=0

test_installer_prompts_for_self_deletion_after_success || ((FAILED++))
test_installer_deletes_current_script_when_confirmed || ((FAILED++))
test_installer_deletion_prompt_is_after_success_message || ((FAILED++))

if [[ $FAILED -eq 0 ]]; then
  echo "✅ All installer tests passed successfully"
  exit 0
fi

echo "❌ $FAILED installer test(s) failed"
exit 1
