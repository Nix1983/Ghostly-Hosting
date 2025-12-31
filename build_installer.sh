#!/bin/bash
# Build script for GhostlyHosting self-extracting encrypted installer
# This creates a self-contained installer that includes all necessary files

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Read version from lib/VERSION
VERSION=$(tr -d '[:space:]' <"$SCRIPT_DIR/lib/VERSION" 2>/dev/null || echo "1.0.0")
OUTPUT_FILE="$SCRIPT_DIR/ghostly-hosting-installer-v${VERSION}.sh"

# Temporary directory for build
BUILD_DIR=""

# Cleanup function
cleanup() {
  if [[ -n "$BUILD_DIR" ]] && [[ -d "$BUILD_DIR" ]]; then
    rm -rf "$BUILD_DIR"
  fi
}

# Set trap for cleanup
trap cleanup EXIT

echo "════════════════════════════════════════════════════════════════"
echo "  📦 GhostlyHosting Installer Builder"
echo "  Version: $VERSION"
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check dependencies
echo "Checking dependencies..."
MISSING_DEPS=()
for dep in tar gzip openssl; do
  if ! command -v "$dep" &>/dev/null; then
    MISSING_DEPS+=("$dep")
  fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  echo -e "${RED}❌ Missing dependencies: ${MISSING_DEPS[*]}${NC}"
  echo "Please install them and try again."
  exit 1
fi
echo -e "${GREEN}✓ All dependencies found${NC}"
echo ""

# Create temporary build directory
echo "Creating build directory..."
BUILD_DIR=$(mktemp -d)
echo -e "${GREEN}✓ Build directory: $BUILD_DIR${NC}"
echo ""

# Copy necessary files
echo "Collecting files..."
mkdir -p "$BUILD_DIR/ghostly-hosting"

# Track files being copied
echo ""
echo -e "${CYAN}Files being packaged:${NC}"
echo "─────────────────────────────────────────────────────────────────"

# Copy main scripts
echo "  • start.sh"
cp "$SCRIPT_DIR/start.sh" "$BUILD_DIR/ghostly-hosting/" || {
  echo -e "${RED}❌ Failed to copy start.sh${NC}"
  exit 1
}

echo "  • run_tests.sh"
cp "$SCRIPT_DIR/run_tests.sh" "$BUILD_DIR/ghostly-hosting/" || {
  echo -e "${RED}❌ Failed to copy run_tests.sh${NC}"
  exit 1
}

echo "  • upload.bat"
cp "$SCRIPT_DIR/upload.bat" "$BUILD_DIR/ghostly-hosting/" || {
  echo -e "${RED}❌ Failed to copy upload.bat${NC}"
  exit 1
}

# Copy lib directory
echo "  • lib/ ($(find "$SCRIPT_DIR/lib" -type f | wc -l) files)"
cp -r "$SCRIPT_DIR/lib" "$BUILD_DIR/ghostly-hosting/" || {
  echo -e "${RED}❌ Failed to copy lib directory${NC}"
  exit 1
}

# Copy config directory
echo "  • config/ ($(find "$SCRIPT_DIR/config" -type f | wc -l) files)"
cp -r "$SCRIPT_DIR/config" "$BUILD_DIR/ghostly-hosting/" || {
  echo -e "${RED}❌ Failed to copy config directory${NC}"
  exit 1
}

# Copy docs directory (optional)
if [[ -d "$SCRIPT_DIR/docs" ]]; then
  echo "  • docs/ ($(find "$SCRIPT_DIR/docs" -type f | wc -l) files)"
  cp -r "$SCRIPT_DIR/docs" "$BUILD_DIR/ghostly-hosting/" || {
    echo -e "${YELLOW}⚠ Warning: Failed to copy docs directory${NC}"
  }
fi

# Copy test directory (optional)
if [[ -d "$SCRIPT_DIR/test" ]]; then
  echo "  • test/ ($(find "$SCRIPT_DIR/test" -type f | wc -l) files)"
  cp -r "$SCRIPT_DIR/test" "$BUILD_DIR/ghostly-hosting/" || {
    echo -e "${YELLOW}⚠ Warning: Failed to copy test directory${NC}"
  }
fi

echo "─────────────────────────────────────────────────────────────────"
echo -e "${GREEN}✓ Files collected${NC}"
echo ""

# Create tar.gz archive
echo "Creating archive..."
ARCHIVE_FILE="$BUILD_DIR/ghostly-hosting.tar.gz"
tar -czf "$ARCHIVE_FILE" -C "$BUILD_DIR" ghostly-hosting || {
  echo -e "${RED}❌ Failed to create archive${NC}"
  exit 1
}
echo -e "${GREEN}✓ Archive created${NC}"
echo ""

# Generate random encryption password
echo "Generating encryption key..."
ENCRYPTION_PASSWORD=$(openssl rand -base64 32)
echo -e "${GREEN}✓ Encryption key generated${NC}"
echo ""

# Encrypt archive
echo "Encrypting archive..."
ENCRYPTED_FILE="$BUILD_DIR/ghostly-hosting.tar.gz.enc"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 10000 -in "$ARCHIVE_FILE" -out "$ENCRYPTED_FILE" -k "$ENCRYPTION_PASSWORD" || {
  echo -e "${RED}❌ Failed to encrypt archive${NC}"
  exit 1
}
echo -e "${GREEN}✓ Archive encrypted${NC}"
echo ""

# Create self-extracting installer
echo "Creating installer script..."

cat >"$OUTPUT_FILE" <<'INSTALLER_HEADER_EOF'
#!/bin/bash
# GhostlyHosting Self-Extracting Installer
# This installer will install GhostlyHosting to /opt/ghostly-hosting

set -euo pipefail

# Installation configuration
INSTALL_DIR="/opt/ghostly-hosting"
SYMLINK_PATH="/usr/local/bin/ghostly-hosting"
PROJECT_NAME="GhostlyHosting"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Temporary directory
TEMP_DIR=""

# Cleanup function
cleanup() {
  if [[ -n "$TEMP_DIR" ]] && [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}

# Set trap for cleanup
trap cleanup EXIT

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}❌ This installer must be run as root${NC}"
  echo "Please run: sudo $0"
  exit 1
fi

# Welcome message
echo "══════════════════════════════════════════════════════════════"
echo -e "  ${CYAN}📬 $PROJECT_NAME Installation${NC}"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "This installer will:"
echo "  • Install $PROJECT_NAME to $INSTALL_DIR"
echo "  • Create command: ghostly-hosting"
echo "  • Set proper file permissions"
echo ""

# Check for existing installation
if [[ -d "$INSTALL_DIR" ]]; then
  echo -e "${YELLOW}⚠ Previous installation found${NC}"
  read -rp "Update existing installation? [y/N] " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
  UPDATING=true
else
  read -rp "Continue with installation? [y/N] " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
  fi
  UPDATING=false
fi

echo ""

# Backup configuration if updating
ENV_SECURE_BACKUP=""
if [[ "$UPDATING" == true ]]; then
  # Determine the config directory for the user who will run the application
  # Check if SUDO_USER is set and not root
  if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
    # Get the home directory of the sudo user
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    CONFIG_DIR="${XDG_CONFIG_HOME:-$USER_HOME/.config}/ghostly-hosting"
  else
    # Fallback to root's config directory
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostly-hosting"
  fi
  
  if [[ -f "$CONFIG_DIR/.env.secure" ]]; then
    echo "==> Backing up configuration..."
    BACKUP_DIR=$(mktemp -d)
    cp -p "$CONFIG_DIR/.env.secure" "$BACKUP_DIR/" || {
      echo -e "${RED}❌ Failed to backup configuration${NC}"
      exit 1
    }
    ENV_SECURE_BACKUP="$BACKUP_DIR/.env.secure"
    echo -e "${GREEN}✓ Backed up .env.secure${NC}"
    echo ""
  fi
fi

# Extract payload from this script
echo "==> Extracting installer payload..."
TEMP_DIR=$(mktemp -d)
PAYLOAD_LINE=$(awk '/^__PAYLOAD_BEGINS__/ {print NR + 1; exit 0; }' "$0")
tail -n +"$PAYLOAD_LINE" "$0" | base64 -d >"$TEMP_DIR/payload.enc"
echo -e "${GREEN}✓ Payload extracted${NC}"
echo ""

# Decrypt payload
echo "==> Decrypting payload..."
INSTALLER_HEADER_EOF

# Add the encryption password to the installer
{
  echo "ENCRYPTION_PASSWORD='$ENCRYPTION_PASSWORD'"
} >>"$OUTPUT_FILE"

cat >>"$OUTPUT_FILE" <<'INSTALLER_DECRYPT_EOF'
openssl enc -aes-256-cbc -d -pbkdf2 -iter 10000 -in "$TEMP_DIR/payload.enc" -out "$TEMP_DIR/ghostly-hosting.tar.gz" -k "$ENCRYPTION_PASSWORD" || {
  echo -e "${RED}❌ Failed to decrypt payload${NC}"
  exit 1
}
echo -e "${GREEN}✓ Payload decrypted${NC}"
echo ""

# Extract files
echo "==> Extracting files..."
tar -xzf "$TEMP_DIR/ghostly-hosting.tar.gz" -C "$TEMP_DIR" || {
  echo -e "${RED}❌ Failed to extract files${NC}"
  exit 1
}
echo -e "${GREEN}✓ Files extracted${NC}"
echo ""

# Remove old installation if updating
if [[ "$UPDATING" == true ]]; then
  echo "==> Removing previous installation..."
  rm -rf "$INSTALL_DIR" || {
    echo -e "${RED}❌ Failed to remove previous installation${NC}"
    exit 1
  }
  echo -e "${GREEN}✓ Removed previous installation${NC}"
  echo ""
fi

# Install files
echo "==> Installing $PROJECT_NAME..."
mkdir -p "$(dirname "$INSTALL_DIR")"
cp -r "$TEMP_DIR/ghostly-hosting" "$INSTALL_DIR" || {
  echo -e "${RED}❌ Failed to install files${NC}"
  exit 1
}
echo -e "${GREEN}✓ Files installed${NC}"
echo ""

# Restore configuration if backed up
if [[ -n "$ENV_SECURE_BACKUP" ]] && [[ -f "$ENV_SECURE_BACKUP" ]]; then
  echo "==> Restoring configuration..."
  
  # Determine the config directory again for restoration
  if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    CONFIG_DIR="${XDG_CONFIG_HOME:-$USER_HOME/.config}/ghostly-hosting"
  else
    CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ghostly-hosting"
  fi
  
  mkdir -p "$CONFIG_DIR"
  cp -p "$ENV_SECURE_BACKUP" "$CONFIG_DIR/" || {
    echo -e "${RED}❌ Failed to restore configuration${NC}"
    exit 1
  }
  chmod 600 "$CONFIG_DIR/.env.secure"
  
  # Set ownership to the original user if installed via sudo
  if [[ -n "${SUDO_USER:-}" ]] && [[ "$SUDO_USER" != "root" ]]; then
    chown -R "$SUDO_USER:$SUDO_USER" "$CONFIG_DIR"
  fi
  
  echo -e "${GREEN}✓ Preserved configuration files${NC}"
  echo ""
fi

# Set permissions
echo "==> Setting file permissions..."
find "$INSTALL_DIR" -type d -exec chmod 755 {} \; || {
  echo -e "${RED}❌ Failed to set directory permissions${NC}"
  exit 1
}
find "$INSTALL_DIR" -type f -name "*.sh" -exec chmod 755 {} \; || {
  echo -e "${RED}❌ Failed to set script permissions${NC}"
  exit 1
}
echo -e "${GREEN}✓ Permissions set${NC}"
echo ""

# Create wrapper script
echo "==> Creating command wrapper..."
cat >"$SYMLINK_PATH" <<'WRAPPER_EOF'
#!/bin/bash
# GhostlyHosting launcher wrapper
INSTALL_DIR="/opt/ghostly-hosting"
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "Error: GhostlyHosting installation not found" >&2
    exit 1
fi
cd "$INSTALL_DIR" && exec ./start.sh "$@"
WRAPPER_EOF

chmod 755 "$SYMLINK_PATH" || {
  echo -e "${RED}❌ Failed to create command wrapper${NC}"
  exit 1
}
echo -e "${GREEN}✓ Command created: ghostly-hosting${NC}"
echo ""

# Success message
echo "══════════════════════════════════════════════════════════════"
if [[ "$UPDATING" == true ]]; then
  echo -e "  ${GREEN}✅ Update Complete!${NC}"
else
  echo -e "  ${GREEN}✅ Installation Complete!${NC}"
fi
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "To start $PROJECT_NAME, run:"
echo "  ghostly-hosting"
echo ""
echo "══════════════════════════════════════════════════════════════"
echo ""

exit 0

__PAYLOAD_BEGINS__
INSTALLER_DECRYPT_EOF

# Encode and append the encrypted payload
base64 <"$ENCRYPTED_FILE" >>"$OUTPUT_FILE"

# Make installer executable
chmod +x "$OUTPUT_FILE" || {
  echo -e "${RED}❌ Failed to make installer executable${NC}"
  exit 1
}

echo -e "${GREEN}✓ Installer script created${NC}"
echo ""

# Display summary
echo "════════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}✅ Build Complete!${NC}"
echo "════════════════════════════════════════════════════════════════"
echo ""
echo -e "Installer created: ${BLUE}$OUTPUT_FILE${NC}"
echo -e "Version: ${YELLOW}$VERSION${NC}"
echo ""
INSTALLER_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
echo -e "Size: ${YELLOW}$INSTALLER_SIZE${NC}"
echo ""
echo "To install, run:"
echo -e "  ${CYAN}sudo ./$(basename "$OUTPUT_FILE")${NC}"
echo ""
echo "════════════════════════════════════════════════════════════════"
echo ""
