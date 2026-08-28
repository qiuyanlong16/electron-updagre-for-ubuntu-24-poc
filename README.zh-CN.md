<div align="center">

# Byclaw — Ubuntu 24.04 上的操作系统原生 Electron 自动升级

**一个可复现、已通过验证的概念验证：通过 GPG 签名的本地 APT 仓库、systemd
定时器、`unattended-upgrades` 与最小化 AppArmor profile，在 Ubuntu 24.04 上
安全地自动升级一个内置 Electron（Vue 3 + TypeScript + Vite）运行时的桌面应用
——无应用内下载器、无 `--no-sandbox`、无 `NOPASSWD`、无密码提示。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2024.04-E95420.svg)
![Validation](https://img.shields.io/badge/validation-18%2F18%20PASS-brightgreen)

[English](./README.md) · **中文**

</div>

> **验证状态：18 PASS · 0 FAIL · 0 NOT-TESTED · 0 虚假 PASS。** 18 个验收用例
> 全部于 2026-08-28 在真实 GNOME Wayland 桌面（`XDG_SESSION_TYPE=wayland`）上
> 实跑——不用 Xvfb，不以代码审查代替运行。两轮真实 `unattended-upgrade` 覆盖核心
> 路径：**1.1.0 → 1.2.0**（`mode=optional` → `READY_OPTIONAL`，操作者重启 →
> `LATEST`）与 **1.2.0 → 1.3.0**（`mode=force` → `READY_FORCE` 冻结界面，操作者
> 重启 → 1.3.0）。篡改的 `InRelease` 被 `BADSIG 8E461A79003247C0` 拒绝（Case 09）。
> 文档改写后又实跑一轮 **1.3.0 → 1.4.0** 端到端升级，证明文档改动未触及升级链。
> 完整真实运行证据见 [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md)。
> 旧报告 `poc/VALIDATION_REPORT.md`（V1）保留不改，但其结论与证据不一致，
> **报告与证据不一致，因此结果不可采信** —— 见 V2 §结论摘要。

---

## 为什么做这个

在 Linux 上更新 Electron 应用，通常的做法是在应用里自带"应用内更新器"，运行时下载
并替换文件。在企业 / OEM 场景下这种方式很别扭：它一般需要 **root**（或 `pkexec`），往往
还要关闭 Chromium 的 **`--no-sandbox`** 沙箱，并以特权进程运行——这些都是实打实的安全风险。

Byclaw 探索一种 **操作系统原生** 的替代方案，思路对标出厂镜像：

- 应用以 **`.deb`** 包形式交付，托管在 **GPG 签名的本地 APT 仓库**（由 `aptly` 管理，
  通过 HTTP 在 `127.0.0.1:8099` 提供）。
- 升级由 **Ubuntu 自带的 `unattended-upgrades`** 完成，由 **systemd 定时器** 驱动——和你
  系统打安全补丁用的是同一套机制。
- 普通 **非 root 用户全程不输入密码**；升级在后台以 root 执行，只动包文件，绝不杀死正在
  运行的应用进程。
- Electron 进程被 **沙箱化**（`app.enableSandbox()`，禁用 `--no-sandbox`），并被 **最小化
  AppArmor profile** 限制（精确路径匹配 + `userns`，不依赖 setuid `chrome-sandbox`）。

> ⚠️ **这是一个概念验证，不是生产级升级系统。** GPG 密钥是免口令的临时密钥，仓库通过
> 明文 HTTP 在 `localhost` 上提供，定时器每 2 分钟触发一次（POC 迭代速度），整套流程假设
> 只有一个可信的 OEM / 发布方。生产私有 APT 接口仅作为契约定义在
> [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md)
> （spec §14.10）——**本 POC 未实现**。见
> [已知限制与量产前修复](#已知限制与量产前修复)。

---

## 这东西证明了什么

| 能力 | 结果 |
|---|---|
| `.deb` **自包含** —— 内置 Electron 运行时 + desktop entry + AppArmor profile + 图标 + config + 维护脚本；安装到 `/opt/lenovo/byclaw`（`root:root`） | ✅ |
| 应用零用户交互自动升级 `1.3.0 → 1.4.0`（root 后台，无密码） | ✅ |
| 只升 `byclaw` —— `Package-Whitelist {"^byclaw$"}` + `Package-Blacklist`；无关包不动 | ✅ |
| 篡改 `InRelease` / `.deb` 被 APT 拒绝 —— GPG `BADSIG` + `SHA256`/`Size` 不匹配 | ✅ |
| 运行中应用**存活**原位升级 —— `postinst` 绝不杀进程；5 秒轮询检测新 `installedVersion` | ✅ |
| 应用以**非 root** 用户运行；应用代码无 `sudo`/`pkexec`/`apt`/`dpkg`（spec §6.4） | ✅ |
| Chromium **沙箱强制**；运行时拒绝 `--no-sandbox`（`app.exit(1)`） | ✅ |
| **最小化 AppArmor** —— 单 profile `flags=(unconfined)` + `userns`；`chrome-sandbox` 保持 `0755`（**非** setuid `4755`） | ✅ |
| 用户配置 + 模型跨升级不变（SHA-256 `a8332527…` 前后一致） | ✅ |
| 仓库离线时应用仍可运行（策略拉取失败 → `ERROR`，绝不崩溃） | ✅ |

---

## 架构

### 两侧，严格分离

```
┌─── OEM / 发布侧（普通用户，无 root）──────────────────────────────────────┐
│  electron-app/  ─build-version.sh─▶  byclaw_<ver>_amd64.deb             │
│  (Vue3 main/preload/   (内置完整         │  (自包含：/opt/lenovo/        │
│   renderer + shared)    Electron 运行时)   ▼   byclaw + desktop + apparmor)│
│                                   aptly repo add + publish update        │
│                                          │  (GPG 签名, Origin=Lenovo       │
│                                          ▼   Label=Byclaw Suite=noble)     │
│                           本地 APT 仓库  (aptly-db/public)                │
└──────────────────────────────────────────┬──────────────────────────────────┘
                                           │ HTTP  (python3 -m http.server :8099, 127.0.0.1)
                                           ▼
┌─── 客户端 / 设备侧（root 一次性，之后无人值守）────────────────────────────┐
│  /etc/apt/sources.list.d/byclaw-poc.sources  ──▶  apt-get update         │
│  /usr/share/keyrings/byclaw-poc.gpg            (校验签名)                 │
│  /etc/apt/apt.conf.d/60byclaw-poc-upgrades     (Allowed-Origins Lenovo:noble│
│                                                 Whitelist ^byclaw$)        │
│  byclaw-poc-upgrade.timer  (OnBootSec=1min, OnUnitActiveSec=2min)          │
│        │                                                                    │
│        ▼                                                                    │
│  byclaw-poc-upgrade.service ─▶ unattended-upgrade -v ─▶ dpkg install      │
│   (oneshot, Nice=19,           (whitelist ^byclaw$,         (1.3.0 → 1.4.0) │
│    IOSchedulingClass=idle)      blacklist 无关包…)                           │
│  /opt/lenovo/byclaw/byclaw   (root:root 0755)                              │
│      └── resources/app.asar  (AppArmor (unconfined)+userns · 沙箱 · 非 root)   │
│  /var/lib/lenovo/byclaw/update-state.json  ← postinst 原子写                │
│   (installedVersion) → 主进程每 5s 轮询 → READY_OPTIONAL / READY_FORCE      │
└─────────────────────────────────────────────────────────────────────────────┘
```

**三种职责** —— `electron-builder` 构建应用运行目录；`dpkg-deb` 制作系统级 DEB；
**APT** 分发并升级 DEB（含签名 + Hash 校验）；**`unattended-upgrades`（root 后台）**
下载安装；**Electron** 只查询版本、显示状态、自我重启——绝不调用 `apt`/`dpkg`/`sudo`/
`pkexec`。

### Electron 应用内部

```
┌── renderer（Vue 3 + TS + Vite）───────────────────────────────────────┐
│  App.vue · VersionButton.vue · UpdateDialog.vue · useUpdateState()     │
│  （不读系统文件、不调 apt/dpkg——版本号绝不硬编码）                       │
└───────────────▲────────────────────────────────contextBridge────────────┘
                │ 仅 5 个安全 IPC 方法
┌───────────────┴── preload（沙箱化）────────────────────────────────────┐
│ getCurrentVersion · checkForUpdates · getUpdateState ·                  │
│ restartApplication · onUpdateStateChanged                                │
│ （不暴露裸 ipcRenderer，不暴露 child_process/fs/shell）                   │
└───────────────▲─────────────────────────────────────────────────────────┘
                │ ipcMain.handle
┌───────────────┴── 主进程 ─────────────────────────────────────────────┐
│ update-service：拉取 update-policy.json（HTTP, 127.0.0.1:8099），        │
│ 读取 /var/lib/lenovo/byclaw/update-state.json，经 PURE 状态机计算状态     │
│ （src/shared/state-machine.ts + semver.ts）。                            │
│ 重启 = app.relaunch(); app.exit(0)——不调 apt/dpkg/sudo/pkexec。          │
│ 单实例锁（requestSingleInstanceLock）；升级后首启横幅由 last-run.ts       │
│ （app.getPath('userData')/last-run.json）驱动。                         │
└──────────────────────────────────────────────────────────────────────────┘
```

### 升级状态机 —— 7 态，semver 比较（绝不字符串比较）

`CHECKING` · `LATEST` · `UPDATE_AVAILABLE` · `READY_OPTIONAL` ·
`READY_FORCE` · `RESTARTING` · `ERROR`

- `latestVersion <= runningVersion` → `LATEST`。
- `latestVersion > runningVersion` 且 `installedVersion <= runningVersion` →
  `UPDATE_AVAILABLE`（发现新版本但后台尚未装完）。
- `installedVersion > runningVersion` 且 `mode=optional` → `READY_OPTIONAL`
  （「稍后/立即重启」）。
- `installedVersion > runningVersion` 且 `mode=force` → `READY_FORCE`（冻结界面，仅可重启）。
- `ERROR`（策略拉取 / 状态文件失败）不冻结、不影响 Byclaw 正常使用；回退 `runningVersion` 继续运行。

仅 `READY_FORCE`（已安装版本 > 运行版本 **且** `mode=force`）冻结界面；"服务端有新版本
但未安装"绝不冻结。主进程每 5 秒轮询状态文件（`main.ts` 中的 `setInterval`），经
`byclaw:update-state-changed` 推送 renderer。

### 版本来源 —— 六处一致，一次构建，自动校验

显示的版本号在任何 Vue 页面中绝不硬编码。它来自 Electron 的 `app.getVersion()`。构建时
`electron-builder` 通过 `extraMetadata.version` 注入（源码 `package.json` 保持
`0.0.0-dev` 基线，不回写）。一次构建把版本注入 **六** 处并保持一致，由 `verify-versions.sh` 校验：

1. `app.getVersion()`（产物 package.json，来自 extraMetadata）
2. `DEBIAN/control` 的 `Version`
3. `postinst` 写入 `update-state.json` 的 `installedVersion`
4. DEB 文件名 `byclaw_<VERSION>_amd64.deb`
5. `update-policy.json` 的 `latestVersion`（构建产物，不手工维护）
6. APT `Packages` 索引中的 `Version`（来自 deb 的 control，经 aptly 形成）

---

## 仓库结构

```
.
├── LICENSE / README.md / README.zh-CN.md       # MIT + 双语 README
├── docs/
│   ├── deployment/private-apt-contract.md        # 生产 APT 契约（spec §14.10）
│   ├── byclaw-file-changelog.md                  # 文件级变更清单
│   └── superpowers/{specs,plans}/2026-08-27-…    # 设计规范（14 节）+ 实施计划
└── poc/
    ├── electron-app/                            # Vue 3 + Electron 源码（见上方"应用内部"）
    │   ├── src/main/      main.ts · update-service.ts · ipc.ts · last-run.ts
    │   ├── src/preload/   preload.ts（contextBridge，5 方法）
    │   ├── src/renderer/  App.vue · components/ · composables/useUpdateState.ts
    │   ├── src/shared/    semver.ts · state-machine.ts · upgrade-detect.ts · types/
    │   └── electron-builder.yml · vite.config.ts · vitest.config.ts · package.json
    ├── scripts/                                 # 构建 / 发布 / 提供 / 校验（见脚本参考）
    ├── apt-repository/                          # aptly 仓库 + GPG home —— 已 gitignore
    ├── client-config/                           # byclaw-poc.sources · keyring · 60byclaw-poc-upgrades
    ├── systemd/                                 # byclaw-poc-upgrade.{service,timer}
    ├── tests-v2/                                # case-01..18.sh + run-all-cases.sh + screenshot.sh
    ├── evidence-v2/                             # 真实运行证据（verdict + 日志 + PNG）—— 已 gitignore
    ├── VALIDATION_REPORT_V2.md                  # 18/18 PASS 真实证据报告
    └── ROOT_OPS_RUNBOOK.md                        # 逐步 sudo runbook
```

> 构建产物**不提交**（见 [本仓库不包含什么](#本仓库不包含什么)）。克隆后跑脚本即在本地重生。

---

## 环境要求

- **Ubuntu 24.04 LTS**（Noble Numbat），`amd64`。在真实 GNOME **Wayland** 会话验证，
  内核 `7.0.0-30-generic`。
- **root**（`sudo`）—— 仅用于一次性客户端配置（`install-client-config.sh`、`dpkg -i`、
  `apparmor_parser`、`apt-get update`、`systemctl`）。手动执行；**无 `NOPASSWD`，不处理密码**。
- 系统包：`aptly`、`gnupg2`、`python3`（HTTP 服务器）、`apparmor` / `apparmor-utils`、
  `unattended-upgrades`、`dpkg-deb`、`systemd`。
- **Node.js 22 + npm** —— 仅用于拉取 Electron 43.4.1 运行时（打进 DEB）。
- GUI 验证（可选）：`gnome-screenshot`（GNOME Wayland 下非交互可用）。

---

## 快速开始

整个流程由 shell 脚本驱动。标准复现：

```bash
# 1. 克隆并一次性装构建依赖（普通用户；系统工具用 apt）。
git clone git@github.com:qiuyanlong16/electron-updagre-for-ubuntu-24-poc.git
cd electron-updagre-for-ubuntu-24-poc
bash poc/scripts/bootstrap.sh                 # 一次性依赖安装（无 sudo）
cd poc/electron-app && npm ci && cd ../..     # 把 electron 43.4.1 拉进 node_modules/

# 2. 一次性：创建 aptly 仓库 + 临时 GPG 密钥（仅普通用户）。
bash poc/scripts/setup-repo.sh

# 3. 构建、发布、提供四个版本 DEB。build-version.sh 先跑单测，再 vite build、
#    electron-builder --dir、dpkg-deb --build，然后 verify-versions.sh（六处一致）。
for v in 1.0.0 1.1.0 1.2.0 1.3.0; do
  bash poc/scripts/build-version.sh $v       # → poc/packages/byclaw_${v}_amd64.deb
  bash poc/scripts/publish-byclaw.sh $v      # → 进 aptly 仓库（重签 InRelease）
done
bash poc/scripts/serve-repo.sh start         # 在 127.0.0.1:8099 提供（| status | stop）

# 4. ROOT（一次性客户端配置——手动执行，每步说明改了哪些系统文件）：
sudo dpkg -i poc/packages/byclaw_1.0.0_amd64.deb
sudo bash poc/scripts/install-client-config.sh   # sources + keyring + apt.conf + 定时器
sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw

# 5. 发布更新版本 + 切策略为 optional/force。
bash poc/scripts/build-version.sh 1.1.0 && bash poc/scripts/publish-byclaw.sh 1.1.0
bash poc/scripts/set-update-policy.sh optional 1.1.0

# 6. ROOT：刷新 + 触发升级（或等定时器 ≤ 2 分钟自动触发）。
sudo apt-get update                            # 注意：此处无关 fish-shell PPA 会 404
sudo systemctl start byclaw-poc-upgrade.service

# 7. 验证自动升级发生。
dpkg-query -W byclaw                           # → byclaw  1.1.0
cat /var/lib/lenovo/byclaw/update-state.json  # → installedVersion: 1.1.0
grep -a byclaw /var/log/dpkg.log | tail        # 注意 -a（dpkg.log 被识别为二进制）
```

### 验证安全姿态

```bash
sudo aa-status | grep -i byclaw                # AppArmor profile 已加载
ps -eo user,args | grep '[b]yclaw'             # 以消费者用户运行，非 root
ps -C byclaw -o args= | grep -c -- '--no-sandbox'   # → 0
ps -C byclaw -o args= | grep -c -- '--enable-sandbox'  # → ≥1（renderer + network service）
```

### 运行自动化测试

```bash
bash poc/tests-v2/run-all-cases.sh            # 18 用例；root 用例在 root 链完成前自报 NOT-TESTED
cd poc/electron-app && npx vitest run          # 40 个单测（状态机 + semver + …）
```

### 清理

本 POC 无专门清理脚本（不同于旧 nanobot POC）。手动移除本 POC 安装的内容：

```bash
sudo apt-get purge -y byclaw
sudo rm -f /etc/apt/sources.list.d/byclaw-poc.sources /usr/share/keyrings/byclaw-poc.gpg
sudo rm -f /etc/apt/apt.conf.d/60byclaw-poc-upgrades
sudo systemctl disable --now byclaw-poc-upgrade.timer 2>/dev/null
sudo rm -f /etc/systemd/system/byclaw-poc-upgrade.{service,timer}
bash poc/scripts/serve-repo.sh stop
```

---

## 自动升级是如何发生的

1. **`setup-repo.sh`**（普通用户）在固定 `GNUPGHOME` 生成免口令临时 GPG 密钥，建 `aptly`
   仓库 `byclaw-poc`（`Origin=Lenovo`、`Label=Byclaw`），发布
   （`-distribution=noble -component=main`），并导出公钥。
2. **`build-version.sh <ver>`** 跑单测，再 `vite build`（renderer + main + preload）、
   `electron-builder --dir`（`extraMetadata.version=<ver>`——**不改**源码 `package.json`），
   组装自包含 staging 树（`/opt/lenovo/byclaw` + desktop entry + AppArmor profile + 图标 +
   `/etc/lenovo/byclaw/config.json` + `/var/lib/lenovo/byclaw/` 占位 +
   `DEBIAN/{control,postinst,prerm,postrm}`，`postinst` 的 `installedVersion` 构建期注入），
   `dpkg-deb --root-owner-group --build` 成 DEB。`verify-versions.sh` 校验六处一致。
3. **`publish-byclaw.sh <ver>`** 跑 `aptly repo add` + `publish update`，重签
   `InRelease`/`Release`，再校验 `Packages` 索引 `Version` = `<ver>`。
4. **`serve-repo.sh start`** 在 `127.0.0.1:8099` 以 HTTP 提供 `aptly-db/public`
   （含 `dists/`、`pool/`、`update-policy.json`）。
5. **`install-client-config.sh`**（root，一次性）安装 APT 源
   （`byclaw-poc.sources` 用 `Signed-By`，**非** `Trusted: yes`）、仓库公钥到
   `/usr/share/keyrings/byclaw-poc.gpg`、`60byclaw-poc-upgrades` apt.conf
   （`Allowed-Origins {"Lenovo:noble"}`、`Package-Whitelist {"^byclaw$"}`、
   `Package-Blacklist`）、`byclaw-poc-upgrade.{service,timer}`；enable 定时器。
6. **`byclaw-poc-upgrade.timer`**（`OnBootSec=1min`、`OnUnitActiveSec=2min`）触发
   **`byclaw-poc-upgrade.service`**——`oneshot`，以 root 跑 `unattended-upgrade -v`，
   `Nice=19`、`IOSchedulingClass=idle`。`dpkg` 换盘（`1.3.0 → 1.4.0`）；正在运行的进程保留
   内存映像，**不在升级中途被杀**。
7. **`postinst`** 原子写 `installedVersion=1.4.0` 到
   `/var/lib/lenovo/byclaw/update-state.json`（临时文件 + `mv`，`root:root 0644`）；刷新
   desktop DB、重载 AppArmor（均软失败）。**不重启**任何进程。
8. 运行中应用每 5 秒轮询读到 `installedVersion(1.4.0) > running(1.3.0)` + `mode` →
   `READY_OPTIONAL` / `READY_FORCE`。用户点"立即重启" → `app.relaunch(); app.exit(0)` →
   新进程加载 1.4.0 二进制 → `LATEST`。因更新走签名 APT 通道，**篡改 `InRelease` 或
   `.deb` 会被检测**（`BADSIG` / Hash 不匹配）并拒绝升级——Case 09 已验证。

---

## 安全模型

| 不变式 | 如何保证 | 证据 |
|---|---|---|
| GPG 签名 APT 仓库，用 keyring 固定 | `Signed-By: /usr/share/keyrings/byclaw-poc.gpg`；**不**用 `Trusted: yes` | Case 08；BADSIG Case 09 |
| 篡改仓库/DEB 被 APT 独立拒绝 | `InRelease` 内联签名；`Packages` 带 `SHA256`+`Size`；APT 安装前校验 | Case 09（`BADSIG …`） |
| Electron 沙箱开启，拒绝 `--no-sandbox` | `app.whenReady()` 之前 `app.enableSandbox()`；`--no-sandbox` → `app.exit(1)` | Case 06 |
| `/opt/lenovo/byclaw` 普通用户不可写 | `root:root`，由 `dpkg` 安装 | Case 02 |
| 应用绝不以 root 运行 | 以消费者用户启动 | Case 04 |
| 最小化 AppArmor profile | 精确路径匹配 + `userns`，`flags=(unconfined)`；无 `sys_admin`/`setuid`/`dac_read_search`；`chrome-sandbox` 保持 `0755`（非 `4755`） | Case 07 |
| unattended-upgrades 免密、仅升 Byclaw | root 后台服务；`Package-Whitelist {"^byclaw$"}` + `Package-Blacklist`；无 `NOPASSWD` | Case 10 |
| 禁用 `chmod 777` | 全程未用 | — |
| 应用运行时绝不调用特权工具 | `sudo`/`pkexec`/`apt`/`apt-get`/`dpkg`/`dpkg-query`/`unattended-upgrade`/`systemctl` **仅**出现在构建脚本、root 安装链、测试脚本中——绝不出现在 Electron 应用代码（spec §6.4） | Case 14 |
| 用户数据 + 模型升级后保留 | `postinst` 不碰 `~/.config`；`postrm` purge 只清系统路径 | Case 18 |

所有 root 工作都在 systemd 单元 / `postinst` / `install-client-config.sh` 中，由管理员执行——
绝不由应用执行。

---

## 验证（18 用例——全 PASS）

来自 [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md) 的真实运行结论，
`feat/byclaw-vue3-redesign` 分支 `b3eabc6`：

| 用例 | 验证内容 | | 用例 | 验证内容 |
|---:|---|---|---:|---|
| 01 | 两版本 DEB 可复现构建（六处一致） | | 10 | 只自动升级 Byclaw，全程无密码无 sudo |
| 02 | `/opt/lenovo/byclaw` 普通用户不可写 | | 11 | 应用未运行时升级，下次启动为新版本 |
| 03 | 新用户可见应用；OEM 阶段不污染未来 Home | | 12 | 应用运行期间升级不退出并检测安装完成 |
| 04 | Electron 以普通用户运行 | | 13 | 检查更新、无更新时正确提示 LATEST |
| 05 | preload/IPC 隔离（5 方法、无禁用 require、无裸 ipcRenderer） | | 14 | 有新版本未安装时不调 APT |
| 06 | 沙箱开启、无 `--no-sandbox` | | 15 | 非强制升级「稍后/立即重启」 |
| 07 | 最小化 AppArmor profile 正常 enforce | | 16 | 强制升级冻结界面，仅可重启 |
| 08 | APT 签名 + `Signed-By` + 客户端配置正确 | | 17 | 重启后新版本且保持单实例 |
| 09 | 篡改 `InRelease`/DEB 被 APT 拒绝（`BADSIG`） | | 18 | 用户配置/模型保留；断网旧版本仍可运行 |

**摘要：18 PASS · 0 FAIL · 0 NOT-TESTED · 0 虚假 PASS。** 四张必需 GUI 截图
（LATEST、UPDATE_AVAILABLE、READY_OPTIONAL、READY_FORCE）由 `gnome-screenshot` 在真实
Wayland 会话抓取，并由现场操作者额外确认。两处会导致误判的 bug（一次升级中途误抓，已隔离为
`case-15-INVALID-*.png`；对二进制识别的 `dpkg.log` 用普通 `grep` 返回空）在记录任何结论前
已发现并修复——正是 spec §17.3 要求的纪律（"禁止用代码审查结论代替运行证据"）。

---

## 脚本参考

| 脚本 | 用途 |
|---|---|
| `scripts/bootstrap.sh` | 一次性依赖安装（普通用户，无 sudo） |
| `scripts/setup-repo.sh` | 生成 GPG 密钥 + 创建 + 发布签名 aptly 仓库（`byclaw-poc`） |
| `scripts/build-version.sh <ver>` | 构建 `byclaw_<ver>.deb`（单测→vite→electron-builder→dpkg-deb→verify） |
| `scripts/publish-byclaw.sh <ver>` | 添加 + 重新发布版本到 aptly（重签 `InRelease`） |
| `scripts/serve-repo.sh {start\|status\|stop}` | 在 `127.0.0.1:8099` 以 HTTP 提供仓库（PID + 日志） |
| `scripts/set-update-policy.sh {none\|optional\|force} [ver]` | 切换提供的 `update-policy.json` 模式 + latestVersion |
| `scripts/install-client-config.sh` | **ROOT**：安装 APT 源 + keyring + apt.conf + systemd 单元 |
| `scripts/verify-versions.sh <ver> [--published <url>]` | 六处版本一致校验（构建期 + 发布后） |
| `scripts/make-icon.sh` | 无图标时生成 256×256 PNG 图标 |
| `tests-v2/run-all-cases.sh` | 18 用例验证运行器 |
| `tests-v2/screenshot.sh` | GUI 截图助手（真实 Wayland 会话） |

---

## 本仓库不包含什么

这些**在本地重新生成**——已 gitignore，使克隆保持小且不泄露密钥：

| 路径 | 排除原因 | 如何重生 |
|---|---|---|
| `poc/packages/` | 构建产物：`.deb` + 解压的 Electron 运行时 | `scripts/build-version.sh <ver>` |
| `poc/electron-app/node_modules/` | npm 依赖树 | `npm ci`（`poc/electron-app/`） |
| `poc/dist-electron/` | `electron-builder --dir` 产物 | `scripts/build-version.sh` |
| `poc/apt-repository/gpg-home/` | **GPG 私钥 + keyring——绝不提交** | `scripts/setup-repo.sh` |
| `poc/apt-repository/aptly-db/` | aptly 数据库 + 发布索引 | `setup-repo.sh` + `publish-byclaw.sh` |
| `poc/logs/`、`poc/tests-v2/results/` | 运行日志 / 测试输出 | 跑脚本/测试 |
| `poc/evidence-v2/*` | 真实运行证据（verdict + 日志 + PNG） | 重跑 `tests-v2/`（保留 `.gitkeep`） |

> 🔑 `gpg-home/` 下的 GPG 密钥是每次 `setup-repo.sh` 运行时新生成的**临时**密钥，绝不提交。
> 若发现密钥材料被提交，视为已泄露，重新生成。

---

## 故障排查

- **定时器从不升级** → 检查 `systemctl status byclaw-poc-upgrade.timer` 是否 `active (waiting)`，
  再 `journalctl -u byclaw-poc-upgrade.service -e`。确认仓库 `Origin`/`Label` 与 `Allowed-Origins`
  一致：`curl -s http://127.0.0.1:8099/dists/noble/Release | grep -E '^(Origin|Label):'`
  （须为 `Lenovo` / `Byclaw`）。
- **AppArmor 拒绝** → `sudo dmesg | grep -i apparmor | grep -i denied`，补缺失路径到 profile，
  再 `sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw`。
- **`apt` 看不到新版本** → `sudo rm -rf /var/lib/apt/lists/*byclaw* && sudo apt-get update`，
  再 `apt-cache policy byclaw`。（无关 `fish-shell` PPA 404 会令 `apt-get update` 退出码非零——
  与 Byclaw 无关；移除：`sudo rm /etc/apt/sources.list.d/*fish*`。）
- **`grep byclaw /var/log/dpkg.log` 返回空** → 该文件被识别为二进制（一个多余非文本字节）；
  用 `grep -a byclaw`（文本模式）。
- **Electron 启动即 exit 0 无窗口** → VS Code 扩展宿主导出了 `ELECTRON_RUN_AS_NODE=1`，
  应用以 Node 进程启动。启动时加前缀 `env -u ELECTRON_RUN_AS_NODE`（用户自己的终端无此变量）。
- **无 GUI / 无头** → Byclaw 在**真实** Wayland 会话验证（spec §17.4——Xvfb 不可替代）。
  真实会话用 `DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0`。

每个 root 用例的完整逐步 sudo runbook 见
[`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md)。

---

## 已知限制与量产前修复

以下**不影响** POC 结论（自动升级模式已验证），但量产前必须处理：

- **`/etc/lenovo/byclaw/config.json` 非 dpkg conffile。** 今日它能在 DEB 升级中保留，仅因打包
  默认值在 1.0.0/1.1.0/1.2.0/1.3.0 中字节相同（sha `a8332527…`，Case 18 证明）。*自定义*
  配置会被后续升级覆盖。**修复：** 声明为 conffile，使本地修改得以保留。
- **明文 HTTP 于 `127.0.0.1:8099`、免口令临时 GPG 密钥、2 分钟定时器。** 仅 POC。生产须用
  HTTPS、托管签名密钥（HSM、口令、过期、轮换/吊销）与日级/策略驱动定时器——见
  [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md)。
- **`Package-Whitelist` 非严格** → 配 `Package-Blacklist` 兜底（已知 POC 限制，spec §21）。
- **验证机上无关 `fish-shell` PPA 404** 令 `apt-get update` 退出码非零；与 Byclaw 无关
  （Byclaw 索引正常拉取）。移除：`sudo rm /etc/apt/sources.list.d/*fish*`。

---

## 文档指引

| 文档 | 说明 |
|---|---|
| [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md) | 真实证据验证报告（18/18 PASS）——上方徽章的事实来源 |
| [`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md) | root 安装链 + 18 用例的逐步 sudo runbook |
| [`poc/evidence-v2/EVIDENCE_NOTES.md`](./poc/evidence-v2/EVIDENCE_NOTES.md) | 逐用例证据表 + 经验教训（如 `dpkg.log` 需 `grep -a`） |
| [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md) | 生产私有 APT 服务接口契约（spec §14.10，POC 未实现） |
| [`docs/byclaw-file-changelog.md`](./docs/byclaw-file-changelog.md) | 本分支的文件级修改清单 |
| [`docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md`](./docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md) | 完整设计规范（14 节） |
| [`docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md`](./docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md) | 实施计划 |
| [`poc/README.md`](./poc/README.md) | 深入教程（自旧 POC 保留；仍用旧 "nanobot" 命名，且有悬空脚本引用——已记录于变更清单） |

---

## 许可

本仓库源码采用 **MIT License** 授权——见 [`LICENSE`](./LICENSE)。

构建出的 `.deb` 包**内置了 Electron 框架**（其中包含 Chromium 与 Node.js）。Electron、
Chromium、Node.js 依其各自的开源协议分发；详见任何构建产物内的 `LICENSES.chromium.html`
与 <https://www.electronjs.org/docs/latest/tutorial/licenses>。本 MIT 声明仅覆盖为本概念验证
编写的原始代码。

---

## 致谢

作为研究 POC 构建，用于验证 Ubuntu 24.04 上 Electron 应用的操作系统原生、基于 APT 的自动
升级模式。感谢 `aptly`、`unattended-upgrades`、AppArmor 与 Electron 的维护者——重活都是他们干的。
