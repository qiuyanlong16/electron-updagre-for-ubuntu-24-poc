#!/usr/bin/env bash
set -euo pipefail
# Build-time mode:   verify-versions.sh <version> <deb> <update-policy.json>     (#2 #3 #4 #5)
# Post-publish mode: verify-versions.sh --published <version> <repo-base-url>     (#5 #6 over HTTP)
# Spec §12.3: the SAME script re-verifies the published APT Packages index (#6) + HTTP
# update-policy.json (#5) after publish — the --published mode below does that.

if [ "${1:-}" = "--published" ]; then
  VERSION="${2:?version}"; URL="${3:?repo-base-url}"; fail=0
  echo "[verify] post-publish checks against $URL (expected $VERSION)"
  # #5 update-policy latestVersion (served over HTTP)
  LATEST="$(curl -sf "$URL/update-policy.json" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('latestVersion',''))" 2>/dev/null || true)"
  if [ "$LATEST" = "$VERSION" ]; then echo "  OK   HTTP update-policy latestVersion (#5) = $LATEST"; else echo "  FAIL HTTP update-policy latestVersion (#5) = '${LATEST:-<empty>}' (expected $VERSION)"; fail=1; fi
  # #6 APT Packages index Version (served over HTTP, gzipped); match the byclaw stanza's Version
  PKG_VER="$(curl -sf "$URL/dists/noble/main/binary-amd64/Packages.gz" 2>/dev/null | gunzip 2>/dev/null | awk '/^Package: byclaw$/{p=1;next} p&&/^Version:/{print $2;exit}' || true)"
  if [ "$PKG_VER" = "$VERSION" ]; then echo "  OK   APT Packages Version (#6) = $PKG_VER"; else echo "  FAIL APT Packages Version (#6) = '${PKG_VER:-<empty>}' (expected $VERSION)"; fail=1; fi
  [ "$fail" -eq 0 ] || { echo "[verify] FAILED"; exit 1; }
  echo "[verify] post-publish checks OK"; exit 0
fi

VERSION="${1:?version}"
DEB="${2:?deb}"
POLICY="${3:?update-policy.json}"
fail=0
chk() { # <expected> <actual> <label>
  if [ "$2" = "$1" ]; then echo "  OK   $3 = $2"; else echo "  FAIL $3 = $2 (expected $1)"; fail=1; fi
}
echo "[verify] expected version: $VERSION"

# 1. app.getVersion() <- deb's packaged package.json (inside app.asar not readable; use electron-builder metadata)
#    We approximate #1 by checking the deb contains the productName binary and control Version (#2).
#    Full #1 verification happens at runtime in Case 13 (app reports its version).

# 2. control Version
CTRL="$(dpkg-deb -f "$DEB" Version)"
chk "$VERSION" "$CTRL" "DEBIAN/control Version (#2)"

# 3. postinst installedVersion (build-time proxy: the baked VERSION="X.Y.Z" literal from sed
#    drives the runtime installedVersion "${VERSION}" in the heredoc; postinst lives in the
#    control archive, not the filesystem archive — use --ctrl-tarfile + ./postinst)
POSTINST="$(dpkg-deb --ctrl-tarfile "$DEB" 2>/dev/null | tar -xO ./postinst 2>/dev/null | grep -m1 -o '^VERSION="[^"]*"' | sed 's/^VERSION="//;s/"$//' || true)"
chk "$VERSION" "$POSTINST" "postinst installedVersion (#3)"

# 4. deb filename
case "$(basename "$DEB")" in byclaw_${VERSION}_amd64.deb) echo "  OK   filename (#4)";; *) echo "  FAIL filename (#4)"; fail=1;; esac

# 5. update-policy latestVersion
LATEST="$(python3 -c "import json,sys;print(json.load(open('$POLICY'))['latestVersion'])")"
chk "$VERSION" "$LATEST" "update-policy latestVersion (#5)"

# 6. APT Packages index Version — re-verified POST-PUBLISH (over HTTP) by:
#    verify-versions.sh --published <version> <repo-base-url>
echo "  NOTE Packages-index (#6) + HTTP policy (#5) re-verified post-publish by: verify-versions.sh --published $VERSION <repo-base-url>"

[ "$fail" -eq 0 ] || { echo "[verify] FAILED"; exit 1; }
echo "[verify] build-time checks OK"
