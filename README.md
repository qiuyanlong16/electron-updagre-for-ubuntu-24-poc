<div align="center">

# Electron Auto-Update for Ubuntu 24.04 (POC)

**A reproducible proof-of-concept for securely auto-updating a bundled
Electron desktop app on Ubuntu 24.04 via a GPG-signed local APT repository,
systemd timers, `unattended-upgrades`, and a dual AppArmor profile.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2024.04-E95420.svg)
![Status](https://img.shields.io/badge/Status-POC-18%2F18%20PASS-brightgreen.svg)

**English** · [中文](./README.zh-CN.md)

</div>

---

## Why this exists

Updating an Electron app on Linux usually means shipping a custom in-app
updater that downloads and replaces files at runtime. In enterprise / OEM
contexts that approach is awkward: it typically needs **root** (or
`pkexec`), frequently disables the Chromium **`--no-sandbox`** flag, and runs
the updater as a privileged process — all of which are real security smells.

This POC explores an **OS-native** alternative, modeled on a factory image:

- The app is shipped as a **`.deb`** and hosted in a **GPG-signed local APT
  repository** (managed by `aptly`, served over HTTP).
- Upgrades are performed by **Ubuntu's own `unattended-upgrades`**, driven by a
  **systemd timer** — exactly the same mechanism that keeps your OS patched.
- A normal **non-root user never types a password**; the upgrade runs as root
  in the background, touches only package files, and never kills the running app.
- The Electron process is **sandboxed** (`app.enableSandbox()`, no
  `--no-sandbox`) and confined by a **dual AppArmor profile**.

Everything is validated against **18 acceptance cases** — all passing on a clean
Ubuntu 24.04.4 LTS machine. See [`poc/VALIDATION_REPORT.md`](./poc/VALIDATION_REPORT.md).

> ⚠️ **This is a proof-of-concept, not a production update system.** The GPG key
> is a throwaway key with no passphrase, the repository is served over plain
> HTTP on `localhost`, and the whole flow assumes a single trusted OEM/publisher.
> Use it to learn and validate the *pattern*, then harden before any real use.

---

## What it proves

| Capability | Result |
|---|---|
| `.deb` bundles the full Electron runtime, installs to `/opt/lenovo/nanobot` (`root:root`) | ✅ |
| App auto-upgrades `1.0.0 → 1.1.0` (and beyond) with **zero user interaction** | ✅ |
| Only `nanobot` upgrades; unrelated repo packages are **blacklisted** | ✅ |
| Tampered `InRelease` / `.deb` are **rejected** by GPG signature + hash checks | ✅ |
| Running app **survives** an in-place upgrade (process is not killed) | ✅ |
| App runs as a **non-root** user; **no `sudo`/`pkexec`/`apt`/`dpkg`** in app code | ✅ |
| Chromium **sandbox enforced**; `--no-sandbox` is refused at runtime | ✅ |
| **Dual AppArmor** profiles (launcher + Electron) in `enforce` mode | ✅ |
| User config + model files unchanged across upgrade (SHA-256 matches) | ✅ |
| App keeps running when the repository is offline | ✅ |

---

## Architecture

```
┌──────────────────────────── OEM / publisher side ────────────────────────────┐
│                                                                              │
│  electron-app/      ─build-deb.sh─▶  nanobot-<ver>.deb                       │
│  (main / preload /        (bundles full        │                              │
│   renderer / index)       Electron runtime)    ▼                              │
│                                       aptly repo add + publish               │
│                                              │  (GPG-signed,                 │
│                                              ▼   Origin=Lenovo Label=Nanobot)│
│                                   local APT repository  (~/.aptly/public)     │
└──────────────────────────────────────────────┬───────────────────────────────┘
                                               │ HTTP  (nginx or python3 :8080)
                                               ▼
┌──────────────────────────── client / device side ────────────────────────────┐
│                                                                              │
│  /etc/apt/sources.list.d/nanobot-poc.sources  ──▶  apt-get update             │
│  /usr/share/keyrings/nanobot-poc.gpg            (verifies signatures)        │
│                                                                              │
│  nanobot-poc-upgrade.timer  (every 2 min)                                     │
│        │                                                                     │
│        ▼                                                                     │
│  nanobot-poc-upgrade.service  ──▶  unattended-upgrade  ──▶  dpkg install      │
│   (oneshot, Nice=19,            (whitelist ^nanobot$,         (1.0.0 → 1.1.0)  │
│    idle I/O)                    blacklist unrelated-…)                        │
│                                                                              │
│  /opt/lenovo/nanobot/nanobot         (launcher, root:root, 0755)              │
│      └── Px ──▶ /opt/lenovo/nanobot/electron/electron                        │
│                  (AppArmor enforce · Chromium sandbox · non-root user)        │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## Project structure

```
.
├── LICENSE                         # MIT (for this POC's own source)
├── README.md                       # you are here (English)
├── README.zh-CN.md                 # 中文概览
└── poc/
    ├── README.md                   # 完整中文分步教程 (deep-dive tutorial, kept as-is)
    ├── VALIDATION_REPORT.md        # 18-case validation report (100% PASS)
    ├── electron-app/               # the Electron app source (main/preload/renderer/index)
    ├── packaging/                  # nanobot.desktop entry
    ├── apparmor/                   # dual AppArmor profiles (launcher + electron)
    ├── systemd/                    # upgrade timer + oneshot service
    ├── client-config/              # APT source + unattended-upgrades config package
    ├── apt-repository/             # generated repo state (GPG key, aptly) — gitignored
    ├── scripts/                    # build / setup / publish / serve / cleanup / acceptance
    ├── tests/                      # scenario scripts A–I + master runner
    └── evidence/                   # screenshots + command output from the validation run
```

> Build artifacts are intentionally **not** committed (see
> [What is NOT in this repo](#what-is-not-in-this-repo)). Clone, run the
> scripts, and they are regenerated locally.

---

## Requirements

- **Ubuntu 24.04 LTS** (Noble Numbat), `amd64`. Validated on **24.04.4**,
  kernel `7.0.0-28-generic`.
- **root** (`sudo`) for the system-level setup scripts.
- System packages: `aptly`, `gnupg2`, `nginx` (or `python3` as a fallback
  HTTP server), `apparmor`, `unattended-upgrades`, `dpkg-deb`, `systemd`.
- **Node.js 22 + npm** — only to fetch the Electron runtime that gets bundled
  into the `.deb`.
- For GUI/headless testing (optional): `xvfb`, `scrot`, `xdotool`,
  `imagemagick`.

---

## Quick start

The whole thing is driven by shell scripts. The canonical reproduction is:

```bash
# 1. Clone and enter the POC directory
git clone git@github.com:qiuyanlong16/electron-updagre-for-ubuntu-24-poc.git
cd electron-updagre-for-ubuntu-24-poc/poc

# 2. Install system dependencies
sudo apt-get update
sudo apt-get install -y aptly gnupg2 nginx python3 \
                        unattended-upgrades apparmor-utils dpkg-dev

# 3. Install Node.js 22 (needed to fetch the Electron runtime)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
cd electron-app && npm install && cd ..        # pulls electron into node_modules/

# 4. One-shot OEM-stage setup:
#      builds + installs nanobot 1.0.0
#      creates a throwaway GPG key + signed local APT repo
#      installs client APT source + unattended-upgrades config
#      installs the desktop entry + dual AppArmor profiles
#      installs + enables the 2-minute upgrade timer
#      starts the HTTP repository server on :8080
sudo ./scripts/init-oem.sh

# 5. Create a non-root user that the app will run as
sudo useradd -m -s /bin/bash nanobot-testuser
sudo passwd nanobot-testuser          # only needed to log in / launch the GUI

# 6. Simulate the OEM publishing a new version (builds + publishes 1.1.0)
./scripts/publish-1.1.sh

# 7. Trigger the upgrade immediately (or just wait ≤ 2 min for the timer)
sudo systemctl start nanobot-poc-upgrade.service

# 8. Verify the auto-upgrade happened
dpkg-query -W nanobot                  # → nanobot  1.1.0
```

### Verify the security posture

```bash
sudo aa-status | grep nanobot          # both profiles in (enforce)
ps -eo user,args | grep '[e]lectron'  # runs as nanobot-testuser, not root
                                       # no --no-sandbox; renderer has --enable-sandbox
```

### Run the automated tests

```bash
sudo ./scripts/acceptance.sh           # fast smoke test (~20 checks)
sudo ./tests/run-all-tests.sh          # full scenario suite A–I (needs the test user + a display)
```

### Clean up

```bash
sudo ./scripts/cleanup-poc.sh          # removes packages, timer, profiles, repo config, test user
```

> The detailed, heavily-commented walkthrough of **every** command and concept
> (in Chinese, aimed at Linux newcomers) lives in
> [`poc/README.md`](./poc/README.md). Sections 5–7 there cover AppArmor,
> systemd/unattended-upgrades, and the 18 validation cases in depth.

---

## How the auto-upgrade works

1. **`init-oem.sh`** builds `nanobot-1.0.0.deb` (bundling the Electron runtime
   into `/opt/lenovo/nanobot/`), installs it, and stands up a signed APT repo.
2. **`setup-repo.sh`** generates a fresh GPG key, creates the `aptly` repo with
   `Origin=Lenovo` / `Label=Nanobot`, publishes it, and serves `~/.aptly/public`
   over HTTP.
3. **`setup-client-config.sh`** installs the APT source
   (`nanobot-poc.sources`, `Signed-By` the repo public key) and the
   `unattended-upgrades` policy that allows only `Lenovo:noble` and only
   `^nanobot$` / `^nanobot-.*` packages.
4. **`publish-1.1.sh`** builds `1.1.0`, adds it to the repo, and re-publishes.
5. The **`nanobot-poc-upgrade.timer`** fires `nanobot-poc-upgrade.service`
   every 2 minutes; the service runs `unattended-upgrade -v` as root at the
   lowest CPU/IO priority. `dpkg` swaps the files on disk; the already-running
   process keeps its in-memory image, so the app is **not** killed mid-flight.
6. Because updates come through the signed APT channel, **tampering with
   `InRelease` or the `.deb` is detected** (signature / hash mismatch) and the
   upgrade is refused.

---

## Security model

- **Non-root execution** — the Electron process runs as the launching user
  (e.g. `nanobot-testuser`), never as root. No `sudo`/`pkexec`/`apt`/`dpkg`
  appears anywhere in the app code (`main.js`, `preload.js`, `renderer.js`).
- **Chromium sandbox enforced** — `app.enableSandbox()` is called before
  `app.whenReady()`; `BrowserWindow` uses `sandbox: true`,
  `contextIsolation: true`, `nodeIntegration: false`; and `main.js`
  **refuses to start** if `--no-sandbox` is passed on the command line.
- **Dual AppArmor profile** —
  `com.lenovo.nanobot` confines the launcher and uses a `Px` transition into
  `com.lenovo.nanobot.electron`, which confines the Electron binary
  (`userns`, `capability sys_chroot`, `/dev/shm`, etc.). Both are in `enforce`.
  `chrome-sandbox` is `setuid root` (`4755`) for sandbox setup.
- **Signed, tamper-evident delivery** — the APT repo is GPG-signed; the client
  pins it with `Signed-By`, so a forged `InRelease` or modified `.deb` is
  rejected. Files under `/opt` are `root:root` and not writable by users.
- **No dangerous config** — no `chmod 777`, no `NOPASSWD: ALL`, no
  `Trusted: yes` (validation Case 16).
- **User data integrity** — upgrades touch only package files; user config and
  model files are byte-for-byte identical before/after (validation Case 13).

---

## Validation (18 cases)

All 18 cases pass. Summary:

| # | Case | # | Case |
|---|---|---|---|
| 1 | Installed under `/opt/lenovo/nanobot` | 10 | User never types a password |
| 2 | Files `root:root`, users can't modify | 11 | Running app survives upgrade |
| 3 | Desktop entry in `/usr/share/applications` | 12 | Restart shows new version |
| 4 | Non-root user can launch it | 13 | User config + model hash unchanged |
| 5 | Electron does not run as root | 14 | Tampered packages rejected by APT |
| 6 | No `sudo`/`pkexec`/`apt`/`dpkg` in app | 15 | App runs when repo is offline |
| 7 | No `--no-sandbox` | 16 | No `chmod 777` / `NOPASSWD` / `Trusted: yes` |
| 8 | Dual AppArmor profile loaded (`enforce`) | 17 | Only `nanobot` upgrades (whitelist+blacklist) |
| 9 | systemd auto-upgrades 1.0 → 1.1 | 18 | Process user + launch params correct |

Full evidence (command output, screenshots) is in
[`poc/VALIDATION_REPORT.md`](./poc/VALIDATION_REPORT.md), and screenshots live
in [`poc/evidence/`](./poc/evidence/).

---

## Scripts reference

| Script | Purpose |
|---|---|
| `scripts/init-oem.sh` | One-shot OEM-stage setup (build → install → repo → client config → timer) |
| `scripts/build-deb.sh <ver>` | Build `nanobot-<ver>.deb` (bundles Electron runtime) |
| `scripts/setup-repo.sh` | Generate GPG key, create + publish the signed aptly repo |
| `scripts/setup-client-config.sh` | Install APT source + `unattended-upgrades` policy + public key |
| `scripts/publish-1.1.sh` | Build + publish a new version (simulates an OEM update push) |
| `scripts/serve-repo.sh [start\|stop\|status]` | Serve the repo over HTTP (nginx, or python3 fallback) |
| `scripts/acceptance.sh` | Fast automated smoke test |
| `tests/run-all-tests.sh` | Full scenario suite (A–I) with report |
| `scripts/cleanup-poc.sh` | Remove everything the POC installed |

---

## What is NOT in this repo

These are **regenerated locally** — they are gitignored so the clone stays
small and no secrets leak:

| Path | Why excluded | How to regenerate |
|---|---|---|
| `poc/packages/` (~3 GB) | Build output: 8 `.deb`s + extracted Electron runtimes | `./scripts/build-deb.sh <ver>` |
| `poc/electron-app/node_modules/` (~327 MB) | npm dependency tree | `npm install` in `poc/electron-app/` |
| `poc/apt-repository/gpg-home/` | **GPG private key + keyring** — never commit | `sudo ./scripts/setup-repo.sh` |
| `poc/apt-repository/aptly.conf`, `nanobot-poc-public.gpg` | Generated by `setup-repo.sh` | same |
| `poc/logs/`, `poc/tests/results/` | Runtime logs / test output | run the scripts/tests |

> 🔑 The GPG key under `gpg-home/` is a **throwaway** key generated fresh on
> every `setup-repo.sh` run. It is never committed. If you ever find key
> material checked in, treat it as compromised and regenerate.

---

## Troubleshooting (highlights)

- **Timer never upgrades anything** → check `systemctl status
  nanobot-poc-upgrade.timer` is `active (waiting)`, then
  `journalctl -u nanobot-poc-upgrade.service -e`. Confirm the repo
  `Origin`/`Label` matches `Allowed-Origins`:
  `curl -s http://localhost:8080/dists/noble/Release | grep -E '^(Origin|Label):'`
  (must be `Lenovo` / `Nanobot`).
- **AppArmor denies** → `sudo dmesg | grep -i apparmor | grep -i denied`
  and add the missing path to the profile, then
  `sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.nanobot*`.
- **No GUI / headless** → `export DISPLAY=:99` and run `Xvfb :99 &` first.
- **`apt` doesn't see the new version** → `sudo rm -rf /var/lib/apt/lists/* && sudo apt-get update`, then `apt-cache policy nanobot`.

The full troubleshooting guide (AppArmor syntax, timer, unattended-upgrades,
GUI, APT cache) is §8 of [`poc/README.md`](./poc/README.md).

---

## Limitations & production notes

- Throwaway, passphrase-less GPG key; plain-HTTP `localhost` repo.
- Single trusted publisher; no key rotation / revocation flow.
- The 2-minute timer cadence is for fast POC iteration — use a sane policy
  (e.g. daily) in real life.
- `unattended-upgrades`' `Package-Whitelist` is **"not strict"**: it must be
  paired with a `Package-Blacklist` to actually exclude non-matching packages
  (this is why both are configured — see validation Case 17).
- Bundling the full Electron runtime makes each `.deb` ~92 MB; consider
  delta/downstream packaging for real distribution.

---

## License

The source code in this repository is licensed under the **MIT License** — see
[`LICENSE`](./LICENSE).

The built `.deb` packages **bundle the Electron framework** (which embeds
Chromium and Node.js). Electron, Chromium and Node.js are distributed under
their own open-source licenses; see `LICENSES.chromium.html` inside any built
package and <https://www.electronjs.org/docs/latest/tutorial/licenses>. This
MIT notice covers only the original code written for this proof-of-concept.

---

## Acknowledgements

Built as a research POC to validate an OS-native, APT-based auto-update pattern
for Electron apps on Ubuntu 24.04. Thanks to the maintainers of `aptly`,
`unattended-upgrades`, AppArmor, and Electron — the heavy lifting is all theirs.
