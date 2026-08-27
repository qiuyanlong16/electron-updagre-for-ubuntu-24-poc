#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?version}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$ROOT/apt-repository"; CONF="$REPO/aptly.conf"; GNUPGHOME="$REPO/gpg-home"
APTLY="aptly -config=$CONF"
export GNUPGHOME
GPG_KEY="$(GNUPGHOME="$GNUPGHOME" gpg --list-keys --with-colons byclaw-poc@localhost | grep '^fpr' | head -1 | cut -d: -f10)"

$APTLY repo add byclaw-poc "$ROOT/packages/byclaw_${VERSION}_amd64.deb"
if $APTLY publish list | grep -q byclaw-poc; then
  $APTLY publish update --gpg-key="$GPG_KEY" --batch --passphrase="" -skip-contents=true noble filesystem:local:
else
  $APTLY publish repo -origin=Lenovo -label=Byclaw -distribution=noble -component=main \
    --gpg-key="$GPG_KEY" --batch --passphrase="" -skip-contents=true byclaw-poc filesystem:local:
fi

# verify APT Packages index Version = VERSION (spec §12.3 #6, post-publish)
PV="$(python3 -c "import gzip,sys;print([l.split(': ',1)[1] for l in gzip.open('$REPO/aptly-db/public/dists/noble/main/binary-amd64/Packages.gz').read().decode().split('\n') if l.startswith('Version')][0])")"
[ "$PV" = "$VERSION" ] || { echo "ERROR: APT Packages Version=$PV != $VERSION"; exit 1; }
echo "[publish] byclaw $VERSION published; Packages Version OK"
