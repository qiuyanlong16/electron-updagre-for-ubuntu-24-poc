// Main process for Nanobot Electron App
const { app, BrowserWindow } = require('electron');
const path = require('path');
const fs = require('fs');

// Read version from package.json
const packagePath = path.join(__dirname, 'package.json');
const pkg = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
const appVersion = pkg.version;

// Prevent --no-sandbox from being used
if (app.commandLine.hasSwitch('no-sandbox')) {
  console.error('ERROR: --no-sandbox is not allowed. AppArmor policy prevents this.');
  app.exit(1);
}

// Enable sandbox mode BEFORE app.ready
app.enableSandbox();

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 600,
    height: 400,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  app.quit();
});

// IPC handler for version query
const { ipcMain } = require('electron');
ipcMain.handle('get-app-version', () => appVersion);
