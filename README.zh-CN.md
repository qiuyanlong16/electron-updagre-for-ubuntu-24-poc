<div align="center">

# Electron 自动升级方案 (Ubuntu 24.04 POC)

**一个可复现的概念验证：通过 GPG 签名的本地 APT 仓库、systemd 定时器、
`unattended-upgrades` 与双重 AppArmor profile，在 Ubuntu 24.04 上安全地自动升级
一个内置 Electron 运行时的桌面应用。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2024.04-E95420.svg)
![Status](https://img.shields.io/badge/Status-POC-18%2F18%20PASS-brightgreen.svg)

[English](./README.md) · **中文**

</div>

---

## 为什么做这个

在 Linux 上更新 Electron 应用，通常的做法是在应用里自带一个"应用内更新器"，运行时下载
并替换文件。在企业 / OEM 场景下这种方式很别扭：它一般需要 **root**（或 `pkexec`），往往
还要关闭 Chromium 的 **`--no-sandbox`** 沙箱，并以特权进程运行——这些都是实打实的安全风险。

本 POC 探索一种 **操作系统原生** 的替代方案，思路对标出厂镜像：

- 应用以 **`.deb`** 包形式交付，托管在 **GPG 签名的本地 APT 仓库**（由 `aptly` 管理，HTTP 提供）。
- 升级由 **Ubuntu 自带的 `unattended-upgrades`** 完成，由 **systemd 定时器** 驱动——和你系统打
  安全补丁用的是同一套机制。
- 普通 **非 root 用户全程不输入密码**；升级在后台以 root 执行，只动包文件，绝不杀死正在运行的
  应用进程。
- Electron 进程被 **沙箱化**（`app.enableSandbox()`，禁用 `--no-sandbox`），并被 **双重 AppArmor
  profile** 限制。

所有能力通过 **18 个验收用例** 验证——在干净的 Ubuntu 24.04.4 LTS 上全部通过。详见
[`poc/VALIDATION_REPORT.md`](./poc/VALIDATION_REPORT.md)。

> ⚠️ **这是一个概念验证，不是生产级升级系统。** GPG 密钥是免口令的临时密钥，仓库通过明文 HTTP
> 在 `localhost` 上提供，整套流程假设只有一个可信的 OEM / 发布方。请用它来学习并验证这个**模式**，
> 真正使用前必须加固。

---

## 它验证了什么

| 能力 | 结果 |
|---|---|
| `.deb` 内置完整 Electron 运行时，安装到 `/opt/lenovo/nanobot`（`root:root`） | ✅ |
| 应用自动从 `1.0.0` 升级到 `1.1.0`（及更高），**用户零交互** | ✅ |
| 只升级 `nanobot`；仓库中的无关包被**黑名单**排除 | ✅ |
| 被篡改的 `InRelease` / `.deb` 会被 GPG 签名 + Hash 校验**拒绝** | ✅ |
| 正在运行的应用**熬过**就地升级（进程不被杀） | ✅ |
| 应用以**非 root** 用户运行；应用代码里**没有 `sudo`/`pkexec`/`apt`/`dpkg`** | ✅ |
| Chromium **沙箱被强制启用**；运行时拒绝 `--no-sandbox` | ✅ |
| **双重 AppArmor** profile（launcher + Electron）处于 `enforce` 模式 | ✅ |
| 用户配置 + 模型文件升级前后不变（SHA-256 一致） | ✅ |
| 仓库离线时应用仍可运行 | ✅ |

---

## 架构

```
┌──────────────────────────── OEM / 发布方 ───────────────────────────────────┐
│                                                                              │
│  electron-app/      ─build-deb.sh─▶  nanobot-<ver>.deb                       │
│  (main / preload /        (内置完整                │                          │
│   renderer / index)       Electron 运行时)         ▼                          │
│                                       aptly repo add + publish               │
│                                              │  (GPG 签名,                    │
│                                              ▼   Origin=Lenovo Label=Nanobot)│
│                                   本地 APT 仓库  (~/.aptly/public)           │
└──────────────────────────────────────────────┬───────────────────────────────┘
                                               │ HTTP  (nginx 或 python3 :8080)
                                               ▼
┌──────────────────────────── 客户端 / 设备 ────────────────────────────────────┐
│                                                                              │
│  /etc/apt/sources.list.d/nanobot-poc.sources  ──▶  apt-get update             │
│  /usr/share/keyrings/nanobot-poc.gpg            (校验签名)                   │
│                                                                              │
│  nanobot-poc-upgrade.timer  (每 2 分钟)                                       │
│        │                                                                     │
│        ▼                                                                     │
│  nanobot-poc-upgrade.service  ──▶  unattended-upgrade  ──▶  dpkg 安装         │
│   (oneshot, Nice=19,            (白名单 ^nanobot$,           (1.0.0 → 1.1.0)  │
│    idle I/O)                    黑名单 unrelated-…)                          │
│                                                                              │
│  /opt/lenovo/nanobot/nanobot         (launcher, root:root, 0755)              │
│      └── Px ──▶ /opt/lenovo/nanobot/electron/electron                        │
│                  (AppArmor enforce · Chromium 沙箱 · 非 root 用户)            │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 目录结构

```
.
├── LICENSE                         # MIT (仅限本 POC 自有源码)
├── README.md                       # 英文版
├── README.zh-CN.md                 # 你在这里 (中文)
└── poc/
    ├── README.md                   # 完整中文分步教程 (新手向，保持原样)
    ├── VALIDATION_REPORT.md        # 18 项验证报告 (100% 通过)
    ├── electron-app/               # Electron 应用源码 (main/preload/renderer/index)
    ├── packaging/                  # nanobot.desktop 桌面入口
    ├── apparmor/                   # 双重 AppArmor profile (launcher + electron)
    ├── systemd/                    # 升级定时器 + oneshot 服务
    ├── client-config/              # APT 源 + unattended-upgrades 配置包
    ├── apt-repository/             # 生成的仓库状态 (GPG 密钥、aptly) — 已 gitignore
    ├── scripts/                    # 构建 / 搭建 / 发布 / 服务 / 清理 / 验收
    ├── tests/                      # 场景脚本 A–I + 主测试器
    └── evidence/                   # 验证运行时的截图与命令输出
```

> 构建产物**故意不提交**（见[本仓库不包含什么](#本仓库不包含什么)）。克隆后运行脚本即可在本地重新生成。

---

## 环境要求

- **Ubuntu 24.04 LTS** (Noble Numbat)，`amd64`。在 **24.04.4**、内核 `7.0.0-28-generic` 上验证。
- **root**（`sudo`）权限，用于系统级安装脚本。
- 系统包：`aptly`、`gnupg2`、`nginx`（或用 `python3` 作为 HTTP 服务回退）、`apparmor`、
  `unattended-upgrades`、`dpkg-deb`、`systemd`。
- **Node.js 22 + npm** —— 仅用于获取要内置进 `.deb` 的 Electron 运行时。
- GUI / 无头测试（可选）：`xvfb`、`scrot`、`xdotool`、`imagemagick`。

---

## 快速开始

全部由 shell 脚本驱动。标准复现流程：

```bash
# 1. 克隆并进入 POC 目录
git clone git@github.com:qiuyanlong16/electron-updagre-for-ubuntu-24-poc.git
cd electron-updagre-for-ubuntu-24-poc/poc

# 2. 安装系统依赖
sudo apt-get update
sudo apt-get install -y aptly gnupg2 nginx python3 \
                        unattended-upgrades apparmor-utils dpkg-dev

# 3. 安装 Node.js 22 (用于获取 Electron 运行时)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
cd electron-app && npm install && cd ..        # 把 electron 拉到 node_modules/

# 4. 一键 OEM 阶段初始化：
#      构建 + 安装 nanobot 1.0.0
#      生成临时 GPG 密钥 + 签名的本地 APT 仓库
#      安装客户端 APT 源 + unattended-upgrades 配置
#      安装桌面入口 + 双重 AppArmor profile
#      安装 + 启用每 2 分钟的升级定时器
#      在 :8080 启动 HTTP 仓库服务
sudo ./scripts/init-oem.sh

# 5. 创建应用运行所用的非 root 用户
sudo useradd -m -s /bin/bash nanobot-testuser
sudo passwd nanobot-testuser          # 仅登录 / 启动 GUI 时需要

# 6. 模拟 OEM 发布新版本 (构建 + 发布 1.1.0)
./scripts/publish-1.1.sh

# 7. 立即触发升级 (或者等 ≤ 2 分钟由定时器触发)
sudo systemctl start nanobot-poc-upgrade.service

# 8. 验证自动升级是否成功
dpkg-query -W nanobot                  # → nanobot  1.1.0
```

### 验证安全姿态

```bash
sudo aa-status | grep nanobot          # 两个 profile 都是 (enforce)
ps -eo user,args | grep '[e]lectron'  # 以 nanobot-testuser 运行，非 root
                                       # 无 --no-sandbox；renderer 有 --enable-sandbox
```

### 运行自动化测试

```bash
sudo ./scripts/acceptance.sh           # 快速冒烟测试 (约 20 项)
sudo ./tests/run-all-tests.sh          # 完整场景套件 A–I (需要测试用户 + 显示环境)
```

### 清理

```bash
sudo ./scripts/cleanup-poc.sh          # 删除包、定时器、profile、仓库配置、测试用户
```

> 逐命令、逐概念的**详尽中文分步教程**（面向 Linux 新手，带大量注释）在
> [`poc/README.md`](./poc/README.md)。其中第 5–7 节深入讲解 AppArmor、
> systemd / unattended-upgrades 以及 18 个验证用例。

---

## 自动升级如何运作

1. **`init-oem.sh`** 构建 `nanobot-1.0.0.deb`（把 Electron 运行时内置到 `/opt/lenovo/nanobot/`），安装，
   并搭起签名 APT 仓库。
2. **`setup-repo.sh`** 生成全新 GPG 密钥，用 `Origin=Lenovo` / `Label=Nanobot` 创建 `aptly` 仓库并发布，
   通过 HTTP 提供 `~/.aptly/public`。
3. **`setup-client-config.sh`** 安装 APT 源（`nanobot-poc.sources`，`Signed-By` 仓库公钥）和
   `unattended-upgrades` 策略：只允许 `Lenovo:noble` 来源、只允许 `^nanobot$` / `^nanobot-.*` 包。
4. **`publish-1.1.sh`** 构建 `1.1.0`，加入仓库并重新发布。
5. **`nanobot-poc-upgrade.timer`** 每 2 分钟触发 `nanobot-poc-upgrade.service`；该服务以 root、最低
   CPU/IO 优先级运行 `unattended-upgrade -v`。`dpkg` 在磁盘上替换文件；已在内存中运行的进程保留
   其内存映像，所以应用**不会**在升级中途被杀。
6. 由于更新走签名 APT 通道，**篡改 `InRelease` 或 `.deb`** 都会被发现（签名 / Hash 不匹配）并被拒绝。

---

## 安全模型

- **非 root 执行** —— Electron 进程以启动它的用户（如 `nanobot-testuser`）身份运行，绝不以 root。
  应用代码（`main.js`、`preload.js`、`renderer.js`）中没有任何 `sudo`/`pkexec`/`apt`/`dpkg`。
- **强制 Chromium 沙箱** —— 在 `app.whenReady()` 之前调用 `app.enableSandbox()`；`BrowserWindow` 使用
  `sandbox: true`、`contextIsolation: true`、`nodeIntegration: false`；且 `main.js` 在命令行传入
  `--no-sandbox` 时**拒绝启动**。
- **双重 AppArmor profile** —— `com.lenovo.nanobot` 限制 launcher，并通过 `Px` 转换进入
  `com.lenovo.nanobot.electron`（限制 Electron 二进制：`userns`、`capability sys_chroot`、
  `/dev/shm` 等）。两者均为 `enforce`。`chrome-sandbox` 为 `setuid root`（`4755`）以搭建沙箱。
- **签名、防篡改的交付** —— APT 仓库经 GPG 签名；客户端用 `Signed-By` 固定公钥，伪造的 `InRelease`
  或被改的 `.deb` 会被拒绝。`/opt` 下文件为 `root:root`，用户不可写。
- **无危险配置** —— 无 `chmod 777`、无 `NOPASSWD: ALL`、无 `Trusted: yes`（验证用例 16）。
- **用户数据完整** —— 升级只动包文件；用户配置和模型文件升级前后逐字节一致（用例 13）。

---

## 验证 (18 项用例)

18 项全部通过。概览：

| # | 用例 | # | 用例 |
|---|---|---|---|
| 1 | 安装在 `/opt/lenovo/nanobot` | 10 | 用户全程不输密码 |
| 2 | 文件 `root:root`，用户不可改 | 11 | 运行中的应用熬过升级 |
| 3 | 桌面入口在 `/usr/share/applications` | 12 | 重启后显示新版本 |
| 4 | 非 root 用户能启动 | 13 | 用户配置 + 模型 Hash 不变 |
| 5 | Electron 不以 root 运行 | 14 | 篡改的包被 APT 拒绝 |
| 6 | 应用代码无 `sudo`/`pkexec`/`apt`/`dpkg` | 15 | 仓库离线时应用仍可运行 |
| 7 | 不使用 `--no-sandbox` | 16 | 无 `chmod 777` / `NOPASSWD` / `Trusted: yes` |
| 8 | 双重 AppArmor profile 已加载 (`enforce`) | 17 | 只升级 `nanobot` (白名单+黑名单) |
| 9 | systemd 自动升级 1.0 → 1.1 | 18 | 进程用户 + 启动参数正确 |

完整证据（命令输出、截图）见 [`poc/VALIDATION_REPORT.md`](./poc/VALIDATION_REPORT.md)，截图在
[`poc/evidence/`](./poc/evidence/)。

---

## 脚本说明

| 脚本 | 用途 |
|---|---|
| `scripts/init-oem.sh` | 一键 OEM 阶段初始化 (构建 → 安装 → 仓库 → 客户端配置 → 定时器) |
| `scripts/build-deb.sh <版本>` | 构建 `nanobot-<版本>.deb` (内置 Electron 运行时) |
| `scripts/setup-repo.sh` | 生成 GPG 密钥，创建 + 发布签名 aptly 仓库 |
| `scripts/setup-client-config.sh` | 安装 APT 源 + `unattended-upgrades` 策略 + 公钥 |
| `scripts/publish-1.1.sh` | 构建 + 发布新版本 (模拟 OEM 推送更新) |
| `scripts/serve-repo.sh [start\|stop\|status]` | 通过 HTTP 提供仓库 (nginx 或 python3 回退) |
| `scripts/acceptance.sh` | 快速自动化冒烟测试 |
| `tests/run-all-tests.sh` | 完整场景套件 (A–I) 含报告 |
| `scripts/cleanup-poc.sh` | 清除 POC 安装的所有内容 |

---

## 本仓库不包含什么

这些会在**本地重新生成**——已 gitignore，保证克隆体量小且不泄密：

| 路径 | 排除原因 | 如何重新生成 |
|---|---|---|
| `poc/packages/` (~3 GB) | 构建产物：8 个 `.deb` + 解压的 Electron 运行时 | `./scripts/build-deb.sh <版本>` |
| `poc/electron-app/node_modules/` (~327 MB) | npm 依赖树 | 在 `poc/electron-app/` 执行 `npm install` |
| `poc/apt-repository/gpg-home/` | **GPG 私钥 + 密钥环** —— 绝不提交 | `sudo ./scripts/setup-repo.sh` |
| `poc/apt-repository/aptly.conf`、`nanobot-poc-public.gpg` | 由 `setup-repo.sh` 生成 | 同上 |
| `poc/logs/`、`poc/tests/results/` | 运行日志 / 测试输出 | 运行脚本 / 测试 |

> 🔑 `gpg-home/` 下的 GPG 密钥是**临时**密钥，每次运行 `setup-repo.sh` 都会重新生成，绝不提交。
> 如果你发现仓库里被提交了密钥材料，请视为已泄露并重新生成。

---

## 排错 (要点)

- **定时器从不升级** → 检查 `systemctl status nanobot-poc-upgrade.timer` 是否 `active (waiting)`，
  再看 `journalctl -u nanobot-poc-upgrade.service -e`。确认仓库 `Origin`/`Label` 与
  `Allowed-Origins` 匹配：
  `curl -s http://localhost:8080/dists/noble/Release | grep -E '^(Origin|Label):'`
  （必须为 `Lenovo` / `Nanobot`）。
- **AppArmor 拒绝访问** → `sudo dmesg | grep -i apparmor | grep -i denied`，按缺的路径补充 profile，
  再 `sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.nanobot*`。
- **无 GUI / 无头** → 先 `export DISPLAY=:99` 并 `Xvfb :99 &`。
- **`apt` 看不到新版本** → `sudo rm -rf /var/lib/apt/lists/* && sudo apt-get update`，再
  `apt-cache policy nanobot`。

完整排错指南（AppArmor 语法、定时器、unattended-upgrades、GUI、APT 缓存）见
[`poc/README.md`](./poc/README.md) 第 8 节。

---

## 局限与生产环境注意事项

- GPG 密钥为免口令临时密钥；仓库为明文 HTTP `localhost`。
- 单一可信发布方；无密钥轮换 / 撤销流程。
- 每 2 分钟的定时器节奏是为了 POC 快速迭代——生产环境请用合理策略（如每天）。
- `unattended-upgrades` 的 `Package-Whitelist` 是**"not strict"（非强制）**：必须配合
  `Package-Blacklist` 才能真正排除不匹配的包（本 POC 因此同时配置了两者——见用例 17）。
- 内置完整 Electron 运行时使每个 `.deb` 约 92 MB；真实分发请考虑增量 / 下游打包。

---

## 许可

本仓库源码采用 **MIT License** 授权——见 [`LICENSE`](./LICENSE)。

构建出的 `.deb` 包**内置了 Electron 框架**（其中包含 Chromium 与 Node.js）。Electron、Chromium、
Node.js 依其各自的开源协议分发；详见任何构建产物内的 `LICENSES.chromium.html` 与
<https://www.electronjs.org/docs/latest/tutorial/licenses>。本 MIT 声明仅覆盖为本概念验证编写的原始代码。

---

## 致谢

作为一个研究型 POC，用于验证"Electron 应用在 Ubuntu 24.04 上走 APT 原生自动升级"的模式。感谢
`aptly`、`unattended-upgrades`、AppArmor、Electron 的维护者——真正出力的是他们。
