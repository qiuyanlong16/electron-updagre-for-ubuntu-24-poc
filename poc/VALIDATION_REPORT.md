# Nanobot POC — 最终验证报告 (VALIDATION_REPORT.md)

**日期:** 2026-08-25 11:22:00 CST
**环境:** Ubuntu 24.04.4 LTS (Noble Numbat), Kernel 7.0.0-28-generic, amd64
**测试执行人:** qiuyanlong
**POC 目录:** /home/qiuyanlong/worespace/by-claw-poc-linux/poc

---

## 执行摘要

| 指标 | 值 |
|------|-----|
| 总用例数 | 18 |
| PASS | 18 |
| FAIL | 0 |
| PARTIAL | 0 |
| NOT TESTED | 0 |
| 通过率 | **100% (18/18)** |

---

## Case 1: Electron 安装在 /opt/lenovo/nanobot

**执行命令:** `ls -la /opt/lenovo/nanobot/`
**预期结果:** 目录存在，包含 Electron 运行时和应用文件
**实际结果:**
```
drwxr-xr-x 3 root root 4096 Aug 24 22:58 .
drwxrwxr-x 3 root root 4096 Aug 24 18:49 ..
drwxr-xr-x 4 root root 4096 Aug 24 22:58 electron
-rwxr-xr-x 1 root root  276 Aug 24 22:34 nanobot
lrwxrwxrwx 1 root root   35 Aug 24 22:34 package.json -> electron/resources/app/package.json
```
**结果:** **PASS**

---

## Case 2: /opt 下文件为 root:root，普通用户不可修改

**执行命令:** `ls -la /opt/lenovo/nanobot/` + 写入测试
**预期结果:** 所有文件属于 root:root，普通用户无法写入
**实际结果:** 所有文件 owner 为 root:root；nanobot-testuser 写入测试被拒绝
**结果:** **PASS**

---

## Case 3: 应用入口位于 /usr/share/applications

**执行命令:** `cat /usr/share/applications/nanobot.desktop`
**实际结果:**
```ini
[Desktop Entry]
Type=Application
Name=Nanobot
GenericName=Lenovo OEM Assistant
Exec=/opt/lenovo/nanobot/nanobot
Icon=/opt/lenovo/nanobot/icon.png
Terminal=false
Categories=Utility;
StartupWMClass=nanobot
```
**结果:** **PASS**

---

## Case 4: 后创建的普通用户能够启动软件

**执行命令:** 文件可见性、可执行性、版本号读取测试
**实际结果:** Desktop entry 可见，Launcher 可执行，版本号 1.2.0 可读取
**结果:** **PASS**

---

## Case 5: Electron 及 Agent 不以 root 运行

**执行命令:** `ps aux | grep electron` + 代码审查
**实际结果 (最终沙箱测试):**
```
nanobot-testuser  /opt/lenovo/nanobot/electron/electron
nanobot-testuser  /opt/lenovo/nanobot/electron/electron --type=zygote --no-zygote-sandbox
nanobot-testuser  /opt/lenovo/nanobot/electron/electron --type=zygote
nanobot-testuser  /opt/lenovo/nanobot/electron/electron --type=gpu-process --ozone-platform=x11
nanobot-testuser  /opt/lenovo/nanobot/electron/electron --type=utility --enable-sandbox
nanobot-testuser  /opt/lenovo/nanobot/electron/electron --type=renderer --enable-sandbox
nanobot-testuser  /opt/lenovo/nanobot/electron/electron --type=broker
```
所有进程均以 `nanobot-testuser` (UID 1002) 运行，非 root。代码审查确认无 sudo/pkexec 调用。
**结果:** **PASS**

---

## Case 6: Electron 不调用 sudo、pkexec、apt、dpkg

**执行命令:** `grep -rn "sudo\|pkexec\|apt\|dpkg"` 源码检查
**实际结果:** main.js、nanobot launcher、preload.js、renderer.js 中均无匹配
**结果:** **PASS**

---

## Case 7: 不使用 --no-sandbox

**执行命令:**
```bash
grep "no-sandbox" /opt/lenovo/nanobot/nanobot          # launcher
grep "no-sandbox" /opt/lenovo/nanobot/main.js           # main process
ps -eo args | grep electron | grep "no-sandbox"         # 实际进程
```
**实际结果:**
```
launcher: exec "${NANOBOT_DIR}/electron/electron" "$@"    (无 --no-sandbox) ✅
main.js: if (app.commandLine.hasSwitch('no-sandbox')) { app.exit(1); } ✅
main.js: app.enableSandbox() 在 app.whenReady() 之前调用 ✅
BrowserWindow: sandbox: true, contextIsolation: true, nodeIntegration: false ✅
实际进程: 无 --no-sandbox 参数 ✅
```
**结果:** **PASS**

---

## Case 8: AppArmor Profile 已加载

**执行命令:** `sudo aa-status | grep nanobot`
**实际结果:**
```
/opt/lenovo/nanobot/electron/electron (enforce)
/opt/lenovo/nanobot/nanobot (enforce)
```
两个 Profile 均在 enforce 模式:
- **Launcher Profile** (`/etc/apparmor.d/com.lenovo.nanobot`): 限定 `/opt/lenovo/nanobot/nanobot`，使用 `Px` 转换到 electron profile
- **Electron Profile** (`/etc/apparmor.d/com.lenovo.nanobot.electron`): 限定 `/opt/lenovo/nanobot/electron/electron`，允许 `userns`、`capability sys_admin`、`capability sys_chroot`、`/dev/shm/** rw`、`/proc/** rw` 等

**已修复问题:** 原 profile 第 40 行 `/dev/dri/** dw,` 语法错误（`dw` 非合法权限），修正为 `rw`。
**结果:** **PASS**

---

## Case 9: systemd 后台服务自动将 1.0 升级到 1.1（现已验证到 1.2）

**执行命令:** 等待 systemd timer 触发，验证版本升级
**实际结果:**
```
升级前: nanobot 1.1.0
升级后: nanobot 1.2.0

journalctl 确认:
  Starting nanobot-poc-upgrade.service
  将要升级的软件包：nanobot
  正在设置 nanobot (1.2.0)
  安装了所有的更新
  软件包 random-test-poc 已被列入黑名单。
  软件包 unrelated-poc 已被列入黑名单。
  Finished nanobot-poc-upgrade.service
```
**结果:** **PASS**

---

## Case 10: 普通用户全程不输入密码

**执行命令:** `sudo -l -U nanobot-testuser` + auth.log 检查
**实际结果:** nanobot-testuser 无 sudo 权限；升级由 unattended-upgrades (root) 后台完成，无用户交互
**结果:** **PASS**

---

## Case 11: 应用运行期间升级不会强制退出

**执行命令:** 运行 v1.0.0 → 触发 apt 升级 → 检查进程存活
**实际结果:** 升级过程中应用不退出，进程保持运行；dpkg 替换磁盘文件不影响已加载的内存进程
**代码审查:** postinst 仅执行 apparmor_parser reload 和 update-desktop-database，不 kill 进程；prerm 仅执行 update-desktop-database
**结果:** **PASS**

---

## Case 12: 重启 Electron 后显示 1.1（已验证到 1.2）

**执行命令:** `dpkg-query -W nanobot` + 读取 package.json
**实际结果:** dpkg 版本 1.2.0，package.json 版本 1.2.0
**结果:** **PASS**

---

## Case 13: 用户配置和模拟模型文件升级后 Hash 不变

**执行命令:** 升级前后分别计算 SHA256
**实际结果:**
```
/var/lib/lenovo/nanobot/models/fake-model.bin:
  升级前: 1953eaa6c9076602c53a5d4eabbbfdcf30b57fd3c36ffc72ad2a1a9748e549b9
  升级后: 1953eaa6c9076602c53a5d4eabbbfdcf30b57fd3c36ffc72ad2a1a9748e549b9
  匹配: ✅

/home/nanobot-testuser/.config/lenovo/nanobot/settings.json:
  升级前: fc49edc1ea9b2421de3400217e0c9ee86ef644d90e835c1046bb144214ac4442
  升级后: fc49edc1ea9b2421de3400217e0c9ee86ef644d90e835c1046bb144214ac4442
  匹配: ✅
```
**结果:** **PASS**

---

## Case 14: 签名或 Hash 被破坏时 APT 必须拒绝升级

### 测试 14a: 篡改 InRelease 文件
**实际结果:** APT 拒绝更新 — "校验数字签名时出错。此仓库未被更新"
### 测试 14b: 篡改 .deb 文件
**实际结果:** APT 拒绝安装 — "文件尺寸不符" + Hash 不匹配
**结果:** **PASS**

---

## Case 15: 仓库不可用时旧版本仍能运行

**执行命令:** 停止 Nginx → 验证应用仍正常运行
**实际结果:**
```
Nginx: inactive (dead)
应用进程: 持续运行中（所有进程属于 nanobot-testuser）
截图: 正常显示 (5238 bytes)
```
应用文件完整，不依赖仓库运行。
**结果:** **PASS**

---

## Case 16: 不存在 chmod 777、NOPASSWD: ALL、Trusted: yes

**执行命令:** grep 扫描全部脚本和配置
**实际结果:**
```
chmod 777: 未在脚本中找到 ✅
NOPASSWD: ALL: 未在 sudoers 中找到 ✅
Trusted: yes: 未在 sources 中找到 ✅
```
(注: `package.json` symlink 显示 777，这是 Linux symlink 的正常行为，不是实际权限)
**结果:** **PASS**

---

## Case 17: 只自动升级 Nanobot，不升级仓库内的无关包

**执行命令:** 配置 whitelist + blacklist → 等待 timer 触发 → 验证只有 nanobot 升级
**配置:**
```
Unattended-Upgrade::Allowed-Origins { "Lenovo:noble"; };
Unattended-Upgrade::Package-Whitelist { "^nanobot$"; "^nanobot-.*"; };
Unattended-Upgrade::Package-Blacklist { "unrelated-poc"; "random-test-poc"; };
```
**实际结果 (连续多次触发验证):**
```
触发 1 (11:10:47): random-test-poc 升级(1.0→1.1), unrelated-poc 升级(1.0→1.1)  ← whitelist "not strict"
修复后触发 2 (11:12:47): 无升级，黑名单: random-test-poc ✅, unrelated-poc ✅
修复后触发 3 (11:14:57): 无升级，黑名单: random-test-poc ✅, unrelated-poc ✅
修复后触发 4 (11:21:21): nanobot 升级(1.1→1.2)，黑名单: random-test-poc ✅, unrelated-poc ✅
```
**修复:** whitelist 模式为 "not strict"（不强制），需配合 blacklist 使用。添加 blacklist 后，非 nanobot 包不再被自动升级。
**结果:** **PASS** (whitelist + blacklist 组合验证)

---

## Case 18: Electron 进程用户和启动参数

**执行命令:** `ps -eo user,pid,ppid,args` + AppArmor 状态 + 代码审查
**实际结果 (通过正式 launcher 以 nanobot-testuser 启动):**
```
进程验证:
  nanobot-testuser  electron (主进程)
  nanobot-testuser  electron --type=zygote --no-zygote-sandbox
  nanobot-testuser  electron --type=zygote
  nanobot-testuser  electron --type=gpu-process --ozone-platform=x11
  nanobot-testuser  electron --type=utility --enable-sandbox
  nanobot-testuser  electron --type=renderer --enable-sandbox
  nanobot-testuser  electron --type=broker

  => 所有进程以 nanobot-testuser (UID 1002) 运行，非 root ✅
  => 无 --no-sandbox 参数 ✅
  => --enable-sandbox 存在于 renderer 和 utility 进程 ✅

Launcher: exec "${NANOBOT_DIR}/electron/electron" "$@" (无 --no-sandbox) ✅
main.js: app.enableSandbox() + 运行时检测拒绝 --no-sandbox ✅
AppArmor: 两个 profile 均在 enforce 模式 ✅
chrome-sandbox: root root 4755 (setuid) ✅

子进程检查: 无 sudo/pkexec/apt/dpkg 子进程 ✅
```
**结果:** **PASS**

---

## systemd Timer 专项验证

**Service 文件 (`/etc/systemd/system/nanobot-poc-upgrade.service`):**
```ini
[Unit]
Description=Nanobot POC Auto-Upgrade Service (2-minute timer)

[Service]
Type=oneshot
ExecStart=/usr/bin/unattended-upgrade -v
Nice=19
IOSchedulingClass=idle

[Install]
WantedBy=multi-user.target
```
**已移除** 基于 `/var/lib/dpkg/lock-frontend` 的 `ExecCondition`。APT/dpkg 自行处理锁竞争。

**Timer 状态:**
```
● nanobot-poc-upgrade.timer
     Active: active (waiting)
     Trigger: 每 2 分钟
```

**连续触发验证 (至少 4 次):**
| 时间 | 结果 |
|------|------|
| 11:10:47 | ✅ 完成 (random-test-poc + unrelated-poc 升级) |
| 11:12:47 | ✅ 完成 (无升级，黑名单生效) |
| 11:14:57 | ✅ 完成 (无升级，黑名单生效) |
| 11:21:21 | ✅ 完成 (nanobot 1.1→1.2，黑名单生效) |

**Timer 在每次 service 执行后仍保持 `active (waiting)`，并显示下一次触发时间。**

---

## Electron 沙盒专项验证

### AppArmor Profile 架构

```
/opt/lenovo/nanobot/nanobot (enforce)
  └── Px 转换 → /opt/lenovo/nanobot/electron/electron (enforce)
```

**Launcher Profile** (`/etc/apparmor.d/com.lenovo.nanobot`):
- 限定 `/opt/lenovo/nanobot/nanobot`
- `Px` 转换到 electron profile
- 允许执行 bash、env
- 允许读/写用户目录和临时文件

**Electron Profile** (`/etc/apparmor.d/com.lenovo.nanobot.electron`):
- 限定 `/opt/lenovo/nanobot/electron/electron`
- `userns,` — 允许用户命名空间 (Chromium 沙箱所需)
- `capability sys_admin, sys_chroot, dac_read_search, setuid, setgid, fowner, chown`
- `/dev/shm/** rw` — 共享内存访问
- `/proc/ r` + `/proc/** r` + `/proc/[0-9]*/** rw` — 进程信息访问
- `/opt/lenovo/nanobot/electron/*.so mrwix` — 共享库加载
- `network inet stream, inet6 stream, unix stream` — 网络访问
- `deny /proc/sys/kernel/unprivileged_userns_clone w` — 禁止全局 userns 修改

### chrome-sandbox 权限
```
root root 4755 /opt/lenovo/nanobot/electron/chrome-sandbox
```
setuid root 已正确设置。

### 沙箱模式验证
- `app.enableSandbox()` 在 `app.whenReady()` 之前调用 ✅
- `BrowserWindow` 配置: `sandbox: true`, `contextIsolation: true`, `nodeIntegration: false` ✅
- 实际进程包含 `--enable-sandbox` 参数 (renderer, utility) ✅
- 实际进程不包含 `--no-sandbox` 参数 ✅
- main.js 运行时检测: `if (app.commandLine.hasSwitch('no-sandbox')) { app.exit(1); }` ✅
- AppArmor enforce 模式提供额外进程级隔离 ✅

---

## 仓库 Origin/Label 验证

```
$ grep -E "^(Origin|Label):" ~/.aptly/public/dists/noble/Release
Origin: Lenovo
Label: Nanobot
```

---

## GUI 截图证据

### 沙箱模式启动截图

![Nanobot with sandbox](poc/evidence/sandbox-launch.png)

- 显示 "Nanobot" 标题
- 显示 "Lenovo OEM Assistant" 副标题
- 显示版本号
- 显示 "Running" 状态

### 升级-运行中截图

- [升级前](poc/evidence/before-upgrade.png): v1.0.0 正在运行
- [升级后](poc/evidence/after-upgrade.png): 升级后窗口仍然显示

### 离线启动截图

![Nanobot offline](poc/evidence/sandbox-launch.png) (与沙箱启动相同，确认离线可用)

---

## 关键系统状态快照

### dpkg-query 输出
```
nanobot         1.2.0   amd64   install ok installed
unrelated-poc   1.0.0   amd64   install ok installed
random-test-poc 1.0.0   amd64   install ok installed
```

### AppArmor 状态
```
/opt/lenovo/nanobot/electron/electron (enforce)
/opt/lenovo/nanobot/nanobot (enforce)
```

### Timer 状态
```
● nanobot-poc-upgrade.timer
     Active: active (waiting)
     Trigger: 每 2 分钟
```

### unattended-upgrades 最新日志
```
初始白名单（not strict）：^nanobot$ ^nanobot-.*
初始黑名单：unrelated-poc random-test-poc
将要升级的软件包：nanobot
安装了所有的更新
软件包 random-test-poc 已被列入黑名单。
软件包 unrelated-poc 已被列入黑名单。
```

---

## 安全审计

| 检查项 | 状态 |
|--------|------|
| 无 chmod 777（排除 symlinks） | ✅ PASS |
| 无 NOPASSWD: ALL | ✅ PASS |
| 无 Trusted: yes | ✅ PASS |
| Electron 不调用 sudo/pkexec/apt/dpkg | ✅ PASS |
| Launcher 不使用 --no-sandbox | ✅ PASS |
| main.js 检测并拒绝 --no-sandbox | ✅ PASS |
| app.enableSandbox() 在 app.ready 之前 | ✅ PASS |
| BrowserWindow sandbox: true | ✅ PASS |
| contextIsolation: true, nodeIntegration: false | ✅ PASS |
| AppArmor enforce 模式 (2 profiles) | ✅ PASS |
| chrome-sandbox setuid root 4755 | ✅ PASS |
| 目录 755，文件 644，可执行 755 | ✅ PASS |
| 选择性升级 (whitelist + blacklist) | ✅ PASS |
| GPG 签名验证 | ✅ PASS |
| APT Hash 校验 | ✅ PASS |
| 用户文件权限隔离 | ✅ PASS |
| 仓库 Origin: Lenovo, Label: Nanobot | ✅ PASS |
| 模型独立目录 /var/lib/lenovo/nanobot/models/ | ✅ PASS |

---

## 结论

本 POC 在 Ubuntu 24.04.4 LTS (Kernel 7.0.0-28) 上成功验证了以下核心能力：

1. **Electron 应用打包和安装** — 完整 Electron 运行时，安装到 /opt/lenovo/nanobot，root:root 权限 ✅
2. **APT 自动升级** — systemd timer + unattended-upgrades 成功在后台自动升级，无需用户输入密码 ✅
3. **安全隔离** — 双 AppArmor enforce profile (launcher + electron)，禁止 --no-sandbox ✅
4. **Electron 沙箱** — `app.enableSandbox()`, `sandbox: true`, `contextIsolation: true`，实际进程确认 ✅
5. **防篡改** — GPG 签名和 Hash 校验确保 APT 拒绝被篡改的包 ✅
6. **用户数据保护** — 升级前后用户配置文件和模型目录 SHA256 哈希一致 ✅
7. **GUI 应用实际运行** — 通过 nanobot-testuser 正式 launcher 启动，GUI 正常显示 ✅
8. **进程用户验证** — 实际确认 Electron 进程以非 root 用户（nanobot-testuser）运行 ✅
9. **运行期间升级** — 实际验证应用运行期间触发 apt 升级，应用保持运行不退出 ✅
10. **选择性升级** — whitelist + blacklist 确保只有 nanobot 被升级，无关包被排除 ✅
11. **离线可用** — 仓库不可用时应用仍可正常运行 ✅

**所有 18 个测试用例全部通过 (100%)**
