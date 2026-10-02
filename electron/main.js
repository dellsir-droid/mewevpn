// MeWeTail desktop app (macOS, Windows, Linux): a window that drives the Tailscale daemon + CLI built from source (see scripts/app-hooks.sh).
//
// Two ways to run, chosen automatically:
//   * System VPN  - a tailscaled service is installed (button "Install system service") and the window just talks to it. Real VPN, all apps.
//   * Limited     - no service: the bundled tailscaled runs inside this app in user-space networking mode (no admin rights needed, but
//                   only a local SOCKS5/HTTP proxy at 127.0.0.1:1055/1056 reaches the tailnet, other apps are not routed).
// Sign-in is the server's: `tailscale up --login-server <hs.m-we.org>` returns a link, we open it in the browser, Headscale sends you to
// oidc.m-we.org (realm mwe) and the node registers. Nothing about the account is stored by this app.
const { app, BrowserWindow, Menu, Tray, shell, nativeImage, dialog, ipcMain, clipboard } = require('electron');
const { spawn, execFile } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const cfg = JSON.parse(fs.readFileSync(path.join(__dirname, 'app.config.json'), 'utf8'));
const DEFAULT_SERVER = (cfg.nativeConfig && cfg.nativeConfig.controlUrl) || 'https://hs.m-we.org';
const packaged = app.isPackaged;
const isWin = process.platform === 'win32', isMac = process.platform === 'darwin';
const dirName = isMac ? 'mac' : isWin ? 'win' : 'linux';
const binDir = packaged ? path.join(process.resourcesPath, 'bin') : path.join(__dirname, 'bin', dirName);
const exe = (n) => path.join(binDir, isWin ? `${n}.exe` : n);
const supportDir = app.getPath('userData');
const stateDir = path.join(supportDir, 'tailscale');
const userSocket = isWin ? null : path.join(stateDir, 'tailscaled.sock');
const settingsFile = path.join(supportDir, 'settings.json');
const SOCKS_PORT = 1055, HTTP_PORT = 1056;

let win = null, tray = null, quitting = false;
let daemon = null;                  // our own tailscaled (limited mode)
let loginProc = null;               // a running `tailscale up` waiting for the browser sign-in
let socketPath = null;              // null = the CLI's default (system service)
let mode = 'none';                  // system | limited | none
let lastStatus = null;

const readSettings = () => { try { return JSON.parse(fs.readFileSync(settingsFile, 'utf8')); } catch { return {}; } };
const writeSettings = (s) => { fs.mkdirSync(supportDir, { recursive: true }); fs.writeFileSync(settingsFile, JSON.stringify(s, null, 2)); };
const server = () => (readSettings().server || DEFAULT_SERVER).replace(/\/+$/, '');

// ---- running the CLI ---------------------------------------------------------------------------------------------------
function cli(args, { timeout = 20000, socket = socketPath } = {}) {
  const full = socket ? ['--socket', socket, ...args] : args;
  return new Promise((resolve) => {
    execFile(exe('tailscale'), full, { timeout, windowsHide: true, maxBuffer: 8 * 1024 * 1024 }, (err, stdout, stderr) => {
      resolve({ ok: !err, code: err ? (err.code ?? 1) : 0, stdout: String(stdout || ''), stderr: String(stderr || '') });
    });
  });
}
async function statusVia(socket) {
  const r = await cli(['status', '--json'], { socket, timeout: 6000 });
  try { const j = JSON.parse(r.stdout); return j && j.BackendState ? j : null; } catch { return null; }
}
const systemSockets = () => (isWin ? [null] : isMac ? ['/var/run/tailscaled.socket', '/var/run/tailscale/tailscaled.sock'] : ['/var/run/tailscale/tailscaled.sock']);

// Find a running system service first, else start our own user-space daemon.
async function ensureDaemon() {
  for (const s of systemSockets()) {
    const st = await statusVia(s);
    if (st) { socketPath = s; mode = 'system'; return st; }
  }
  if (isWin) { mode = 'none'; return null; }        // Windows needs the service (user-space mode has no usable socket there)
  if (!daemon) {
    fs.mkdirSync(stateDir, { recursive: true });
    if (!fs.existsSync(exe('tailscaled'))) throw new Error(`tailscaled is missing at ${exe('tailscaled')}. Rebuild with the build menu.`);
    try { fs.unlinkSync(userSocket); } catch { /* none */ }
    daemon = spawn(exe('tailscaled'), ['--tun=userspace-networking', `--socket=${userSocket}`, `--statedir=${stateDir}`,
      `--socks5-server=localhost:${SOCKS_PORT}`, `--outbound-http-proxy-listen=localhost:${HTTP_PORT}`],
      { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true, env: { ...process.env, TS_NO_LOGS_NO_SUPPORT: 'true' } });   // private network: no log upload to tailscale.com
    daemon.stdout.on('data', (d) => process.stdout.write(d));
    daemon.stderr.on('data', (d) => process.stderr.write(d));
    daemon.on('exit', (c) => { daemon = null; if (!quitting) console.error(`tailscaled exited (${c})`); });
  }
  for (let i = 0; i < 40; i++) {
    const st = await statusVia(userSocket);
    if (st) { socketPath = userSocket; mode = 'limited'; return st; }
    await new Promise((r) => setTimeout(r, 400));
  }
  throw new Error('tailscaled did not start.');
}

// ---- state for the window ------------------------------------------------------------------------------------------------
function shape(st) {
  if (!st) return { mode, backend: 'NoDaemon', server: server(), peers: [], self: null, auth: null, exitNode: null, version: null };
  const peers = Object.values(st.Peer || {}).map((p) => ({
    id: p.ID, name: (p.DNSName || p.HostName || '').replace(/\.$/, '').split('.')[0] || p.HostName, dns: (p.DNSName || '').replace(/\.$/, ''),
    ip: (p.TailscaleIPs || [])[0] || '', os: p.OS || '', online: !!p.Online, exitOption: !!p.ExitNodeOption, exitNode: !!p.ExitNode,
    user: st.User && st.User[p.UserID] ? st.User[p.UserID].LoginName : ''
  })).sort((a, b) => Number(b.online) - Number(a.online) || a.name.localeCompare(b.name));
  const self = st.Self ? { name: (st.Self.HostName || ''), ip: (st.Self.TailscaleIPs || [])[0] || '', dns: (st.Self.DNSName || '').replace(/\.$/, ''), os: st.Self.OS || '' } : null;
  const me = st.Self && st.User && st.User[st.Self.UserID] ? st.User[st.Self.UserID] : null;
  return { mode, backend: st.BackendState, server: server(), version: st.Version, auth: st.AuthURL || null, peers, self,
    user: me ? { name: me.DisplayName || me.LoginName, login: me.LoginName } : null, exitNode: (peers.find((p) => p.exitNode) || {}).id || null,
    health: st.Health || [], proxy: mode === 'limited' ? { socks: `127.0.0.1:${SOCKS_PORT}`, http: `127.0.0.1:${HTTP_PORT}` } : null };
}
async function refresh() {
  let st = null;
  try { st = await statusVia(socketPath); } catch { st = null; }
  if (!st) { try { st = await ensureDaemon(); } catch (e) { return { ...shape(null), error: e.message }; } }
  lastStatus = st;
  return shape(st);
}
const push = async () => { const s = await refresh(); if (win && !win.isDestroyed()) win.webContents.send('state', s); updateTray(s); return s; };

// ---- actions ---------------------------------------------------------------------------------------------------------------
async function connect() {
  await ensureDaemon();
  const args = ['up', `--login-server=${server()}`, '--accept-routes', '--accept-dns=true', `--hostname=${os.hostname()}`, '--timeout=0s'];
  if (loginProc) { try { loginProc.kill(); } catch { /* gone */ } loginProc = null; }
  const full = socketPath ? ['--socket', socketPath, ...args] : args;
  loginProc = spawn(exe('tailscale'), full, { stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
  let out = '';
  const grab = (d) => { out += d; const m = out.match(/https?:\/\/\S+/); if (m && !grab.opened) { grab.opened = true; shell.openExternal(m[0].replace(/[)\].,]+$/, '')); } };
  loginProc.stdout.on('data', grab); loginProc.stderr.on('data', grab);
  loginProc.on('exit', () => { loginProc = null; push(); });
  // The sign-in link also shows up in the status (AuthURL): the poller below opens it when the CLI output didn't contain one.
  return { ok: true };
}
async function disconnect() {
  if (loginProc) { try { loginProc.kill(); } catch { /* gone */ } loginProc = null; }
  return cli(['down']);
}
async function logout() { if (loginProc) { try { loginProc.kill(); } catch { /* gone */ } loginProc = null; } return cli(['logout']); }
async function setExitNode(id) {
  const peer = lastStatus && Object.values(lastStatus.Peer || {}).find((p) => String(p.ID) === String(id));
  const ip = peer ? (peer.TailscaleIPs || [])[0] : '';
  return cli(['set', `--exit-node=${ip || ''}`, '--exit-node-allow-lan-access=true']);
}

// Elevated, one-off: install tailscaled as a system service (real VPN for every app).
function elevate(cmdLine) {
  return new Promise((resolve) => {
    let child;
    if (isMac) child = spawn('osascript', ['-e', `do shell script "${cmdLine.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}" with administrator privileges`]);
    else if (isWin) child = spawn('powershell', ['-NoProfile', '-Command', `Start-Process -Verb RunAs -Wait -WindowStyle Hidden -FilePath '${exe('tailscaled')}' -ArgumentList '${cmdLine}'`]);
    else child = spawn('pkexec', ['sh', '-c', cmdLine]);
    let err = '';
    child.stderr && child.stderr.on('data', (d) => (err += d));
    child.on('error', (e) => resolve({ ok: false, error: e.message }));
    child.on('exit', (c) => resolve({ ok: c === 0, error: c === 0 ? '' : err || `exit ${c}` }));
  });
}
async function installService() {
  if (daemon) { try { daemon.kill(); } catch { /* gone */ } daemon = null; }
  let r;
  if (isWin) r = await elevate('install-system-daemon');
  // The signed-in desktop user becomes the daemon's "operator", so connecting later needs no admin password.
  else if (isMac) r = await elevate(`'${exe('tailscaled')}' install-system-daemon && sleep 3 && /usr/local/bin/tailscale set --operator='${os.userInfo().username}'`);   // tailscaled copies itself to /usr/local/bin and loads the launchd job
  else {
    // An AppImage is mounted for the current user only, root cannot read it: stage the files in a temp folder first.
    const stage = fs.mkdtempSync(path.join(os.tmpdir(), 'mewetail-'));
    for (const f of ['tailscaled', 'tailscale', 'linux-install-service.sh']) fs.copyFileSync(path.join(binDir, f), path.join(stage, f));
    r = await elevate(`sh '${path.join(stage, 'linux-install-service.sh')}' '${stage}' '${os.userInfo().username}'; rm -rf '${stage}'`);
  }
  socketPath = null; mode = 'none';
  await new Promise((r2) => setTimeout(r2, 2500));
  await push();
  return r;
}
async function removeService() {
  let r;
  if (isWin) r = await elevate('uninstall-system-daemon');
  else if (isMac) r = await elevate(`'${exe('tailscaled')}' uninstall-system-daemon`);
  else r = await elevate("systemctl disable --now tailscaled; rm -f /etc/systemd/system/tailscaled.service /usr/local/bin/tailscaled /usr/local/bin/tailscale; systemctl daemon-reload");
  socketPath = null; mode = 'none';
  await push();
  return r;
}

// ---- window, tray ------------------------------------------------------------------------------------------------------------
const iconPath = path.join(__dirname, 'build', 'icon.png');
function createWindow() {
  win = new BrowserWindow({
    width: 980, height: 740, minWidth: 360, minHeight: 480, title: cfg.name, icon: iconPath,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false, sandbox: true }
  });
  win.setMenuBarVisibility(false);
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https?:/.test(url)) shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.on('will-navigate', (e, url) => { if (!url.startsWith('file:')) { e.preventDefault(); if (/^https?:/.test(url)) shell.openExternal(url); } });
  win.on('close', (e) => { if (!quitting) { e.preventDefault(); win.hide(); } });     // keep the connection in the background
  win.loadFile(path.join(__dirname, 'www', 'index.html'));
}
function updateTray(s) {
  if (!tray) return;
  const up = s && s.backend === 'Running';
  tray.setToolTip(`${cfg.name} — ${up ? 'connected' : s && s.backend === 'NeedsLogin' ? 'sign-in needed' : 'disconnected'}`);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: `Open ${cfg.name}`, click: () => (win ? win.show() : createWindow()) },
    { label: up ? 'Disconnect' : 'Connect', click: async () => { if (up) await disconnect(); else await connect(); push(); } },
    { type: 'separator' },
    { label: 'Quit', click: () => app.quit() }
  ]));
}
function ipc() {
  const h = (name, fn) => ipcMain.handle(name, async (_e, ...a) => { try { const r = await fn(...a); await push(); return r ?? { ok: true }; } catch (e) { return { ok: false, error: String(e.message || e) }; } });
  ipcMain.handle('state', () => refresh());
  ipcMain.handle('config', () => ({ defaultServer: DEFAULT_SERVER, name: cfg.name, settings: readSettings(), platform: process.platform }));
  h('connect', connect); h('disconnect', disconnect); h('logout', logout); h('exitNode', setExitNode);
  h('installService', installService); h('removeService', removeService);
  h('setSettings', (s) => { writeSettings({ ...readSettings(), ...s }); });
  ipcMain.handle('openAdmin', () => shell.openExternal(server()));
  ipcMain.handle('openUrl', (_e, u) => { if (/^https:\/\/m-we\.org\/?/.test(u)) shell.openExternal(u); });
  ipcMain.handle('copy', (_e, t) => clipboard.writeText(String(t)));
}

const lock = app.requestSingleInstanceLock();
if (!lock) app.quit();
else {
  app.on('second-instance', () => win && win.show());
  app.whenReady().then(async () => {
    ipc();
    Menu.setApplicationMenu(Menu.buildFromTemplate([...(isMac ? [{ role: 'appMenu' }] : [{ role: 'fileMenu' }]), { role: 'editMenu' }, { role: 'windowMenu' }]));
    const img = nativeImage.createFromPath(iconPath);
    tray = new Tray(img.isEmpty() ? img : img.resize({ width: 18, height: 18 }));
    tray.on('click', () => (win ? win.show() : createWindow()));
    createWindow();
    app.on('activate', () => (win ? win.show() : createWindow()));
    await push();
    // Poll: keeps the window fresh and opens the sign-in link when the daemon asks for one.
    let openedFor = '';
    setInterval(async () => {
      const s = await push();
      if (s && s.auth && s.backend === 'NeedsLogin' && loginProc && s.auth !== openedFor) { openedFor = s.auth; shell.openExternal(s.auth); }
    }, 3000);
  }).catch((e) => { dialog.showErrorBox(`${cfg.name} could not start`, String(e.message || e)); app.quit(); });
  app.on('before-quit', () => { quitting = true; for (const c of [daemon, loginProc]) if (c) try { c.kill(); } catch { /* gone */ } });
  app.on('window-all-closed', () => { /* stay alive in the tray */ });
}
