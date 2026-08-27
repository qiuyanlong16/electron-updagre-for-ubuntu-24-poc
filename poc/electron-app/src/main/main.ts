import { app, BrowserWindow } from 'electron';
import * as path from 'node:path';
import { createService, registerIpc, pushState } from './ipc';
import { detectUpgrade } from './last-run';
import type { UpdateState } from '../shared/types/update';

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

// Focus the existing window when a second instance is launched (OEM UX; spec §10 single-instance).
app.on('second-instance', () => {
  if (mainWindow) {
    if (mainWindow.isMinimized()) mainWindow.restore();
    mainWindow.focus();
  }
});

app.whenReady().then(async () => {
  // First-run-after-upgrade detection (spec §11). detectUpgrade reads lastSeen from disk,
  // decides, then markSeen(current) for next launch. The returned prior version is held in
  // memory for the whole session and attached to EVERY pushed state by decorate(), so the
  // 5s poll never drops the banner mid-session (re-reading disk each tick would flicker it
  // off once markSeen has advanced lastSeen to == current).
  const upgradedFrom = detectUpgrade(app.getVersion());
  const decorate = (s: UpdateState): UpdateState => upgradedFrom ? { ...s, upgradedFrom } : s;

  registerIpc(service, () => mainWindow, decorate);

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

  // Initial state + 5s poll (spec §7.4). safeTick swallows rejections so a forever-ticking
  // interval never surfaces an unhandledRejection (compute() can't reject in practice — it
  // try/catches internally — but this is defense-in-depth if computeState's throwing surface grows).
  const tick = async () => { const s = decorate(await service.compute()); pushState(() => mainWindow, s); };
  const safeTick = () => tick().catch(e => console.error('[byclaw] tick failed:', e));
  await safeTick();
  setInterval(safeTick, 5000);
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
