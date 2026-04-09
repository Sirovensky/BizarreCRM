/**
 * Preload Script — Secure IPC bridge between renderer and main process.
 * Exposes a `window.management` API object via contextBridge.
 */
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('management', {
  // Auth
  login: (username, password) => ipcRenderer.invoke('management:login', username, password),

  // Stats
  getStats: () => ipcRenderer.invoke('management:get-stats'),

  // Crashes
  getCrashes: () => ipcRenderer.invoke('management:get-crashes'),
  getDisabledRoutes: () => ipcRenderer.invoke('management:get-disabled-routes'),
  reenableRoute: (route) => ipcRenderer.invoke('management:reenable-route', route),
  clearCrashes: () => ipcRenderer.invoke('management:clear-crashes'),

  // Updates
  getUpdateStatus: () => ipcRenderer.invoke('management:get-update-status'),
  checkUpdates: () => ipcRenderer.invoke('management:check-updates'),
  performUpdate: () => ipcRenderer.invoke('management:perform-update'),

  // Server control
  restartServer: () => ipcRenderer.invoke('management:restart-server'),
  stopServer: () => ipcRenderer.invoke('management:stop-server'),
  openBrowser: () => ipcRenderer.invoke('management:open-browser'),
  viewLogs: () => ipcRenderer.invoke('management:view-logs'),

  // Dashboard window control
  closeDashboard: () => ipcRenderer.invoke('management:close-dashboard'),
});
