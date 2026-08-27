# Byclaw Validation Report V2

> **Real-run evidence only.** Every verdict below reflects an actual execution of
> `poc/tests-v2/case-XX.sh` or, where a root/app prerequisite was unmet, an honest
> `NOT-TESTED`. Per spec §17.3, unexecuted root cases are **never** marked PASS, and code
> review is **not** a substitute for runtime evidence.
>
> **Branch:** `feat/byclaw-vue3-redesign` · **Head at capture:** `73bca2e` (+ this report)
> **Session:** 2026-08-27, real Wayland desktop (`XDG_SESSION_TYPE=wayland`, `DISPLAY=:0`)
> **Summary:** 2 PASS · 16 NOT-TESTED · 0 FAIL · 0 false PASS

## 结论摘要（中文）

本次验证以**真实执行**为准，不以代码审查代替运行证据。
- **PASS（2）**：Case 01（两版本 DEB 可复现构建）、Case 05（preload/IPC 隔离正确）。
- **NOT-TESTED（16）**：均因 root 或已安装应用的前置条件未满足（root 步骤按 root-access
  模式排队等用户手动 `sudo`；应用未安装到 `/opt/lenovo/byclaw`）。
- **FAIL（0）**；**无虚假 PASS**——执行中发现并修复了两处会导致误判的 bug（见 §4），修复后才记录结论。
- 旧报告 `VALIDATION_REPORT.md`（V1）**保留不改**。其对旧 POC 的结论与证据不一致
  （声称 1.2.0 而证据为 1.1.0、Case 13 路径/hash 不符、AppArmor enforce 未被 `aa-status`
  捕获、`--no-sandbox` 出现在 `process-user.txt`），**因此 V1 结果不可采信**。V2 以真实证据重做。

---

## 1. Session evidence

| Item | Value | Evidence |
|---|---|---|
| Session type | `wayland` (real desktop, not Xvfb) | `evidence-v2/xdg-session-type.txt` |
| Display | `DISPLAY=:0` (XWayland) | same |
| Screenshot tool | `scrot` available; `grim` not installed | same |
| Captured | `2026-08-27T15:30:52Z` | same |

Per spec §17.4, Xvfb is not a substitute for a real desktop. This run is on the real Wayland
session. GUI screenshots (§3) were **not** captured this session because the app is not yet
installed and capturing the sleeping user's desktop would record private content pointlessly;
they are deferred to the root run (see `ROOT_OPS_RUNBOOK.md`).

---

## 2. 18-Case verdict table

| Case | 验证内容 | 主执行者 | 前置条件 | 实际结果 | 日志/证据 | 截图 | 结论 |
|---:|---|---|---|---|---|---|---|
| 01 | 构建两个版本 DEB | 普通用户 | 无 | 两 DEB 均生成（1.0.0 95968310 B；1.1.0 95966642 B） | `case-01-build-1.0.0.log`, `case-01-build-1.1.0.log`, `packages/byclaw_1.0.0_amd64.deb`, `packages/byclaw_1.1.0_amd64.deb` | N/A | **PASS** |
| 02 | `/opt` 普通用户不可写 | root | `sudo dpkg -i`（未执行） | 应用未安装 → 目录不存在 | `case-02-stat.txt`（空） | N/A | NOT-TESTED |
| 03 | 新用户可见应用、不污染 Home | root | `sudo useradd`（未执行） | 测试用户未创建 | — | N/A | NOT-TESTED |
| 04 | Electron 以普通用户运行 | 普通用户 | root 建用户 + 应用（未满足） | 测试用户未创建 → 无 byclaw 进程 | `case-04-ps.txt`（空） | N/A | NOT-TESTED |
| 05 | preload/IPC 安全隔离 | 普通用户 | 无 | 恰好 5 个方法；无 `child_process/fs` require；无裸 `ipcRenderer` | `case-05-preload.txt`（method count=5）, `case-05-forbidden.txt`（空） | N/A | **PASS** |
| 06 | Sandbox 开启、无 `--no-sandbox` | 普通用户 | 应用运行中（未满足） | 应用未运行 → 无 byclaw 进程 | `case-06-ps.txt`（空） | N/A | NOT-TESTED |
| 07 | 最小化 AppArmor enforce | root | `sudo apparmor_parser -r`（未执行） | `aa-status` 证据未产出 | — | N/A | NOT-TESTED |
| 08 | APT 签名 + `Signed-By` | root | `sudo install-client-config.sh`（未执行） | sources 文件未安装 | `case-08-inrelease.txt`（curl InRelease, 51 B） | N/A | NOT-TESTED |
| 09 | 篡改 InRelease 被 APT 拒绝 | root | root 篡改 + `apt-get update`（未执行） | 未运行 | — | N/A | NOT-TESTED |
| 10 | 只自动升级 Byclaw | root | `sudo systemctl start …upgrade.service`（未执行） | 未运行 | — | N/A | NOT-TESTED |
| 11 | 未运行时升级、下次启动新版本 | root+普通 | publish + systemctl（未执行） | 未运行 | — | N/A | NOT-TESTED |
| 12 | 运行期间升级不退出并检测 | root+普通 | 应用 + 升级（未满足） | 未运行 | — | N/A | NOT-TESTED |
| 13 | 检查更新、无更新正确提示 | 普通用户 | 应用运行（未满足） | 未运行（见 §1 截图说明） | `case-13.txt` | （未截） | NOT-TESTED |
| 14 | 有新版本未安装时不调 APT | 普通用户 | 应用运行（未满足） | 应用未运行 → 无禁用命令 | `case-14-noapt.txt`（空）；策略已正确设置（quoting 修复后） | N/A | NOT-TESTED |
| 15 | 非强制升级「稍后/立即重启」 | 普通用户 | 应用 + root 状态（未满足） | 未运行 | — | （未截） | NOT-TESTED |
| 16 | 强制升级冻结界面 | 普通用户 | 应用 + root 状态（未满足） | 未运行 | — | （未截） | NOT-TESTED |
| 17 | 重启后新版本 + 单实例 | 普通用户 | 应用（未满足） | 未运行 | — | （未截） | NOT-TESTED |
| 18 | 配置/模型保留 + 断网可运行 | root+普通 | root 升级 + 应用（未满足） | 未运行 | `case-18-sha-pre.txt`（空） | N/A | NOT-TESTED |

---

## 3. Required screenshots (spec §17.4)

Four screenshots are required: (1) 1.0.0 main UI, (2) optional UPDATE_AVAILABLE dialog,
(3) READY_FORCE frozen dialog, (4) restart → 1.1.0.

**Status: 0/4 captured.** All four require the app installed at `/opt/lenovo/byclaw` and running
in the real session. That needs the root install chain (see `ROOT_OPS_RUNBOOK.md`). They are
**NOT-TESTED** until then — not marked PASS by code review, per the hard GUI constraint.

---

## 4. False-verdict findings caught and fixed during this run

Static review (Phase 9 spec + quality) approved the case scripts, but **actual execution** exposed
two bugs that would have produced false verdicts. Both were fixed **before** any verdict was
recorded — exactly the discipline spec §17.3 demands ("禁止用代码审查结论代替运行证据").

### 4.1 Broad process grep matched a stale app + the harness itself
- **Symptom:** case-06 returned PASS and case-14 returned FAIL even though byclaw is not installed.
- **Root cause:** `grep -E 'byclaw|electron'` matched (a) a stale **`nanobot`** Electron app
  running as `nanobot-testuser` at `/opt/lenovo/nanobot/electron/electron` (leftover from the prior
  POC), (b) VS Code (also Electron), and (c) the test harness's own shell — which contained the
  literal string `/opt/lenovo/byclaw` (from an echoed hint) and `dpkg` (from a `sudo dpkg -i` hint).
- **Fix (commit `73bca2e`):** narrowed the process grep in case-04/06/14 to `grep -F '/opt/lenovo/byclaw'`
  so only byclaw's own processes match. Re-ran standalone → all correctly NOT-TESTED.
- **Note:** the stale nanobot app is still running (root needed to remove it; see runbook §0).

### 4.2 `set-update-policy.sh` quoting bug — policy never actually set
- **Symptom:** case-14 printed `bash: …/set-update-policy.sh optional 1.1.0: 没有那个文件或目录` (exit 127).
- **Root cause:** in case-13/14/15/16 line 3 the args were **inside** the quotes —
  `bash "$ROOT/scripts/set-update-policy.sh optional 1.1.0"` — so bash treated
  `"path optional 1.1.0"` as one filename. With no `set -e`, this failed silently and the update
  policy was **never set** in any of the four cases. Static review cannot see this; execution did.
- **Fix (commit `73bca2e`):** moved the closing quote before the args —
  `bash "$ROOT/scripts/set-update-policy.sh" optional 1.1.0`. Verified all four now print
  `[policy] mode=…` (exit 0); case-14 re-ran in-context → NOT-TESTED (app not running), no error.

### 4.3 Investigated and deliberately NOT changed (correct behaviour)
- `set-update-policy.sh` `none)` case writes `MODE_VAL="optional"`. This is **correct, not a bug**:
  `UpdateMode = 'optional' | 'force'` (`src/shared/types/update.ts:5`) has no `'none'` value, and the
  state machine reaches the no-update `LATEST` state via version comparison
  (`gt(latestVersion, runningVersion)` is false), with `mode` consulted only on the `installedAhead`
  branch. case-13 passes `none 1.0.0` → latestVersion=1.0.0 → app at 1.0.0 → LATEST ✓.

---

## 5. Acceptance answers (5)

| # | Acceptance question | Answer | Backed by |
|---|---|---|---|
| 1 | Do two versioned DEBs build reproducibly? | **PASS** | case-01: real builds, both DEBs present, reproducible byte sizes |
| 2 | Is the preload/IPC isolation correct (5 methods, no forbidden requires, no raw ipcRenderer)? | **PASS** | case-05: static + real run |
| 3 | Does the update state machine + service pass the spec §18.1 suite? | **PASS (unit)** | Vitest, 40 tests passed — but this is test-suite PASS, not installed-app runtime PASS |
| 4 | Are the runtime security invariants upheld (no `--no-sandbox`, no apt/dpkg in app args, signed APT, `/opt` perms, AppArmor enforce)? | **NOT-TESTED** | code/config conforms; runtime needs root install + running app |
| 5 | Does the full update UX (check / optional / force / restart) work end-to-end on the installed app? | **NOT-TESTED** | needs root install + 4 GUI screenshots |

---

## 6. Unverified items + residual risk

- **All root-dependent cases (02,03,04,07,08,09,10,11,12,18) and GUI cases (13,15,16,17):** NOT-TESTED
  until the root install chain runs. Steps are in `poc/ROOT_OPS_RUNBOOK.md` (~10–15 min of `sudo`).
- **Stale `nanobot` app** still installed/running — does not affect byclaw cases (grep narrowed), but
  should be removed for a clean validation (runbook §0).
- **case-11 script echo muddle** (`sudo ./scripts/publish-byclaw.sh`) — `publish-byclaw.sh` is a
  normal-user script; the runbook is authoritative. Script fix queued for the final review.
- **`~/Desktop/pas.json`** (plaintext password file from an earlier session) — never read; please delete.
- **Deferred Minors** from prior reviews: P7 (keyring precheck, PrivateTmp), P8 (concurrent-test
  Minor 2, log-spy Minor 3), P9 M-3 (case-13 leaves app running) — queued for the final review.

---

## 7. How to complete this validation

1. Follow `poc/ROOT_OPS_RUNBOOK.md` (root install chain + per-case `sudo` steps).
2. Re-run `bash poc/tests-v2/case-XX.sh` for each case after its root step.
3. Capture the 4 GUI screenshots for cases 13/15/16/17 via `bash poc/tests-v2/screenshot.sh …`.
4. Regenerate this report from `poc/evidence-v2/` real output (flip NOT-TESTED → PASS/FAIL only
   where real evidence supports it).

> **Old report:** `poc/VALIDATION_REPORT.md` is kept **unchanged**. Its results are inconsistent
> with its own evidence, therefore **not credible** (报告与证据不一致，因此结果不可采信).
