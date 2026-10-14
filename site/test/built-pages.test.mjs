// Checks on the built site (site/dist). Without a build the tests are skipped and say so; CI and the
// local check run them after `npm run build`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';

import { SITE } from '../src/lib/repo.mjs';
import { SITE_URL } from '../src/lib/site.mjs';

const dist = join(SITE, 'dist');
const skip = !existsSync(join(dist, 'index.html')) && 'site/dist is not built (run npm run build in site/)';

// Every page Astro wrote, by its URL path. Read on first use, so a skipped run never reads site/dist.
let built;
export const pages = () => (built ??= readPages());

function readPages() {
  const out = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) {
        if (!['_astro', 'pagefind', 'media', 'brand'].includes(name)) walk(path);
      } else if (name.endsWith('.html')) {
        const rel = relative(dist, path).split(sep).join('/');
        const url = rel === 'index.html' ? '/' : rel.endsWith('/index.html') ? `/${rel.slice(0, -'index.html'.length)}` : `/${rel}`;
        out.push({ url, html: readFileSync(path, 'utf8') });
      }
    }
  };
  walk(dist);
  return out;
}

const attr = (tag, name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];

// The script budget's first rule: React islands hydrate on first interaction (never client:load or
// client:idle), and no page pulls a script, stylesheet or font from another origin.
test('islands hydrate on interaction; nothing loads from another origin', { skip }, () => {
  const origin = new URL(SITE_URL).origin;
  const problems = [];
  let islands = 0;
  for (const p of pages()) {
    for (const [tag] of p.html.matchAll(/<astro-island\b[^>]*>/g)) {
      islands += 1;
      if (attr(tag, 'client') !== 'interaction') problems.push(`${p.url}: an island with client="${attr(tag, 'client')}"`);
    }
    for (const [tag] of p.html.matchAll(/<(script|img|video|source|iframe)\b[^>]*>/g)) {
      const src = attr(tag, 'src');
      if (src && new URL(src, SITE_URL).origin !== origin) problems.push(`${p.url}: ${tag.slice(1, tag.indexOf(' '))} ${src}`);
    }
    for (const [tag] of p.html.matchAll(/<link\b[^>]*>/g)) {
      const rel = (attr(tag, 'rel') ?? '').toLowerCase().split(/\s+/);
      const href = attr(tag, 'href');
      if (href && rel.some((r) => ['stylesheet', 'preload', 'preconnect', 'dns-prefetch', 'modulepreload', 'icon'].includes(r)) && new URL(href, SITE_URL).origin !== origin) {
        problems.push(`${p.url}: <link rel="${rel.join(' ')}"> ${href}`);
      }
    }
    for (const [, url] of p.html.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g)) {
      if (/^https?:/.test(url) && new URL(url).origin !== origin) problems.push(`${p.url}: CSS url(${url})`);
    }
  }
  assert.ok(islands > 0, 'no <astro-island> in the build: the header menu is one, so the pattern no longer matches');
  assert.deepEqual(problems, []);
});

test('every page sets its theme inline in <head>, before any stylesheet could paint', { skip }, () => {
  for (const p of pages()) {
    const head = p.html.slice(0, p.html.indexOf('</head>'));
    const init = head.indexOf("dataset.theme=t");
    assert.ok(init > 0, `${p.url}: no inline theme script in <head>`);
    assert.doesNotMatch(p.html, /<html[^>]*data-theme=/, `${p.url}: the server must not fix a theme`);
  }
});
