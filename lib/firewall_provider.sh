#!/bin/bash
# shellcheck disable=SC1091
# Provider abstraction layer — delegates firewall and menu operations to the
# selected cloud provider based on the CLOUD_PROVIDER environment variable.
# Supported values: upcloud | digitalocean | other

# =============================================================================
# Display name helper
# =============================================================================

get_provider_display_name() {
  case "${CLOUD_PROVIDER:-}" in
    upcloud)      echo "UpCloud" ;;
    digitalocean) echo "Digital Ocean" ;;
    other)        echo "" ;;
    *)            echo "" ;;
  esac
}

# =============================================================================
# Firewall rule management
# =============================================================================

apply_firewall_rules() {
  case "${CLOUD_PROVIDER:-}" in
    upcloud)
      apply_upcloud_firewall_rules
      ;;
    digitalocean)
      apply_digitalocean_firewall_rules
      ;;
    other)
      echo "ℹ️ Firewall management disabled. Please configure firewall rules manually."
      return 0
      ;;
    *)
      echo "⚠️ Unknown cloud provider '${CLOUD_PROVIDER:-}'. Skipping firewall rule application."
      return 0
      ;;
  esac
}

delete_all_firewall_rules() {
  case "${CLOUD_PROVIDER:-}" in
    upcloud)
      delete_all_upcloud_firewall_rules
      ;;
    digitalocean)
      delete_all_digitalocean_firewall_rules
      ;;
    other)
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}

# =============================================================================
# Provider admin menu
# =============================================================================

show_provider_menu() {
  case "${CLOUD_PROVIDER:-}" in
    upcloud)
      show_upcloud_menu
      ;;
    digitalocean)
      show_digitalocean_menu
      ;;
    other)
      return 0
      ;;
    *)
      return 0
      ;;
  esac
}
