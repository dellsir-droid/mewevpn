const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('tail', {
  state: () => ipcRenderer.invoke('state'),
  config: () => ipcRenderer.invoke('config'),
  connect: () => ipcRenderer.invoke('connect'),
  disconnect: () => ipcRenderer.invoke('disconnect'),
  logout: () => ipcRenderer.invoke('logout'),
  exitNode: (id) => ipcRenderer.invoke('exitNode', id),
  installService: () => ipcRenderer.invoke('installService'),
  removeService: () => ipcRenderer.invoke('removeService'),
  setSettings: (s) => ipcRenderer.invoke('setSettings', s),
  openAdmin: () => ipcRenderer.invoke('openAdmin'),
  openUrl: (u) => ipcRenderer.invoke('openUrl', u),
  copy: (t) => ipcRenderer.invoke('copy', t),
  onState: (fn) => ipcRenderer.on('state', (_e, s) => fn(s))
});
