# Lenovo Nanobot POC — 从零到通过的完整学习指南

> **目标**: 构建一个 Electron 桌面应用，通过 Linux 本地 APT 仓库实现自动升级，同时满足严格的安全要求。
>
> **适用人群**: Linux 初学者。本文档包含大量注释，解释每个命令和概念的含义。

---

## 📋 目录

1. [环境准备](#1-环境准备)
2. [Electron 应用开发](#2-electron-应用开发)
3. [构建 .deb 安装包](#3-构建-deb-安装包)
4. [搭建 APT 本地仓库](#4-搭建-apt-本地仓库)
5. [AppArmor 安全配置](#5-apparmor-安全配置)
6. [systemd Timer 自动升级](#6-systemd-timer-自动升级)
7. [18 个验证用例](#7-18-个验证用例)
8. [常见问题排查](#8-常见问题排查)
9. [Linux 基础知识速查](#9-linux-基础知识速查)

---

## 1. 环境准备

### 1.1 操作系统

本 POC 在 **Ubuntu 24.04.4 LTS (Noble Numbat)** 上验证，内核版本 7.0.0-28。

```bash
# 查看操作系统版本
# lsb_release 是 "Linux Standard Base" 的缩写，用于显示发行版信息
# -a 表示显示全部信息 (all)
lsb_release -a

# 查看内核版本
# uname 是 "UNIX name" 的缩写
# -r 显示内核 release 版本，-a 显示全部信息
uname -r        # 输出: 7.0.0-28-generic

# 查看系统架构
# dpkg 是 Debian Package 的缩写，用于管理 .deb 包
# --print-architecture 打印当前系统架构
dpkg --print-architecture   # 输出: amd64 (即 64 位 x86 架构)
```

### 1.2 安装依赖

```bash
# apt-get 是 Ubuntu 的包管理命令
# update: 刷新软件包列表（从配置的远程仓库获取最新包列表）
# install: 安装指定的软件包
# -y: 自动确认所有提示（yes 的缩写），不需要手动输入 Y
sudo apt-get update && sudo apt-get install -y \
    electron \        # Electron 框架，用于构建跨平台桌面应用
    nginx \           # 高性能 Web 服务器，本 POC 用于本地 APT 仓库服务
    aptly \           # APT 仓库管理工具，用于创建和管理本地 .deb 仓库
    gnupg2 \          # GPG 加密工具，用于给 APT 仓库签名（防止篡改）
    scrot \           # 截图工具（screen capture 的缩写）
    xdotool \         # 模拟键盘鼠标操作，用于自动化 GUI 测试
    xvfb \            # X Virtual Frame Buffer，虚拟显示服务（无显示器时用）
    imagemagick       # 图像处理工具，import 命令可用于截图
```

> **💡 新手提示**:
> - `sudo` = "superuser do"，以管理员权限执行命令
> - `&&` 表示前一个命令成功后才执行后一个
> - `\` 是换行符，让长命令分多行写，更易读
> - `#` 开头的行是注释，不会被执行

### 1.3 安装 Node.js 和 npm

```bash
# Node.js 是 JavaScript 运行时，npm 是其包管理器
# 本 POC 使用 nodesource 仓库安装 Node.js 22

# 下载并执行 nodesource 安装脚本
# curl: 从网络下载文件的命令
# -fsSL: f=失败不显示错误, s=静默模式, S=显示错误, L=跟随重定向
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -

# 安装 Node.js（包含 npm）
sudo apt-get install -y nodejs

# 验证安装
# -v 或 --version 显示版本号
node -v       # 输出: v22.x.x
npm -v        # 输出: 10.x.x
```

### 1.4 安装 Electron

```bash
# 全局安装 Electron（-g = global，安装到系统目录而非项目目录）
# ELECTRON_MIRROR: 设置环境变量，使用国内镜像加速下载
ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/ npm install -g electron

# 验证 Electron 安装
# which 命令查找可执行文件的完整路径
which electron
electron --version
```

### 1.5 创建测试用户

```bash
# useradd: 创建新用户
# -m: 自动创建用户主目录 (home directory)
# -s: 指定用户的登录 shell (/bin/bash 是标准 shell)
sudo useradd -m -s /bin/bash nanobot-testuser

# passwd: 设置用户密码
# nanobot-testuser: 用户名（请根据需要设置密码）
sudo passwd nanobot-testuser

# 验证用户创建
# id: 显示用户 ID 和所属组信息
id nanobot-testuser
# 输出类似: uid=1002(nanobot-testuser) gid=1002(nanobot-testuser) groups=1002(nanobot-testuser)

# 查看用户主目录
ls -la /home/nanobot-testuser/
```

> **💡 新手提示**:
> - Linux 每个用户有自己的主目录，位于 `/home/用户名/`
> - `uid` = User ID，`gid` = Group ID
> - root 用户的 uid = 0，普通用户 uid ≥ 1000

---

## 2. Electron 应用开发

### 2.1 项目结构

```
poc/
├── electron-app/          # Electron 应用源码
│   ├── main.js            # 主进程入口文件
│   ├── preload.js         # 预加载脚本（连接主进程和渲染进程）
│   ├── renderer.js        # 渲染进程（UI 逻辑）
│   ├── index.html         # 主页面
│   └── package.json       # 项目配置和依赖
├── apparmor/              # AppArmor 安全配置文件
│   ├── com.lenovo.nanobot           # Launcher 的 AppArmor profile
│   └── com.lenovo.nanobot.electron  # Electron 二进制的 AppArmor profile
├── scripts/               # 构建和部署脚本
│   ├── build-deb.sh       # 构建 .deb 安装包
│   ├── setup-repo.sh      # 搭建 APT 仓库
│   └── setup-client-config.sh  # 配置客户端 APT 源
├── packages/              # 构建产出的 .deb 包存放目录
├── evidence/              # 测试证据（截图、日志等）
└── VALIDATION_REPORT.md   # 验证报告
```

### 2.2 main.js — 主进程

```javascript
// 引入 Electron 的 app 和 BrowserWindow 模块
// app: 控制应用的生命周期（启动、退出等）
// BrowserWindow: 创建和管理浏览器窗口
const { app, BrowserWindow } = require('electron');
const path = require('path');   // path 模块处理文件路径
const fs = require('fs');       // fs 模块处理文件读写

// 从 package.json 读取版本号
const packagePath = path.join(__dirname, 'package.json');
const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
const appVersion = pkg.version;

// ===== 安全: 禁止使用 --no-sandbox 参数 =====
// --no-sandbox 会禁用 Chromium 的沙箱安全机制
// 在生产环境中，这会导致安全漏洞
// 我们在这里主动检测并拒绝启动
if (app.commandLine.hasSwitch('no-sandbox')) {
  console.error('ERROR: --no-sandbox is not allowed.');
  app.exit(1);  // exit(1) 表示异常退出（0 = 正常退出）
}

// ===== 启用沙箱模式 =====
// app.enableSandbox() 必须在 app.whenReady() 之前调用
// 它启用 Electron 的进程沙箱，隔离渲染进程和系统
// 这样即使网页代码被攻击，也无法访问系统资源
app.enableSandbox();

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 600,
    height: 400,
    webPreferences: {
      // preload: 在页面加载前执行的脚本
      // 它运行在一个特殊的环境中，可以安全地暴露 API 给渲染进程
      preload: path.join(__dirname, 'preload.js'),

      // ===== 安全三重奏 =====
      sandbox: true,            // 启用沙箱，隔离渲染进程
      contextIsolation: true,   // 隔离 Node.js 和浏览器上下文
      nodeIntegration: false,   // 禁止在页面中使用 Node.js API
      // 这三个配置确保渲染进程（HTML/JS）无法直接访问系统
    },
  });

  // 加载本地 HTML 文件
  mainWindow.loadFile(path.join(__dirname, 'index.html'));

  // 窗口关闭时清理引用
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// 当 Electron 初始化完成后创建窗口
app.whenReady().then(createWindow);

// 所有窗口关闭时退出应用（macOS 除外）
app.on('window-all-closed', () => {
  app.quit();
});
```

### 2.3 preload.js — 预加载脚本

```javascript
// preload.js 运行在渲染进程和主进程之间
// 它可以安全地向页面暴露有限的 API，而不暴露整个 Node.js 环境

const { contextBridge, ipcRenderer } = require('electron');

// contextBridge.exposeInMainWorld: 向页面（window 对象）暴露 API
// 这里只暴露一个安全的 getAppVersion 方法
contextBridge.exposeInMainWorld('electronAPI', {
  getAppVersion: () => ipcRenderer.invoke('get-app-version'),
  // ipcRenderer.invoke: 向主进程发送请求并等待响应
  // 这样页面可以安全地获取版本号，而不需要直接访问 fs 模块
});
```

### 2.4 index.html — 主页面

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Nanobot</title>
  <style>
    /* 简单的样式，显示应用信息 */
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      margin: 0; padding: 20px;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white; text-align: center;
      min-height: 100vh;
    }
    h1 { font-size: 2.5em; margin-bottom: 10px; }
    .subtitle { font-size: 1.2em; opacity: 0.9; }
    .version { font-size: 2em; margin: 20px 0; color: #4fc3f7; font-weight: bold; }
    .status { font-size: 1.1em; margin: 15px 0; }
    .features {
      max-width: 400px; margin: 20px auto;
      text-align: left; font-size: 0.95em; line-height: 1.8;
    }
  </style>
</head>
<body>
  <h1>Nanobot</h1>
  <div class="subtitle">Lenovo OEM Assistant</div>
  <div class="version" id="version">Loading...</div>
  <div class="status">Running</div>
  <div class="features">
    ✅ AppArmor Protected<br>
    ✅ Auto-Update Enabled<br>
    ✅ Sandboxed Electron Process
  </div>
  <script src="renderer.js"></script>
</body>
</html>
```

### 2.5 renderer.js — 渲染进程逻辑

```javascript
// renderer.js 运行在浏览器环境中（不是 Node.js 环境）
// 它通过 preload.js 暴露的 API 与主进程通信

window.addEventListener('DOMContentLoaded', async () => {
  // 页面加载完成后，通过安全 API 获取版本号并显示
  const version = await window.electronAPI.getAppVersion();
  document.getElementById('version').textContent = 'v' + version;
});
```

### 2.6 package.json — 项目配置

```json
{
  "name": "nanobot",
  "version": "1.0.0",
  "main": "main.js",
  "scripts": {
    "start": "electron ."
  }
}
```

---

## 3. 构建 .deb 安装包

### 3.1 什么是 .deb 包？

`.deb` 是 Debian/Ubuntu 系统的软件包格式。它本质上是一个带有特殊结构的归档文件，包含：
- **DEBIAN/control**: 包的元数据（名称、版本、依赖等）
- **DEBIAN/postinst**: 安装后执行的脚本
- **DEBIAN/prerm**: 卸载前执行的脚本
- **应用文件**: 实际安装到系统的文件

### 3.2 build-deb.sh 详解

```bash
#!/usr/bin/env bash
# build-deb.sh — 构建 Nanobot .deb 安装包
#
# 用法: ./scripts/build-deb.sh <版本号>
# 示例: ./scripts/build-deb.sh 1.0.0
#
# 输出: poc/packages/nanobot-<版本号>.deb

# set -euo pipefail 是 bash 的安全模式：
# -e: 任何命令失败立即退出
# -u: 使用未定义的变量时报错
# -o pipefail: 管道中任何命令失败都视为整体失败
set -euo pipefail

# 获取脚本所在目录的上级目录（即 poc/ 目录）
# $(cd "$(dirname "$0")/.." && pwd) 的意思是：
#   dirname "$0"    → 获取脚本所在目录 (scripts/)
#   cd ..           → 切换到上级目录 (poc/)
#   pwd             → 打印当前目录的完整路径
POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 第一个参数是版本号
VERSION="${1:-}"

# 如果没有提供版本号，打印用法并退出
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <version>"
  exit 1
fi

# 定义构建目录
PKG_DIR="${POC_DIR}/packages"                     # 最终 .deb 输出目录
BUILD_DIR="${PKG_DIR}/build-${VERSION}"           # 临时构建目录
DEBIAN_DIR="${BUILD_DIR}/DEBIAN"                  # DEBIAN 元数据目录
INSTALL_DIR="${BUILD_DIR}/opt/lenovo/nanobot"     # 应用安装目录

# 清理旧的构建目录并重新创建
# rm -rf: 递归强制删除（recursive force）
# mkdir -p: 递归创建目录（包括不存在的父目录）
rm -rf "${BUILD_DIR}"
mkdir -p "${PKG_DIR}" "${DEBIAN_DIR}" "${INSTALL_DIR}"

echo "Building nanobot ${VERSION}..."

# --- 定位 Electron 二进制文件 ---
# 按顺序查找 Electron 安装位置
ELECTRON_BIN=""
if [[ -x "$HOME/.npm-global/lib/node_modules/electron/dist/electron" ]]; then
  # 如果 Electron 安装在全局 npm 目录
  ELECTRON_BIN="$HOME/.npm-global/lib/node_modules/electron/dist"
elif [[ -x "$(which electron 2>/dev/null)" ]]; then
  # 如果 electron 命令在 PATH 中
  ELECTRON_BIN=$(node -e "console.log(require('electron'))" 2>/dev/null | xargs dirname)
fi

if [[ -z "${ELECTRON_BIN}" || ! -x "${ELECTRON_BIN}/electron" ]]; then
  # 最后尝试项目内的 node_modules
  ELECTRON_BIN="${POC_DIR}/electron-app/node_modules/electron/dist"
fi

if [[ ! -x "${ELECTRON_BIN}/electron" ]]; then
  echo "ERROR: Electron binary not found."
  exit 1
fi

echo "  Using Electron from: ${ELECTRON_BIN}"

# --- 复制 Electron 应用文件 ---
# 创建 resources/app 目录，Electron 会自动从这里加载应用
mkdir -p "${INSTALL_DIR}/electron/resources/app"

# 复制应用源码到 resources/app 目录
# cp: 复制文件
cp "${POC_DIR}/electron-app/main.js"         "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/preload.js"       "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/renderer.js"      "${INSTALL_DIR}/electron/resources/app/"
cp "${POC_DIR}/electron-app/index.html"       "${INSTALL_DIR}/electron/resources/app/"

# 用 sed 替换 package.json 中的版本号为当前构建版本
# sed: 流编辑器，用于文本替换
# "s/原模式/新模式/" 是替换语法
sed "s/\"version\": \"[^\"]*\"/\"version\": \"${VERSION}\"/" \
  "${POC_DIR}/electron-app/package.json" > "${INSTALL_DIR}/electron/resources/app/package.json"

# --- 捆绑 Electron 运行时 ---
echo "  Bundling Electron runtime..."
# cp -a: 归档模式复制（保留权限、时间戳等）
# "${ELECTRON_BIN}/." 中的 ". " 表示复制目录内容（不包括目录本身）
cp -a "${ELECTRON_BIN}/." "${INSTALL_DIR}/electron/"

# --- 创建 Launcher 脚本 ---
# 这是用户双击桌面图标时实际执行的脚本
cat > "${INSTALL_DIR}/nanobot" << 'LAUNCHER'
#!/usr/bin/env bash
# Nanobot launcher — 启动捆绑的 Electron，强制执行沙箱
NANOBOT_DIR="/opt/lenovo/nanobot"
# exec 替换当前 shell 进程为 electron 进程（不创建子进程）
# "$@" 传递所有命令行参数
exec "${NANOBOT_DIR}/electron/electron" "$@"
LAUNCHER

# chmod: 修改文件权限
# 0755 = rwxr-xr-x（所有者可读写执行，组和其他只读执行）
chmod 0755 "${INSTALL_DIR}/nanobot"

# --- 创建版本号软链接 ---
# ln -sf: 创建符号链接（类似 Windows 的快捷方式）
# 这样可以通过 /opt/lenovo/nanobot/package.json 读取版本号
ln -sf electron/resources/app/package.json "${INSTALL_DIR}/package.json"

# --- DEBIAN/control — 包的元数据 ---
cat > "${DEBIAN_DIR}/control" << CONTROL
Package: nanobot
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: Lenovo OEM <oem@lenovo.com>
Description: Lenovo Nanobot OEM Assistant
 An Electron-based OEM assistant application.
 Installed to /opt/lenovo/nanobot.
 Auto-upgrade via APT and unattended-upgrades.
CONTROL

# --- DEBIAN/postinst — 安装后脚本 ---
# 这个脚本在 dpkg 安装/升级包之后自动执行
cat > "${DEBIAN_DIR}/postinst" << 'POSTINST'
#!/bin/bash
set -e

NANOBOT_DIR="/opt/lenovo/nanobot"
RESOURCES_APP="${NANOBOT_DIR}/electron/resources/app"

# 确保 resources/app 目录存在
mkdir -p "${RESOURCES_APP}"

# 复制应用文件到 resources/app（如果顶层有独立文件）
for f in main.js preload.js renderer.js index.html package.json; do
  if [ -f "${NANOBOT_DIR}/${f}" ] && [ ! -L "${NANOBOT_DIR}/${f}" ]; then
    cp "${NANOBOT_DIR}/${f}" "${RESOURCES_APP}/"
  fi
done

# --- 修复文件权限 ---
# find: 查找文件
# -type d: 只查找目录
# -type f: 只查找普通文件
# -not -name "xxx": 排除名为 xxx 的文件
# -exec cmd {} \;: 对每个找到的文件执行 cmd

# 所有目录设为 0755 (rwxr-xr-x)
find "${NANOBOT_DIR}" -type d -exec chmod 0755 {} \;

# 普通文件设为 0644 (rw-r--r--)，排除可执行文件
find "${NANOBOT_DIR}" -type f \
  -not -name "nanobot" \
  -not -name "chrome-sandbox" \
  -not -name "electron" \
  -not -name "chrome_crashpad_handler" \
  -exec chmod 0644 {} \;

# 可执行文件设为 0755
chmod 0755 "${NANOBOT_DIR}/nanobot"
chmod 0755 "${NANOBOT_DIR}/electron/electron"
chmod 0755 "${NANOBOT_DIR}/electron/chrome_crashpad_handler"

# --- chrome-sandbox 设为 setuid root ---
# setuid (Set User ID) 是 Linux 的特殊权限位
# 4755 = 4(setuid) + 755(rwxr-xr-x)
# setuid 表示: 无论谁执行这个文件，都以文件所有者 (root) 的权限运行
# chrome-sandbox 需要 setuid 来创建安全的沙箱环境
if [ -f "${NANOBOT_DIR}/electron/chrome-sandbox" ]; then
  chown root:root "${NANOBOT_DIR}/electron/chrome-sandbox"
  chmod 4755 "${NANOBOT_DIR}/electron/chrome-sandbox"
fi

# 重新加载 AppArmor profile（如果存在）
if [ -f /etc/apparmor.d/com.lenovo.nanobot ]; then
  apparmor_parser -r /etc/apparmor.d/com.lenovo.nanobot 2>/dev/null || true
fi

# 刷新桌面入口数据库
update-desktop-database /usr/share/applications 2>/dev/null || true

# 启用自动升级 timer（如果已安装）
if systemctl list-unit-files nanobot-poc-upgrade.timer >/dev/null 2>&1; then
  systemctl enable --now nanobot-poc-upgrade.timer 2>/dev/null || true
fi

# 记录安装日志
# logger: 向系统日志写入消息
# -t nanobot: 指定标签 (tag) 为 nanobot
logger -t nanobot "Nanobot ${VERSION} installed successfully"

exit 0
POSTINST

chmod 0755 "${DEBIAN_DIR}/postinst"

# --- DEBIAN/prerm — 卸载前脚本 ---
cat > "${DEBIAN_DIR}/prerm" << 'PRERM'
#!/bin/bash
set -e
# 刷新桌面入口数据库
update-desktop-database /usr/share/applications 2>/dev/null || true
# 记录卸载日志
logger -t nanobot "Nanobot prerm executed"
exit 0
PRERM
chmod 0755 "${DEBIAN_DIR}/prerm"

# --- 修复构建目录权限 ---
# 确保 .deb 包内的文件权限正确
find "${BUILD_DIR}" -type d -exec chmod 0755 {} \;
find "${DEBIAN_DIR}" -type f -exec chmod 0755 {} \;

find "${BUILD_DIR}" -type f \
  -not -path "${DEBIAN_DIR}/*" \
  -not -name "nanobot" \
  -not -name "chrome-sandbox" \
  -not -name "electron" \
  -not -name "chrome_crashpad_handler" \
  -exec chmod 0644 {} \;

chmod 0755 "${INSTALL_DIR}/nanobot"
chmod 0755 "${INSTALL_DIR}/electron/electron"
chmod 0755 "${INSTALL_DIR}/electron/chrome_crashpad_handler"

if [ -f "${INSTALL_DIR}/electron/chrome-sandbox" ]; then
  chmod 4755 "${INSTALL_DIR}/electron/chrome-sandbox"
fi

# --- 构建 .deb 包 ---
# dpkg-deb: Debian 包管理工具
# --build: 从目录构建 .deb 包
# --root-owner-group: 包内文件所有者设为 root:root
dpkg-deb --build --root-owner-group "${BUILD_DIR}" "${PKG_DIR}/nanobot-${VERSION}.deb"

echo "Built: ${PKG_DIR}/nanobot-${VERSION}.deb"
echo "  Size: $(du -h "${PKG_DIR}/nanobot-${VERSION}.deb" | cut -f1)"
echo "  Version: ${VERSION}"
```

### 3.3 构建第一个版本

```bash
# 进入 poc 目录
cd /home/qiuyanlong/worespace/by-claw-poc-linux/poc

# 构建 1.0.0 版本
./scripts/build-deb.sh 1.0.0

# 查看生成的 .deb 包
ls -la packages/nanobot-1.0.0.deb
# 输出类似: -rwxr-xr-x 1 user user 96M Aug 24 18:38 packages/nanobot-1.0.0.deb

# 查看 .deb 包的元信息
# dpkg-deb --info: 显示包的元数据
dpkg-deb --info packages/nanobot-1.0.0.deb
```

---

## 4. 搭建 APT 本地仓库

### 4.1 什么是 APT 仓库？

APT (Advanced Package Tool) 仓库是 Ubuntu/Debian 系统下载和安装软件的地方。
官方仓库如 `archive.ubuntu.com` 存放 Ubuntu 官方软件包。
本 POC 搭建一个**本地仓库**，用于存放和分发 nanobot 包，模拟 OEM 升级场景。

### 4.2 setup-repo.sh 详解

```bash
#!/usr/bin/env bash
# setup-repo.sh — 初始化本地 APT 仓库
#
# 需要以 root 权限运行: sudo ./scripts/setup-repo.sh

set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="${POC_DIR}/apt-repository"
SERVE_PORT="${NANOBOT_REPO_PORT:-8080}"  # 默认端口 8080，可通过环境变量覆盖

# --- 检查 root 权限 ---
# id -u: 打印当前用户的 UID
# 0 = root，非 0 = 普通用户
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: This script requires root privileges."
  echo "Run with: sudo $0"
  exit 1
fi

echo "=== Setting up Nanobot POC APT Repository ==="

# --- 安装依赖 ---
echo "[1/5] Installing dependencies..."
apt-get update -qq 2>/dev/null || true  # -qq: 非常安静模式
apt-get install -y -qq aptly gnupg2 nginx python3 2>/dev/null || true

# --- 生成 GPG 密钥 ---
echo "[2/5] Generating temporary test GPG key..."
GNUPG_HOME="${REPO_DIR}/gpg-home"
rm -rf "${GNUPG_HOME}"
mkdir -m 0700 "${GNUPG_HOME}"  # -m 0700: 仅所有者可读写执行

# GPG 密钥生成参数
cat > "${GNUPG_HOME}/keygen.params" << 'KEYGEN'
%no-protection          # 不设置密码保护（仅用于 POC 测试）
Key-Type: RSA           # 密钥类型
Key-Length: 2048        # 密钥长度
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: Nanobot POC
Name-Email: nanobot-poc@localhost
Expire-Date: 0          # 0 = 永不过期
%commit
KEYGEN

# 生成 GPG 密钥
# --homedir: 指定 GPG 主目录（不使用默认的 ~/.gnupg）
# --batch: 批处理模式（不交互）
# --gen-key: 生成密钥
gpg --homedir "${GNUPG_HOME}" --batch --gen-key "${GNUPG_HOME}/keygen.params" 2>/dev/null

# 导出公钥（客户端需要这个来验证仓库签名）
# --armor: 输出 ASCII 格式（而非二进制）
# --export: 导出指定用户的公钥
gpg --homedir "${GNUPG_HOME}" --armor --export "nanobot-poc@localhost" \
  > "${REPO_DIR}/nanobot-poc-public.gpg"

echo "  Public key exported to: ${REPO_DIR}/nanobot-poc-public.gpg"

# --- 初始化 aptly ---
echo "[3/5] Initializing aptly repository..."

# 创建 aptly 仓库
# -distribution: 发行版名称（noble = Ubuntu 24.04 的代号）
# -component: 仓库组件（main = 主要软件包）
aptly repo create -distribution=noble -component=main nanobot-poc 2>/dev/null || true

# 获取 GPG 密钥 ID
GPG_KEY_ID=$(gpg --homedir "${GNUPG_HOME}" --list-keys --with-colons "nanobot-poc@localhost" \
  | grep '^fpr' | head -1 | cut -d: -f10)
echo "  GPG Key ID: ${GPG_KEY_ID}"

# --- 发布仓库 ---
# 设置 Origin 和 Label，这是 unattended-upgrades 识别包的依据
echo "  Publishing repository with Origin=Lenovo, Label=Nanobot..."
aptly publish repo \
  -origin="Lenovo" \
  -label="Nanobot" \
  -distribution=noble \
  -component=main \
  nanobot-poc 2>/dev/null || true

# --- 配置 nginx ---
echo "[4/5] Configuring nginx..."
PUBLISH_DIR="${HOME}/.aptly/public"
mkdir -p "${PUBLISH_DIR}"

cat > /etc/nginx/sites-available/nanobot-poc << NGINX
server {
    listen ${SERVE_PORT};
    server_name localhost;

    root ${PUBLISH_DIR};   # nginx 服务的根目录

    location / {
        autoindex on;      # 允许目录列表
        autoindex_exact_size off;
        add_header Content-Type text/plain;
    }

    # .deb 文件的 MIME 类型
    location ~ \.deb$ {
        default_type application/octet-stream;
    }

    access_log /var/log/nginx/nanobot-poc-access.log;
    error_log /var/log/nginx/nanobot-poc-error.log;
}
NGINX

# 启用 nginx 站点
# ln -sf: 创建符号链接（-s = 符号链接, -f = 强制覆盖）
# nginx 通过 sites-enabled/ 目录中的链接启用站点
ln -sf /etc/nginx/sites-available/nanobot-poc /etc/nginx/sites-enabled/nanobot-poc

# 测试配置并重载 nginx
nginx -t && nginx -s reload 2>/dev/null || systemctl restart nginx 2>/dev/null || true

echo "[5/5] Repository setup complete."
echo "  Repository URL: http://localhost:${SERVE_PORT}"
echo "  Public key:     ${REPO_DIR}/nanobot-poc-public.gpg"
```

### 4.3 执行仓库搭建

```bash
# 以 root 权限运行
sudo ./scripts/setup-repo.sh

# 验证仓库可访问
curl -s http://localhost:8080/dists/noble/InRelease | head -10
# 应该看到 PGP 签名和 Origin: Lenovo 信息
```

### 4.4 添加 .deb 包到仓库

```bash
# 将构建好的 .deb 包添加到 aptly 仓库
aptly repo add nanobot-poc /home/qiuyanlong/worespace/by-claw-poc-linux/poc/packages/nanobot-1.0.0.deb

# 更新发布（重新生成仓库索引）
# -passphrase="": 密钥无密码
aptly publish update -passphrase="" noble

# 查看仓库中的包
aptly repo show -with-packages nanobot-poc
```

### 4.5 配置客户端 APT 源

```bash
# 创建 APT 源配置（告诉 apt 从哪里下载 nanobot）
# .sources 是新的源格式（替代旧的 .list 格式）
cat > /tmp/nanobot-poc.sources << 'EOF'
Types: deb
URIs: http://localhost:8080
Suites: noble
Components: main
Signed-By: /home/qiuyanlong/worespace/by-claw-poc-linux/poc/apt-repository/nanobot-poc-public.gpg
EOF

sudo cp /tmp/nanobot-poc.sources /etc/apt/sources.list.d/nanobot-poc.sources

# 刷新 APT 缓存
sudo apt-get update

# 验证 nanobot 包在 APT 中可用
apt-cache policy nanobot
# 应该显示:
# nanobot:
#   已安装：(none)
#   候选： 1.0.0
```

---

## 5. AppArmor 安全配置

### 5.1 什么是 AppArmor？

AppArmor (Application Armor) 是 Linux 内核的**强制访问控制**（MAC）系统。
它通过**配置文件**（profile）限制应用程序可以做什么：
- 可以访问哪些文件
- 可以使用哪些网络协议
- 可以执行哪些系统调用

与传统的文件权限不同，AppArmor 的权限是**强制的**，即使文件本身有读写权限，如果 AppArmor 策略不允许，进程也无法访问。

### 5.2 双 Profile 架构

本 POC 使用两个 AppArmor Profile：

```
/opt/lenovo/nanobot/nanobot (enforce)     ← Launcher 脚本
  └── Px 转换 →
     /opt/lenovo/nanobot/electron/electron (enforce)  ← Electron 二进制
```

**为什么需要两个 Profile？**
- Launcher 只需要读取配置和执行 electron
- Electron 需要更广泛的权限（网络、共享内存、用户命名空间等）
- 通过 `Px` (Profile transition) 实现精确的权限过渡

### 5.3 Launcher Profile

```apparmor
# /etc/apparmor.d/com.lenovo.nanobot
# 这是 Launcher 脚本 (/opt/lenovo/nanobot/nanobot) 的 AppArmor 配置文件

#include <tunables/global>     # 引入全局可调参数（如 @{HOME}）

/opt/lenovo/nanobot/nanobot {  # Profile 名称 = 受限程序的完整路径
  #include <abstractions/base>          # 引入基础抽象（标准系统访问）
  #include <abstractions/nameservice>    # 引入名称服务抽象（DNS 等）
  #include <abstractions/bash>           # 引入 bash 抽象

  # --- 用户命名空间 ---
  userns,                    # 允许创建用户命名空间（Chromium 沙箱需要）
  capability sys_admin,      # 允许系统管理权限

  # --- 禁止修改内核参数 ---
  deny /proc/sys/kernel/unprivileged_userns_clone w,  # 禁止写入这个内核参数

  # --- 应用文件访问 ---
  /opt/lenovo/nanobot/                 r,     # 读取目录列表
  /opt/lenovo/nanobot/**               r,     # 递归读取所有文件
  /opt/lenovo/nanobot/nanobot          mrpix, # 自身可执行（递归进入）
                                             # m=内存映射, r=读, p=可执行, i=继承, x=执行

  # --- 可执行的文件 ---
  /usr/bin/bash                        mix,   # m=内存映射, i=继承, x=执行
  /bin/bash                            mix,
  /usr/bin/env                         mix,
  # Px = Profile transition（切换到另一个 Profile）
  # 当 launcher 执行 electron 时，自动切换到 electron 的 Profile
  /opt/lenovo/nanobot/electron/electron Px,

  # --- 共享库 ---
  /opt/lenovo/nanobot/electron/*.so    mrwix, # .so 文件需要内存映射+读写执行
  /opt/lenovo/nanobot/electron/locales/** r,
  /opt/lenovo/nanobot/electron/**      r,
  /opt/lenovo/nanobot/electron/chrome-sandbox mrwix,
  /opt/lenovo/nanobot/electron/chrome_crashpad_handler mrpix,

  # --- 系统库 ---
  /usr/lib/x86_64-linux-gnu/**         r,
  /usr/lib/**                          r,
  /usr/share/**                        r,
  /lib/x86_64-linux-gnu/**             r,
  /lib/**                              r,

  # --- 系统资源 ---
  /etc/**                              r,
  /dev/null                            rw,     # 读写 /dev/null
  /dev/zero                            rw,
  /dev/random                          r,
  /dev/urandom                         r,
  /dev/tty                             rw,
  /dev/dri/**                          rw,    # GPU 设备
  /proc/                               r,     # 读取 /proc 目录
  /proc/**                             r,     # 读取 /proc 下所有
  /proc/[0-9]*/**                      rw,    # 进程信息读写
  /proc/[0-9]*/setgroups               rw,
  /proc/[0-9]*/uid_map                 rw,
  /proc/[0-9]*/gid_map                 rw,
  /sys/**                              r,
  /sys/fs/cgroup/**                    r,

  # --- 用户数据 ---
  # owner 关键字表示: 只有文件所有者才能访问
  # @{HOME} 是 AppArmor 的变量，展开为用户主目录
  owner @{HOME}/.config/nanobot/**     rw,
  owner @{HOME}/.cache/nanobot/**      rw,
  owner /tmp/**                        rw,

  # --- 网络 ---
  network inet  stream,     # TCP (IPv4)
  network inet6 stream,     # TCP (IPv6)
  network unix   stream,    # Unix domain socket
}
```

### 5.4 Electron Profile

```apparmor
# /etc/apparmor.d/com.lenovo.nanobot.electron
# 这是 Electron 二进制 (/opt/lenovo/nanobot/electron/electron) 的 AppArmor 配置文件

#include <tunables/global>

/opt/lenovo/nanobot/electron/electron {
  #include <abstractions/base>
  #include <abstractions/nameservice>
  #include <abstractions/bash>

  # --- Chromium 沙箱所需权限 ---
  userns,                      # 允许用户命名空间
  capability sys_admin,        # 系统管理
  capability sys_chroot,       # chroot 权限（Chromium 沙箱需要）
  capability dac_read_search,  # 绕过文件读权限检查
  capability setuid,           # 设置用户 ID
  capability setgid,           # 设置组 ID
  capability fowner,           # 文件所有者权限
  capability chown,            # 修改文件所有者

  # --- 禁止修改内核参数 ---
  deny /proc/sys/kernel/unprivileged_userns_clone w,

  # 其余权限与 Launcher Profile 类似...
  /opt/lenovo/nanobot/                 r,
  /opt/lenovo/nanobot/**               r,
  /opt/lenovo/nanobot/electron/electron mrpix,
  /opt/lenovo/nanobot/electron/*.so    mrwix,
  /opt/lenovo/nanobot/electron/**      r,
  /opt/lenovo/nanobot/electron/chrome-sandbox mrwix,
  /dev/shm/**                      rw,    # 共享内存（Chromium 进程间通信需要）

  /usr/lib/x86_64-linux-gnu/**         r,
  /usr/lib/**                          r,
  /etc/**                              r,
  /dev/null                            rw,
  /dev/zero                            rw,
  /dev/random                          r,
  /dev/urandom                         r,
  /dev/tty                             rw,
  /dev/dri/**                          rw,
  /proc/                               r,
  /proc/**                             r,
  /proc/[0-9]*/**                      rw,
  /sys/**                              r,
  /sys/fs/cgroup/**                    r,

  owner @{HOME}/.config/nanobot/**     rw,
  owner @{HOME}/.cache/nanobot/**      rw,
  owner /tmp/**                        rw,

  network inet  stream,
  network inet6 stream,
  network unix   stream,
}
```

### 5.5 加载 Profile

```bash
# 将配置文件复制到 AppArmor 目录
sudo cp poc/apparmor/com.lenovo.nanobot /etc/apparmor.d/
sudo cp poc/apparmor/com.lenovo.nanobot.electron /etc/apparmor.d/

# 加载 Profile
# apparmor_parser -a: 添加 (add) 新 Profile
# apparmor_parser -r: 重新加载 (reload) 已有 Profile
sudo apparmor_parser -a /etc/apparmor.d/com.lenovo.nanobot
sudo apparmor_parser -a /etc/apparmor.d/com.lenovo.nanobot.electron

# 或者两个一起重新加载
sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.nanobot /etc/apparmor.d/com.lenovo.nanobot.electron

# 查看 AppArmor 状态
# aa-status: AppArmor Status
sudo aa-status
# 输出应包含:
#   /opt/lenovo/nanobot/nanobot (enforce)
#   /opt/lenovo/nanobot/electron/electron (enforce)

# enforce 模式 = 强制执行策略，违反则阻止
# complain 模式 = 仅记录违规，不阻止（用于调试）
```

### 5.6 文件权限速查

| 权限值 | 含义 | 说明 |
|--------|------|------|
| `r` (4) | 读 | 读取文件内容或目录列表 |
| `w` (2) | 写 | 修改文件或在目录中创建/删除文件 |
| `x` (1) | 执行 | 执行文件或进入目录 |
| `m` | 内存映射 | 将文件映射到内存（.so 库需要） |
| `i` | 继承 | 继承当前 Profile 的执行权限 |
| `p` | 可执行 | 允许内存映射执行 |

特殊权限位:
| 值 | 名称 | 说明 |
|----|------|------|
| 4 | setuid | 以文件所有者权限执行 |
| 2 | setgid | 以文件所属组权限执行 |
| 1 | sticky | 仅文件所有者可删除 |

示例: `4755` = setuid + rwxr-xr-x

---

## 6. systemd Timer 自动升级

### 6.1 什么是 systemd Timer？

systemd Timer 是 Linux 的**定时任务**系统，类似于传统的 `cron`，但更强大：
- 可以与 systemd Service 关联
- 支持更灵活的时间表达式
- 有完整的日志和状态管理

### 6.2 Timer 文件

```ini
# /etc/systemd/system/nanobot-poc-upgrade.timer
[Unit]
Description=Nanobot POC Auto-Upgrade Timer (every 2 minutes)

[Timer]
# 定时器激活后每 2 分钟触发一次
OnUnitActiveSec=2min
# 定时器首次激活后 10 秒开始触发
OnBootSec=10sec
# 随机延迟最多 30 秒（防止多个定时器同时触发）
RandomizedDelaySec=30sec
# 持久化：如果系统关机期间错过了触发时间，开机后补触发
Persistent=false

[Install]
# WantedBy: 这个 timer 属于哪个 target（目标）
# multi-user.target = 多用户模式（类似 runlevel 3）
WantedBy=multi-user.target
```

### 6.3 Service 文件

```ini
# /etc/systemd/system/nanobot-poc-upgrade.service
[Unit]
Description=Nanobot POC Auto-Upgrade Service (2-minute timer)
Documentation=file:///home/qiuyanlong/worespace/by-claw-poc-linux/poc/README.md

[Service]
# Type=oneshot: 执行一次后退出（不是常驻服务）
Type=oneshot
# 执行 unattended-upgrade 命令进行自动升级
# -v: verbose（详细输出）
ExecStart=/usr/bin/unattended-upgrade -v
# 低优先级运行，不影响系统性能
Nice=19                  # CPU 优先级最低（-20 最高，19 最低）
IOSchedulingClass=idle   # 仅在其他进程不需要 I/O 时才读写磁盘

[Install]
WantedBy=multi-user.target
```

> **⚠️ 注意**: 早期版本有一个 `ExecCondition` 行检查 lock 文件是否存在。
> 这会导致误判（lock 文件始终存在），已移除。
> APT 和 dpkg 自己处理锁竞争，不需要额外检查。

### 6.4 启用 Timer

```bash
# 重新加载 systemd 配置
# daemon-reload: 告诉 systemd 重新读取所有 unit 文件
sudo systemctl daemon-reload

# 启用并启动 timer
# enable: 开机自动启动
# --now: 立即启动（不等下次开机）
sudo systemctl enable --now nanobot-poc-upgrade.timer

# 查看 timer 状态
systemctl status nanobot-poc-upgrade.timer
# 应显示: Active: active (waiting)
#         Trigger: 显示下一次触发时间

# 查看所有活跃的 timer
systemctl list-timers --all | grep nanobot

# 查看 service 运行日志
journalctl -u nanobot-poc-upgrade.service
```

### 6.5 unattended-upgrades 配置

```bash
# /etc/apt/apt.conf.d/60nanobot-poc-upgrades
# 这个文件告诉 unattended-upgrades 哪些包可以自动升级

// 允许的来源
Unattended-Upgrade::Allowed-Origins {
    "Lenovo:noble";    // Origin: Lenovo, Suite: noble
};

// 白名单: 只有匹配这些正则表达式的包才会被自动升级
Unattended-Upgrade::Package-Whitelist {
    "^nanobot$";       // 精确匹配 "nanobot"
    "^nanobot-.*";     // 匹配 "nanobot-" 开头的包（如 nanobot-agent）
};

// 黑名单: 明确阻止某些包自动升级（白名单是 "not strict" 模式，需配合黑名单）
Unattended-Upgrade::Package-Blacklist {
    "unrelated-poc";      // 测试包，不应自动升级
    "random-test-poc";    // 另一个测试包
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";  // 自动修复中断的安装
Unattended-Upgrade::MinimalSteps "true";            // 最小化步骤，减少风险
```

### 6.6 验证 Timer 工作

```bash
# 安装 1.0.0 版本
sudo apt-get install -y nanobot=1.0.0

# 构建并发布 1.1.0
./scripts/build-deb.sh 1.1.0
aptly repo add nanobot-poc packages/nanobot-1.1.0.deb
aptly publish update -passphrase="" noble
sudo apt-get update

# 等待 timer 触发（最多 2 分钟）
# 查看升级日志
journalctl -u nanobot-poc-upgrade.service --since "3 min ago"

# 验证版本升级
dpkg-query -W nanobot
# 应该显示: nanobot  1.1.0
```

---

## 7. 18 个验证用例

### Case 1: Electron 安装在 /opt/lenovo/nanobot

```bash
# 验证安装目录存在且包含预期文件
ls -la /opt/lenovo/nanobot/
# 预期: electron/, nanobot, package.json 等
```

### Case 2: /opt 下文件为 root:root，普通用户不可修改

```bash
# 查看文件所有者
ls -la /opt/lenovo/nanobot/
# 预期: 所有文件 owner 为 root:root

# 测试普通用户无法写入
sudo -u nanobot-testuser bash -c "touch /opt/lenovo/nanobot/test-write"
# 预期: Permission denied
```

### Case 3: 应用入口位于 /usr/share/applications

```bash
cat /usr/share/applications/nanobot.desktop
# 预期: [Desktop Entry] 段，Exec=/opt/lenovo/nanobot/nanobot
```

### Case 4: 普通用户能够启动软件

```bash
# 验证用户可见 desktop entry
sudo -u nanobot-testuser test -f /usr/share/applications/nanobot.desktop && echo "OK"

# 验证 launcher 可执行
sudo -u nanobot-testuser test -x /opt/lenovo/nanobot/nanobot && echo "OK"

# 验证可读取版本号
sudo -u nanobot-testuser python3 -c "import json; print(json.load(open('/opt/lenovo/nanobot/package.json'))['version'])"
```

### Case 5: Electron 不以 root 运行

```bash
# 查看运行中的 electron 进程
ps aux | grep electron | grep -v grep
# 预期: 进程用户为普通用户（非 root）
```

### Case 6: Electron 不调用 sudo/pkexec/apt/dpkg

```bash
# 源码扫描
grep -rn "sudo\|pkexec\|apt\|dpkg" \
  /opt/lenovo/nanobot/main.js \
  /opt/lenovo/nanobot/nanobot \
  /opt/lenovo/nanobot/preload.js \
  /opt/lenovo/nanobot/renderer.js
# 预期: 无匹配结果
```

### Case 7: 不使用 --no-sandbox

```bash
# 检查 launcher 脚本
grep "no-sandbox" /opt/lenovo/nanobot/nanobot
# 预期: 无匹配

# 检查 main.js
grep "no-sandbox" /opt/lenovo/nanobot/main.js
# 预期: 有检测并拒绝的代码

# 检查实际进程
ps -eo args | grep electron | grep "no-sandbox"
# 预期: 无匹配
```

### Case 8: AppArmor Profile 已加载

```bash
sudo aa-status | grep nanobot
# 预期:
#   /opt/lenovo/nanobot/nanobot (enforce)
#   /opt/lenovo/nanobot/electron/electron (enforce)
```

### Case 9: systemd 自动升级

```bash
# 升级前
dpkg-query -W nanobot        # → 1.0.0

# 等待 timer 触发...

# 升级后
dpkg-query -W nanobot        # → 1.1.0
```

### Case 10: 普通用户全程不输入密码

```bash
# 验证用户无 sudo 权限
sudo -l -U nanobot-testuser
# 预期: 无权运行 sudo

# 检查 auth.log
sudo grep "sudo.*nanobot-testuser" /var/log/auth.log
# 预期: 无记录
```

### Case 11: 运行期间升级不强制退出

```bash
# 启动应用
/opt/lenovo/nanobot/nanobot &
APP_PID=$!

# 触发升级
sudo apt-get install -y nanobot

# 检查进程是否存活
kill -0 $APP_PID && echo "Process still alive"
# 预期: 进程存活
```

### Case 12: 重启后显示新版本

```bash
dpkg-query -W nanobot                           # → 1.1.0
python3 -c "import json; print(json.load(open('/opt/lenovo/nanobot/package.json'))['version'])"
# 预期: 都显示 1.1.0
```

### Case 13: 用户配置和模型 Hash 不变

```bash
# 升级前
sha256sum /var/lib/lenovo/nanobot/models/fake-model.bin
sha256sum /home/nanobot-testuser/.config/lenovo/nanobot/settings.json

# 升级后再次执行
# 预期: 两次 SHA256 完全一致
```

### Case 14: 签名/Hash 被破坏时 APT 拒绝

```bash
# 测试 14a: 篡改 InRelease
echo "TAMPERED" >> ~/.aptly/public/dists/noble/InRelease
sudo apt-get update
# 预期: GPG 签名错误

# 测试 14b: 篡改 .deb
echo "TAMPERED" >> ~/.aptly/public/pool/main/n/nanobot/nanobot-1.1.0.deb
sudo apt-get install -y nanobot
# 预期: Hash 不匹配
```

### Case 15: 仓库不可用时旧版本仍能运行

```bash
# 停止仓库服务
sudo systemctl stop nginx

# 验证应用文件完整
test -x /opt/lenovo/nanobot/nanobot && echo "Launcher OK"

# 启动应用验证 GUI 正常显示
# 应用不依赖仓库运行

# 恢复
sudo systemctl start nginx
```

### Case 16: 不存在危险配置

```bash
# 扫描脚本和配置
grep -rn "chmod 777" poc/scripts/ poc/packaging/
grep -rn "NOPASSWD" /etc/sudoers /etc/sudoers.d/
grep "Trusted: yes" /etc/apt/sources.list.d/nanobot-poc.sources
# 预期: 均无匹配
```

### Case 17: 只升级 Nanobot，不升级无关包

```bash
# 验证配置
cat /etc/apt/apt.conf.d/60nanobot-poc-upgrades

# 验证升级日志
journalctl -u nanobot-poc-upgrade.service --since "5 min ago"
# 预期: 只升级 nanobot，blacklisted 包不被升级
```

### Case 18: Electron 进程用户和启动参数

```bash
# 查看完整进程信息
ps -eo user,pid,ppid,args | grep "/opt/lenovo/nanobot" | grep -v grep

# 预期:
# - 所有进程用户为 nanobot-testuser
# - 无 --no-sandbox 参数
# - 有 --enable-sandbox 参数（renderer/utility 进程）

# 查看 AppArmor 审计日志
journalctl -k | grep -i apparmor | grep -i nanobot
```

---

## 8. 常见问题排查

### 8.1 AppArmor Profile 语法错误

```bash
# 如果 profile 加载失败，检查语法
sudo apparmor_parser -d /etc/apparmor.d/com.lenovo.nanobot 2>&1
# -d: 调试模式，显示详细错误信息

# 常见错误:
# - "dw" 不是合法权限（应为 "rw"）
# - 缺少逗号
# - 路径格式错误

# 修复后重新加载
sudo apparmor_parser -r /etc/apparmor.d/com.lenovo.nanobot
```

### 8.2 AppArmor 阻止文件访问

```bash
# 查看 AppArmor 拒绝日志
sudo dmesg | grep -i "apparmor.*denied"
# 或
journalctl -k | grep -i "apparmor.*denied"

# 日志格式:
# apparmor="DENIED" operation="open" profile="..." name="/path/to/file"
# 根据 denied 的路径，在 profile 中添加对应的允许规则
```

### 8.3 systemd Timer 不触发

```bash
# 检查 timer 状态
systemctl status nanobot-poc-upgrade.timer

# 如果是 inactive (dead)，重新启动
sudo systemctl start nanobot-poc-upgrade.timer

# 检查 service 是否有 ExecCondition 阻止
cat /etc/systemd/system/nanobot-poc-upgrade.service

# 查看 service 失败原因
journalctl -u nanobot-poc-upgrade.service -e
# -e: 跳转到末尾（查看最新日志）
```

### 8.4 unattended-upgrade 不升级

```bash
# 手动运行测试（verbose 模式）
sudo unattended-upgrade -v -d
# -v: verbose
# -d: debug（更详细的输出）

# 查看日志
tail -f /var/log/unattended-upgrades/unattended-upgrades.log

# 检查 Allowed-Origins 是否匹配
# 查看仓库的 Origin:
curl -s http://localhost:8080/dists/noble/Release | grep -E "^(Origin|Label):"
```

### 8.5 Electron 无法启动 GUI

```bash
# 检查是否有 DISPLAY 环境变量
echo $DISPLAY
# 无显示器环境需要设置虚拟显示:
export DISPLAY=:99

# 检查 Electron 报错信息
/opt/lenovo/nanobot/nanobot 2>&1 | head -20

# 常见错误:
# - "Missing X server or $DISPLAY" → 需要 Xvfb 或实际显示器
# - "libffmpeg.so: cannot open" → 检查 .so 文件权限和 AppArmor 规则
# - "sys_chroot failed" → 需要 capability sys_chroot
```

### 8.6 APT 缓存问题

```bash
# 如果 apt 看不到新版本的包，清理缓存
sudo rm -rf /var/lib/apt/lists/*
sudo apt-get update

# 验证仓库索引
apt-cache policy nanobot
# 应显示候选版本和来源
```

---

## 9. Linux 基础知识速查

### 9.1 常用命令

| 命令 | 全称 | 说明 |
|------|------|------|
| `ls` | list | 列出目录内容 |
| `cd` | change directory | 切换目录 |
| `pwd` | print working directory | 显示当前目录 |
| `cp` | copy | 复制文件 |
| `mv` | move | 移动/重命名文件 |
| `rm` | remove | 删除文件 |
| `cat` | concatenate | 显示文件内容 |
| `chmod` | change mode | 修改文件权限 |
| `chown` | change owner | 修改文件所有者 |
| `grep` | global regular expression print | 搜索文本 |
| `find` | find | 查找文件 |
| `ps` | process status | 查看进程 |
| `kill` | kill | 终止进程 |
| `mkdir` | make directory | 创建目录 |
| `ln` | link | 创建链接 |
| `stat` | status | 显示文件状态 |

### 9.2 目录结构

| 目录 | 说明 |
|------|------|
| `/` | 根目录 |
| `/home/用户名/` | 用户主目录 |
| `/opt/` | 可选应用软件安装目录 |
| `/etc/` | 配置文件目录 |
| `/var/` | 可变数据（日志、缓存等） |
| `/usr/` | 用户程序（系统安装的软件） |
| `/tmp/` | 临时文件 |
| `/proc/` | 进程信息（虚拟文件系统） |
| `/dev/` | 设备文件 |
| `/sys/` | 系统信息（虚拟文件系统） |

### 9.3 文件权限

```
-rwxr-xr-x  1 root root  1234 Jan 1 12:00 filename
││││││││││  │ │    │     │    │    │       │
││││││││││  │ │    │     │    │    │       └── 文件名
││││││││││  │ │    │     │    │    └── 修改时间
││││││││││  │ │    │     │    └── 文件大小 (字节)
││││││││││  │ │    │     └── 所属组
││││││││││  │ │    └── 所有者
││││││││││  │ └── 硬链接数
││││││││││  └── 文件类型
││││││││││
│└┬┘└┬┘└┬┘
│ │   │   └── 其他人权限 (others)
│ │   └── 所属组权限 (group)
│ └── 所有者权限 (owner)
└── 文件类型 (- = 普通文件, d = 目录, l = 链接)
```

权限值:
- `r` = 4 (读)
- `w` = 2 (写)
- `x` = 1 (执行)
- `-` = 0 (无权限)

示例: `rwxr-xr-x` = 755 = 所有者(rwx=7) + 组(r-x=5) + 其他人(r-x=5)

### 9.4 管道和重定向

```bash
# 管道 (|): 将前一个命令的输出传给后一个命令的输入
ps aux | grep electron | grep -v grep

# 重定向 (>): 将输出写入文件（覆盖）
echo "hello" > /tmp/test.txt

# 追加 (>>): 将输出追加到文件
echo "world" >> /tmp/test.txt

# 标准错误重定向 (2>): 将错误输出写入文件
some_command 2> /tmp/error.log

# 合并标准输出和错误 (>&): 所有输出写入文件
some_command > /tmp/all_output.log 2>&1

# /dev/null: 黑洞设备，丢弃所有写入的数据
some_command 2>/dev/null  # 隐藏错误输出
```

### 9.5 环境变量

```bash
# 设置环境变量
export MY_VAR="hello"

# 查看环境变量
echo $MY_VAR

# 常见环境变量:
# $HOME      - 用户主目录
# $PATH      - 可执行文件搜索路径
# $USER      - 当前用户名
# $DISPLAY   - X11 显示地址
# $PWD       - 当前工作目录
```

### 9.6 进程管理

```bash
# 查看所有进程
ps aux

# 查看特定进程
ps aux | grep electron

# 查看进程树
pstree -p

# 终止进程
kill PID              # 发送 SIGTERM（优雅终止）
kill -9 PID           # 发送 SIGKILL（强制终止）
pkill -f "pattern"    # 按名称模式终止

# 后台运行
command &             # 后台执行
nohup command &       # 忽略挂断信号，后台执行
```

### 9.7 systemd 常用命令

```bash
# 查看服务状态
systemctl status <服务名>

# 启动/停止/重启服务
sudo systemctl start <服务名>
sudo systemctl stop <服务名>
sudo systemctl restart <服务名>

# 启用/禁用开机启动
sudo systemctl enable <服务名>
sudo systemctl disable <服务名>

# 重新加载配置
sudo systemctl daemon-reload

# 查看日志
journalctl -u <服务名>           # 全部日志
journalctl -u <服务名> -e        # 跳转到末尾
journalctl -u <服务名> --since "5 min ago"  # 最近 5 分钟
```

### 9.8 网络调试

```bash
# 检查端口监听
ss -tlnp | grep 8080

# 测试 HTTP 访问
curl http://localhost:8080

# 查看网络连接
ss -tnp

# 下载文件
curl -O http://example.com/file.deb
wget http://example.com/file.deb
```

---

## 验证沙箱模式（DevTools 实操）

### 2.1 打开 DevTools

Electron 支持 Chromium DevTools，有三种方式打开：

```bash
# 方式 1: 在 main.js 中添加，窗口自动弹出 DevTools
mainWindow.webContents.openDevTools();

# 方式 2: 启动时加命令行参数
/opt/lenovo/nanobot/nanobot --remote-debugging-port=9222
# 然后在浏览器访问 http://localhost:9222

# 方式 3: 快捷键（如果启用）
# Ctrl+Shift+I 或 F12
```

### 2.2 在 DevTools Console 中验证沙箱

打开 DevTools 后，在 **Console** 标签页中执行以下命令：

#### 测试 A: 检查 process.sandboxed

```javascript
// 在沙箱模式下，process 对象仍然可用（这是 Electron 注入的全局对象）
// 但 process.sandboxed 属性会告诉你是否在沙箱中
console.log(process.sandboxed);
// 预期: true （沙箱模式启用）
// 如果 false 或 undefined: 沙箱未启用

// process.type 告诉你当前是什么进程
console.log(process.type);
// 预期: 'renderer' （渲染进程）
```

#### 测试 B: 检查 Node.js API 是否可用

```javascript
// 在沙箱模式下，require() 不可用
try {
  const fs = require('fs');
  console.log('NODE.JS AVAILABLE - 沙箱未启用！');
} catch (e) {
  console.log('require is not defined - 沙箱已启用 ✅');
  // 预期: "ReferenceError: require is not defined"
}

// process.versions 包含版本信息
console.log(process.versions);
// 沙箱模式下: 有 electron, chromium, v8，但无 node 路径信息
// 非沙箱模式下: 有完整的 node 版本信息
```

#### 测试 C: 对比 preload.js 的环境差异

preload.js 运行在一个**特权上下文**中，即使渲染进程被沙箱化，
preload.js 仍然可以访问 Node.js API。这就是为什么我们能用 `contextBridge` 暴露安全 API：

```javascript
// preload.js 中（不是 DevTools Console）：
const { contextBridge, ipcRenderer } = require('electron');  // ✅ 可用
// 因为 preload.js 在沙箱的"隔离世界"中运行，有 Node.js 访问权限

// renderer.js / DevTools Console 中：
require('fs');  // ❌ ReferenceError: require is not defined
```

#### 测试 D: 检查 process-internals 页面

在地址栏输入（如果 Electron 支持）：
```
chrome://process-internals
```
可以看到每个进程的类型和沙箱状态。

### 2.3 完整验证脚本

在 DevTools Console 中一次性运行：

```javascript
console.log('=== Nanobot 沙箱验证 ===');
console.log('1. process.sandboxed:', process.sandboxed);
console.log('2. process.type:', process.type);
console.log('3. nodeIntegration:', typeof require === 'function' ? 'ENABLED (❌ 不安全!)' : 'DISABLED (✅ 安全)');
console.log('4. contextIsolation:', typeof window === 'object' && typeof window.electronAPI === 'object' ? 'ENABLED (✅ 安全)' : 'UNKNOWN');
console.log('5. Electron 版本:', process.versions.electron);
console.log('6. Chromium 版本:', process.versions.chrome);

// 尝试访问 Node.js API
try {
  require('fs').readFileSync('/etc/passwd', 'utf8');
  console.log('7. 文件系统访问: ENABLED (❌ 严重安全漏洞!)');
} catch (e) {
  console.log('7. 文件系统访问: BLOCKED (✅ 安全)');
}

// 总结
const isSandboxed = process.sandboxed === true;
const noNodeIntegration = typeof require !== 'function';
console.log('');
console.log(isSandboxed && noNodeIntegration ? '✅ 沙箱模式已正确启用' : '❌ 沙箱配置有问题!');
```

### 2.4 非沙箱 vs 沙箱模式对比

| 检查项 | 非沙箱模式 (`--no-sandbox`) | 沙箱模式 (`app.enableSandbox()`) |
|--------|---------------------------|--------------------------------|
| `process.sandboxed` | `false` 或 `undefined` | `true` |
| `require('fs')` | ✅ 可读取任意文件 | ❌ `ReferenceError` |
| `process.type` | `'renderer'` | `'renderer'` |
| preload.js 的 `require` | ✅ 可用 | ✅ 可用（隔离上下文） |
| `contextIsolation` | 通常 `false` | `true` |
| DevTools 能否访问 Node API | ✅ 能（危险） | ❌ 不能（安全） |

---

## 快速开始

```bash
# 1. 克隆或进入项目目录
cd /home/qiuyanlong/worespace/by-claw-poc-linux/poc

# 2. 构建 1.0.0 版本
./scripts/build-deb.sh 1.0.0

# 3. 安装应用
sudo dpkg -i packages/nanobot-1.0.0.deb

# 4. 搭建本地仓库
sudo ./scripts/setup-repo.sh

# 5. 配置客户端 APT 源
sudo ./scripts/setup-client-config.sh

# 6. 加载 AppArmor profile
sudo apparmor_parser -a /etc/apparmor.d/com.lenovo.nanobot
sudo apparmor_parser -a /etc/apparmor.d/com.lenovo.nanobot.electron

# 7. 启用自动升级 timer
sudo systemctl daemon-reload
sudo systemctl enable --now nanobot-poc-upgrade.timer

# 8. 构建并发布 1.1.0
./scripts/build-deb.sh 1.1.0
aptly repo add nanobot-poc packages/nanobot-1.1.0.deb
aptly publish update -passphrase="" noble
sudo apt-get update

# 9. 等待 timer 触发（最多 2 分钟）...

# 10. 验证升级
dpkg-query -W nanobot    # 应该显示 1.1.0
```

---

**POC 验证状态: 18/18 PASS ✅**
