// The JavaScript budget (R10): before any interaction a page loads less than 25 KB of gzipped
// JavaScript on the home page and less than 10 KB on every other page. "Before any interaction" is
// every inline script, every module script and its static imports, and the dynamic imports a page
// starts on load (the video player, on pages with a figure). The palette, React and the islands load
// on first use and are not counted; that islands hydrate only on interaction is held by
// built-pages.test.mjs.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { join } from 'node:path';

import { readPages } from '../scripts/check-site.mjs';
import { DIST as dist, skip } from './built.mjs';

const gz = (text) => gzipSync(Buffer.from(text), { level: 9 }).length;

export const HOME_LIMIT = 25 * 1024;
export const PAGE_LIMIT = 10 * 1024;

/**
 * The gzipped bytes a page's scripts weigh before interaction, by file.
 * @param {string} html  the page
 * @param {(path: string) => string} read  a site path (/_astro/x.js) to its text
 */
export function scriptBytes(html, read) {
  const files = new Map();
  let inline = 0;
  const follow = (path, seen) => {
    if (seen.has(path)) return;
    seen.add(path);
    const code = read(path);
    files.set(path, gz(code));
    // static imports: import{a}from"./x.js" and import"./x.js"
    for (const [, spec] of code.matchAll(/\bimport\s*(?:[\w${},\s*]+\s*from\s*)?["']([^"']+\.js)["']/g)) follow(new URL(spec, `https://x${path}`).pathname, seen);
    // the video player, imported on load by pages that have a figure
    if (/data-vfig/.test(html)) {
      for (const [, spec] of code.matchAll(/import\(["']([^"']*video[^"']*\.js)["']\)/g)) follow(new URL(spec, `https://x${path}`).pathname, seen);
    }
  };
  const seen = new Set();
  for (const [tag, body] of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)) {
    if (/type="application\/(ld\+)?json"/.test(tag)) continue;
    const src = tag.match(/\ssrc="([^"]+)"/)?.[1];
    if (src) follow(new URL(src, 'https://x').pathname, seen);
    else inline += gz(body);
  }
  const total = inline + [...files.values()].reduce((a, b) => a + b, 0);
  return { total, inline, files };
}

const readDist = (path) => readFileSync(join(dist, path), 'utf8');

test('every page stays inside its script budget before interaction', { skip }, () => {
  const over = [];
  for (const p of readPages(dist)) {
    const { total } = scriptBytes(p.html, readDist);
    const limit = p.url === '/' ? HOME_LIMIT : PAGE_LIMIT;
    if (total >= limit) over.push(`${p.url}: ${(total / 1024).toFixed(1)} KB gzipped (limit ${limit / 1024} KB)`);
  }
  assert.deepEqual(over, []);
});

test('the budget counts static imports and the on-load video import, not the palette', () => {
  const files = {
    '/_astro/a.js': 'import{x}from"./b.js";if(document.querySelector("[data-vfig]"))import("./video.js");document.addEventListener("keydown",()=>import("./mount.js"))',
    '/_astro/b.js': 'export const x=1;' + 'y'.repeat(4000),
    '/_astro/video.js': 'export const v=2;' + 'z'.repeat(4000),
    '/_astro/mount.js': 'export const m=3;' + 'm'.repeat(4000),
  };
  const read = (path) => files[path];
  const withFigure = scriptBytes('<script type="module" src="/_astro/a.js"></script><figure data-vfig></figure>', read);
  assert.deepEqual([...withFigure.files.keys()].sort(), ['/_astro/a.js', '/_astro/b.js', '/_astro/video.js']);
  const without = scriptBytes('<script type="module" src="/_astro/a.js"></script><script>let t=1</script>', read);
  assert.deepEqual([...without.files.keys()].sort(), ['/_astro/a.js', '/_astro/b.js']);
  assert.ok(without.inline > 0);
});

test('a content page whose scripts total 11 KB gzipped fails the 10 KB limit, while the home limit is 25 KB', () => {
  // incompressible text, so its gzipped size is about its length
  let seed = 7;
  const noise = (n) => Array.from({ length: n }, () => String.fromCharCode(33 + ((seed = (seed * 48271) % 2147483647) % 90))).join('');
  // 90 symbols carry about 6.5 bits each, so 14 KB of noise gzips to about 11 KB
  const big = { '/_astro/big.js': noise(14 * 1024) };
  const { total } = scriptBytes('<script type="module" src="/_astro/big.js"></script>', (p) => big[p]);
  assert.ok(Math.abs(total - 11 * 1024) < 1024, `about 11 KB gzipped: ${total} bytes`);
  assert.ok(total > PAGE_LIMIT && total < HOME_LIMIT);
});
