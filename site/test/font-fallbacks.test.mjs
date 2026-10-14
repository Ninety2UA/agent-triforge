// Tests for the metric-matched fallback faces in site/src/styles/global.css and their wiring through
// the Fonts API in site/astro.config.mjs. Familjen Grotesk loads with font-display: block, so until it
// arrives the browser lays the page out, invisibly, in the first fallback family. These faces carry
// Familjen's measured widths (per weight band for letters, one face for digits, one for the space) and
// its vertical metrics, so that layout already has Familjen's line breaks and nothing moves when the
// font replaces it. The widths were measured in Chrome; these tests hold what can be checked without a
// browser: every weight the stylesheets use has a face for spaces, digits and letters, the metric
// overrides come out at Familjen's ascent, descent and line gap, and the built pages use these faces.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { SITE } from '../src/lib/repo.mjs';

const dist = join(SITE, 'dist');
const skip = !existsSync(join(dist, 'index.html')) && 'site/dist is not built (run npm run build in site/)';

// FamiljenGrotesk-var.woff2: ascender 1230, descender -270, line gap 0, at 1200 units per em (hhea, OS/2 typo).
const FAMILJEN = { ascent: 102.5, descent: 22.5, lineGap: 0 };
// SometypeMono-var.woff2: ascender 925, descender -275, line gap 0, at 1000 units per em.
const SOMETYPE = { ascent: 92.5, descent: 27.5, lineGap: 0 };

const styles = join(SITE, 'src', 'styles');
const global = readFileSync(join(styles, 'global.css'), 'utf8');

const faces = (family) =>
  [...global.matchAll(/@font-face\s*\{([^}]*)\}/g)]
    .map(([, body]) => Object.fromEntries([...body.matchAll(/([\w-]+)\s*:\s*([^;]+)/g)].map(([, k, v]) => [k, v.trim()])))
    .filter((f) => f['font-family']?.replace(/["']/g, '') === family)
    .map((f) => {
      const [lo, hi = lo] = f['font-weight'].split(/\s+/).map(Number);
      const chars = (f['unicode-range'] ?? 'U+0-10FFFF').split(',').map((r) => {
        const [a, b = a] = r.trim().replace(/^U\+/i, '').split('-').map((h) => Number.parseInt(h, 16));
        return [a, b];
      });
      return { ...f, weight: [lo, hi], chars, pct: (k) => Number.parseFloat(f[k]) };
    });

// Every font-weight the site's stylesheets and components set, plus body text and <strong>.
function usedWeights() {
  const weights = new Set([400, 700]);
  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name);
      if (e.isDirectory()) walk(p);
      else if (/\.(css|astro|tsx?)$/.test(e.name)) {
        const text = readFileSync(p, 'utf8');
        for (const [, w] of text.matchAll(/font-weight\s*:\s*(\d{3})/g)) weights.add(Number(w));
        for (const [, w] of text.matchAll(/\bfont\s*:\s*(\d{3})\s/g)) weights.add(Number(w));
        for (const [, name] of text.matchAll(/\bfont-(medium|semibold|bold)\b/g)) weights.add({ medium: 500, semibold: 600, bold: 700 }[name]);
      }
    }
  };
  walk(join(SITE, 'src'));
  return [...weights].filter((w) => w <= 700);
}

test('every weight the site uses has a Familjen fallback face for spaces, digits and letters', () => {
  const fam = faces('Familjen Grotesk Fallback');
  assert.ok(fam.length > 0, 'no @font-face for "Familjen Grotesk Fallback" in global.css');
  const missing = [];
  for (const w of usedWeights()) {
    const match = fam.filter((f) => f.weight[0] <= w && w <= f.weight[1]);
    for (const ch of [0x20, 0x30, 0x61]) {
      const n = match.filter((f) => f.chars.some(([lo, hi]) => lo <= ch && ch <= hi)).length;
      if (n !== 1) missing.push(`${w} U+${ch.toString(16)}: ${n} faces`);
    }
  }
  assert.deepEqual(missing, [], 'each weight and character class needs exactly one face');
});

for (const [family, metrics, local] of [
  ['Familjen Grotesk Fallback', FAMILJEN, /local\("Arial"\)/],
  ['Sometype Mono Fallback', SOMETYPE, /local\("Menlo"\)/],
]) {
  test(`each ${family} face scales to the font's ascent, descent and line gap`, () => {
    const list = faces(family);
    assert.ok(list.length > 0, `no @font-face for "${family}"`);
    for (const f of list) {
      const k = f.pct('size-adjust') / 100;
      const label = `${f['font-weight']} ${f['unicode-range'] ?? ''}`;
      assert.ok(Math.abs(f.pct('ascent-override') * k - metrics.ascent) < 0.02, `${label}: ascent`);
      assert.ok(Math.abs(f.pct('descent-override') * k - metrics.descent) < 0.02, `${label}: descent`);
      assert.equal(f.pct('line-gap-override'), metrics.lineGap, `${label}: line gap`);
      assert.match(f.src, local, `${label}: src`);
    }
  });
}

test('the built pages lay text out in these faces and preload only Familjen', { skip }, () => {
  const html = readFileSync(join(dist, 'index.html'), 'utf8');
  const familjen = html.match(/--font-familjen:([^;}]+)/)?.[1];
  assert.ok(familjen, 'no --font-familjen in index.html');
  assert.match(familjen, /^"Familjen Grotesk-\w+","Familjen Grotesk Fallback",/, '--font-familjen');
  assert.match(html.match(/--font-sometype:([^;}]+)/)?.[1] ?? '', /^"Sometype Mono-\w+","Sometype Mono Fallback",/, '--font-sometype');
  assert.doesNotMatch(html, /fallback: Arial/, 'a generated fallback face is still there');
  assert.match(html, /@font-face\{font-family:"?Familjen Grotesk Fallback"?/, 'the fallback faces were not inlined');
  assert.match(html, /font-family:"Familjen Grotesk-\w+";src:url\([^)]+\) format\("woff2"\);font-display:block/, 'Familjen is not font-display: block');
  assert.equal(html.match(/<link rel="preload"[^>]*as="font"/g)?.length, 1, 'one preloaded font file');
});
