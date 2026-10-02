// MeWeTail window: talks to the main process (preload.js -> window.tail). No framework; the state object comes from main.js `shape()`.
const $ = (id) => document.getElementById(id);
const T = {
  en: {
    tagline: 'Private network for your devices', thisDevice: 'This device', exitNode: 'Exit node', exitHelp: 'Send all internet traffic through one of your devices.',
    devices: 'Devices', connection: 'Connection', server: 'Server', serverHelp: "Sign-in uses the server's single sign-on (oidc.m-we.org).", save: 'Save', reset: 'Default',
    connected: 'Connected', disconnected: 'Disconnected', needsLogin: 'Sign-in needed', starting: 'Starting…', noDaemon: 'Service not installed',
    connectedText: (n, s) => `${n} · ${s}`, disconnectedText: 'Turn on to join your private network.', needsLoginText: 'A browser window opens: sign in with your MeWe account (single sign-on).',
    noDaemonText: 'This computer needs the MeWeTail background service (asks for an administrator password once).',
    connect: 'Connect', disconnect: 'Disconnect', signIn: 'Sign in', logout: 'Log out', install: 'Install system service', remove: 'Remove system service', openAdmin: 'Open server',
    modeSystem: 'System VPN — all apps use your private network.', modeLimited: (p) => `Limited mode — only apps using the proxy reach your devices (SOCKS5 ${p.socks}, HTTP ${p.http}). Install the system service for a full VPN.`,
    modeNone: 'No daemon running.', none: 'None', online: 'online', offline: 'offline', exitOption: 'exit node', copied: 'Copied', noExit: 'No exit node', waiting: 'Waiting for sign-in in the browser…'
  },
  zh: {
    tagline: '你的设备私有网络', thisDevice: '本设备', exitNode: '出口节点', exitHelp: '让所有上网流量经由你的某台设备。',
    devices: '设备', connection: '连接方式', server: '服务器', serverHelp: '登录使用服务器的统一登录 (oidc.m-we.org)。', save: '保存', reset: '默认',
    connected: '已连接', disconnected: '未连接', needsLogin: '需要登录', starting: '启动中…', noDaemon: '未安装系统服务',
    connectedText: (n, s) => `${n} · ${s}`, disconnectedText: '打开开关以加入你的私有网络。', needsLoginText: '将打开浏览器：请用你的 MeWe 账号登录（统一登录）。',
    noDaemonText: '本电脑需要 MeWeTail 后台服务（只需输入一次管理员密码）。',
    connect: '连接', disconnect: '断开', signIn: '登录', logout: '退出登录', install: '安装系统服务', remove: '移除系统服务', openAdmin: '打开服务器',
    modeSystem: '系统 VPN —— 所有应用都使用私有网络。', modeLimited: (p) => `受限模式 —— 只有使用代理的应用能访问你的设备（SOCKS5 ${p.socks}，HTTP ${p.http}）。安装系统服务可获得完整 VPN。`,
    modeNone: '后台服务未运行。', none: '无', online: '在线', offline: '离线', exitOption: '可作出口', copied: '已复制', noExit: '不使用出口节点', waiting: '等待在浏览器中登录…'
  }
};
let lang = localStorage.getItem('lang') || ((navigator.language || 'en').startsWith('zh') ? 'zh' : 'en');
let theme = localStorage.getItem('theme') || 'light';
let st = null, cfg = null, busy = false;
const t = (k, ...a) => { const v = (T[lang] || T.en)[k] ?? T.en[k] ?? k; return typeof v === 'function' ? v(...a) : v; };

function applyTheme() {
  const dark = theme === 'dark' || (theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.documentElement.dataset.theme = dark ? 'dark' : 'light';
  $('themeBtn').textContent = theme === 'light' ? '☀️' : theme === 'dark' ? '🌙' : '🖥️';
}
function applyLang() {
  document.documentElement.lang = lang; $('langBtn').textContent = lang === 'zh' ? '中文' : 'EN';
  document.querySelectorAll('[data-i18n]').forEach((n) => { n.textContent = t(n.dataset.i18n); });
  if (st) render(st);
}
const btn = (label, cls, fn) => { const b = document.createElement('button'); b.type = 'button'; b.className = `btn ${cls || ''}`; b.textContent = label; b.onclick = async () => { b.disabled = true; try { await fn(); } finally { b.disabled = false; } }; return b; };
async function act(p) { const r = await p; if (r && r.ok === false && r.error) showErr(r.error); else showErr(''); return r; }
function showErr(m) { $('err').hidden = !m; $('err').textContent = m || ''; }

function render(s) {
  st = s;
  const b = s.backend, actions = $('actions'); actions.replaceChildren();
  const dot = $('dot'); dot.className = 'dot';
  if (b === 'Running') {
    dot.classList.add('on'); $('stateTitle').textContent = t('connected');
    $('stateText').textContent = t('connectedText', s.self ? s.self.name : '', s.self ? s.self.ip : '');
    actions.append(btn(t('disconnect'), 'btn--ghost', () => act(window.tail.disconnect())), btn(t('logout'), 'btn--danger', () => act(window.tail.logout())));
  } else if (b === 'NeedsLogin') {
    dot.classList.add('wait'); $('stateTitle').textContent = t('needsLogin');
    $('stateText').textContent = s.auth ? t('waiting') : t('needsLoginText');
    actions.append(btn(t('signIn'), '', () => act(window.tail.connect())));
    if (s.auth) actions.append(btn(t('openAdmin'), 'btn--ghost', () => window.tail.openAdmin()));
  } else if (b === 'NoDaemon') {
    dot.classList.add('wait'); $('stateTitle').textContent = t('noDaemon'); $('stateText').textContent = t('noDaemonText');
    actions.append(btn(t('install'), '', () => act(window.tail.installService())));
  } else if (b === 'Starting' || b === 'NoState') {
    dot.classList.add('wait'); $('stateTitle').textContent = t('starting'); $('stateText').textContent = '';
  } else {
    $('stateTitle').textContent = t('disconnected'); $('stateText').textContent = t('disconnectedText');
    actions.append(btn(t('connect'), '', () => act(window.tail.connect())));
  }
  if (s.error) showErr(s.error);

  const running = b === 'Running';
  $('user').textContent = s.user ? s.user.name : '';
  $('selfCard').hidden = !(running && s.self);
  if (s.self) { $('selfName').textContent = s.self.dns || s.self.name; $('selfIp').textContent = s.self.ip; $('selfIp').onclick = () => { window.tail.copy(s.self.ip); $('selfIp').textContent = t('copied'); setTimeout(() => { $('selfIp').textContent = s.self.ip; }, 900); }; }

  const exits = (s.peers || []).filter((p) => p.exitOption);
  $('exitCard').hidden = !(running && exits.length);
  const sel = $('exitSel');
  if (!$('exitCard').hidden && document.activeElement !== sel) {
    sel.replaceChildren(new Option(t('noExit'), ''), ...exits.map((p) => new Option(`${p.name}${p.online ? '' : ' (' + t('offline') + ')'}`, p.id)));
    sel.value = s.exitNode || '';
  }
  $('peersCard').hidden = !(running && s.peers && s.peers.length);
  if (!$('peersCard').hidden) {
    $('peerCount').textContent = `${s.peers.filter((p) => p.online).length}/${s.peers.length}`;
    $('peers').replaceChildren(...s.peers.map((p) => {
      const li = document.createElement('li');
      const d = document.createElement('span'); d.className = `dot ${p.online ? 'on' : ''}`;
      const n = document.createElement('span'); n.className = 'name'; n.textContent = p.name;
      const sm = document.createElement('small'); sm.textContent = [p.os, p.user].filter(Boolean).join(' · '); n.append(sm);
      const ip = document.createElement('button'); ip.type = 'button'; ip.className = 'link'; ip.textContent = p.ip; ip.onclick = () => { window.tail.copy(p.ip); ip.textContent = t('copied'); setTimeout(() => { ip.textContent = p.ip; }, 900); };
      li.append(d, n, ...(p.exitNode ? [Object.assign(document.createElement('span'), { className: 'tag', textContent: t('exitNode') })] : []), ip);
      return li;
    }));
  }

  $('modeText').textContent = s.mode === 'system' ? t('modeSystem') : s.mode === 'limited' ? t('modeLimited', s.proxy) : t('modeNone');
  const ma = $('modeActions'); ma.replaceChildren();
  if (s.mode === 'limited') ma.append(btn(t('install'), 'btn--ghost', () => act(window.tail.installService())));
  if (s.mode === 'system') ma.append(btn(t('remove'), 'btn--ghost', () => act(window.tail.removeService())));
  if (document.activeElement !== $('serverInput')) $('serverInput').value = s.server || '';
  $('version').textContent = s.version ? `tailscale ${s.version.split('-')[0]}` : '';
}

$('langBtn').onclick = () => { lang = lang === 'en' ? 'zh' : 'en'; localStorage.setItem('lang', lang); applyLang(); };
$('themeBtn').onclick = () => { theme = { light: 'dark', dark: 'system', system: 'light' }[theme]; localStorage.setItem('theme', theme); applyTheme(); };
$('serverSave').onclick = async () => {
  const v = $('serverInput').value.trim().replace(/\/+$/, '');
  if (!/^https?:\/\/\S+$/.test(v)) return showErr('URL?');
  await act(window.tail.setSettings({ server: v }));
};
$('serverReset').onclick = async () => { await window.tail.setSettings({ server: '' }); $('serverInput').value = cfg.defaultServer; };
$('exitSel').onchange = () => act(window.tail.exitNode($('exitSel').value));

(async () => {
  applyTheme(); matchMedia('(prefers-color-scheme: dark)').addEventListener('change', applyTheme);
  cfg = await window.tail.config();
  applyLang();
  window.tail.onState(render);
  render(await window.tail.state());
})();
