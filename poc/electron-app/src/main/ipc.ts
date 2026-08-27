import { ipcMain, app, BrowserWindow } from 'electron';
import { UpdateService } from './update-service';
import type { UpdatePolicy, UpdateState } from '../shared/types/update';
import { readFileSync } from 'node:fs';

const STATE_PATH = '/var/lib/lenovo/byclaw/update-state.json';
const CONFIG_PATH = '/etc/lenovo/byclaw/config.json';

function readStateFile(): Promise<string> {
  return Promise.resolve().then(() => readFileSync(STATE_PATH, 'utf8'));
}

function readPolicyUrl(): string {
  try {
    const cfg = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
    return cfg.updatePolicyUrl as string;
  } catch {
    return 'http://127.0.0.1:8099/update-policy.json';
  }
}

export function createService(runningVersion: string): UpdateService {
  return new UpdateService({
    runningVersion,
    readStateFile,
    fetchPolicy: async (): Promise<UpdatePolicy> => {
      const url = readPolicyUrl();
      const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
      if (!res.ok) throw new Error(`policy http ${res.status}`);
      return (await res.json()) as UpdatePolicy;
    },
  });
}

export function registerIpc(service: UpdateService, getWindow: () => BrowserWindow | null) {
  ipcMain.handle('byclaw:get-current-version', () => app.getVersion());
  ipcMain.handle('byclaw:check-for-updates', () => service.compute());
  ipcMain.handle('byclaw:get-update-state', () => service.compute());
  ipcMain.handle('byclaw:restart-application', () => {
    app.relaunch();
    app.exit(0);
  });
}

export function pushState(getWindow: () => BrowserWindow | null, state: UpdateState) {
  getWindow()?.webContents.send('byclaw:update-state-changed', state);
}
