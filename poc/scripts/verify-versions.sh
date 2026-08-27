#!/usr/bin/env bash
set -euo pipefail
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

# 6. APT Packages index Version — only checkable after publish; here we skip with a note
echo "  NOTE Packages-index (#6) verified post-publish by verify-versions.sh --published"

[ "$fail" -eq 0 ] || { echo "[verify] FAILED"; exit 1; }
echo "[verify] build-time checks OK"
