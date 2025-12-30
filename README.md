# GhostlyHosting

Provision and configure an Ubuntu server to host a Blazor app automatically.

## 🚀 Installation

### Quick Install (Recommended)

Download and run the installer:

```bash
# Download latest installer
wget https://github.com/Nix1983/Blazor-Hosting/releases/latest/download/ghostly-hosting-installer-v1.0.3.sh

# Make executable
chmod +x ghostly-hosting-installer-v1.0.3.sh

# Run installer
sudo ./ghostly-hosting-installer-v1.0.3.sh
```

### Start GhostlyHosting

After installation, start GhostlyHosting from any directory:

```bash
ghostly-hosting
```

### Manual Installation

If you prefer to install manually or for development:

```bash
git clone https://github.com/Nix1983/Blazor-Hosting.git
cd Blazor-Hosting
sudo ./start.sh
```

## 🔄 Updating

Simply run the new installer - your configuration will be preserved:

```bash
# Download new version
wget https://github.com/Nix1983/Blazor-Hosting/releases/latest/download/ghostly-hosting-installer-v1.1.0.sh

# Make executable
chmod +x ghostly-hosting-installer-v1.1.0.sh

# Run installer (your .env.secure will be preserved)
sudo ./ghostly-hosting-installer-v1.1.0.sh
```

## 🗑️ Uninstallation

To completely remove GhostlyHosting:

```bash
# Remove installation
sudo rm -rf /opt/ghostly-hosting

# Remove command
sudo rm /usr/local/bin/ghostly-hosting

# Remove configuration (optional - contains your API tokens)
rm -rf ~/.config/ghostly-hosting
```

## 📦 Building the Installer

For developers who want to build the installer from source, see [docs/BUILD.md](docs/BUILD.md)
