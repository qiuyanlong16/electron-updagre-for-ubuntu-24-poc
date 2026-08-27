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
  const DEFAULT = 'http://127.0.0.1:8099/update-policy.json';
  try {
    const cfg = JSON.parse(readFileSync(CONFIG_PATH, 'utf8'));
    const url = cfg.updatePolicyUrl;
    if (typeof url === 'string' && url.length > 0) return url;
    return DEFAULT;
  } catch {
    return DEFAULT;
  }
}

export function createService(runningVersion: string): UpdateService {
  return new UpdateService({
    runningVersion,
    readStateFile,
    fetchPolicy: async (): Promise<UpdatePolicy> => {
      const url = readPolicyUrl();
      // AbortSignal cancels the HTTP socket; UpdateService.withTimeout (same 3s) caps the
      // whole fetchPolicy incl. res.json() parsing. Intentional belt-and-suspenders.
      const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
      if (!res.ok) throw new Error(`policy http ${res.status}`);
      return (await res.json()) as UpdatePolicy;
    },
  });
}

export function registerIpc(
  service: UpdateService,
  getWindow: () => BrowserWindow | null,
  decorate: (s: UpdateState) => UpdateState,
) {
  ipcMain.handle('byclaw:get-current-version', () => app.getVersion());
  // check-for-updates (user-initiated) and get-update-state (initial load) both call the same
  // decorated compute() (main attaches the upgradedFrom banner field); semantically distinct, may diverge.
  const compute = async () => decorate(await service.compute());
  ipcMain.handle('byclaw:check-for-updates', compute);
  ipcMain.handle('byclaw:get-update-state', compute);
  ipcMain.handle('byclaw:restart-application', () => {
    app.relaunch();
    app.exit(0);
  });
}

export function pushState(getWindow: () => BrowserWindow | null, state: UpdateState) {
  getWindow()?.webContents.send('byclaw:update-state-changed', state);
}
