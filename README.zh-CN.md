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
> 完整真实运行证据见 [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md)。
> 一个 4-agent 对抗式验证工作流逐条重审所有结论与原始证据；其标记的风险已通过
> **重新抓取**或**诚实限定范围**处理，无虚假 PASS 存活（V2 §6）。旧报告
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
> 明文 HTTP 在 `localhost` 上提供，定时器每 2 分钟触发一次（POC 迭代速度），整套流程假设
> 只有一个可信的 OEM / 发布方。生产私有 APT 接口仅作为契约定义在
> [`docs/deployment/private-apt-contract.md`](./docs/deployment/private-apt-contract.md)
> （spec §14.10）——**本 POC 未实现**。见
> [已知限制与量产前修复](#已知限制--量产前修复)。

---

## 架构

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

**三种职责严格分离** —— `electron-builder` 构建应用运行目录；`dpkg-deb` 制作系统级
DEB；**APT** 分发并升级 DEB（含签名 + Hash 校验）；**`unattended-upgrades`（root 后台）**
下载安装；**Electron** 只查询版本、显示状态、自我重启——绝不调用 `apt`/`dpkg`/`sudo`/
`pkexec`（spec §6.4）。

**升级状态机** —— 主进程用 semver 比较（绝不字符串比较）计算以下七态之一：

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
但未安装"绝不冻结。只有 `installedVersion > runningVersion` 才可进入
`READY_OPTIONAL`/`READY_FORCE`。主进程每 5 秒轮询状态文件（`main.ts` 中的
`setInterval`），经 `byclaw:update-state-changed` 推送 renderer。

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

## 仓库布局

```
.
├── README.md / README.zh-CN.md / LICENSE         # 本文件（双语）+ MIT
├── docs/
│   ├── deployment/private-apt-contract.md          # 生产 APT 契约（§14.10）
│   ├── byclaw-file-changelog.md                    # 文件级变更清单
│   └── superpowers/{specs,plans}/2026-08-27-…     # 设计规范 + 实施计划
└── poc/
    ├── electron-app/                              # Vue 3 + Electron 源码
    │   ├── src/
    │   │   ├── main/      main.ts · update-service.ts · ipc.ts · last-run.ts
    │   │   ├── preload/   preload.ts（contextBridge，5 方法）
    │   │   ├── renderer/  App.vue · components/ · composables/useUpdateState.ts
    │   │   └── shared/    semver.ts · state-machine.ts · upgrade-detect.ts · types/
    │   ├── electron-builder.yml · vite.config.ts · vitest.config.ts · package.json
    ├── scripts/                                   # 构建 / 发布 / 提供 / 校验
    ├── apt-repository/                            # aptly 仓库 + GPG home（已 gitignore）
    ├── client-config/                             # sources · keyring · apt.conf · systemd 单元
    ├── tests-v2/                                  # 18 用例脚本 + run-all + screenshot
    ├── evidence-v2/                               # 真实运行证据（verdict + 日志 + PNG）
    ├── VALIDATION_REPORT_V2.md                    # 18/18 PASS 真实证据报告
    └── ROOT_OPS_RUNBOOK.md                        # 逐步 sudo runbook
```

构建产物已 gitignore，在本地重新生成——`poc/packages/`（DEB + 解压的 Electron
运行时）、`poc/electron-app/node_modules/`、`poc/dist-electron/`，以及
`poc/apt-repository/gpg-home/` 下的 GPG 材料（绝不提交）。

---

## 复现

### 普通用户（无 sudo）

```bash
# 0. 克隆并一次性安装构建依赖（Node.js 22 + npm；验证机已具备系统工具：
#    aptly、gnupg2、apparmor、dpkg-deb）。
git clone git@github.com:qiuyanlong16/electron-updagre-for-ubuntu-24-poc.git
cd electron-updagre-for-ubuntu-24-poc

# 1. 一次性：创建 aptly 仓库 + 临时 GPG 密钥（仅普通用户）。
bash poc/scripts/setup-repo.sh

# 2. 构建、发布、提供四个版本 DEB。build-version.sh 先跑单测，再 vite build、
#    electron-builder --dir、dpkg-deb --build；verify-versions.sh 校验六处一致。
for v in 1.0.0 1.1.0 1.2.0 1.3.0; do
  bash poc/scripts/build-version.sh $v     # → poc/packages/byclaw_${v}_amd64.deb
  bash poc/scripts/publish-byclaw.sh $v    # → 进 aptly 仓库（重签 InRelease）
done
bash poc/scripts/serve-repo.sh start       # 在 127.0.0.1:8099 提供（| status | stop）

# 3. 单独运行单测套件（纯状态机 + update-service + semver + upgrade-detect
#    + restart-dedup，共 5 个测试文件，40 个用例）。
cd poc/electron-app && npm ci && npx vitest run && cd ../..

# 4. 运行 18 用例验证。普通用户用例真实执行；root / 已安装应用用例在 root 链
#    （见下）完成前自报 NOT-TESTED。
bash poc/tests-v2/run-all-cases.sh

# 5. 切换已提供的更新策略（none | optional | force）。
bash poc/scripts/set-update-policy.sh optional 1.2.0
```

### root 安装链（操作者手动 `sudo`）

已安装应用 / GUI / 篡改用例需要一次性配置客户端。每一步都会说明改了哪些系统文件，
并暂停等你手动 `sudo`——**无 `NOPASSWD`，不索取/保存/回显密码**。完整序列见
[`poc/ROOT_OPS_RUNBOOK.md`](./poc/ROOT_OPS_RUNBOOK.md)：

```bash
sudo dpkg -i poc/packages/byclaw_1.0.0_amd64.deb
sudo bash poc/scripts/install-client-config.sh   # sources + keyring + apt.conf + 定时器
sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.byclaw
sudo apt-get update                                # 注意：此处一个无关 fish-shell PPA 会 404
# 按 runbook 驱动每个用例，之后重跑对应 case-XX.sh；用 poc/tests-v2/screenshot.sh
# 截四张必需的 GUI 截图。
```

> **提示：** 验证机上的 `/var/log/dpkg.log` 被识别为*二进制*文件（一个多余的非文本字节），
> 普通 `grep byclaw` 会静默地不返回任何内容。请用 `grep -a`（文本模式）——见 V2 §5。

---

## 安全姿态

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
绝不由应用执行。应用只查询版本、显示状态、自我重启。

---

## 验证（18 用例——全 PASS）

来自 [`poc/VALIDATION_REPORT_V2.md`](./poc/VALIDATION_REPORT_V2.md) 的真实运行结论，
`feat/byclaw-vue3-redesign` 分支 `b3eabc6`：

| 用例 | 验证内容 | 结论 |
|---:|---|---|
| 01 | 两版本 DEB 可复现构建（六处版本一致） | **PASS** |
| 02 | `/opt/lenovo/byclaw` 普通用户不可写 | **PASS** |
| 03 | 新用户可见应用；OEM 阶段不污染未来用户 Home | **PASS** |
| 04 | Electron 以普通用户运行 | **PASS** |
| 05 | preload/IPC 隔离（5 方法、无禁用 require、无裸 ipcRenderer） | **PASS** |
| 06 | 沙箱开启、无 `--no-sandbox` | **PASS** |
| 07 | 最小化 AppArmor profile 正常 enforce | **PASS** |
| 08 | APT 签名 + `Signed-By` + 客户端配置正确 | **PASS** |
| 09 | 篡改 `InRelease`/DEB 被 APT 拒绝（`BADSIG`） | **PASS** |
| 10 | 只自动升级 Byclaw，全程无密码无 sudo | **PASS** |
| 11 | 应用未运行时升级，下次启动为新版本 | **PASS** |
| 12 | 应用运行期间升级不退出并检测安装完成 | **PASS** |
| 13 | 检查更新、无更新时正确提示 LATEST | **PASS** |
| 14 | 有新版本未安装时不调 APT | **PASS** |
| 15 | 非强制升级「稍后/立即重启」 | **PASS** |
| 16 | 强制升级冻结界面，仅可重启 | **PASS** |
| 17 | 重启后新版本且保持单实例 | **PASS** |
| 18 | 用户配置/模型保留；断网旧版本仍可运行 | **PASS** |

**摘要：18 PASS · 0 FAIL · 0 NOT-TESTED · 0 虚假 PASS。** 四张必需 GUI 截图
（LATEST、UPDATE_AVAILABLE、READY_OPTIONAL、READY_FORCE）由 `gnome-screenshot` 在真实
Wayland 会话抓取，并由现场操作者额外确认（控制器无法渲染 PNG）。两处会导致误判的 bug
（一次升级中途误抓，已隔离为 `case-15-INVALID-*.png`；对二进制识别的 `dpkg.log` 用普通
`grep` 返回空）在记录任何结论前已发现并修复——正是 spec §17.3 要求的纪律
（"禁止用代码审查结论代替运行证据"）。

---

## 已知限制 & 量产前修复

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
