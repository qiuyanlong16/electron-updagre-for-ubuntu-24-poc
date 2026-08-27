import { contextBridge, ipcRenderer } from 'electron';
import type { UpdateState } from '../shared/types/update';

const CHANNEL = 'byclaw:update-state-changed';

contextBridge.exposeInMainWorld('byclawAPI', {
  getCurrentVersion: (): Promise<string> => ipcRenderer.invoke('byclaw:get-current-version'),
  checkForUpdates: (): Promise<UpdateState> => ipcRenderer.invoke('byclaw:check-for-updates'),
  getUpdateState: (): Promise<UpdateState> => ipcRenderer.invoke('byclaw:get-update-state'),
  restartApplication: (): Promise<void> => ipcRenderer.invoke('byclaw:restart-application'),
  onUpdateStateChanged: (cb: (s: UpdateState) => void): (() => void) => {
    const listener = (_e: unknown, state: UpdateState) => cb(state);
    ipcRenderer.on(CHANNEL, listener);
    return () => { ipcRenderer.removeListener(CHANNEL, listener); };
  },
});
