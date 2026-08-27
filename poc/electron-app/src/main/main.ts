import { app, BrowserWindow } from 'electron';
import * as path from 'node:path';
import { createService, registerIpc, pushState } from './ipc';

// Refuse --no-sandbox (spec §6.1, §13.2)
if (app.commandLine.hasSwitch('no-sandbox')) {
  console.error('ERROR: --no-sandbox is not allowed.');
  app.exit(1);
}
app.enableSandbox();

// Single instance (spec §10)
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) { app.exit(0); }

let mainWindow: BrowserWindow | null = null;
const service = createService(app.getVersion());

app.whenReady().then(async () => {
  registerIpc(service, () => mainWindow);

  mainWindow = new BrowserWindow({
    width: 960, height: 680,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  mainWindow.loadFile(path.join(__dirname, 'renderer/index.html'));

  // Initial state + 5s poll (spec §7.4)
  const tick = async () => { const s = await service.compute(); pushState(() => mainWindow, s); };
  await tick();
  setInterval(tick, 5000);
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
