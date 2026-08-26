// Preload script - exposes version to renderer via contextBridge
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('nanobotAPI', {
  getAppVersion: () => ipcRenderer.invoke('get-app-version'),
});
