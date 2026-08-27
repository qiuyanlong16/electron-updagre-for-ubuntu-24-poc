# Byclaw Vue 3 + Electron 改造设计文档

- 日期：2026-08-27
- 范围：在现有 `poc/` 原地改造，把 nanobot POC 升级为 Byclaw 产品（Vue 3 + TS + Vite + Electron + electron-builder + dpkg-deb + APT/unattended-upgrades），并补齐「检查更新 / 升级状态 / 强制 / 非强制 / 升级后重启」完整交互与 18 Case 真实验证。
- 不另起新项目；保留 `poc/VALIDATION_REPORT.md`（V1）与旧 nanobot 代码/包作为历史，新增 `poc/VALIDATION_REPORT_V2.md`。
- 旧 V1 报告与证据存在不一致（声称 1.2.0 而所有 evidence 为 1.1.0；Case 13 hash/路径对不上；AppArmor enforce 未被 `aa-status` 捕获；`--no-sandbox` 出现在 `process-user.txt`），**因此 V1 结果不可采信**。V2 须以真实执行证据为准。

---

## 1. 目标与非目标

### 1.1 目标
1. renderer 重写为 Vue 3 + TypeScript + Vite。
2. 主进程/preload 实现安全的升级状态模型与 5 方法 preload API。
3. 两层打包：`electron-builder --dir` → `linux-unpacked` → `dpkg-deb` → `byclaw_X.Y.Z_amd64.deb`，DEB 自包含。
4. 修复 `${VERSION}` postinst 缺陷，单一版本源注入六处并构建期校验一致。
5. 最小化 AppArmor（userns 精确匹配，不依赖 setuid chrome-sandbox）。
6. 修复 Aptly（固定普通用户独占、固定 rootDir/GNUPGHOME、`-config=`、`127.0.0.1`、无 `|| true`）。
7. 18 Case 真实执行证据（root 步骤由用户手动 `sudo` 执行，未执行标 NOT TESTED）。

### 1.2 非目标
- 不实现生产私有 APT 服务，仅输出独立部署说明与接口约定（见 §14.10）。
- 不实现 GitHub Release / electron-updater / 自动下载 DEB 自行安装。
- 不复用 nanobot 1.2.0 作为 byclaw 直升级；从 Byclaw 1.0.0 重建升级链。
- SUID chrome-sandbox 仅作单独评审备选，非默认方案（见 §13.9）。

---

## 2. 现状已确认缺陷（须在本轮修复）

| # | 缺陷 | 位置 | 修复点 |
|---|------|------|--------|
| D1 | `${VERSION}` postinst 不展开（单引号 heredoc `<< 'POSTINST'`），1.0.0→1.3.4 全未修复 | `poc/scripts/build-deb.sh` 与生成产物 `build-*/DEBIAN/postinst` | §12 单一版本源构建期注入 |
| D2 | DEB 不自包含：desktop / AppArmor / 图标不在包内，靠 `init-oem.sh` 包外 cp；postinst 只重载一个 profile；无 postrm；`icon.png` 不存在 | `build-deb.sh`、`init-oem.sh` | §12 自包含 DEB |
| D3 | AppArmor 过宽：launcher `userns+sys_admin`；electron `userns+sys_admin+sys_chroot+dac_read_search+setuid+setgid+fowner+chown`；`/etc/** r`、`/proc/** r`、`/proc/[0-9]*/** rw`、`/sys/** r`、`owner /tmp/** rw`、`/dev/shm/** rw`（重复一次） | `poc/apparmor/com.lenovo.nanobot(.electron)` | §13 重写最小化 |
| D4 | aptly 无 `FileSystemPublishEndpoints`（`filesystem:local:` 未定义）；rootDir 提交版 `/root/.aptly`、运行时 `${HOME}/.aptly` → root 与用户分仓；无脚本传 `-config=`；多处 `|| true` 掩 publish 失败；提交版 gpgKey 历史残留 | `poc/scripts/setup-repo.sh`、`poc/apt-repository/aptly.conf` | §14 重写 |
| D5 | V1 报告与证据不一致：声称 1.2.0 实为 1.1.0；Case 13 hash/路径不符；enforce 未捕获；`--no-sandbox` 见于 `process-user.txt` | `poc/VALIDATION_REPORT.md`、`poc/evidence/*` | 不改 V1；V2 以真实证据重做 |

---

## 3. 命名与路径统一表

| 项 | 值 |
|----|----|
| Debian 包名 | `byclaw` |
| 产品名 | `Byclaw` |
| App ID | `com.lenovo.byclaw` |
| 程序目录 | `/opt/lenovo/byclaw` |
| 主程序入口（electron-builder 产物） | `/opt/lenovo/byclaw/byclaw` |
| Desktop Entry | `/usr/share/applications/com.lenovo.byclaw.desktop` |
| 图标 | `/opt/lenovo/byclaw/resources/icon.png`（随包发布） |
| AppArmor Profile | `/etc/apparmor.d/com.lenovo.byclaw`（按真实产物决定是否需要第二个，见 §13.6） |
| 系统配置 | `/etc/lenovo/byclaw/config.json`（root:root 0644） |
| 升级状态 | `/var/lib/lenovo/byclaw/update-state.json`（root:root，目录 0755，文件 0644） |
| 模型模拟文件 | `/var/lib/lenovo/byclaw/models/` |
| 用户配置（运行时创建） | `app.getPath('userData')` → 默认 `~/.config/lenovo/byclaw/` |
| 用户数据 | `app.getPath('appData')`/`getPath('cache')` 对应 `~/.local/share/lenovo/byclaw/`、`~/.cache/lenovo/byclaw/` |
| APT 源 | `/etc/apt/sources.list.d/byclaw-poc.sources` |
| Keyring | `/usr/share/keyrings/byclaw-poc.gpg` |
| unattended 配置 | `/etc/apt/apt.conf.d/60byclaw-poc-upgrades` |
| systemd 单元 | `byclaw-poc-upgrade.service` / `.timer`（`/etc/systemd/system/`） |
| aptly 仓库名 | `byclaw-poc`；distribution `noble`；component `main`；Origin `Lenovo`；Label `Byclaw` |
| Allowed-Origins | `Lenovo:noble`（byclaw 独立 sources，与 nanobot 不共用） |
| 仓库 HTTP | `http://127.0.0.1:8099/`（POC 固定端口，见 §8.4） |

> 说明：本机已装 nanobot 1.3.3 与 `nanobot-poc.sources`。byclaw 使用独立 sources 文件、独立 aptly 仓库名、独立 Allowed-Origins，二者互不干扰。nanobot 保持现状不动。

---

## 4. 总体架构

```
┌─ 开发/构建（普通用户） ──────────────────────────────────────┐
│  Vue3+TS+Vite  →  electron-builder --dir  →  linux-unpacked   │
│  （extraMetadata.version 注入，不改源码 package.json）        │
│  linux-unpacked + desktop + apparmor + icon + DEBIAN/脚本     │
│     → dpkg-deb --root-owner-group --build                     │
│     → byclaw_X.Y.Z_amd64.deb                                  │
└───────────────────────────────────────────────────────────────┘
                          │ 普通 aptly（固定普通用户）
                          ▼
┌─ 本地 APT 仓库（普通用户独占操作） ─────────────────────────┐
│  aptly repo add / publish（-config=，固定 rootDir/GNUPGHOME）│
│  python3 -m http.server 127.0.0.1:8099（start/status/stop）  │
│  + update-policy.json（升级策略 JSON）                       │
└───────────────────────────────────────────────────────────────┘
                          │ 客户端（root 一次性配置）
                          ▼
┌─ 客户端设备（root 装源/公钥/AppArmor/DEB；之后无人值守） ────┐
│  sources.list.d + keyrings + 60byclaw-poc-upgrades + timer    │
│  unattended-upgrade（root）→ dpkg 换盘文件                   │
│  Byclaw 以普通用户运行（不碰 apt/dpkg/sudo/pkexec）          │
│  Electron 仅查版本/显示状态/重启；不下载安装 DEB             │
└───────────────────────────────────────────────────────────────┘
```

职责分离：
- **electron-builder**：构建 Electron/Vue3 应用运行目录。
- **dpkg-deb**：制作最终系统级 DEB。
- **APT**：分发与升级最终 DEB（含签名 + Hash 校验）。
- **unattended-upgrades（root 后台）**：下载与安装。
- **Electron**：只查询版本、显示状态、重启；不调用 apt/dpkg/sudo/pkexec。

---

## 5. 前端（Vue 3）结构与交互

### 5.1 目录结构（在 `poc/electron-app/` 原地重写）
```
poc/electron-app/
├── src/
│   ├── main/
│   │   ├── main.ts            # 主进程
│   │   ├── update-service.ts  # 状态机 + 策略拉取 + 文件轮询
│   │   └── ipc.ts             # ipcMain.handle 注册
│   ├── preload/
│   │   └── preload.ts         # contextBridge 安全 API
│   ├── renderer/
│   │   ├── App.vue
│   │   ├── main.ts            # Vue 入口
│   │   ├── components/
│   │   │   ├── VersionButton.vue
│   │   │   └── UpdateDialog.vue
│   │   └── types/
│   │       └── update.ts      # UpdateState/UpdateInfo 类型
│   └── shared/
│       └── semver.ts          # semver 比较（主进程与单测共用）
├── electron-builder.yml
├── vite.config.ts
├── tsconfig.json
├── vitest.config.ts
└── package.json
```

### 5.2 主界面元素
1. 产品名「Byclaw」。
2. 当前运行版本「版本 vX.Y.Z」，版本号来自 `app.getVersion()`（经 preload `getCurrentVersion()`），**禁止硬编码**。
3. 版本号可点击，旁注「点击检查更新」。
4. 点击后显示「正在检查更新」（CHECKING）。
5. 无更新显示「当前已是最新版本」（LATEST）。
6. 有更新显示 Vue 弹窗（**禁用浏览器 alert**）。
7. 弹窗显示新版本号、升级类型（optional/force）、简单更新说明（releaseNotes）。

### 5.3 三种弹窗（文案严格按 spec）
- **UPDATE_AVAILABLE**：「发现新版本 X.Y.Z」+「Ubuntu 正在后台准备更新，整个过程不需要输入密码。更新完成后，Byclaw 会通知你重启应用。」按钮「[知道了]」。不显示「下载并安装」，不调 apt。
- **READY_OPTIONAL**：「Byclaw X.Y.Z 已经安装完成」+「重启应用后即可使用新版本。」按钮「[稍后重启] [立即重启]」。稍后可继续用当前版本。
- **READY_FORCE**：「必须更新 Byclaw」+「新版本已经安装完成，需要重启后继续使用。」按钮「[立即重启]」。
  - 不可点遮罩关闭、不可 Esc 关闭、隐藏关闭按钮、冻结主业务区、仅可立即重启。
  - **仅 `installedVersion > runningVersion` 且 mode=force 时冻结**；不得因「服务端有新版本但未安装」提前冻结。

---

## 6. Electron 主进程与 preload 安全 API

### 6.1 BrowserWindow 安全
```ts
webPreferences: {
  preload: path.join(__dirname, 'preload.js'),
  sandbox: true,
  contextIsolation: true,
  nodeIntegration: false,
}
```
- 主进程 `app.enableSandbox()`（whenReady 之前）；`--no-sandbox` 出现即 `app.exit(1)`。

### 6.2 preload（contextBridge，仅暴露 5 方法）
```ts
contextBridge.exposeInMainWorld('byclawAPI', {
  getCurrentVersion: () => ipcRenderer.invoke('byclaw:get-current-version'),
  checkForUpdates:   () => ipcRenderer.invoke('byclaw:check-for-updates'),
  getUpdateState:    () => ipcRenderer.invoke('byclaw:get-update-state'),
  restartApplication:() => ipcRenderer.invoke('byclaw:restart-application'),
  onUpdateStateChanged: (cb) => {
    const listener = (_e, state) => cb(state);
    ipcRenderer.on('byclaw:update-state-changed', listener);
    return () => ipcRenderer.removeListener('byclaw:update-state-changed', listener); // 取消监听
  },
});
```
- 渲染端封装 `useUpdateState()` composable，组件 `onUnmounted` 调 unsubscribe，避免重复注册。

### 6.3 禁止向 renderer 暴露
`ipcRenderer` 整对象、`child_process`、`fs`、`shell`、任意 channel 调用能力。Vue 页面不读系统文件、不访问 APT。

### 6.4 禁用命令清单（Electron/Vue/preload 中严禁出现）
`sudo`、`pkexec`、`apt`、`apt-get`、`dpkg`、`dpkg-query`、`unattended-upgrade`、`systemctl`。仅允许出现在构建脚本、系统安装脚本、自动化测试中。

### 6.5 禁用项
`electron-updater`、Electron `autoUpdater`、GitHub Release 自动下载、下载 DEB 后自行安装、`--no-sandbox`、`chmod 777`、`NOPASSWD: ALL`、`Trusted: yes`。

---

## 7. 升级状态模型

### 7.1 三版本
- `runningVersion`：`app.getVersion()`。
- `installedVersion`：读 `/var/lib/lenovo/byclaw/update-state.json` 的 `installedVersion`。文件不存在/损坏/不可读 → 临时回退 `runningVersion` 以保证启动，但**必须返回 `stateSource: "fallback"`**；UI 不得声称「已验证安装完成」；日志记明确错误。
- `latestVersion`：由**主进程**从本地 HTTP `update-policy.json` 获取。**renderer 不得直接访问更新服务器**。POC 用 HTTP，生产须 HTTPS。

### 7.2 七状态
`CHECKING | LATEST | UPDATE_AVAILABLE | READY_OPTIONAL | READY_FORCE | RESTARTING | ERROR`

### 7.3 判断逻辑（全用 semver，禁字符串比较）
- `latestVersion <= runningVersion` → `LATEST`。
- `latestVersion > runningVersion` 且 `installedVersion <= runningVersion` → `UPDATE_AVAILABLE`（发现新版本但后台未装完）。
- `installedVersion > runningVersion` 且 `mode=optional` → `READY_OPTIONAL`。
- `installedVersion > runningVersion` 且 `mode=force` → `READY_FORCE`。
- `installedVersion == runningVersion` → 不显示「等待重启」。
- 检查更新失败 → `ERROR`，**不冻结窗口、不影响 Byclaw 正常使用**。
- `RESTARTING`：用户点立即重启后置位，给 UI 短暂显示「正在重启」。

> `semver` 比较实现于 `src/shared/semver.ts`，主进程与 Vitest 单测共用同一份，避免双实现。

### 7.4 轮询与推送
- 主进程启动时读一次状态文件；用户点版本号时重读；运行期每 5 秒重读。
- 文件变化经 IPC `byclaw:update-state-changed` 推送 renderer（`webContents.send`）。
- 状态文件读取失败仅记日志，**不退出程序**。

### 7.5 强制规则
- 仅 `installedVersion > runningVersion` 可进入 `READY_OPTIONAL`/`READY_FORCE`。
- 仅 `READY_FORCE` 冻结主界面。
- 服务端「有新版本但未安装」不得冻结。

---

## 8. 模拟升级策略服务

### 8.1 update-policy.json（由主进程拉取）
```json
{
  "product": "byclaw",
  "channel": "stable",
  "latestVersion": "1.1.0",
  "minimumSupportedVersion": "1.0.0",
  "mode": "optional",
  "releaseNotes": ["升级为 Vue 3 页面", "增加系统升级完成检测", "增加强制/非强制升级交互"]
}
```

### 8.2 三种策略脚本
- `./scripts/set-update-policy.sh none` → latestVersion = 当前版本。
- `./scripts/set-update-policy.sh optional` → mode=optional。
- `./scripts/set-update-policy.sh force` → mode=force。

### 8.3 配置来源
- 策略 URL 从 `/etc/lenovo/byclaw/config.json`（root-owned）的 `updatePolicyUrl` 读取，**禁止硬编码于 Vue/renderer**。主进程读该配置；renderer 只通过 preload `checkForUpdates()` 间接得到结果。

### 8.4 HTTP server（POC，127.0.0.1）
- 默认仅监听 `127.0.0.1:8099`（选 8099 避开已装 nanobot 仓库占用的 8080，两仓互不干扰）。两台 VM 场景再显式配置测试网卡 IP；**不得无说明监听 `0.0.0.0`**。
- 提供 `scripts/serve-repo.sh {start|status|stop}`：start 记 PID 到 `poc/apt-repository/.server.pid`、日志到 `poc/logs/serve-repo.log`；status 检查 PID 存活 + `curl` 探活；stop 按 PID 终止。
- 策略接口只告知「是否有版本、是否强制」；**DEB 真实性仍由 APT 仓库签名 + Hash 校验保证**，策略接口不作包安全校验依据。

### 8.5 生产约束
- POC 用本地 HTTP；生产必须 HTTPS。Electron 只查询版本与显示状态，不下载/安装 DEB；下载安装由系统后台 APT/unattended-upgrades 完成。

---

## 9. postinst 原子写 update-state.json

### 9.1 postinst 行为（幂等）
- 安装成功后原子写 `/var/lib/lenovo/byclaw/update-state.json`：
```json
{ "status": "installed", "installedVersion": "1.1.0", "installedAt": "2026-08-27T10:00:00Z" }
```
- `installedVersion` 由**构建期注入**（postinst 模板占位符替换为字面版本，不依赖运行时变量）；`installedAt` 由 postinst **运行时** `date -u +%Y-%m-%dT%H:%M:%SZ` 生成。
- 目录 `root:root 0755`；文件 `root:root 0644`。
- 用临时文件写再 `mv` 原子替换。
- 读失败仅记日志，不导致程序退出（见 §7.4）。

### 9.2 维护脚本
- `postinst`：创建 `/var/lib/lenovo/byclaw/` 与 `models/`；写 update-state.json；装 desktop entry（已在包内 → `update-desktop-database`）；装 + 重载 AppArmor（`apparmor_parser -r`，失败记日志但**不阻断安装**? 见 §13.8 边界）；`logger -t byclaw`。
- `prerm`：刷新 desktop 缓存。
- `postrm`：purge 时清理系统侧 `/var/lib/lenovo/byclaw` 与 `/etc/lenovo/byclaw`；**不清理用户 Home**（用户数据保留，见 §11.4）。
- 全部幂等；`set -e` 但对 `update-desktop-database`/`apparmor_parser` 等非致命步骤用 `|| <记日志>` 而非 `|| true` 静默吞错。

---

## 10. 立即重启

- 主进程执行：`app.relaunch(); app.exit(0);`。
- **不用** `electron-updater.quitAndInstall()`；不执行 apt/dpkg/sudo/pkexec。
- `requestSingleInstanceLock()` 保证单实例；重启后启动磁盘新版本。
- 防重复点击：置 `RESTARTING` 态后按钮置灰。
- 重启前给 renderer 短暂显示「正在重启」。

---

## 11. 首次升级后提示

### 11.1 存储
- 用 `app.getPath('userData')` 获取当前消费者配置目录，写 `last-run.json`：
```json
{ "lastSeenVersion": "1.0.0" }
```
- **不硬编码 `~/.config`**；由 Electron 决定路径。

### 11.2 显示条件
- OEM 制像阶段**不得向任何未来用户 Home 写文件**（无 `init-oem` 写 `~/.config/...`）。
- 首次运行无 `lastSeenVersion` → 不显示「升级成功」。
- 仅当 `lastSeenVersion` 存在且 `getVersion()` semver 大于 `lastSeenVersion` 时，显示「Byclaw 已更新到 X.Y.Z」横幅，随后写入 `lastSeenVersion = getVersion()`。
- 升级**不得删除用户配置文件**。

### 11.3 证据要求
- Case 必须保存升级前后用户配置文件 SHA256（见 §17 Case 18）。

---

## 12. 两层打包流程

### 12.1 流程
```
build-version.sh <VERSION>
  → vite build（renderer → dist）
  → electron-builder --dir（extraMetadata.version=<VERSION>，linux-unpacked，不产 DEB）
  → 组装 staging 目录：/opt/lenovo/byclaw ← linux-unpacked 内容
  → 加 desktop entry、AppArmor、icon、/etc/lenovo/byclaw/config.json、/var/lib/lenovo/byclaw/
  → 加 DEBIAN/{control,postinst,prerm,postrm}（postinst 的 installedVersion 构建期注入）
  → dpkg-deb --root-owner-group --build staging byclaw_<VERSION>_amd64.deb
```

### 12.2 不永久改源码 package.json
- 用 electron-builder `extraMetadata.version`（命令行 `-c.extraMetadata.version=<VERSION>` 或 `--config.extraMetadata.version`）注入版本到产物内 package.json，使 `app.getVersion()` 返回 `<VERSION>`。源码 `poc/electron-app/package.json` 的 version 字段保持基线（如 `0.0.0-dev`），构建用临时目录与生成的元数据，**不回写源码**。

### 12.3 单一版本源六处一致
`build-version.sh <VERSION>` 必须使以下全部等于 `<VERSION>`：
1. `app.getVersion()`（产物 package.json，来自 extraMetadata）
2. `DEBIAN/control` 的 `Version`
3. `postinst` 写入 `update-state.json` 的 `installedVersion`
4. DEB 文件名 `byclaw_<VERSION>_amd64.deb`
5. `update-policy.json` 的 `latestVersion`（**由 build-version.sh 一并生成为构建产物**，publish 时部署到仓库 HTTP 根）
6. APT `Packages` 索引中的 `Version`（来自 deb 的 control，aptly publish 后形成）

校验分两步：
- **构建后**：`verify-versions.sh` 校验 1/2/3/4（从 deb 与产物读）+ 5（从生成的 update-policy.json 读）；任一不符即非零退出（构建失败）。
- **发布后**：同一脚本对已发布的 APT `Packages` 索引（6）与 HTTP 上 `update-policy.json`（5）再校验一次，确保线上与构建一致。

> 因此 `update-policy.json` 的 `latestVersion` 是构建产物，不手工维护；发布即部署该产物。

### 12.4 产物自包含
DEB 内含：`/opt/lenovo/byclaw`（程序+资源+图标）、`/usr/share/applications/com.lenovo.byclaw.desktop`、`/etc/apparmor.d/com.lenovo.byclaw`（按 §13）、`/etc/lenovo/byclaw/config.json`、`/var/lib/lenovo/byclaw/`（占位）、`DEBIAN/{control,postinst,prerm,postrm}`。**不再依赖 `init-oem.sh` 单独复制 desktop/AppArmor**。

---

## 13. AppArmor 最小化（默认 userns 方案）

### 13.1 方向（Ubuntu 24.04 官方推荐：精确匹配 + userns）
默认采用「AppArmor 精确匹配程序路径 + userns」，**不默认依赖 setuid chrome-sandbox**。推荐起点：
```
abi <abi/4.0>,
include <tunables/global>

/opt/lenovo/byclaw/byclaw flags=(unconfined) {
  userns,
  include if exists <local/com.lenovo.byclaw>
}
```
- `flags=(unconfined)` + `userns`：profile 附着到真实入口二进制，但以 unconfined 运行（满足 Chromium 广泛文件访问需求），仅对 userns 创建施加控制并可叠加 deny。
- **具体语法必须在 Ubuntu 24.04 实机用 `apparmor_parser` 与 `aa-status` 验证。**

### 13.2 强制要求
1. 只匹配 electron-builder 实际生成并最终安装的主程序路径。
2. 保留 Electron/Chromium 沙箱。
3. 禁止 `--no-sandbox`。
4. 禁止全局关闭 `kernel.apparmor_restrict_unprivileged_userns`。
5. 禁止 `sys_admin/sys_chroot/dac_read_search/setuid/setgid/fowner/chown` 等宽泛 Capability。
6. 不再用 `/etc/**`、`/proc/** rw`、`/sys/**` 等宽泛规则。
7. `chrome-sandbox` **不默认设置 4755**。
8. 不混用 userns AppArmor 与 SUID 两套沙箱方案。
9. 是否需要两个 Profile，**根据 electron-builder 真实产物决定**；若仅一个实际入口，不强行创建两个。
10. 若真实 Wayland 中 userns 方案失败 → 对应 Case 标 **FAIL**；先确认 Profile 是否匹配真实可执行文件，**不得静默切换 SUID**。
11. SUID chrome-sandbox 仅作单独评审备选，非默认。

### 13.3 与 electron-builder 产物的匹配
- `electron-builder --dir` 产物 `linux-unpacked/` 含产品名二进制（`byclaw`）、`resources/app.asar`、`chrome-sandbox`、`*.so`、`locales/`。安装后主入口为 `/opt/lenovo/byclaw/byclaw`。预期**单 profile** 匹配该路径。
- 实机构建后用 `file` / `readlink` 确认真实入口路径再定 profile subject。

### 13.4 chrome-sandbox 处理
- 不 chmod 4755；保持 0755。Electron 在支持 unprivileged userns 的内核上以 userns 沙箱运行，无需 setuid helper。
- 若实机验证发现 Electron 仍尝试 exec `chrome-sandbox`，profile 中按需加窄规则；不改 SUID。

### 13.5 禁全局 userns 限制
- 不修改 `/proc/sys/kernel/unprivileged_userns_clone`、不设 `kernel.apparmor_restrict_unprivileged_userns=0`。

### 13.6 profile 数量决策
- 构建产物若仅 `/opt/lenovo/byclaw/byclaw` 一个实际入口 → 单 profile `com.lenovo.byclaw`。
- 若 electron-builder 额外产生需独立 confine 的入口（实测后判断）→ 再加；否则不强求第二个。

### 13.7 发布与重载
- profile 文件打入 DEB `/etc/apparmor.d/com.lenovo.byclaw`；postinst 执行 `apparmor_parser -r`。

### 13.8 失败处理边界
- `apparmor_parser -r` 失败：postinst 记日志，**不使 dpkg 安装失败**（profile 可后续修复），但 Case 7 须如实记录 enforce 结果（PASS/FAIL）。

### 13.9 SUID 备选评审（非默认）
- 仅作为独立评审段落：若 userns 方案在真实 Wayland 失败且经查非 profile 匹配问题，可在**单独评审**中尝试 setuid chrome-sandbox 方案并记录对比；不作为本次默认，不覆盖默认 profile。

---

## 14. Aptly 修复

### 14.1 固定普通用户独占
- 所有 `aptly create/add/snapshot/publish` **只由固定普通用户执行**（开发机即 `qiuyanlong`）。
- **禁止 root 与普通用户交替修改同一 aptly 数据库**。
- root 只负责：安装客户端仓库配置、安装仓库公钥、加载 AppArmor、安装 DEB、启动 unattended-upgrades 验证。

### 14.2 固定路径
- `rootDir` 固定绝对路径，不依赖 `${HOME}`：`/home/qiuyanlong/worespace/by-claw-poc-linux/poc/apt-repository/aptly-db`。
- `FileSystemPublishEndpoints` 的 `local` → 该 rootDir 下 `public`。
- 固定 `GNUPGHOME`：`poc/apt-repository/gpg-home`（不依赖执行用户 `~/.gnupg`）。
- `poc/apt-repository/aptly.conf` 为唯一配置源。

### 14.3 显式 -config= 与去 || true
- 所有 aptly 命令显式 `aptly -config=<REPO>/aptly.conf ...`。
- 删除关键步骤（`repo create`、`publish repo`、`publish update`、`repo add`）的 `|| true` 与 `2>/dev/null || true`。
- publish 失败必须非零退出。

### 14.4 filesystem endpoint 完整
设 `REPO=/home/qiuyanlong/worespace/by-claw-poc-linux/poc/apt-repository`（脚本中以绝对路径注入）。aptly.conf 包含：
```json
{
  "rootDir": "<REPO>/aptly-db",
  "architectures": ["amd64"],
  "gpgProvider": "gpg2",
  "gpgDisableSign": false,
  "skipContents": true,
  "FileSystemPublishEndpoints": { "local": { "rootDir": "<REPO>/aptly-db/public", "linkMethod": "copy" } }
}
```
（`<REPO>` 在生成时替换为绝对路径；提交版 aptly.conf 不硬编码历史 gpgKey fingerprint，gpgKey 在运行时从固定 GNUPGHOME 动态取得，经命令行 `--gpg-key` 传入。）

### 14.5 GPG
- 固定 GNUPGHOME 生成/使用 POC 密钥（POC 可 `%no-protection`），公钥导出到 `poc/apt-repository/byclaw-poc-public.gpg`，客户端装到 `/usr/share/keyrings/byclaw-poc.gpg`（0644）。

### 14.6 HTTP server（POC）
- `python3 -m http.server --bind 127.0.0.1 8099`，rootDir = `aptly-db/public`（含 `dists/`、`pool/`、`update-policy.json`）。
- `serve-repo.sh {start|status|stop}`，PID + 日志（§8.4）。
- 两台 VM 再显式绑测试网卡 IP；不无说明 `0.0.0.0`。

### 14.7 Origin/Label/Allowed-Origins 锁步
- publish `-origin=Lenovo -label=Byclaw -distribution=noble`；`60byclaw-poc-upgrades` 的 `Allowed-Origins {"Lenovo:noble";}`；二者不一致即报错。

### 14.8 选择性升级
- `Package-Whitelist {"^byclaw$";}` + `Package-Blacklist {"unrelated-poc"; "random-test-poc";}`（POC 验证只升 byclaw；unattended whitelist 非严格，须配 blacklist）。

### 14.9 root 职责脚本（用户手动 sudo）
- `scripts/install-client-config.sh`（root）：装 sources、keyring、60byclaw-poc-upgrades、systemd 单元、enable timer。每步说明改哪些系统文件，执行前暂停等用户。

### 14.10 生产私有 APT 服务（仅说明）
- 本轮不实现；输出 `docs/deployment/private-apt-contract.md`：接口约定（HTTPS、签名密钥轮换、Origin/Label、Allowed-Origins、版本索引字段、Hash 校验）、与 POC 的差异、生产部署步骤要点。

---

## 15. unattended-upgrades 与 systemd

- 复用既有机制：`byclaw-poc-upgrade.timer`（OnBootSec=1min、OnUnitActiveSec=2min，POC 值）→ `byclaw-poc-upgrade.service`（oneshot，`ExecStart=/usr/bin/unattended-upgrade -v`，Nice=19，IOSchedulingClass=idle，root）。
- 客户端配置由 `byclaw-poc-repo-config` DEB 或 `install-client-config.sh` 安装。
- 独立 Origin/Sources/Allowed-Origins，不与 nanobot 共用。
- 只自动升级 byclaw，不升级无关测试包（whitelist+blacklist）。
- 升级由 root 后台完成，普通用户全程不输 sudo/密码。

---

## 16. 安全要求清单（不可破坏）

- 签名 APT 仓库；unattended-upgrades 无密码升级。
- `/opt` 普通用户不可写；Electron 不以 root 运行。
- 不用 sudo/pkexec/apt/dpkg（应用运行时）。
- Electron Sandbox 开启；`--no-sandbox` 拒绝。
- 用户数据与模型文件升级后保留。
- 仓库不可用时旧版本仍能运行（Electron 不强依赖策略接口，失败回退 LATEST/ERROR 但不崩）。
- 只自动升级 Byclaw。
- 不向未来消费者 Home、`/root`、`/etc/skel` 写数据（OEM 阶段）。
- 不全局关 userns 限制；不 chmod 777；不 NOPASSWD: ALL；不 Trusted: yes。

---

## 17. 18 Case 验证方法论

### 17.1 每 Case 字段
前置条件 / 执行命令 / 实际结果 / 日志证据 / GUI 截图（适用时）/ PASS|FAIL|NOT TESTED。

### 17.2 18 Case 清单（与测试脚本一一对应）

| Case | 验证内容 | 主执行者 |
|---:|---|---|
| 1 | Vue3+Electron 构建两个版本 DEB | 普通用户 |
| 2 | 程序安装到 `/opt/lenovo/byclaw` 且普通用户不可写 | root（用户执行） |
| 3 | 后创建用户能看到应用，OEM 阶段不污染未来用户 Home | root + 普通用户 |
| 4 | Electron 以消费者普通用户运行 | 普通用户 |
| 5 | preload/IPC 安全隔离正确 | 普通用户（代码+运行） |
| 6 | Sandbox 开启且无 `--no-sandbox` | 普通用户 |
| 7 | 最小化 AppArmor Profile 正常 enforce | root + 普通用户 |
| 8 | APT 仓库签名、`Signed-By` 与客户端配置正确 | root（用户执行） |
| 9 | 篡改 InRelease 或 DEB 后 APT 拒绝升级 | root（用户执行） |
| 10 | 只自动升级 Byclaw，全程无密码无 sudo | root（用户执行） |
| 11 | Byclaw 未运行时升级，下次直接启动新版本 | root + 普通用户 |
| 12 | Byclaw 运行期间升级不退出，并检测安装完成 | root + 普通用户 |
| 13 | 点击版本号检查更新，无更新时正确提示 | 普通用户 |
| 14 | 有新版本但尚未安装时显示提示，不调用 APT | 普通用户 |
| 15 | 非强制升级显示「稍后/立即重启」 | 普通用户 |
| 16 | 强制升级冻结业务界面，只允许立即重启 | 普通用户 |
| 17 | 重启后运行新版本且保持单实例 | 普通用户 |
| 18 | 用户配置、模型数据保留；断网时旧版本仍可运行 | root + 普通用户 |

### 17.3 验证纪律
- root 步骤：先生成精确 root 命令脚本，每次执行前说明改哪些系统文件，**暂停等用户手动 `sudo` 执行**，从 `poc/evidence-v2/` 读真实输出。
- 未真实执行的 root Case 一律 NOT TESTED，**不写 PASS**。
- 禁止创建 NOPASSWD；禁止索取/保存/回显 sudo 密码；禁止用代码审查结论代替运行证据。
- 保留旧 `VALIDATION_REPORT.md` 不修改；新报告 `VALIDATION_REPORT_V2.md`。对旧报告描述用「报告与证据不一致，因此结果不可采信」，**不用「造假」等主观措辞**。

### 17.4 真实桌面验证（不只 Xvfb）
- 保存 `echo "$XDG_SESSION_TYPE"` 证据（实测 `wayland`）。
- 至少完成主要 Wayland 验证；X11 兼容可选；**Xvfb 不可替代真实桌面证据**。
- 必要截图四张：
  1. Byclaw 1.0.0 主界面。
  2. 普通更新弹窗（optional UPDATE_AVAILABLE）。
  3. 强制更新冻结弹窗（READY_FORCE）。
  4. 系统已装 1.1.0 但旧进程仍显 1.0.0 → 点重启 → 新进程显 1.1.0。
- GUI 未验证时标 NOT TESTED。

---

## 18. 自动化测试

### 18.1 Vitest（状态机，`src/shared/semver.ts` + `update-service.ts` 纯函数）
覆盖：
1. 1.0.0 vs 1.0.0 → LATEST
2. running 1.0.0，latest 1.1.0，installed 1.0.0 → UPDATE_AVAILABLE
3. running 1.0.0，installed 1.1.0，optional → READY_OPTIONAL
4. running 1.0.0，installed 1.1.0，force → READY_FORCE
5. 1.10.0 vs 1.9.0 正确 SemVer 比较
6. 状态文件不存在 → fallback + stateSource=fallback
7. 状态文件损坏 → fallback + stateSource=fallback + 日志错误
8. 策略接口超时 → ERROR，不冻结
9. 重复点击检查更新 → 去重（不并发触发）
10. 重复点击立即重启 → 去重（仅 relaunch 一次）

### 18.2 Shell 自动化（18 Case 脚本）
- `poc/tests-v2/case-01.sh` … `case-18.sh`，与 `run-all-cases.sh` 一一对应。
- 普通 Case 自动跑；root Case 输出「等待用户手动执行 root 步骤」并暂停/收集 evidence。
- GUI 截图脚本（`scrot`）在真实会话执行。

---

## 19. 交付物清单

1. 修改后的完整源码。
2. 一键安装依赖与构建命令（`scripts/bootstrap.sh` + `build-version.sh`）。
3. Byclaw 1.0.0 与 1.1.0 两个 DEB。
4. 一键发布 1.1.0 到本地 APT 仓库的脚本（`publish-byclaw.sh 1.1.0`）。
5. 三种升级策略切换脚本（`set-update-policy.sh {none|optional|force}`）。
6. 自动化验收脚本（18 Case + Vitest）。
7. GUI 截图（四张）。
8. 更新后的 README.md / README.zh-CN.md。
9. `VALIDATION_REPORT_V2.md`（18 Case 真实证据）。
10. 文件级修改清单。
11. 实际执行命令及真实输出。
12. 未验证项目与剩余风险。
13. `docs/deployment/private-apt-contract.md`（生产部署说明与接口约定）。

---

## 20. 执行顺序与 root 暂停点

### 20.1 计划确认后普通用户可立即执行
- 安装 npm 依赖、Vite/Vue3 脚手架、写源码、Vitest 单测、`build-version.sh 1.0.0` 与 `1.1.0`、构建 linux-unpacked、`dpkg-deb --build`（普通用户可建，`--root-owner-group` 仅置元数据属主）、aptly repo add/publish（普通用户独占）、serve-repo start、本地 HTTP 策略切换、真实会话启动 app + `scrot` 截图（Case 1/4/5/6/13/14/15/16/17 的普通用户部分）。

### 20.2 root 暂停点（用户手动 sudo，执行前说明 + 暂停）
- 安装 keyring + sources + 60byclaw-poc-upgrades + systemd 单元（Case 8/10）。
- `dpkg -i byclaw_1.0.0` 与升级到 1.1.0（Case 2/11/12/17/18）。
- `apparmor_parser -r` + `aa-status`（Case 7）。
- 篡改 InRelease/DEB 后 `apt-get update`/`apt-get install` 验证拒绝（Case 9）。
- 启动 unattended-upgrade 验证（Case 10/11/12）。

### 20.3 不立即执行 root
本设计文档与实施计划交付后，**先由用户检查**；root 操作在实施阶段按 §17.3 逐步暂停等待。

---

## 21. 范围排除与剩余风险

- 生产私有 APT 服务：仅输出说明，不在本轮实现。
- 生产 HTTPS 策略接口、密钥轮换/吊销：不在本轮。
- timer 2 分钟为 POC 值，生产应日级。
- unattended whitelist 非严格，须靠 blacklist 兜底（已知限制）。
- AppArmor userns 方案在真实 Wayland 是否成功须经实机验证；失败即标 FAIL，不静默切 SUID。
- 旧 V1 报告不可采信，V2 以真实证据为准；部分 root Case 若用户未执行则 NOT TESTED。
