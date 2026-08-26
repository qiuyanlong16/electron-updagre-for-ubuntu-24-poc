#!/usr/bin/env bash
# setup-repo.sh — Initialize local APT repository using aptly
#
# Sets up a local APT repository with a temporary test GPG key
# for POC purposes. The repository serves packages via HTTP.
#
# Usage:
#   sudo ./scripts/setup-repo.sh
#
# Requires: aptly, gpg, nginx (or python3 for fallback server)

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${POC_DIR}/apt-repository"
SERVE_PORT="${NANOBOT_REPO_PORT:-8080}"

# Check root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: This script requires root privileges."
  echo "Run with: sudo $0"
  exit 1
fi

echo "=== Setting up Nanobot POC APT Repository ==="

# Install dependencies
echo "[1/5] Installing dependencies..."
apt-get update -qq 2>/dev/null || true
apt-get install -y -qq aptly gnupg2 nginx python3 2>/dev/null || true

# Verify aptly is available
if ! command -v aptly &>/dev/null; then
  echo "ERROR: aptly is not installed. Please install it first."
  echo "  sudo apt install aptly"
  exit 1
fi

# Generate temporary test GPG key (NOT for production use)
echo "[2/5] Generating temporary test GPG key..."
GNUPG_HOME="${REPO_DIR}/gpg-home"
rm -rf "${GNUPG_HOME}"
mkdir -m 0700 "${GNUPG_HOME}"

cat > "${GNUPG_HOME}/keygen.params" << 'KEYGEN'
%no-protection
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Nanobot POC
Name-Email: nanobot-poc@localhost
Expire-Date: 0
%commit
KEYGEN

gpg --homedir "${GNUPG_HOME}" --batch --gen-key "${GNUPG_HOME}/keygen.params" 2>/dev/null

# Export the public key for clients
gpg --homedir "${GNUPG_HOME}" --armor --export "nanobot-poc@localhost" \
  > "${REPO_DIR}/nanobot-poc-public.gpg"

echo "  Public key exported to: ${REPO_DIR}/nanobot-poc-public.gpg"

# Initialize aptly configuration
echo "[3/5] Initializing aptly repository..."
aptly config show &>/dev/null || true

# Create local repository
aptly repo create -distribution=noble -component=main nanobot-poc 2>/dev/null || true

# Configure aptly to use our GPG key
GPG_KEY_ID=$(gpg --homedir "${GNUPG_HOME}" --list-keys --with-colons "nanobot-poc@localhost" \
  | grep '^fpr' | head -1 | cut -d: -f10)

echo "  GPG Key ID: ${GPG_KEY_ID}"

# Create aptly config to use our GPG home
cat > "${REPO_DIR}/aptly.conf" << APTLY_CONF
{
  "rootDir": "${HOME}/.aptly",
  "architectures": ["amd64"],
  "gpgProvider": "gpg2",
  "gpgDisableSign": false,
  "gpgKey": "${GPG_KEY_ID}",
  "skipContents": true,
  "skipBz2": false
}
APTLY_CONF

# Publish the repository with proper Origin and Label
echo "  Publishing repository with Origin=Lenovo, Label=Nanobot..."
aptly publish repo \
  -origin="Lenovo" \
  -label="Nanobot" \
  -distribution=noble \
  -component=main \
  nanobot-poc 2>/dev/null || true

# Setup nginx to serve the published repository
echo "[4/5] Configuring nginx..."
PUBLISH_DIR="${HOME}/.aptly/public"
mkdir -p "${PUBLISH_DIR}"

cat > /etc/nginx/sites-available/nanobot-poc << NGINX
server {
    listen ${SERVE_PORT};
    server_name localhost;

    root ${PUBLISH_DIR};

    location / {
        autoindex on;
        autoindex_exact_size off;
        add_header Content-Type text/plain;
    }

    location ~ \.deb$ {
        default_type application/octet-stream;
    }

    access_log /var/log/nginx/nanobot-poc-access.log;
    error_log /var/log/nginx/nanobot-poc-error.log;
}
NGINX

# Enable the site
ln -sf /etc/nginx/sites-available/nanobot-poc /etc/nginx/sites-enabled/nanobot-poc
nginx -t && nginx -s reload 2>/dev/null || systemctl restart nginx 2>/dev/null || true

echo "[5/5] Repository setup complete."
echo ""
echo "  Repository URL: http://localhost:${SERVE_PORT}"
echo "  Public key:     ${REPO_DIR}/nanobot-poc-public.gpg"
echo "  GPG key ring:   ${GNUPG_HOME}"
echo ""
echo "Next steps:"
echo "  1. Run: ./scripts/build-deb.sh 1.0.0"
echo "  2. Run: ./scripts/init-oem.sh"
echo "  3. Run: sudo ./scripts/setup-client-config.sh"
