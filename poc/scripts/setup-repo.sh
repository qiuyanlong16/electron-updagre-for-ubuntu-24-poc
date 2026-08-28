#!/usr/bin/env bash
# Run as a FIXED NORMAL USER (not root). Creates byclaw-poc aptly repo + GPG key.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/apt-repository"
CONF="$REPO/aptly.conf"
# Generate aptly.conf from the template with absolute paths (spec §14.2/§14.4:
# a fixed rootDir that does NOT depend on ${HOME} or a specific user path — any
# clone path works; the committed config is the .tmpl, never a hardcoded path).
sed -e "s|__APTLY_DB__|$REPO/aptly-db|" \
    -e "s|__APTLY_PUBLIC__|$REPO/aptly-db/public|" \
    "$REPO/aptly.conf.tmpl" > "$CONF"
GNUPGHOME="$REPO/gpg-home"
APTLY="aptly -config=$CONF"

[ "$(id -u)" -ne 0 ] || { echo "ERROR: run as normal user, not root"; exit 1; }
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"

# GPG key (fixed GNUPGHOME, not user ~/.gnupg) (spec §14.2)
if ! GNUPGHOME="$GNUPGHOME" gpg --list-keys byclaw-poc@localhost >/dev/null 2>&1; then
  GNUPGHOME="$GNUPGHOME" gpg --batch --gen-key <<KEY
%no-protection
Key-Type: RSA
Key-Length: 2048
Name-Real: Byclaw POC
Name-Email: byclaw-poc@localhost
Expire-Date: 0
%commit
KEY
fi
GPG_KEY="$(GNUPGHOME="$GNUPGHOME" gpg --list-keys --with-colons byclaw-poc@localhost | grep '^fpr' | head -1 | cut -d: -f10)"
[ -n "$GPG_KEY" ] || { echo "ERROR: no GPG key"; exit 1; }
export GNUPGHOME GPG_KEY
# Binary keybox (NOT --armor): apt's Signed-By keyring must be binary; an ASCII-armored
# file makes apt emit "NO_PUBKEY" / "invalid packet (ctb=2d)" (Case 08, spec §14.2).
GNUPGHOME="$GNUPGHOME" gpg --export byclaw-poc@localhost > "$REPO/byclaw-poc-public.gpg"

# aptly repo (fixed normal user only; no || true; nonzero exit on failure) (spec §14.1, §14.3)
if ! $APTLY repo show byclaw-poc >/dev/null 2>&1; then
  $APTLY repo create -distribution=noble -component=main byclaw-poc
fi
# initial empty publish (creates InRelease)
if ! $APTLY publish list | grep -q byclaw-poc; then
  $APTLY publish repo -origin=Lenovo -label=Byclaw -distribution=noble -component=main \
    --gpg-key="$GPG_KEY" --batch --passphrase="" -skip-contents=true byclaw-poc filesystem:local:
fi
echo "[setup-repo] OK; GPG key: $GPG_KEY"
