<div align="center">

# Byclaw — Electron Auto-Update for Ubuntu 24.04 (POC)

**A reproducible proof-of-concept for securely auto-updating a bundled
Electron (Vue 3 + TypeScript + Vite) desktop app on Ubuntu 24.04 via a
GPG-signed local APT repository, systemd timer, `unattended-upgrades`,
and a minimal AppArmor profile.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2024.04-E95420.svg)
![Validation](https://img.shields.io/badge/validation-2%20PASS%20%C2%B7%2016%20NOT--TESTED-yellow)

**English** · [中文](./README.zh-CN.md)

</div>

> **Honest validation status.** Of 18 acceptance cases, **2 PASS** (Case 01 —
> two-version DEB reproducible build; Case 05 — preload/IPC isolation) and
> **16 NOT-TESTED** (root / installed-app prerequisites not yet met). **0 FAIL,
> 0 false PASS.** The root-dependent cases are queued in
> [`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md) (~10–15 min of `sudo`).
> Full real-run evidence: [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md).
> The old `poc/VALIDATION_REPORT.md` (V1) is kept unchanged but its verdicts are
> **not credible** (报告与证据不一致，因此结果不可采信) — see V2 §结论摘要.

---

## Why this exists

Updating an Electron app on Linux usually means shipping a custom in-app
updater that downloads and replaces files at runtime. In enterprise / OEM
contexts that approach is awkward: it typically needs **root** (or
`pkexec`), frequently disables the Chromium **`--no-sandbox`** flag, and runs
the updater as a privileged process — all real security smells.

Byclaw explores an **OS-native** alternative, modeled on a factory image:

- The app is shipped as a **`.deb`** and hosted in a **GPG-signed local APT
  repository** (managed by `aptly`, served over HTTP on `127.0.0.1:8099`).
- Upgrades are performed by **Ubuntu's own `unattended-upgrades`**, driven by a
  **systemd timer** — the same mechanism that keeps your OS patched.
- A normal **non-root user never types a password**; the upgrade runs as root in
  the background, touches only package files, and never kills the running app.
- The Electron process is **sandboxed** (`app.enableSandbox()`, no `--no-sandbox`)
  and confined by a **minimal AppArmor profile** (precise path match + `userns`,
  no setuid `chrome-sandbox`).

> ⚠️ **This is a proof-of-concept, not a production update system.** The GPG key
> is a throwaway key with no passphrase, the repository is served over plain
> HTTP on `localhost`, and the whole flow assumes a single trusted publisher.
> The production private-APT interface is defined as a contract only in
> [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md)
> (spec §14.10) — **not implemented** in this POC.

---

## Architecture

```
┌── renderer (Vue 3 + TS + Vite) ───────────────────────────────────────┐
│  App.vue · VersionButton.vue · UpdateDialog.vue · useUpdateState()     │
│  (never reads system files, never calls apt/dpkg — no hardcoded version)│
└───────────────▲───────────────────────────────────contextBridge────────┘
                │ 5 safe IPC methods only
┌───────────────┴── preload (sandboxed) ─────────────────────────────────┐
│ getCurrentVersion · checkForUpdates · getUpdateState ·                  │
│ restartApplication · onUpdateStateChanged                               │
│ (no raw ipcRenderer, no child_process/fs/shell exposed)                 │
└───────────────▲─────────────────────────────────────────────────────────┘
                │ ipcMain.handle
┌───────────────┴── main process ───────────────────────────────────────┐
│ update-service: fetches update-policy.json (HTTP, 127.0.0.1:8099),      │
│ reads /var/lib/lenovo/byclaw/update-state.json, computes state via a     │
│ PURE state-machine (src/shared/state-machine.ts + semver.ts).            │
│ restart = app.relaunch(); app.exit(0) — no apt/dpkg/sudo/pkexec.         │
└───────────────▲─────────────────────────────────────────────────────────┘
                │ built + packaged (normal user, no root)
┌───────────────┴── delivery ────────────────────────────────────────────┐
│ vite build → electron-builder --dir (extraMetadata.version) →           │
│ dpkg-deb --build → byclaw_X.Y.Z_amd64.deb → installs to /opt/lenovo/byclaw│
│ aptly signed repo (Origin=Lenovo, Label=Byclaw, Suite=noble) →          │
│ unattended-upgrades (root, passwordless, no NOPASSWD) + systemd timer + │
│ minimal AppArmor profile (/etc/apparmor.d/com.lenovo.byclaw)            │
└──────────────────────────────────────────────────────────────────────────┘
```

**Update state machine** — the main process computes one of seven states using
semver comparison (never string comparison):

`CHECKING` · `LATEST` · `UPDATE_AVAILABLE` · `READY_OPTIONAL` ·
`READY_FORCE` · `RESTARTING` · `ERROR`

Only `READY_FORCE` (an installed version newer than the running one **and**
`mode=force`) freezes the UI; a server-only "new version available but not yet
installed" never freezes. Only `installedVersion > runningVersion` may enter
`READY_OPTIONAL`/`READY_FORCE`. `ERROR` never freezes and never blocks normal
use.

**Version source.** The displayed version is never hardcoded in any Vue page.
It comes from Electron's `app.getVersion()` (delivered to the renderer through
`getCurrentVersion()`). At build time `electron-builder` injects the version via
`extraMetadata.version` (the source `package.json` stays at the `0.0.0-dev`
baseline and is never rewritten). One build injects the version consistently
into **six** places, verified by `verify-versions.sh`:

1. `app.getVersion()` (product package.json via extraMetadata)
2. `DEBIAN/control` `Version`
3. `postinst` `installedVersion` written to `update-state.json`
4. DEB filename `byclaw_<VERSION>_amd64.deb`
5. `update-policy.json` `latestVersion` (a build artifact, not hand-maintained)
6. APT `Packages` index `Version` (from the deb control via aptly)

---

## Reproduce it (normal user, no sudo)

Everything below runs as a normal user. Root steps are optional and clearly
marked; they are queued in
[`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md).

```bash
# 0. Clone and install build deps once (Node.js 22 + npm; system tools already
#    present on the validation host: aptly, gnupg2, apparmor, dpkg-deb).
git clone git@github.com:qiuyanlong16/electron-updagre-for-ubuntu-24-poc.git
cd electron-updagre-for-ubuntu-24-poc

# 1. Build both versioned DEBs (reproducible). build-version.sh runs the unit
#    suite, then vite build, then electron-builder --dir, then dpkg-deb --build.
bash poc/scripts/build-version.sh 1.0.0    # → poc/packages/byclaw_1.0.0_amd64.deb
bash poc/scripts/build-version.sh 1.1.0    # → poc/packages/byclaw_1.1.0_amd64.deb

# 2. Run the unit suite alone (pure state-machine + update-service + semver +
#    upgrade-detect + restart-dedup, 5 test files).
cd poc/electron-app && npm ci && npx vitest run && cd ../..

# 3. Run the 18-case validation. Normal-user cases execute for real; root /
#    installed-app cases self-report NOT-TESTED (they never claim PASS without
#    real evidence — per spec §17.3).
bash poc/tests-v2/run-all-cases.sh

# 4. Serve the aptly repo on 127.0.0.1:8099 (start | status | stop).
bash poc/scripts/serve-repo.sh start
```

> Build artifacts are gitignored and regenerated locally — `poc/packages/`
> (DEBs + extracted Electron runtime), `poc/electron-app/node_modules/`, and the
> GPG material under `poc/apt-repository/gpg-home/` (never committed).

### Optional: complete the root-dependent validation

The 16 NOT-TESTED cases need the root install chain (install keyring + APT
source + unattended config + systemd timer, `dpkg -i`, AppArmor enforce,
tamper tests). Each step explains which system files it touches and pauses for
you to run `sudo` manually — **no NOPASSWD, no password handling**. Start in
[`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md), then re-run the matching
`case-XX.sh` and capture the four required GUI screenshots via
`poc/tests-v2/screenshot.sh`.

---

## Security posture

| Invariant | How it is upheld |
|---|---|
| GPG-signed APT repo, pinned by keyring | `Signed-By: /usr/share/keyrings/byclaw-poc.gpg`; **not** `Trusted: yes` |
| Electron sandbox on, `--no-sandbox` refused | `app.enableSandbox()` before `whenReady()`; `--no-sandbox` → `app.exit(1)` |
| `/opt/lenovo/byclaw` not writable by normal user | `root:root`, installed by `dpkg`; Case 02 |
| App never runs as root | launched as the consumer user; Case 04 |
| Minimal AppArmor profile | precise path match + `userns`; no `sys_admin`/`setuid`/`dac_read_search`; `chrome-sandbox` kept `0755` (not `4755`) |
| Unattended-upgrades passwordless | root background service; no `NOPASSWD`, no password handling |
| No `chmod 777` | never used anywhere |
| App runtime never invokes privileged tools | `sudo`/`pkexec`/`apt`/`apt-get`/`dpkg`/`dpkg-query`/`unattended-upgrade`/`systemctl` appear **only** in build scripts, the root install chain, and test scripts — never in the Electron app code (spec §6.4) |

All root work lives in the systemd unit / `postinst` /
`install-client-config.sh`, run by the admin — never by the app. The app only
queries versions, displays state, and relaunches itself.

---

## Validation (18 cases)

Real-run verdicts from [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md):

| Case | Verifies | Verdict |
|---:|---|---|
| 01 | Two versioned DEBs build reproducibly | **PASS** |
| 05 | preload/IPC isolation (5 methods, no forbidden requires, no raw ipcRenderer) | **PASS** |
| 02, 03, 04, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18 | root / installed-app / GUI cases | **NOT-TESTED** |

**Summary: 2 PASS · 16 NOT-TESTED · 0 FAIL · 0 false PASS.** During the real run
two bugs that would have produced false verdicts were caught and fixed before
any verdict was recorded (V2 §4) — exactly the discipline spec §17.3 demands
("禁止用代码审查结论代替运行证据").

---

## Pointers

| Document | What it is |
|---|---|
| [`poc/README.md`](./poc/README.md) | Deep-dive tutorial (kept from the prior POC; still references the old "nanobot" name and needs a Byclaw update — tracked in the changelog) |
| [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md) | Real-evidence validation report (source of truth for the badge above) |
| [`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md) | How to complete the 16 root-dependent cases |
| [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md) | Production private-APT service interface contract (spec §14.10, not implemented in POC) |
| [`docs/byclaw-file-changelog.md`](./docs/byclaw-file-changelog.md) | File-level modification list for this branch |
| [`docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md`](./docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md) | Full design spec |
| [`docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md`](./docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md) | Implementation plan |

---

## License

The source code in this repository is licensed under the **MIT License** — see
[`LICENSE`](./LICENSE).

The built `.deb` packages **bundle the Electron framework** (which embeds
Chromium and Node.js). Electron, Chromium, and Node.js are distributed under
their own open-source licenses; see `LICENSES.chromium.html` inside any built
package and <https://www.electronjs.org/docs/latest/tutorial/licenses>. This MIT
notice covers only the original code written for this proof-of-concept.
