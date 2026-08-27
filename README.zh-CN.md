<div align="center">

# Byclaw — Ubuntu 24.04 上的 Electron 自动升级（POC）

**一个可复现的概念验证：通过 GPG 签名的本地 APT 仓库、systemd 定时器、
`unattended-upgrades` 与最小化 AppArmor profile，在 Ubuntu 24.04 上安全地
自动升级一个内置 Electron（Vue 3 + TypeScript + Vite）运行时的桌面应用。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
![Platform](https://img.shields.io/badge/Platform-Ubuntu%2024.04-E95420.svg)
![Validation](https://img.shields.io/badge/validation-2%20%E9%A1%B9%20PASS%20%C2%B7%2016%20%E9%A1%B9%20NOT--TESTED-yellow)

[English](./README.md) · **中文**

</div>

> **诚实的验证状态。** 18 个验收用例中，**2 项 PASS**（Case 01 —— 两版本
> DEB 可复现构建；Case 05 —— preload/IPC 隔离），**16 项 NOT-TESTED**（root /
> 已安装应用的前置条件尚未满足）。**0 项 FAIL，0 项虚假 PASS。** 依赖 root
> 的用例已排队至 [`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md)
> （约 10–15 分钟 `sudo`）。完整真实运行证据见
> [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md)。旧报告
> `poc/VALIDATION_REPORT.md`（V1）保留不改，但其结论与证据不一致，
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
> 明文 HTTP 在 `localhost` 上提供，整套流程假设只有一个可信的 OEM / 发布方。生产私有 APT
> 接口仅作为契约定义在
> [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md)
> （spec §14.10）——**本 POC 未实现**。

---

## 架构

```
┌── renderer（Vue 3 + TS + Vite）───────────────────────────────────────┐
│  App.vue · VersionButton.vue · UpdateDialog.vue · useUpdateState()     │
│  （不读系统文件、不调 apt/dpkg——版本号绝不硬编码）                       │
└───────────────▲──────────────────────────────contextBridge──────────────┘
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
└───────────────▲─────────────────────────────────────────────────────────┘
                │ 构建 + 打包（普通用户，无 root）
┌───────────────┴── 交付 ────────────────────────────────────────────────┐
│ vite build → electron-builder --dir（extraMetadata.version）→           │
│ dpkg-deb --build → byclaw_X.Y.Z_amd64.deb → 安装到 /opt/lenovo/byclaw    │
│ aptly 签名仓库（Origin=Lenovo, Label=Byclaw, Suite=noble）→            │
│ unattended-upgrades（root, 免密, 无 NOPASSWD）+ systemd 定时器 +        │
│ 最小化 AppArmor profile（/etc/apparmor.d/com.lenovo.byclaw）            │
└──────────────────────────────────────────────────────────────────────────┘
```

**升级状态机** —— 主进程用 semver 比较（绝不字符串比较）计算以下七态之一：

`CHECKING` · `LATEST` · `UPDATE_AVAILABLE` · `READY_OPTIONAL` ·
`READY_FORCE` · `RESTARTING` · `ERROR`

仅 `READY_FORCE`（已安装版本 > 运行版本 **且** `mode=force`）冻结界面；"服务端有新版本
但未安装"绝不冻结。只有 `installedVersion > runningVersion` 才可进入
`READY_OPTIONAL`/`READY_FORCE`。`ERROR` 不冻结、不影响 Byclaw 正常使用。

**版本来源。** 显示的版本号在任何 Vue 页面中绝不硬编码。它来自 Electron 的
`app.getVersion()`（经 `getCurrentVersion()` 传给 renderer）。构建时 `electron-builder`
通过 `extraMetadata.version` 注入（源码 `package.json` 保持 `0.0.0-dev` 基线，不回写）。一次
构建把版本注入 **六** 处并保持一致，由 `verify-versions.sh` 校验：

1. `app.getVersion()`（产物 package.json，来自 extraMetadata）
2. `DEBIAN/control` 的 `Version`
3. `postinst` 写入 `update-state.json` 的 `installedVersion`
4. DEB 文件名 `byclaw_<VERSION>_amd64.deb`
5. `update-policy.json` 的 `latestVersion`（构建产物，不手工维护）
6. APT `Packages` 索引中的 `Version`（来自 deb 的 control，经 aptly 形成）

---

## 复现（普通用户，无 sudo）

以下全部由普通用户执行。root 步骤为可选，已明确标注，排队至
[`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md)。

```bash
# 0. 克隆并一次性安装构建依赖（Node.js 22 + npm；验证机已具备系统工具：
#    aptly、gnupg2、apparmor、dpkg-deb）。
git clone git@github.com:qiuyanlong16/electron-updagre-for-ubuntu-24-poc.git
cd electron-updagre-for-ubuntu-24-poc

# 1. 构建两个版本 DEB（可复现）。build-version.sh 会先跑单测，再 vite build，
#    再 electron-builder --dir，最后 dpkg-deb --build。
bash poc/scripts/build-version.sh 1.0.0    # → poc/packages/byclaw_1.0.0_amd64.deb
bash poc/scripts/build-version.sh 1.1.0    # → poc/packages/byclaw_1.1.0_amd64.deb

# 2. 单独运行单测套件（纯状态机 + update-service + semver + upgrade-detect
#    + restart-dedup，共 5 个测试文件）。
cd poc/electron-app && npm ci && npx vitest run && cd ../..

# 3. 运行 18 用例验证。普通用户用例真实执行；root / 已安装应用用例自报
#    NOT-TESTED（没有真实证据绝不标 PASS —— 见 spec §17.3）。
bash poc/tests-v2/run-all-cases.sh

# 4. 在 127.0.0.1:8099 提供 aptly 仓库（start | status | stop）。
bash poc/scripts/serve-repo.sh start
```

> 构建产物已 gitignore，在本地重新生成——`poc/packages/`（DEB + 解压的 Electron
> 运行时）、`poc/electron-app/node_modules/`，以及 `poc/apt-repository/gpg-home/` 下的
> GPG 材料（绝不提交）。

### 可选：完成依赖 root 的验证

16 个 NOT-TESTED 用例需要 root 安装链（装 keyring + APT 源 + unattended 配置 + systemd
定时器、`dpkg -i`、AppArmor enforce、篡改测试）。每一步都会说明改了哪些系统文件，并暂停
等你手动 `sudo`——**无 NOPASSWD，不索取/保存/回显密码**。从
[`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md) 开始，之后重跑对应的
`case-XX.sh` 并用 `poc/tests-v2/screenshot.sh` 截四张必需的 GUI 截图。

---

## 安全姿态

| 不变式 | 如何保证 |
|---|---|
| GPG 签名 APT 仓库，用 keyring 固定 | `Signed-By: /usr/share/keyrings/byclaw-poc.gpg`；**不**用 `Trusted: yes` |
| Electron 沙箱开启，拒绝 `--no-sandbox` | `app.whenReady()` 之前 `app.enableSandbox()`；`--no-sandbox` → `app.exit(1)` |
| `/opt/lenovo/byclaw` 普通用户不可写 | `root:root`，由 `dpkg` 安装；Case 02 |
| 应用绝不以 root 运行 | 以消费者用户启动；Case 04 |
| 最小化 AppArmor profile | 精确路径匹配 + `userns`；无 `sys_admin`/`setuid`/`dac_read_search`；`chrome-sandbox` 保持 `0755`（非 `4755`） |
| unattended-upgrades 免密 | root 后台服务；无 `NOPASSWD`，不处理密码 |
| 禁用 `chmod 777` | 全程未用 |
| 应用运行时绝不调用特权工具 | `sudo`/`pkexec`/`apt`/`apt-get`/`dpkg`/`dpkg-query`/`unattended-upgrade`/`systemctl` **仅**出现在构建脚本、root 安装链、测试脚本中——绝不出现在 Electron 应用代码（spec §6.4） |

所有 root 工作都在 systemd 单元 / `postinst` / `install-client-config.sh` 中，由管理员执行——
绝不由应用执行。应用只查询版本、显示状态、自我重启。

---

## 验证（18 用例）

来自 [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md) 的真实运行结论：

| 用例 | 验证内容 | 结论 |
|---:|---|---|
| 01 | 两版本 DEB 可复现构建 | **PASS** |
| 05 | preload/IPC 隔离（5 方法、无禁用 require、无裸 ipcRenderer） | **PASS** |
| 02, 03, 04, 06, 07, 08, 09, 10, 11, 12, 13, 14, 15, 16, 17, 18 | root / 已安装应用 / GUI 用例 | **NOT-TESTED** |

**摘要：2 项 PASS · 16 项 NOT-TESTED · 0 项 FAIL · 0 项虚假 PASS。** 真实运行中在记录任何结论
之前，已发现并修复了两处会导致误判的 bug（V2 §4）——正是 spec §17.3 要求的纪律
（"禁止用代码审查结论代替运行证据"）。

---

## 文档指引

| 文档 | 说明 |
|---|---|
| [`poc/README.md`](./poc/README.md) | 深入教程（自旧 POC 保留；仍用旧 "nanobot" 命名，需更新为 Byclaw —— 已记录于变更清单） |
| [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md) | 真实证据验证报告（上方徽章的事实来源） |
| [`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md) | 如何完成 16 个依赖 root 的用例 |
| [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md) | 生产私有 APT 服务接口契约（spec §14.10，POC 未实现） |
| [`docs/byclaw-file-changelog.md`](./docs/byclaw-file-changelog.md) | 本分支的文件级修改清单 |
| [`docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md`](./docs/superpowers/specs/2026-08-27-byclaw-vue3-redesign-design.md) | 完整设计文档 |
| [`docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md`](./docs/superpowers/plans/2026-08-27-byclaw-vue3-redesign.md) | 实施计划 |

---

## 许可

本仓库源码采用 **MIT License** 授权——见 [`LICENSE`](./LICENSE)。

构建出的 `.deb` 包**内置了 Electron 框架**（其中包含 Chromium 与 Node.js）。Electron、
Chromium、Node.js 依其各自的开源协议分发；详见任何构建产物内的 `LICENSES.chromium.html`
与 <https://www.electronjs.org/docs/latest/tutorial/licenses>。本 MIT 声明仅覆盖为本概念验证
编写的原始代码。
