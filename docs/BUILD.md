# Building the Installer

## Prerequisites

The build script requires the following tools to be installed:

- `tar` - Archive creation
- `gzip` - Compression
- `openssl` - Encryption
- `bash` 4.0+ - Script execution

These tools are typically pre-installed on most Linux distributions.

## Build Process

1. Navigate to the repository root:
   ```bash
   cd /path/to/Blazor-Hosting
   ```

2. Run the build script:
   ```bash
   ./build_installer.sh
   ```

3. The installer will be created in the repository root:
   ```
   ghostly-hosting-installer-v{VERSION}.sh
   ```

The version number is automatically read from `lib/VERSION`.

## What Gets Packaged

The installer includes only the essential runtime files for GhostlyHosting:

- `start.sh` - Main entry point
- `LICENSE` - MIT License file
- `lib/` - All library scripts including:
  - `app.sh`, `app_manager.sh`
  - `certbot.sh`, `cloudflare.sh`
  - `common.sh`, `const.sh`
  - `dotnet.sh`, `fail2ban.sh`
  - `git.sh`, `github.sh`
  - `log.sh`, `nginx.sh`
  - `print.sh`, `server.sh`
  - `server_manager.sh`
  - `upcloud.sh`, `version.sh`
  - `VERSION` - Version file
- `config/` - Configuration files
  - `upcloud_firewall_rules.json` (UpCloud: separate IPv4/IPv6 entries with `family` and `position`)
  - `digitalocean_firewall_rules.json` (Digital Ocean: one entry per port, no family field)

## Security

The build process implements the following security measures:

- **Archive encryption**: The archive is encrypted with AES-256-CBC
- **Random password**: A random 32-byte password is generated per build
- **Embedded password**: The password is embedded in the installer script
- **Tamper protection**: The payload cannot be extracted without the complete installer script

The encryption ensures that:
- The installer payload is protected during distribution
- Only the full installer script can extract and install the files
- Each build has a unique encryption key

## Build Output

When the build completes successfully, you'll see:

```
════════════════════════════════════════════════════════════════
  ✅ Build Complete!
════════════════════════════════════════════════════════════════

Installer created: ghostly-hosting-installer-v1.0.3.sh
Version: 1.0.3

Size: [size]

To install, run:
  sudo ./ghostly-hosting-installer-v1.0.3.sh

════════════════════════════════════════════════════════════════
```

## Distribution

### GitHub Releases

Upload the installer to GitHub Releases for easy distribution:

```bash
# Using GitHub CLI
gh release create v1.0.3 ghostly-hosting-installer-v1.0.3.sh \
  --title "GhostlyHosting v1.0.3" \
  --notes "Release notes here"
```

### Direct Distribution

You can also distribute the installer file directly:

```bash
# Copy to web server
scp ghostly-hosting-installer-v1.0.3.sh user@webserver:/var/www/downloads/

# Share via URL
wget https://example.com/downloads/ghostly-hosting-installer-v1.0.3.sh
```

## Troubleshooting

### Missing Dependencies

If you see an error about missing dependencies:

```bash
# Ubuntu/Debian
sudo apt-get install tar gzip openssl

# RHEL/CentOS/Fedora
sudo yum install tar gzip openssl

# Alpine
sudo apk add tar gzip openssl
```

### Permission Errors

The build script needs to:
- Read files from the repository
- Create temporary directories
- Create the installer file in the repository root

Ensure you have:
- Read permissions for all repository files
- Write permissions for the repository root directory

### Build Verification

To verify the build was successful:

```bash
# Check if installer exists
ls -lh ghostly-hosting-installer-v*.sh

# Verify it's executable
file ghostly-hosting-installer-v*.sh
# Should show: "Bourne-Again shell script, ASCII text executable"

# Check the version matches
head -5 ghostly-hosting-installer-v*.sh | grep "GhostlyHosting"
```

## Version Management

The version is managed through `lib/VERSION`:

1. Update the version number:
   ```bash
   echo "1.0.4" > lib/VERSION
   ```

2. Rebuild the installer:
   ```bash
   ./build_installer.sh
   ```

3. The new installer will be named with the updated version:
   ```
   ghostly-hosting-installer-v1.0.4.sh
   ```

## Clean Build

The build script automatically cleans up temporary files. If you need to manually clean:

```bash
# Remove old installers
rm -f ghostly-hosting-installer-v*.sh

# Rebuild from scratch
./build_installer.sh
```
