#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?usage: build-version.sh <version> e.g. 1.0.0}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "ERROR: bad version '$VERSION' (expected X.Y.Z)"; exit 1; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/electron-app"
PKG_DIR="$ROOT/packages"
STAGE="$PKG_DIR/build-${VERSION}"
DEB="$PKG_DIR/byclaw_${VERSION}_amd64.deb"

echo "[build] version=${VERSION}"
cd "$APP"
npm install --no-audit --no-fund
npx vitest run                    # unit tests must pass before packaging
npx vite build                    # renderer -> dist/renderer; main/preload -> dist/main.js, dist/preload.js (flat layout)
# electron-builder --dir with extraMetadata.version (does NOT mutate source package.json) (spec §12.2)
# --config.electronDist points at the electron npm package's pre-extracted dist (node_modules/electron/dist)
# so electron-builder copies the runtime locally instead of downloading electron-v*.zip from GitHub
# release assets — HTTPS to github.com is blocked on this build host (SSH-only). (spec §12.2)
npx electron-builder --dir --config.extraMetadata.version="${VERSION}" --config.electronDist=node_modules/electron/dist
# electron-builder output: $ROOT/dist-electron/linux-unpacked

UNPACKED="$ROOT/dist-electron/linux-unpacked"
[ -d "$UNPACKED" ] || { echo "ERROR: linux-unpacked missing"; exit 1; }

echo "[build] stage DEB tree"
rm -rf "$STAGE"
mkdir -p "$STAGE/opt/lenovo/byclaw"
cp -a "$UNPACKED/." "$STAGE/opt/lenovo/byclaw/"

# packaging overlays
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/share/applications" "$STAGE/etc/lenovo/byclaw" "$STAGE/etc/apparmor.d" "$STAGE/opt/lenovo/byclaw/resources"
cp "$ROOT/packaging/byclaw/usr/share/applications/com.lenovo.byclaw.desktop" "$STAGE/usr/share/applications/"
cp "$ROOT/packaging/byclaw/etc/lenovo/byclaw/config.json" "$STAGE/etc/lenovo/byclaw/"
cp "$ROOT/packaging/byclaw/etc/apparmor.d/com.lenovo.byclaw" "$STAGE/etc/apparmor.d/"
# icon (generated placeholder if absent)
if [ ! -f "$STAGE/opt/lenovo/byclaw/resources/icon.png" ]; then
  "$ROOT/scripts/make-icon.sh" "$STAGE/opt/lenovo/byclaw/resources/icon.png" || true
fi

# maintainer scripts with version injection
sed "s/__VERSION__/${VERSION}/g" "$ROOT/packaging/byclaw/DEBIAN/control.tmpl" > "$STAGE/DEBIAN/control"
INSTALLED_SIZE="$(du -sk "$STAGE/opt/lenovo/byclaw" | cut -f1)"
sed -i "s/__INSTALLED_SIZE__/${INSTALLED_SIZE}/" "$STAGE/DEBIAN/control"
sed "s/__VERSION__/${VERSION}/g" "$ROOT/packaging/byclaw/DEBIAN/postinst.tmpl" > "$STAGE/DEBIAN/postinst"
cp "$ROOT/packaging/byclaw/DEBIAN/prerm" "$STAGE/DEBIAN/prerm"
cp "$ROOT/packaging/byclaw/DEBIAN/postrm" "$STAGE/DEBIAN/postrm"
chmod 0755 "$STAGE/DEBIAN/"{postinst,prerm,postrm}

# perms: dirs 0755, files 0644, entry 0755 (chrome-sandbox stays 0755 NOT 4755) (spec §13.4, §16)
find "$STAGE" -type d -exec chmod 0755 {} \;
find "$STAGE" -path "$STAGE/DEBIAN" -prune -o -type f -exec chmod 0644 {} \;
[ -f "$STAGE/opt/lenovo/byclaw/byclaw" ] && chmod 0755 "$STAGE/opt/lenovo/byclaw/byclaw"
# chrome-sandbox explicitly NOT setuid
[ -f "$STAGE/opt/lenovo/byclaw/chrome-sandbox" ] && chmod 0755 "$STAGE/opt/lenovo/byclaw/chrome-sandbox"

# build update-policy.json as a build artifact (latestVersion = VERSION) (spec §12.3 #5)
mkdir -p "$ROOT/apt-repository/aptly-db/public"
cat > "$ROOT/apt-repository/aptly-db/public/update-policy.json" <<EOF
{
  "product": "byclaw",
  "channel": "stable",
  "latestVersion": "${VERSION}",
  "minimumSupportedVersion": "1.0.0",
  "mode": "optional",
  "releaseNotes": ["Byclaw ${VERSION}"]
}
EOF

echo "[build] dpkg-deb"
dpkg-deb --root-owner-group --build "$STAGE" "$DEB"

echo "[build] verify six-place version consistency"
bash "$ROOT/scripts/verify-versions.sh" "$VERSION" "$DEB" "$ROOT/apt-repository/aptly-db/public/update-policy.json"

echo "[build] OK -> $DEB"
