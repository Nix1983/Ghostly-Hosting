# GhostlyHosting — Blazor Server Hosting Made Easy

> **The all-in-one, SEO-friendly hosting tool for Blazor Server, Blazor WebAssembly, and any .NET web application.**  
> Deploy, manage, and secure your apps on your own Ubuntu VPS — through an intuitive, user-friendly console application.

GhostlyHosting is an interactive command-line tool that turns a fresh Ubuntu server into a fully configured, production-ready hosting environment for **Blazor Server** and other .NET applications. It automates SSL certificates, DNS management, GitHub-integrated deployments, reverse-proxy setup, and firewall configuration — all without writing a single config file.

### Why GhostlyHosting?

- **Blazor Server & SSR Hosting** — Full support for Blazor Server-Side Rendering, ensuring your pages are **SEO-friendly** and indexable by search engines out of the box.
- **User-Friendly Console App** — No YAML, no complex CLI flags. Just an interactive, menu-driven terminal UI that guides you step by step.
- **Self-Hosted & Private** — You own your server, your data, and your deployments. No vendor lock-in.

## ✨ Features

- 🚀 Deploy unlimited Blazor Server / .NET apps directly from GitHub repositories
- 🔍 SEO-optimized hosting — server-side rendering ensures search engines can crawl your Blazor apps
- 🖥️ Interactive, menu-driven console app — no config files required
- 🔒 Automatic HTTPS via Let's Encrypt with Cloudflare DNS setup
- 🌩️ Cloudflare proxy integration (DDoS protection, CDN, HTTP/2)
- 🛡️ Fail2Ban for SSH and nginx brute-force protection
- 🔄 One-command app updates & rollbacks (commit-based)
- 💾 Automatic backups before every deployment
- 📊 Real-time server health dashboard (CPU, RAM, disk, uptime)
- ☁️ Cloud provider firewall management (UpCloud, DigitalOcean, or manual)
- 🔑 All credentials encrypted and stored locally on your server

---

## 📋 Prerequisites

Before running the installer, make sure you have:

| Requirement | Details |
|---|---|
| **Ubuntu 22.04 LTS** (or newer) | A fresh VPS is recommended |
| **Root access** | The tool must run as `root` |
| **Cloudflare account** | Your domain must be managed by Cloudflare |
| **GitHub Personal Access Token** | Needs `repo` scope (and `read:org` for org repos) |
| **Cloud provider account** | UpCloud, DigitalOcean, or manual firewall management |

### Cloudflare API Token

Create a token at [https://dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens) with:
- `Zone:DNS:Edit`
- `Zone:Zone:Read`

### GitHub Personal Access Token

Generate a token at [https://github.com/settings/tokens](https://github.com/settings/tokens) with:
- `repo` (full repository access)
- `read:org` *(optional – needed for organisation repositories)*

### Cloud Provider API Token

- **UpCloud**: Create an API token in your [UpCloud control panel](https://signup.upcloud.com/?promo=AW9TF8)
- **DigitalOcean**: Create a Personal Access Token (read & write) in your [DO dashboard](https://cloud.digitalocean.com/account/api/tokens)
- **Other**: You manage firewall rules manually (ports 22, 80, 443 must be open)

---

## 🚀 Installation

### Quick Install (Recommended)

```bash
# Download latest installer
wget https://github.com/Nix1983/Blazor-Hosting/releases/latest/download/ghostly-hosting-installer.sh

# Make executable
chmod +x ghostly-hosting-installer.sh

# Run installer (requires root)
sudo ./ghostly-hosting-installer.sh
```

On first run you will be guided through:
1. Cloud provider selection (UpCloud / DigitalOcean / manual)
2. Cloud provider API token setup
3. GitHub Personal Access Token
4. Cloudflare API token

### Start GhostlyHosting

After installation, start the tool from any directory:

```bash
ghostly-hosting
```

### Manual Installation (Development)

```bash
git clone https://github.com/Nix1983/Blazor-Hosting.git
cd Blazor-Hosting
sudo ./start.sh
```

---

## 🔄 Updating

Simply run the new installer — your configuration (`.env.secure`) is preserved:

```bash
wget https://github.com/Nix1983/Blazor-Hosting/releases/latest/download/ghostly-hosting-installer.sh
chmod +x ghostly-hosting-installer.sh
sudo ./ghostly-hosting-installer.sh
```

---

## 🗑️ Uninstallation

```bash
# Remove the installation
sudo rm -rf /opt/ghostly-hosting

# Remove the shell command
sudo rm -f /usr/local/bin/ghostly-hosting

# Remove configuration (contains your API tokens – back up first!)
rm -rf ~/.config/ghostly-hosting
```

---

## 🖥️ What Happens During Server Initialisation

Running **Init Server** from the Server Control Panel installs and configures:

| Component | Purpose |
|---|---|
| **nginx** | Reverse proxy for all hosted apps |
| **Fail2Ban** | Brute-force protection (SSH + nginx) |
| **Certbot** | Let's Encrypt SSL certificate management |
| **git** | Required for cloning your repositories |
| **Swap** | 2 GB swap file (if none exists) |
| **Firewall rules** | Opens ports 22, 80, 443 via your cloud provider API |

---

## 🏗️ Adding a New App

1. Your domain must already point to this server in Cloudflare DNS (or the tool will create the record).
2. From the App Manager, choose **Add new App**.
3. Select your GitHub repository, branch/tag, and follow the prompts.
4. The tool will:
   - Clone the repo and publish the .NET project
   - Create a `systemd` service (Kestrel)
   - Configure nginx with an SSL-terminating reverse proxy
   - Request a Let's Encrypt certificate
   - Enable Cloudflare proxy mode

---

## 📦 Building the Installer

For developers who want to build the installer from source, see [docs/BUILD.md](docs/BUILD.md).

---

## 📚 Documentation

| Document | Description |
|---|---|
| [docs/BUILD.md](docs/BUILD.md) | How to build the self-extracting installer |
| [docs/TESTING.md](docs/TESTING.md) | Running the test suite |
| [docs/VERSIONING.md](docs/VERSIONING.md) | Version numbering conventions |
| [docs/ERROR_LOGGING.md](docs/ERROR_LOGGING.md) | Error log locations and format |
