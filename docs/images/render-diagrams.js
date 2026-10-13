#!/usr/bin/env node
// render-diagrams.js — Render each .diagram container in render-diagrams.html to a
// 2x PNG named after its id. Playwright blocks file:// URLs, so this folder is
// served over http on a free port first. Usage:
//   node docs/images/render-diagrams.js [--only id1,id2] [--out DIR]
//
// A full render (no --only) also writes render-diagrams.sha256 into the output
// directory: the sha256 of render-diagrams.html and of each excalidraw/*.svg, in
// `shasum -a 256` format. validate-versions compares it with those files, so a
// source edited without a re-render fails the gates.
//
// Exits non-zero, before writing anything, when an --only id is unknown or when
// the page has no FontFace for Inter or for JetBrains Mono with status `loaded`
// (the PNGs would carry a fallback font); and after the run when nothing rendered.
// Playwright is loaded from outside the repo: the root package.json may hold no
// dependencies.
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const DIR = __dirname;
const PAGE = 'render-diagrams.html';
const STAMP = 'render-diagrams.sha256';
const FONTS = ['Inter', 'JetBrains Mono'];

const args = process.argv.slice(2);
const getArg = (name, def) => {
  const i = args.indexOf(name);
  return i >= 0 && args[i + 1] ? args[i + 1] : def;
};
const only = (getArg('--only', '') || '').split(',').filter(Boolean);
const outDir = path.resolve(getArg('--out', DIR));

// Playwright from this folder's resolution, then the global npm root, then the
// copy the global @playwright/cli carries.
function loadPlaywright() {
  const tried = ['playwright'];
  const candidates = ['playwright'];
  try {
    const root = execFileSync('npm', ['root', '-g'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    if (root) {
      candidates.push(path.join(root, 'playwright'), path.join(root, '@playwright', 'cli', 'node_modules', 'playwright'));
    }
  } catch (e) {
    // no npm on PATH: only the local resolution is tried
  }
  for (const c of candidates) {
    try {
      return require(c);
    } catch (e) {
      if (e.code !== 'MODULE_NOT_FOUND') throw e;
      if (!tried.includes(c)) tried.push(c);
    }
  }
  throw new Error(`Playwright not found (tried ${tried.join(', ')}). Install it with: npm install -g playwright`);
}

// Minimal static server for this folder, excalidraw/ included.
const mime = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript',
  '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2',
};
const server = http.createServer((req, res) => {
  const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || PAGE;
  const fp = path.resolve(DIR, rel);
  if (!fp.startsWith(DIR + path.sep) || !fs.existsSync(fp) || fs.statSync(fp).isDirectory()) {
    res.writeHead(404); res.end('not found'); return;
  }
  res.writeHead(200, { 'Content-Type': mime[path.extname(fp)] || 'application/octet-stream' });
  fs.createReadStream(fp).pipe(res);
});

// The stamp's lines: render-diagrams.html first, then excalidraw/*.svg by path.
function stampLines() {
  const files = [PAGE];
  const exDir = path.join(DIR, 'excalidraw');
  if (fs.existsSync(exDir)) {
    fs.readdirSync(exDir).filter((f) => f.endsWith('.svg')).sort().forEach((f) => files.push(`excalidraw/${f}`));
  }
  return files.map((f) => {
    const hex = crypto.createHash('sha256').update(fs.readFileSync(path.join(DIR, f))).digest('hex');
    return `${hex}  docs/images/${f}\n`;
  }).join('');
}

(async () => {
  const { chromium } = loadPlaywright();
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address();

  // System Chrome first; the bundled Chromium when Chrome is not installed.
  let browser;
  try {
    browser = await chromium.launch({ channel: 'chrome' });
  } catch (e) {
    try {
      browser = await chromium.launch();
    } catch (e2) {
      throw new Error(`no browser: system Chrome failed (${e.message.split('\n')[0]}) and so did the bundled Chromium (${e2.message.split('\n')[0]}). Install Google Chrome, or run: npx playwright install chromium`);
    }
  }
  try {
    const page = await browser.newPage({ deviceScaleFactor: 2 });
    await page.goto(`http://127.0.0.1:${port}/${PAGE}`, { waitUntil: 'networkidle' });
    await page.evaluate(async () => { await document.fonts.ready; });

    // document.fonts.check() is true when no face for a family exists at all,
    // so look for a loaded FontFace of each family instead.
    const faces = await page.evaluate(() => Array.from(document.fonts).map((f) => ({
      family: f.family.replace(/^["']|["']$/g, ''), status: f.status,
    })));
    for (const fam of FONTS) {
      const mine = faces.filter((f) => f.family === fam);
      const bad = mine.filter((f) => f.status === 'error').length;
      if (!mine.some((f) => f.status === 'loaded') || bad) {
        throw new Error(`font ${fam} did not load (${mine.length} face(s), ${bad} failed); the Google Fonts stylesheet must be reachable. Nothing rendered.`);
      }
    }
    // Two frames so the loaded faces are painted before the first capture.
    await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));

    const ids = await page.$$eval('.diagram', (els) => els.map((el) => el.id).filter(Boolean));
    const unknown = only.filter((id) => !ids.includes(id));
    if (unknown.length) {
      throw new Error(`unknown --only id(s): ${unknown.join(', ')} (known: ${ids.join(', ')}). Nothing rendered.`);
    }

    fs.mkdirSync(outDir, { recursive: true });
    const rendered = [];
    for (const id of ids) {
      if (only.length && !only.includes(id)) continue;
      const el = await page.$(`.diagram#${id}`);
      await el.scrollIntoViewIfNeeded();
      const outPath = path.join(outDir, `${id}.png`);
      await el.screenshot({ path: outPath });
      rendered.push(`${id}.png (${Math.round(fs.statSync(outPath).size / 1024)} KB)`);
    }
    if (!rendered.length) throw new Error(`no .diagram with an id in ${PAGE}: nothing rendered`);

    console.log(`Rendered ${rendered.length} diagram(s) at 2x to ${outDir}:`);
    rendered.forEach((r) => console.log('  ' + r));
    if (!only.length) {
      fs.writeFileSync(path.join(outDir, STAMP), stampLines());
      console.log(`  ${STAMP} (sources stamped)`);
    }
  } finally {
    await browser.close();
  }
})().then(() => server.close()).catch((e) => {
  console.error(`render-diagrams: ${e.message}`);
  server.close();
  process.exit(1);
});
