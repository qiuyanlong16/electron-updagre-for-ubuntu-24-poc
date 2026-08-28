<div align="center">

# Byclaw — OS-Native Electron Auto-Update for Ubuntu 24.04

**A reproducible, validated proof-of-concept for securely auto-updating a
bundled Electron (Vue 3 + TypeScript + Vite) desktop app on Ubuntu 24.04 via a
GPG-signed local APT repository, a systemd timer, `unattended-upgrades`, and a
minimal AppArmor profile — no in-app downloader, no `--no-sandbox`, no
`NOPASSWD`, no password prompts.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2024.04-E95420.svg)
![Validation](https://img.shields.io/badge/validation-18%2F18%20PASS-brightgreen)

**English** · [中文](./README.zh-CN.md)

</div>

> **Validation status: 18 PASS · 0 FAIL · 0 NOT-TESTED · 0 false PASS.** Every
> one of the 18 acceptance cases ran on a real GNOME Wayland desktop
> (`XDG_SESSION_TYPE=wayland`), 2026-08-28 — no Xvfb, no code-review-as-truth.
> Two real `unattended-upgrade` cycles cover the core path:
> **1.1.0 → 1.2.0** (`mode=optional` → `READY_OPTIONAL`, operator restart →
> `LATEST`) and **1.2.0 → 1.3.0** (`mode=force` → `READY_FORCE` frozen UI,
> operator restart → 1.3.0). A tampered `InRelease` was rejected with
> `BADSIG 8E461A79003247C0` (Case 09). A post-rewrite regression run then
> upgraded **1.3.0 → 1.4.0** end-to-end to prove the docs change did not touch
> the upgrade chain. Full real-run evidence:
> [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md). The old
> `poc/VALIDATION_REPORT.md` (V1) is kept unchanged but its verdicts are
> **not credible** (报告与证据不一致，因此结果不可采信) — see V2 §结论摘要.

---

## Why this exists

Updating an Electron app on Linux usually means shipping a custom in-app
updater that downloads and replaces files at runtime. In enterprise / OEM
contexts that approach is awkward: it typically needs **root** (or `pkexec`),
frequently disables the Chromium **`--no-sandbox`** flag, and runs the updater
as a privileged process — all real security smells.

Byclaw explores an **OS-native** alternative, modeled on a factory image:

- The app is shipped as a **`.deb`** and hosted in a **GPG-signed local APT
  repository** (managed by `aptly`, served over HTTP on `127.0.0.1:8099`).
- Upgrades are performed by **Ubuntu's own `unattended-upgrades`**, driven by a
  **systemd timer** — the same mechanism that keeps your OS patched.
- A normal **non-root user never types a password**; the upgrade runs as root
  in the background, touches only package files, and never kills the running app.
- The Electron process is **sandboxed** (`app.enableSandbox()`, no `--no-sandbox`)
  and confined by a **minimal AppArmor profile** (precise path match + `userns`,
  no setuid `chrome-sandbox`).

> ⚠️ **This is a proof-of-concept, not a production update system.** The GPG key
> is a throwaway key with no passphrase, the repository is served over plain
> HTTP on `localhost`, the timer fires every 2 minutes (POC iteration speed),
> and the whole flow assumes a single trusted publisher. The production
> private-APT interface is defined as a contract only in
> [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md)
> (spec §14.10) — **not implemented** in this POC. See
> [Known limitations and pre-production fixes](#known-limitations-and-pre-production-fixes).

---

## What it proves

| Capability | Result |
|---|---|
| `.deb` is **self-contained** — bundles the Electron runtime + desktop entry + AppArmor profile + icon + config + maintainer scripts; installs to `/opt/lenovo/byclaw` (`root:root`) | ✅ |
| App auto-upgrades `1.3.0 → 1.4.0` with **zero user interaction** (root background, no password) | ✅ |
| Only `byclaw` upgrades — `Package-Whitelist {"^byclaw$"}` + `Package-Blacklist`; unrelated packages untouched | ✅ |
| Tampered `InRelease` / `.deb` are **rejected** by APT — GPG `BADSIG` + `SHA256`/`Size` mismatch | ✅ |
| Running app **survives** an in-place upgrade — `postinst` never kills the process; the 5 s poll detects the new `installedVersion` | ✅ |
| App runs as a **non-root** user; **no `sudo`/`pkexec`/`apt`/`dpkg`** in app code (spec §6.4) | ✅ |
| Chromium **sandbox enforced**; `--no-sandbox` is refused at runtime (`app.exit(1)`) | ✅ |
| **Minimal AppArmor** — single profile `flags=(unconfined)` + `userns`; `chrome-sandbox` kept `0755` (**not** setuid `4755`) | ✅ |
| User config + model files unchanged across upgrade (SHA-256 `a8332527…` matches before/after) | ✅ |
| App keeps running when the repository is offline (policy fetch failure → `ERROR`, never crashes) | ✅ |

---

## Architecture

### Two sides, strictly separated

```
┌─── OEM / publisher side (normal user, no root) ─────────────────────────────┐
│  electron-app/  ─build-version.sh─▶  byclaw_<ver>_amd64.deb               │
│  (Vue3 main/preload/   (bundles full       │  (self-contained: /opt/lenovo/ │
│   renderer + shared)    Electron runtime)   ▼   byclaw + desktop + apparmor)│
│                                   aptly repo add + publish update          │
│                                          │  (GPG-signed, Origin=Lenovo     │
│                                          ▼   Label=Byclaw Suite=noble)     │
│                           local APT repository  (aptly-db/public)          │
└──────────────────────────────────────────┬──────────────────────────────────┘
                                           │ HTTP  (python3 -m http.server :8099, 127.0.0.1)
                                           ▼
┌─── client / device side (root once, then unattended) ──────────────────────┐
│  /etc/apt/sources.list.d/byclaw-poc.sources  ──▶  apt-get update           │
│  /usr/share/keyrings/byclaw-poc.gpg            (verifies signatures)       │
│  /etc/apt/apt.conf.d/60byclaw-poc-upgrades     (Allowed-Origins Lenovo:noble│
│                                                 Whitelist ^byclaw$)        │
│  byclaw-poc-upgrade.timer  (OnBootSec=1min, OnUnitActiveSec=2min)          │
│        │                                                                    │
│        ▼                                                                    │
│  byclaw-poc-upgrade.service ─▶ unattended-upgrade -v ─▶ dpkg install       │
│   (oneshot, Nice=19,           (whitelist ^byclaw$,         (1.3.0 → 1.4.0) │
│    IOSchedulingClass=idle)      blacklist unrelated-…)                      │
│  /opt/lenovo/byclaw/byclaw   (root:root 0755)                              │
│      └── resources/app.asar  (AppArmor (unconfined)+userns · sandbox · non-root)│
│  /var/lib/lenovo/byclaw/update-state.json  ← postinst atomic write         │
│   (installedVersion) → main process polls every 5 s → READY_OPTIONAL / READY_FORCE│
└─────────────────────────────────────────────────────────────────────────────┘
```

**Three roles** — `electron-builder` builds the app runtime; `dpkg-deb`
produces the system-level DEB; **APT** distributes and upgrades the DEB with
signature + hash verification; **`unattended-upgrades` (root background)**
downloads and installs; **Electron** only queries versions, displays state,
and relaunches itself — it never calls `apt`/`dpkg`/`sudo`/`pkexec`.

### Inside the Electron app

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
│ single-instance lock (requestSingleInstanceLock); first-upgrade banner   │
│ via last-run.ts (app.getPath('userData')/last-run.json).                 │
└──────────────────────────────────────────────────────────────────────────┘
```

### Update state machine — 7 states, semver comparison (never string)

`CHECKING` · `LATEST` · `UPDATE_AVAILABLE` · `READY_OPTIONAL` ·
`READY_FORCE` · `RESTARTING` · `ERROR`

- `latestVersion <= runningVersion` → `LATEST`.
- `latestVersion > runningVersion` and `installedVersion <= runningVersion` →
  `UPDATE_AVAILABLE` (new version announced but not yet installed in background).
- `installedVersion > runningVersion` and `mode=optional` → `READY_OPTIONAL`
  ("restart now / later").
- `installedVersion > runningVersion` and `mode=force` → `READY_FORCE` (frozen
  UI, restart only).
- `ERROR` (policy fetch / state-file failure) never freezes and never blocks
  normal use; the app falls back to `runningVersion` and keeps running.

Only `READY_FORCE` (an installed version newer than the running one **and**
`mode=force`) freezes the UI; a server-only "new version available but not yet
installed" never freezes. The main process polls the state file every 5 s
(`setInterval` in `main.ts`) and pushes changes to the renderer via
`byclaw:update-state-changed`.

### Version source — six places, one build, verified

The displayed version is never hardcoded in any Vue page. It comes from
Electron's `app.getVersion()`. At build time `electron-builder` injects it via
`extraMetadata.version` (source `package.json` stays at the `0.0.0-dev`
baseline, never rewritten). One build stamps the version consistently into
**six** places, checked by `verify-versions.sh`:

1. `app.getVersion()` (product package.json via extraMetadata)
2. `DEBIAN/control` `Version`
3. `postinst` `installedVersion` written to `update-state.json`
4. DEB filename `byclaw_<VERSION>_amd64.deb`
5. `update-policy.json` `latestVersion` (a build artifact, not hand-maintained)
6. APT `Packages` index `Version` (from the deb control via aptly)

---

## Project structure

```
.
├── LICENSE / README.md / README.zh-CN.md       # MIT + bilingual READMEs
├── docs/
│   ├── deployment/private-apt-contract.md        # production APT contract (spec §14.10)
│   ├── byclaw-file-changelog.md                  # file-level change log
│   └── superpowers/{specs,plans}/2026-08-27-…    # design spec (14 sections) + impl plan
└── poc/
    ├── electron-app/                            # Vue 3 + Electron source (see "inside" above)
    │   ├── src/main/      main.ts · update-service.ts · ipc.ts · last-run.ts
    │   ├── src/preload/   preload.ts (contextBridge, 5 methods)
    │   ├── src/renderer/  App.vue · components/ · composables/useUpdateState.ts
    │   ├── src/shared/    semver.ts · state-machine.ts · upgrade-detect.ts · types/
    │   └── electron-builder.yml · vite.config.ts · vitest.config.ts · package.json
    ├── scripts/                                 # build / publish / serve / verify (see Scripts reference)
    ├── apt-repository/                          # aptly repo + GPG home — gitignored
    ├── client-config/                           # byclaw-poc.sources · keyring · 60byclaw-poc-upgrades
    ├── systemd/                                 # byclaw-poc-upgrade.{service,timer}
    ├── tests-v2/                                # case-01..18.sh + run-all-cases.sh + screenshot.sh
    ├── evidence-v2/                             # real-run evidence (verdicts + logs + PNGs) — gitignored
    ├── VALIDATION_REPORT_V2.md                  # 18/18 PASS real-evidence report
    └── ROOT_OPS_RUNBOOK.md                      # step-by-step sudo runbook
```

> Build artifacts are intentionally **not** committed (see
> [What is NOT in this repo](#what-is-not-in-this-repo)). Clone, run the
> scripts, and they regenerate locally.

---

## Requirements

- **Ubuntu 24.04 LTS** (Noble Numbat), `amd64`. Validated on a real GNOME
  **Wayland** session, kernel `7.0.0-30-generic`.
- **root** (`sudo`) — only for the one-time client setup (`install-client-config.sh`,
  `dpkg -i`, `apparmor_parser`, `apt-get update`, `systemctl`). Run manually;
  **no `NOPASSWD`, no password handling**.
- System packages: `aptly`, `gnupg2`, `python3` (HTTP server),
  `apparmor` / `apparmor-utils`, `unattended-upgrades`, `dpkg-deb`, `systemd`.
- **Node.js 22 + npm** — only to fetch the Electron 43.4.1 runtime that gets
  bundled into the `.deb`.
- GUI validation (optional): `gnome-screenshot` (works non-interactively on
  GNOME Wayland).

---

## Quick start

The whole flow is driven by shell scripts. Canonical reproduction:

```bash
# 1. Clone and install build deps once (normal user; system tools via apt).
git clone git@github.com:qiuyanlong16/electron-updagre-for-ubuntu-24-poc.git
cd electron-updagre-for-ubuntu-24-poc
bash poc/scripts/bootstrap.sh                 # one-shot dep installer (no sudo)
cd poc/electron-app && npm ci && cd ../..     # pulls electron 43.4.1 into node_modules/

# 2. One-time: create the aptly repo + throwaway GPG key (normal user only).
bash poc/scripts/setup-repo.sh

# 3. Build, publish, and serve four versioned DEBs. build-version.sh runs the
#    unit suite first, then vite build, electron-builder --dir, dpkg-deb --build,
#    then verify-versions.sh (six-place consistency).
for v in 1.0.0 1.1.0 1.2.0 1.3.0; do
  bash poc/scripts/build-version.sh $v       # → poc/packages/byclaw_${v}_amd64.deb
  bash poc/scripts/publish-byclaw.sh $v      # → into aptly repo (re-signs InRelease)
done
bash poc/scripts/serve-repo.sh start         # serve on 127.0.0.1:8099 (| status | stop)

# 4. ROOT (one-time client setup — run manually, each step explains what it touches):
sudo dpkg -i poc/packages/byclaw_1.0.0_amd64.deb
sudo bash poc/scripts/install-client-config.sh   # sources + keyring + apt.conf + timer
sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw

# 5. Publish a newer version + flip the policy to optional/force.
bash poc/scripts/build-version.sh 1.1.0 && bash poc/scripts/publish-byclaw.sh 1.1.0
bash poc/scripts/set-update-policy.sh optional 1.1.0

# 6. ROOT: refresh + trigger the upgrade (or just wait ≤ 2 min for the timer).
sudo apt-get update                            # note: an unrelated fish-shell PPA 404s here
sudo systemctl start byclaw-poc-upgrade.service

# 7. Verify the auto-upgrade happened.
dpkg-query -W byclaw                           # → byclaw  1.1.0
cat /var/lib/lenovo/byclaw/update-state.json  # → installedVersion: 1.1.0
grep -a byclaw /var/log/dpkg.log | tail        # NOTE: -a (dpkg.log is binary-detected)
```

### Verify the security posture

```bash
sudo aa-status | grep -i byclaw                # AppArmor profile loaded
ps -eo user,args | grep '[b]yclaw'             # runs as the consumer user, not root
ps -C byclaw -o args= | grep -c -- '--no-sandbox'   # → 0
ps -C byclaw -o args= | grep -c -- '--enable-sandbox'  # → ≥1 (renderer + network service)
```

### Run the automated tests

```bash
bash poc/tests-v2/run-all-cases.sh            # 18 cases; root cases self-report NOT-TESTED
                                               # until the root chain is done
cd poc/electron-app && npx vitest run          # 40 unit cases (state machine + semver + …)
```

### Clean up

There is no dedicated cleanup script (unlike the prior nanobot POC). Remove
what the POC installed, manually:

```bash
sudo apt-get purge -y byclaw
sudo rm -f /etc/apt/sources.list.d/byclaw-poc.sources /usr/share/keyrings/byclaw-poc.gpg
sudo rm -f /etc/apt/apt.conf.d/60byclaw-poc-upgrades
sudo systemctl disable --now byclaw-poc-upgrade.timer 2>/dev/null
sudo rm -f /etc/systemd/system/byclaw-poc-upgrade.{service,timer}
bash poc/scripts/serve-repo.sh stop
```

---

## How the auto-upgrade works

1. **`setup-repo.sh`** (normal user) generates a throwaway, passphrase-less GPG
   key into a fixed `GNUPGHOME`, creates the `aptly` repo `byclaw-poc`
   (`Origin=Lenovo`, `Label=Byclaw`), publishes it
   (`-distribution=noble -component=main`), and exports the public key.
2. **`build-version.sh <ver>`** runs the unit suite, then `vite build`
   (renderer + main + preload), `electron-builder --dir`
   (`extraMetadata.version=<ver>` — does **not** mutate source `package.json`),
   assembles a self-contained staging tree (`/opt/lenovo/byclaw` + desktop entry
   + AppArmor profile + icon + `/etc/lenovo/byclaw/config.json` +
   `/var/lib/lenovo/byclaw/` placeholder + `DEBIAN/{control,postinst,prerm,postrm}`,
   with `postinst`'s `installedVersion` injected at build time), and
   `dpkg-deb --root-owner-group --build`s the DEB. `verify-versions.sh` checks
   six-place consistency.
3. **`publish-byclaw.sh <ver>`** runs `aptly repo add` + `publish update`,
   re-signing `InRelease`/`Release`, then re-verifies the `Packages` index
   `Version` equals `<ver>`.
4. **`serve-repo.sh start`** serves `aptly-db/public` over HTTP on
   `127.0.0.1:8099` (carrying `dists/`, `pool/`, and `update-policy.json`).
5. **`install-client-config.sh`** (root, once) installs the APT source
   (`byclaw-poc.sources` with `Signed-By`, **not** `Trusted: yes`), the repo
   public key to `/usr/share/keyrings/byclaw-poc.gpg`, the
   `60byclaw-poc-upgrades` apt.conf (`Allowed-Origins {"Lenovo:noble"}`,
   `Package-Whitelist {"^byclaw$"}`, `Package-Blacklist`), and the
   `byclaw-poc-upgrade.{service,timer}`; enables the timer.
6. The **`byclaw-poc-upgrade.timer`** (`OnBootSec=1min`, `OnUnitActiveSec=2min`)
   fires **`byclaw-poc-upgrade.service`** — a `oneshot` running
   `unattended-upgrade -v` as root at `Nice=19`, `IOSchedulingClass=idle`.
   `dpkg` swaps the files on disk (`1.3.0 → 1.4.0`); the already-running
   process keeps its in-memory image, so the app is **not** killed mid-flight.
7. **`postinst`** atomically writes `installedVersion=1.4.0` to
   `/var/lib/lenovo/byclaw/update-state.json` (temp-file + `mv`, `root:root 0644`);
   it refreshes the desktop DB and reloads AppArmor (both soft-fail). It does
   **not** restart any process.
8. The running app's 5 s poll reads `installedVersion(1.4.0) > running(1.3.0)`
   + `mode` → `READY_OPTIONAL` / `READY_FORCE`. The user clicks "restart now" →
   `app.relaunch(); app.exit(0)` → the new process loads the 1.4.0 binary →
   `LATEST`. Because updates come through the signed APT channel, **tampering
   with `InRelease` or the `.deb` is detected** (`BADSIG` / hash mismatch) and
   the upgrade is refused — verified by Case 09.

---

## Security model

| Invariant | How it is upheld | Evidence |
|---|---|---|
| GPG-signed APT repo, pinned by keyring | `Signed-By: /usr/share/keyrings/byclaw-poc.gpg`; **not** `Trusted: yes` | Case 08; BADSIG Case 09 |
| Tampered repo/DEB rejected by APT alone | `InRelease` inline-signed; `Packages` carries `SHA256`+`Size`; APT verifies before install | Case 09 (`BADSIG …`) |
| Electron sandbox on, `--no-sandbox` refused | `app.enableSandbox()` before `whenReady()`; `--no-sandbox` → `app.exit(1)` | Case 06 |
| `/opt/lenovo/byclaw` not writable by normal user | `root:root`, installed by `dpkg` | Case 02 |
| App never runs as root | launched as the consumer user | Case 04 |
| Minimal AppArmor profile | precise path match + `userns`, `flags=(unconfined)`; no `sys_admin`/`setuid`/`dac_read_search`; `chrome-sandbox` kept `0755` (not `4755`) | Case 07 |
| Unattended-upgrades passwordless, Byclaw-only | root background service; `Package-Whitelist {"^byclaw$"}` + `Package-Blacklist`; no `NOPASSWD` | Case 10 |
| No `chmod 777` | never used anywhere | — |
| App runtime never invokes privileged tools | `sudo`/`pkexec`/`apt`/`apt-get`/`dpkg`/`dpkg-query`/`unattended-upgrade`/`systemctl` appear **only** in build scripts, the root install chain, and test scripts — never in the Electron app code (spec §6.4) | Case 14 |
| User data + models survive upgrade | `postinst` never touches `~/.config`; `postrm` purge cleans system paths only | Case 18 |

All root work lives in the systemd unit / `postinst` /
`install-client-config.sh`, run by the admin — never by the app.

---

## Validation (18 cases — all PASS)

Real-run verdicts from [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md),
head `b3eabc6` on `feat/byclaw-vue3-redesign`:

| Case | Verifies | | Case | Verifies |
|---:|---|---|---:|---|
| 01 | Two versioned DEBs build reproducibly (six-place consistency) | | 10 | Only Byclaw auto-upgraded, no password, no sudo |
| 02 | `/opt/lenovo/byclaw` not writable by normal user | | 11 | App not running → upgrade → next launch is new version |
| 03 | New user sees the app; OEM stage does not pollute future Home | | 12 | App running during upgrade survives; detects completion |
| 04 | Electron runs as a normal user | | 13 | Check-for-updates, no-update → correct LATEST prompt |
| 05 | preload/IPC isolation (5 methods, no forbidden requires, no raw ipcRenderer) | | 14 | New version not yet installed → prompt, no APT call |
| 06 | Sandbox on, no `--no-sandbox` | | 15 | Optional upgrade → "restart now / later" |
| 07 | Minimal AppArmor profile enforces | | 16 | Forced upgrade → frozen UI, restart only |
| 08 | APT signing + `Signed-By` + client config correct | | 17 | Restart runs new version + stays single-instance |
| 09 | Tampered `InRelease`/DEB rejected by APT (`BADSIG`) | | 18 | User config/models preserved; offline old version still runs |

**Summary: 18 PASS · 0 FAIL · 0 NOT-TESTED · 0 false PASS.** The four required
GUI screenshots (LATEST, UPDATE_AVAILABLE, READY_OPTIONAL, READY_FORCE) were
captured with `gnome-screenshot` on the real Wayland session and additionally
confirmed by the live operator. Two bugs that would have produced false
verdicts (a mid-flight mis-capture quarantined as `case-15-INVALID-*.png`;
empty `grep` on binary-detected `dpkg.log`) were caught and fixed before any
verdict was recorded — the discipline spec §17.3 demands
("禁止用代码审查结论代替运行证据").

---

## Scripts reference

| Script | Purpose |
|---|---|
| `scripts/bootstrap.sh` | One-shot dependency installer (normal user, no sudo) |
| `scripts/setup-repo.sh` | Generate GPG key + create + publish the signed aptly repo (`byclaw-poc`) |
| `scripts/build-version.sh <ver>` | Build `byclaw_<ver>.deb` (tests → vite → electron-builder → dpkg-deb → verify) |
| `scripts/publish-byclaw.sh <ver>` | Add + re-publish a version into aptly (re-signs `InRelease`) |
| `scripts/serve-repo.sh {start\|status\|stop}` | Serve the repo over HTTP on `127.0.0.1:8099` (PID + log) |
| `scripts/set-update-policy.sh {none\|optional\|force} [ver]` | Flip the served `update-policy.json` mode + latestVersion |
| `scripts/install-client-config.sh` | **ROOT**: install APT source + keyring + apt.conf + systemd units |
| `scripts/verify-versions.sh <ver> [--published <url>]` | Six-place version consistency check (build-time + post-publish) |
| `scripts/make-icon.sh` | Generate a 256×256 PNG icon if none exists |
| `tests-v2/run-all-cases.sh` | 18-case validation runner |
| `tests-v2/screenshot.sh` | GUI screenshot helper (real Wayland session) |

---

## What is NOT in this repo

These are **regenerated locally** — gitignored so the clone stays small and no
secrets leak:

| Path | Why excluded | How to regenerate |
|---|---|---|
| `poc/packages/` | Build output: `.deb`s + extracted Electron runtimes | `scripts/build-version.sh <ver>` |
| `poc/electron-app/node_modules/` | npm dependency tree | `npm ci` in `poc/electron-app/` |
| `poc/dist-electron/` | `electron-builder --dir` output | `scripts/build-version.sh` |
| `poc/apt-repository/gpg-home/` | **GPG private key + keyring — never commit** | `scripts/setup-repo.sh` |
| `poc/apt-repository/aptly-db/` | aptly database + published indices | `setup-repo.sh` + `publish-byclaw.sh` |
| `poc/logs/`, `poc/tests-v2/results/` | Runtime logs / test output | run the scripts/tests |
| `poc/evidence-v2/*` | Real-run evidence (verdicts + logs + PNGs) | re-run `tests-v2/` (`!.gitkeep` is kept) |

> 🔑 The GPG key under `gpg-home/` is a **throwaway** key generated fresh on
> every `setup-repo.sh` run. It is never committed. If you ever find key
> material checked in, treat it as compromised and regenerate.

---

## Troubleshooting

- **Timer never upgrades anything** → check
  `systemctl status byclaw-poc-upgrade.timer` is `active (waiting)`, then
  `journalctl -u byclaw-poc-upgrade.service -e`. Confirm the repo
  `Origin`/`Label` matches `Allowed-Origins`:
  `curl -s http://127.0.0.1:8099/dists/noble/Release | grep -E '^(Origin|Label):'`
  (must be `Lenovo` / `Byclaw`).
- **AppArmor denies** → `sudo dmesg | grep -i apparmor | grep -i denied`, add
  the missing path to the profile, then
  `sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw`.
- **`apt` doesn't see the new version** →
  `sudo rm -rf /var/lib/apt/lists/*byclaw* && sudo apt-get update`, then
  `apt-cache policy byclaw`. (An unrelated `fish-shell` PPA 404 makes
  `apt-get update` exit non-zero — unrelated to Byclaw; remove with
  `sudo rm /etc/apt/sources.list.d/*fish*`.)
- **`grep byclaw /var/log/dpkg.log` returns nothing** → the file is
  binary-detected (a stray non-text byte); use `grep -a byclaw` (text mode).
- **Electron launches and exits 0 with no window** → the VS Code extension
  host exports `ELECTRON_RUN_AS_NODE=1`, so the app starts as a Node process.
  Prefix the launch with `env -u ELECTRON_RUN_AS_NODE` (the user's own terminal
  does not have this variable).
- **No GUI / headless** → Byclaw is validated on a **real** Wayland session
  (spec §17.4 — Xvfb is not a substitute). For a real session use
  `DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0`.

The full step-by-step sudo runbook for every root case lives in
[`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md).

---

## Known limitations and pre-production fixes

These do **not** affect the POC conclusion (the auto-update pattern is
validated), but must be addressed before mass production:

- **`/etc/lenovo/byclaw/config.json` is not a dpkg conffile.** It survives a DEB
  upgrade today only because the packaged default is byte-identical across
  1.0.0/1.1.0/1.2.0/1.3.0 (sha `a8332527…`, proven by Case 18). A *customized*
  config would be clobbered by a subsequent upgrade. **Fix:** declare it a
  conffile so local edits survive.
- **Plain HTTP on `127.0.0.1:8099`, throwaway passphrase-less GPG key, 2-minute
  timer.** POC-only. Production must use HTTPS, a managed signing key (HSM,
  passphrase, expiry, rotation/revocation), and a daily/policy-driven timer —
  see [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md).
- **`Package-Whitelist` is not strict** → paired with a `Package-Blacklist`
  (known POC limitation, spec §21).
- **Unrelated `fish-shell` PPA 404** on the validation host makes
  `apt-get update` exit non-zero; unrelated to Byclaw (the Byclaw indices fetch
  fine). Remove with `sudo rm /etc/apt/sources.list.d/*fish*`.

---

## Pointers

| Document | What it is |
|---|---|
| [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md) | Real-evidence validation report (18/18 PASS) — source of truth for the badge above |
| [`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md) | Step-by-step sudo runbook for the root install chain + 18 cases |
| [`poc/evidence-v2/EVIDENCE_NOTES.md`](./poc/evidence-v2/EVIDENCE_NOTES.md) | Per-case evidence table + lessons (e.g. `grep -a` on `dpkg.log`) |
| [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md) | Production private-APT service interface contract (spec §14.10, not implemented in POC) |
| [`docs/byclaw-file-changelog.md`](./docs/byclaw-file-changelog.md) | File-level modification list for this branch |
| [`docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md`](./docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md) | Full design spec (14 sections) |
| [`docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md`](./docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md) | Implementation plan |
| [`poc/README.md`](./poc/README.md) | Deep-dive tutorial (kept from the prior POC; still uses the old "nanobot" name and has dangling script references — tracked in the changelog) |

---

## License

The source code in this repository is licensed under the **MIT License** — see
[`LICENSE`](./LICENSE).

The built `.deb` packages **bundle the Electron framework** (which embeds
Chromium and Node.js). Electron, Chromium, and Node.js are distributed under
their own open-source licenses; see `LICENSES.chromium.html` inside any built
package and <https://www.electronjs.org/docs/latest/tutorial/licenses>. This MIT
notice covers only the original code written for this proof-of-concept.

---

## Acknowledgements

Built as a research POC to validate an OS-native, APT-based auto-update pattern
for Electron apps on Ubuntu 24.04. Thanks to the maintainers of `aptly`,
`unattended-upgrades`, AppArmor, and Electron — the heavy lifting is all theirs.
