#!/usr/bin/env node
// Draws the MeWeTail icon (a 3x3 dot grid, "tail" dots fading out, on a purple rounded square) with no image libraries, so it
// works anywhere Node runs. Used when no icon PNG is supplied; the build menus prefer your own PNG (ICON_SRC) when it exists.
//   node scripts/gen-icons.js png <size> <out.png> [full|foreground|banner]
//     full        rounded square with the dots (default)
//     foreground  transparent, art inside the Android adaptive-icon safe zone
//     banner      Android TV banner (320x180 ratio; size = width)
const fs = require('node:fs');
const zlib = require('node:zlib');

const BG1 = [108, 92, 231], BG2 = [72, 52, 212];          // brand purple gradient
const WHITE = [255, 255, 255];
// 3x3 grid: (col,row) -> opacity. Bottom row fades like a tail.
const DOTS = [[0, 0, 1], [1, 0, 1], [2, 0, 1], [0, 1, 0.35], [1, 1, 1], [2, 1, 0.35], [0, 2, 0.35], [1, 2, 0.35], [2, 2, 1]];

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function png(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

// Signed distance helpers (negative inside).
const sdRoundRect = (px, py, cx, cy, hw, hh, r) => {
  const qx = Math.abs(px - cx) - (hw - r), qy = Math.abs(py - cy) - (hh - r);
  return Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};
const cover = (d) => Math.min(1, Math.max(0, 0.5 - d));   // 1px anti-aliasing

function render(w, h, style) {
  const rgba = Buffer.alloc(w * h * 4);
  const s = Math.min(w, h);
  // art box: the dot grid lives in a square of `art` px centred in the canvas
  const art = style === 'foreground' ? s * 0.5 : style === 'banner' ? s * 0.62 : s * 0.5;
  const pitch = art / 3, rad = pitch * 0.34;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = (y * w + x) * 4;
    let col = [0, 0, 0], a = 0;
    if (style !== 'foreground') {
      const d = style === 'banner' ? 0 : sdRoundRect(x + 0.5, y + 0.5, w / 2, h / 2, w / 2, h / 2, s * 0.22);
      a = style === 'banner' ? 1 : cover(d);
      const t = (x / w + y / h) / 2;
      col = [0, 1, 2].map((k) => BG1[k] + (BG2[k] - BG1[k]) * t);
    }
    for (const [cx, cy, op] of DOTS) {
      const dx = w / 2 + (cx - 1) * pitch, dy = h / 2 + (cy - 1) * pitch;
      const c = cover(Math.hypot(x + 0.5 - dx, y + 0.5 - dy) - rad) * op;
      if (c > 0) {
        const na = c + a * (1 - c);
        col = [0, 1, 2].map((k) => (WHITE[k] * c + col[k] * a * (1 - c)) / (na || 1));
        a = na;
      }
    }
    rgba[i] = col[0]; rgba[i + 1] = col[1]; rgba[i + 2] = col[2]; rgba[i + 3] = Math.round(a * 255);
  }
  return rgba;
}

const [cmd, sizeArg, out, style = 'full'] = process.argv.slice(2);
if (cmd === 'ico') {        // gen-icons.js ico <out.ico>   (PNG-compressed 16..256 px entries, supported since Windows Vista)
  const sizes = [16, 32, 48, 64, 128, 256];
  const imgs = sizes.map((n) => png(n, n, render(n, n, 'full')));
  const head = Buffer.alloc(6); head.writeUInt16LE(1, 2); head.writeUInt16LE(sizes.length, 4);
  let off = 6 + 16 * sizes.length; const dir = [];
  imgs.forEach((b, i) => { const e = Buffer.alloc(16); e[0] = sizes[i] % 256; e[1] = sizes[i] % 256; e.writeUInt16LE(1, 4); e.writeUInt16LE(32, 6); e.writeUInt32LE(b.length, 8); e.writeUInt32LE(off, 12); off += b.length; dir.push(e); });
  fs.mkdirSync(require('node:path').dirname(sizeArg), { recursive: true });
  fs.writeFileSync(sizeArg, Buffer.concat([head, ...dir, ...imgs]));
  process.exit(0);
}
if (cmd !== 'png' || !sizeArg || !out) { console.error('usage: gen-icons.js png <size> <out.png> [full|foreground|banner] | ico <out.ico>'); process.exit(2); }
const size = parseInt(sizeArg, 10);
const [w, h] = style === 'banner' ? [size, Math.round(size * 9 / 16)] : [size, size];
fs.mkdirSync(require('node:path').dirname(out), { recursive: true });
fs.writeFileSync(out, png(w, h, render(w, h, style)));
