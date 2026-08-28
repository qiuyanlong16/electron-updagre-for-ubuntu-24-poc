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
> `BADSIG 8E461A79003247C0` (Case 09). Full real-run evidence:
> [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md). A 4-agent
> adversarial-verification workflow re-checked every verdict against the raw
> evidence; its flagged risks were re-captured or honestly scoped — no false
> PASS survives (V2 §6). The old `poc/VALIDATION_REPORT.md` (V1) is kept
> unchanged but its verdicts are **not credible**
> (报告与证据不一致，因此结果不可采信) — see V2 §结论摘要.

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
- A normal **non-root user never types a password**; the upgrade runs as root in
  the background, touches only package files, and never kills the running app.
- The Electron process is **sandboxed** (`app.enableSandbox()`, no `--no-sandbox`)
  and confined by a **minimal AppArmor profile** (precise path match + `userns`,
  no setuid `chrome-sandbox`).

> ⚠️ **This is a proof-of-concept, not a production update system.** The GPG key
> is a throwaway key with no passphrase, the repository is served over plain
> HTTP on `localhost`, the timer fires every 2 minutes (POC iteration speed), and
> the whole flow assumes a single trusted publisher. The production private-APT
> interface is defined as a contract only in
> [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md)
> (spec §14.10) — **not implemented** in this POC. See
> [Known limitations](#known-limitations--pre-production-fixes).

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
│ single-instance lock (requestSingleInstanceLock); first-upgrade banner   │
│ via last-run.ts (app.getPath('userData')/last-run.json).                 │
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

**Three roles, strictly separated** — `electron-builder` builds the app
runtime; `dpkg-deb` produces the system-level DEB; **APT** distributes and
upgrades the DEB with signature + hash verification; **`unattended-upgrades`
(root background)** downloads and installs; **Electron** only queries versions,
displays state, and relaunches itself — it never calls `apt`/`dpkg`/`sudo`/
`pkexec` (spec §6.4).

**Update state machine** — the main process computes one of seven states using
semver comparison (never string comparison):

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
installed" never freezes. Only `installedVersion > runningVersion` may enter
`READY_OPTIONAL`/`READY_FORCE`. The main process polls the state file every 5 s
(`setInterval` in `main.ts`) and pushes changes to the renderer via
`byclaw:update-state-changed`.

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

## Repository layout

```
.
├── README.md / README.zh-CN.md / LICENSE         # this file (bilingual) + MIT
├── docs/
│   ├── deployment/private-apt-contract.md          # production APT contract (§14.10)
│   ├── byclaw-file-changelog.md                    # file-level change log
│   └── superpowers/{specs,plans}/2026-08-27-…     # design spec + implementation plan
└── poc/
    ├── electron-app/                              # Vue 3 + Electron source
    │   ├── src/
    │   │   ├── main/      main.ts · update-service.ts · ipc.ts · last-run.ts
    │   │   ├── preload/   preload.ts (contextBridge, 5 methods)
    │   │   ├── renderer/  App.vue · components/ · composables/useUpdateState.ts
    │   │   └── shared/    semver.ts · state-machine.ts · upgrade-detect.ts · types/
    │   ├── electron-builder.yml · vite.config.ts · vitest.config.ts · package.json
    ├── scripts/                                   # build / publish / serve / verify
    ├── apt-repository/                            # aptly repo + GPG home (gitignored)
    ├── client-config/                             # sources · keyring · apt.conf · systemd units
    ├── tests-v2/                                  # 18 case scripts + run-all + screenshot
    ├── evidence-v2/                               # real-run evidence (verdicts + logs + PNGs)
    ├── VALIDATION_REPORT_V2.md                    # 18/18 PASS real-evidence report
    └── ROOT_OPS_RUNBOOK.md                        # step-by-step sudo runbook
```

Build artifacts are gitignored and regenerated locally — `poc/packages/` (DEBs +
extracted Electron runtime), `poc/electron-app/node_modules/`, `poc/dist-electron/`,
and the GPG material under `poc/apt-repository/gpg-home/` (never committed).

---

## Reproduce it

### Normal user (no sudo)

```bash
# 0. Clone and install build deps once (Node.js 22 + npm; system tools already
#    present on the validation host: aptly, gnupg2, apparmor, dpkg-deb).
git clone git@github.com:qiuyanlong16/electron-updagre-for-ubuntu-24-poc.git
cd electron-updagre-for-ubuntu-24-poc

# 1. One-time: create the aptly repo + throwaway GPG key (normal user only).
bash poc/scripts/setup-repo.sh

# 2. Build, publish, and serve four versioned DEBs. build-version.sh runs the
#    unit suite first, then vite build, electron-builder --dir, dpkg-deb --build;
#    verify-versions.sh checks the six-place consistency.
for v in 1.0.0 1.1.0 1.2.0 1.3.0; do
  bash poc/scripts/build-version.sh $v     # → poc/packages/byclaw_${v}_amd64.deb
  bash poc/scripts/publish-byclaw.sh $v    # → into aptly repo (re-signs InRelease)
done
bash poc/scripts/serve-repo.sh start       # serve on 127.0.0.1:8099 (| status | stop)

# 3. Run the unit suite alone (pure state-machine + update-service + semver +
#    upgrade-detect + restart-dedup, 5 test files, 40 cases).
cd poc/electron-app && npm ci && npx vitest run && cd ../..

# 4. Run the 18-case validation. Normal-user cases execute for real; root /
#    installed-app cases self-report NOT-TESTED until the root chain (below) is done.
bash poc/tests-v2/run-all-cases.sh

# 5. Switch the served update policy (none | optional | force).
bash poc/scripts/set-update-policy.sh optional 1.2.0
```

### Root install chain (operator runs `sudo` manually)

The installed-app / GUI / tamper cases need the client configured once. Each
step explains which system files it touches and pauses for you to run `sudo` —
**no `NOPASSWD`, no password handling**. Full sequence in
[`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md):

```bash
sudo dpkg -i poc/packages/byclaw_1.0.0_amd64.deb
sudo bash poc/scripts/install-client-config.sh   # sources + keyring + apt.conf + timer
sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw
sudo apt-get update                                # note: an unrelated fish-shell PPA 404s here
# drive each case per the runbook, then re-run its case-XX.sh; capture the four
# required GUI screenshots via poc/tests-v2/screenshot.sh.
```

> **Tip:** `/var/log/dpkg.log` on the validation host is detected as a *binary*
> file (a stray non-text byte), so plain `grep byclaw` silently returns nothing.
> Use `grep -a` (text mode) when grepping it — see V2 §5.

---

## Security posture

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
`install-client-config.sh`, run by the admin — never by the app. The app only
queries versions, displays state, and relaunches itself.

---

## Validation (18 cases — all PASS)

Real-run verdicts from [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md),
head `b3eabc6` on `feat/byclaw-vue3-redesign`:

| Case | Verifies | Verdict |
|---:|---|---|
| 01 | Two versioned DEBs build reproducibly (six-place version consistency) | **PASS** |
| 02 | `/opt/lenovo/byclaw` not writable by normal user | **PASS** |
| 03 | New user sees the app; OEM stage does not pollute future user Home | **PASS** |
| 04 | Electron runs as a normal user | **PASS** |
| 05 | preload/IPC isolation (5 methods, no forbidden requires, no raw ipcRenderer) | **PASS** |
| 06 | Sandbox on, no `--no-sandbox` | **PASS** |
| 07 | Minimal AppArmor profile enforces | **PASS** |
| 08 | APT signing + `Signed-By` + client config correct | **PASS** |
| 09 | Tampered `InRelease`/DEB rejected by APT (`BADSIG`) | **PASS** |
| 10 | Only Byclaw auto-upgraded, no password, no sudo | **PASS** |
| 11 | App not running → upgrade → next launch is the new version | **PASS** |
| 12 | App running during upgrade survives; detects install completion | **PASS** |
| 13 | Check-for-updates, no-update → correct LATEST prompt | **PASS** |
| 14 | New version not yet installed → prompt, no APT call | **PASS** |
| 15 | Optional upgrade → "restart now / later" | **PASS** |
| 16 | Forced upgrade → frozen UI, restart only | **PASS** |
| 17 | Restart runs new version + stays single-instance | **PASS** |
| 18 | User config / models preserved; offline old version still runs | **PASS** |

**Summary: 18 PASS · 0 FAIL · 0 NOT-TESTED · 0 false PASS.** The four required
GUI screenshots (LATEST, UPDATE_AVAILABLE, READY_OPTIONAL, READY_FORCE) were
captured with `gnome-screenshot` on the real Wayland session and additionally
confirmed by the live operator (the controller cannot render PNGs). Two bugs
that would have produced false verdicts (a mid-flight mis-capture quarantined
as `case-15-INVALID-*.png`; empty `grep` on binary-detected `dpkg.log`) were
caught and fixed before any verdict was recorded — exactly the discipline spec
§17.3 demands ("禁止用代码审查结论代替运行证据").

---

## Known limitations & pre-production fixes

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
