// Writes app.config.json (what this app is) and package.json (what electron-builder needs) from the APP_* variables that
// scripts/common.sh exports from scripts/app.conf. Same file in every mewe* repo.
const fs = require('node:fs');
const e = process.env;
const need = (k) => { if (!e[k]) throw new Error(`${k} is not set — run this through a build.sh menu`); return e[k]; };

const cfg = {
  name: need('APP_NAME'), slug: need('APP_SLUG'), id: need('APP_ID'), scheme: e.APP_SCHEME || '', desc: e.APP_DESC || '',
  startUrl: e.START_URL || '', fallbackUrl: e.FALLBACK_URL || '',
  oidc: e.OIDC_CLIENT ? { issuer: e.OIDC_ISSUER || 'https://oidc.m-we.org/realms/mwe', clientId: e.OIDC_CLIENT, scope: 'openid profile email', authGlobal: e.AUTH_GLOBAL || '' } : null,
  nativeConfig: JSON.parse(e.NATIVE_CONFIG || '{}'),
  hasWww: fs.existsSync(`${__dirname}/www/index.html`)
};
fs.writeFileSync(`${__dirname}/app.config.json`, JSON.stringify(cfg, null, 2));

const pkg = JSON.parse(fs.readFileSync(`${__dirname}/package.base.json`, 'utf8'));
Object.assign(pkg, {
  name: cfg.slug, productName: cfg.name, version: e.APP_VERSION || '1.0.0', description: cfg.desc || cfg.name,
  author: { name: 'MeWe', email: 'dg9999@gmail.com' }, homepage: cfg.startUrl || 'https://m-we.org'
});
Object.assign(pkg.build, { appId: cfg.id, productName: cfg.name });
pkg.build.linux.executableName = cfg.slug;
pkg.build.linux.category = (e.LINUX_CATEGORY || 'Utility;').split(';')[0] || 'Utility';
pkg.build.mac.category = e.MAC_CATEGORY || 'public.app-category.utilities';
if (cfg.scheme) pkg.build.protocols = [{ name: `${cfg.name} sign-in`, schemes: [cfg.scheme] }];
// Per-app additions (e.g. extraResources for a bundled helper): electron/package.extra.json is merged into "build".
const extraFile = `${__dirname}/package.extra.json`;
if (fs.existsSync(extraFile)) {
  const extra = JSON.parse(fs.readFileSync(extraFile, 'utf8'));
  const isObj = (x) => x && typeof x === 'object' && !Array.isArray(x);
  const merge = (a, b) => { for (const [k, v] of Object.entries(b)) a[k] = Array.isArray(v) && Array.isArray(a[k]) ? [...a[k], ...v] : isObj(v) && isObj(a[k]) ? merge(a[k], v) : v; return a; };
  merge(pkg.build, extra);
}
if (e.EXTRA_FILES) pkg.build.files.push(...e.EXTRA_FILES.split(','));
fs.writeFileSync(`${__dirname}/package.json`, JSON.stringify(pkg, null, 2));
