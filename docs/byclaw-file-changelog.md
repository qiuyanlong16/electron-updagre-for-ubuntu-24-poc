# Byclaw — File-Level Modification List

> Branch `feat/byclaw-vue3-redesign` vs `main`. Authoritative source:
> `git diff --name-status main..HEAD` (**73 entries**: 68 added, 5 modified).
> This is the file-level modification list deliverable (spec §19, item 10).
>
> The product is **Byclaw** (the rename of the old "nanobot" POC): a Vue 3 +
> TypeScript + Vite + Electron app, packaged as a `.deb`, auto-updated via a
> GPG-signed local aptly APT repository + systemd timer + unattended-upgrades
> + AppArmor. Old nanobot files remain in the tree but are not the product.

Legend: **A** = added · **M** = modified · kept = unchanged from `main`.

---

## New (A) — 68 files

### Docs & reports
- `docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md` — full design spec (§1–§21).
- `docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md` — implementation plan.
- `poc/VALIDATION_REPORT_V2.md` — real-evidence validation report (2 PASS / 16 NOT-TESTED / 0 FAIL).
- `poc/ROOT_OPS_RUNBOOK.md` — root install chain + per-case `sudo` steps to complete the 16 NOT-TESTED cases.
- `poc/evidence-v2/.gitkeep` — real-evidence output directory placeholder.

### Electron app — main process
- `poc/electron-app/src/main/main.ts` — main entry; `app.enableSandbox()` before `whenReady()`, single-instance lock, refuses `--no-sandbox`.
- `poc/electron-app/src/main/update-service.ts` — fetches `update-policy.json`, reads `update-state.json`, computes state, pushes `byclaw:update-state-changed`.
- `poc/electron-app/src/main/ipc.ts` — `ipcMain.handle` for the 5 IPC methods.
- `poc/electron-app/src/main/last-run.ts` — `lastSeenVersion` tracking for the upgrade banner.

### Electron app — preload
- `poc/electron-app/src/preload/preload.ts` — `contextBridge` exposing exactly 5 safe methods; no raw `ipcRenderer`, no `child_process`/`fs`/`shell`.

### Electron app — renderer (Vue 3)
- `poc/electron-app/src/renderer/App.vue` — root component.
- `poc/electron-app/src/renderer/main.ts` — Vue entry.
- `poc/electron-app/src/renderer/index.html` — HTML entry.
- `poc/electron-app/src/renderer/components/VersionButton.vue` — clickable version → `checkForUpdates()`.
- `poc/electron-app/src/renderer/components/UpdateDialog.vue` — the three dialogs (UPDATE_AVAILABLE / READY_OPTIONAL / READY_FORCE).
- `poc/electron-app/src/renderer/composables/useUpdateState.ts` — state subscription with unsubscribe on `onUnmounted`.

### Electron app — shared (main + tests)
- `poc/electron-app/src/shared/semver.ts` — pure semver comparison (no string compare).
- `poc/electron-app/src/shared/state-machine.ts` — pure update state machine (7 states).
- `poc/electron-app/src/shared/types/update.ts` — `UpdateState` / `UpdateInfo` types.
- `poc/electron-app/src/shared/upgrade-detect.ts` — `installedAhead` / `mode=force` detection.

### Electron app — tests (Vitest, 5 files)
- `poc/electron-app/tests/state-machine.test.ts` — 7-state transitions.
- `poc/electron-app/tests/update-service.test.ts` — service behavior incl. fallback + timeout.
- `poc/electron-app/tests/semver.test.ts` — semver comparison incl. `1.10.0` vs `1.9.0`.
- `poc/electron-app/tests/upgrade-detect.test.ts` — install-ahead / force detection.
- `poc/electron-app/tests/restart-dedup.test.ts` — restart click dedup.

### Electron app — config
- `poc/electron-app/electron-builder.yml` — linux target, `extraMetadata.version`, `electronDist` (no GitHub download — host is SSH-only).
- `poc/electron-app/tsconfig.json` — TS config.
- `poc/electron-app/vite.config.ts` — flat output (`dist/main.js`, `dist/preload.js`, `dist/renderer`).
- `poc/electron-app/vitest.config.ts` — Vitest config.
- `poc/electron-app/.gitignore` — local build/exclude rules.

### Packaging (byclaw DEB templates, self-contained)
- `poc/packaging/byclaw/DEBIAN/control.tmpl` — control; `Version` templated at build.
- `poc/packaging/byclaw/DEBIAN/postinst.tmpl` — atomic write `update-state.json` (`installedVersion` build-injected), install desktop + AppArmor reload.
- `poc/packaging/byclaw/DEBIAN/prerm` — refresh desktop cache.
- `poc/packaging/byclaw/DEBIAN/postrm` — purge-time system-side cleanup (never touches user Home).
- `poc/packaging/byclaw/etc/apparmor.d/com.lenovo.byclaw` — minimal AppArmor profile (precise path + `userns`, no setuid).
- `poc/packaging/byclaw/etc/lenovo/byclaw/config.json` — system config (`updatePolicyUrl`).
- `poc/packaging/byclaw/usr/share/applications/com.lenovo.byclaw.desktop` — desktop entry.

### Aptly repo
- `poc/apt-repository/aptly.conf` — fixed `rootDir`/`GNUPGHOME`, `FileSystemPublishEndpoints` local, no committed `gpgKey` fingerprint.

### Client config (byclaw-poc-repo-config)
- `poc/client-config/byclaw-poc-repo-config/etc/apt/sources.list.d/byclaw-poc.sources` — APT source; `Signed-By` keyring (not `Trusted: yes`).
- `poc/client-config/byclaw-poc-repo-config/etc/apt/apt.conf.d/60byclaw-poc-upgrades` — `Allowed-Origins {"Lenovo:noble"}`, `Package-Whitelist {"^byclaw$"}`.

### Scripts (normal user)
- `poc/scripts/build-version.sh` — single version source → 6-place consistent DEB (runs vitest + vite + electron-builder `--dir` + dpkg-deb).
- `poc/scripts/verify-versions.sh` — verify 6-place version consistency (build + post-publish).
- `poc/scripts/publish-byclaw.sh` — add + publish to the local aptly repo.
- `poc/scripts/set-update-policy.sh` — `none | optional | force` policy switch.
- `poc/scripts/make-icon.sh` — icon generation.

### Scripts (root — admin runs, never the app)
- `poc/scripts/install-client-config.sh` — ROOT: installs keyring + sources + apt.conf + systemd units, enables timer, `apt-get update`.

### systemd
- `poc/systemd/byclaw-poc-upgrade.service` — oneshot `unattended-upgrade -v` (Nice=19, idle I/O).
- `poc/systemd/byclaw-poc-upgrade.timer` — `OnBootSec=1min`, `OnUnitActiveSec=2min` (POC value).

### tests-v2 (18-case validation, 20 files)
- `poc/tests-v2/case-01.sh` … `poc/tests-v2/case-18.sh` — 18 case scripts.
- `poc/tests-v2/run-all-cases.sh` — master runner + verdict summary.
- `poc/tests-v2/screenshot.sh` — GUI screenshot harness (`scrot`, real Wayland session).

---

## Modified (M) — 5 files
- `.gitignore` — add byclaw build/evidence/GPG exclusion rules.
- `poc/electron-app/package.json` — Vue 3 + Vite + Electron + Vitest deps; `version` kept at `0.0.0-dev` baseline (product version injected at build, never hardcoded).
- `poc/electron-app/package-lock.json` — lockfile refresh for the new dependency tree.
- `poc/scripts/serve-repo.sh` — port `8099`, PID + log, `start|status|stop`, InRelease reachability check (was 8080/nanobot).
- `poc/scripts/setup-repo.sh` — aptly fixes: explicit `-config=`, fixed `rootDir`/`GNUPGHOME`, removed `|| true` / `2>/dev/null`, publish failure exits non-zero.

---

## Kept (unchanged from `main`) — old nanobot POC, not the product
- `LICENSE` — MIT, unchanged.
- `poc/README.md` — old nanobot deep-dive tutorial; still says "Lenovo Nanobot POC" prominently. **Kept; needs a Byclaw update — out of scope for this task (tracked here, not rewritten).**
- `poc/VALIDATION_REPORT.md` — old V1 report; kept unchanged. Its verdicts are not credible (报告与证据不一致，因此结果不可采信) — superseded by `poc/VALIDATION_REPORT_V2.md`.
- `poc/evidence/` — old V1 evidence (screenshots + command output); superseded by `poc/evidence-v2/`.
- `poc/apparmor/com.lenovo.nanobot`, `poc/apparmor/com.lenovo.nanobot.electron` — old over-wide nanobot profiles; unused by Byclaw (which ships its own minimal profile inside the DEB).
- `poc/scripts/60nanobot-poc-upgrades` — old nanobot unattended-upgrades config; unused by Byclaw.
- `poc/scripts/build-deb.sh`, `poc/scripts/init-oem.sh`, `poc/scripts/publish-1.1.sh`, `poc/scripts/setup-client-config.sh`, `poc/scripts/acceptance.sh`, `poc/scripts/cleanup-poc.sh` — old nanobot scripts; kept but unused by Byclaw.
- `poc/tests/` — old scenario scripts (A–I) + `run-all-tests.sh` + `results/`; superseded by `poc/tests-v2/`.
- Old nanobot client-config pieces — kept but unused by Byclaw; Byclaw uses its own `byclaw-poc-repo-config` tree (independent sources/keyring/`Allowed-Origins`, does not share with nanobot).

---

## This task (Task 11.1) — committed with this changelog
- `README.md` — **rewritten (M)**: Byclaw title, honest validation badge, reproducibility commands, architecture, security posture.
- `README.zh-CN.md` — **rewritten (M)**: Simplified-Chinese mirror with the same honest badge.
- `docs/deployment/private-apt-contract.md` — **new (A)**: production private-APT service interface contract (spec §14.10, not implemented in POC).
- `docs/byclaw-file-changelog.md` — **new (A)**: this file (self-referential).
