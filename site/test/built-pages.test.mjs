// Checks on the built site (site/dist). Without a build the tests are skipped and say so; CI and the
// local check run them after `npm run build`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { parseHTML } from 'linkedom';

import { getReleases } from '../src/lib/releases.mjs';
import { REPO, SITE } from '../src/lib/repo.mjs';
import { SITE_URL, VERSION } from '../src/lib/site.mjs';
import { DIST as dist, skip } from './built.mjs';
import { readPages } from '../scripts/check-site.mjs';

// Every page Astro wrote, by its URL path. Read on first use, so a skipped run never reads site/dist.
let built;
export const pages = () => (built ??= readPages(dist));

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

test('every page has one skip link to #main and one h1', { skip }, () => {
  for (const p of pages()) {
    assert.equal(p.html.match(/<a class="skip" href="#main"/g)?.length, 1, `${p.url}: skip links`);
    assert.equal(p.html.match(/<main id="main"/g)?.length, 1, `${p.url}: <main id="main">`);
    assert.equal(p.html.match(/<h1[\s>]/g)?.length, 1, `${p.url}: h1 elements`);
  }
});

test('the 404 page has no canonical link; every other page has one', { skip }, () => {
  for (const p of pages()) {
    const canonical = p.html.match(/<link rel="canonical" href="([^"]+)"/)?.[1];
    if (p.url === '/404.html') assert.equal(canonical, undefined, '404: canonical');
    else assert.equal(canonical, new URL(p.url, SITE_URL).href, `${p.url}: canonical`);
  }
});

test('every page has its own title and its own description', { skip }, () => {
  const seen = { title: new Map(), description: new Map() };
  for (const p of pages()) {
    const title = p.html.match(/<title>([^<]*)<\/title>/)?.[1];
    const description = p.html.match(/<meta name="description" content="([^"]*)"/)?.[1];
    assert.ok(title, `${p.url}: no title`);
    assert.ok(description, `${p.url}: no description`);
    for (const [kind, value] of [['title', title], ['description', description]]) {
      const other = seen[kind].get(value);
      assert.equal(other, undefined, `${p.url} and ${other} share the ${kind} "${value}"`);
      seen[kind].set(value, p.url);
    }
  }
});

// ---- the changelog (R2, KTD14) ----

const changelog = () => {
  const p = pages().find((x) => x.url === '/changelog/');
  assert.ok(p, 'no /changelog/ page in the build');
  return parseHTML(p.html).document;
};

test('the changelog lists every release note once, newest first, each under its own anchor', { skip }, () => {
  const doc = changelog();
  const releases = getReleases();
  const entries = [...doc.querySelectorAll('[data-release]')];
  assert.deepEqual(entries.map((e) => e.getAttribute('data-release')), releases.map((r) => r.anchor), 'entries in getReleases() order');
  for (const r of releases) {
    assert.equal(doc.querySelectorAll(`[id="${r.anchor}"]`).length, 1, `${r.anchor}: one element carries the anchor`);
    const entry = doc.querySelector(`[data-release="${r.anchor}"]`);
    assert.ok(entry.querySelector(`[id="${r.anchor}"]`), `${r.anchor}: the anchor is inside its own entry`);
    const heading = entry.querySelector('h2').textContent;
    assert.ok(heading.includes(r.title), `${r.anchor}: its heading carries the note's title`);
    if (r.version) assert.ok(heading.includes(r.version), `${r.anchor}: its heading carries the version`);
    assert.ok(entry.querySelector(`time[datetime="${r.date}"]`), `${r.anchor}: no <time datetime="${r.date}">`);
  }
  // ids stay unique once every note's own headings share one page
  const ids = [...doc.querySelectorAll('[id]')].map((e) => e.id);
  assert.deepEqual(ids.filter((id, i) => ids.indexOf(id) !== i), [], 'duplicate ids on the changelog');
});

test("the v2.4.0 entry keeps its title's inner dashes", { skip }, () => {
  const raw = readFileSync(join(REPO, 'docs/releases/v2.4.0.md'), 'utf8').split('\n')[0];
  const title = raw.slice(raw.indexOf('v2.4.0: ') + 'v2.4.0: '.length);
  assert.ok(title.includes(' — '), 'the v2.4.0 header lost its inner dash; pick another note');
  const heading = changelog().querySelector('[data-release="v2-4-0"] h2').textContent.replace(/\s+/g, ' ');
  assert.ok(heading.toLowerCase().includes(title.toLowerCase()), `heading "${heading}" does not carry "${title}"`);
});

test('the newest note is open and every older one is collapsed, its notes still in the page', { skip }, () => {
  const entries = [...changelog().querySelectorAll('[data-release]')];
  entries.forEach((entry, i) => {
    const name = entry.getAttribute('data-release');
    const details = entry.matches('details') ? entry : entry.querySelector('details');
    assert.ok(details, `${name}: not a <details>`);
    assert.equal(details.hasAttribute('open'), i === 0, `${name}: open`);
    assert.ok(details.querySelector('summary h2'), `${name}: its heading is not in the <summary>`);
    assert.ok(details.querySelector('.rel-body').textContent.trim().length > 40, `${name}: the notes are missing`);
    // the note's own headings sit under the entry's h2
    assert.equal(details.querySelectorAll('.rel-body h1, .rel-body h2').length, 0, `${name}: an h1 or h2 inside the notes`);
  });
});

test('the changelog states the version and the release count, and ranks below current docs in search', { skip }, () => {
  const doc = changelog();
  assert.equal(doc.querySelector('title').textContent, 'Changelog · Agent Triforge');
  assert.ok(doc.querySelector('[data-claim="releases"]'), 'no data-claim="releases"');
  assert.ok(doc.querySelector('[data-version]')?.textContent.includes(VERSION), `the page does not state ${VERSION}`);
  const main = doc.querySelector('main');
  assert.equal(main.getAttribute('data-pagefind-filter'), 'section:Releases');
  const weight = Number(main.getAttribute('data-pagefind-weight'));
  assert.ok(weight > 0 && weight < 1, `main weight ${main.getAttribute('data-pagefind-weight')}`);
  // Pagefind boosts headings (h1 7 down to h6 2) unless a heading carries its own weight
  for (const h of doc.querySelectorAll('main h1, main h2, main h3, main h4, main h5, main h6')) {
    const w = Number(h.getAttribute('data-pagefind-weight'));
    const boost = 8 - Number(h.tagName[1]);
    assert.ok(w > 0 && w < boost, `${h.tagName} "${h.textContent.trim().slice(0, 40)}": weight ${h.getAttribute('data-pagefind-weight')}, the default boost is ${boost}`);
  }
});

// ---- the sitemap, robots.txt and the dev-only kit (KTD15) ----

const sitemapFiles = () => readdirSync(dist).filter((f) => /^sitemap-\d+\.xml$/.test(f));
const sitemapLocs = () => sitemapFiles().flatMap((f) => [...readFileSync(join(dist, f), 'utf8').matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]));

test('the sitemap lists every page but the 404 at its canonical URL, and robots.txt names it', { skip }, () => {
  const locs = sitemapLocs();
  assert.equal(new Set(locs).size, locs.length, 'a URL is listed twice');
  const canonicals = pages()
    .filter((p) => p.url !== '/404.html')
    .map((p) => p.html.match(/<link rel="canonical" href="([^"]+)"/)?.[1]);
  assert.deepEqual([...locs].sort(), [...canonicals].sort());
  const index = readFileSync(join(dist, 'sitemap-index.xml'), 'utf8');
  for (const f of sitemapFiles()) assert.ok(index.includes(`<loc>${SITE_URL}/${f}</loc>`), `the sitemap index misses ${f}`);
  assert.match(readFileSync(join(dist, 'robots.txt'), 'utf8'), new RegExp(`^Sitemap: ${SITE_URL}/sitemap-index\\.xml$`, 'm'));
});

test('the media kit is not in the build: no page, no link, no README GIF, not in the sitemap or llms.txt', { skip }, () => {
  assert.equal(existsSync(join(dist, 'kit')), false, 'dist/kit exists');
  assert.equal(existsSync(join(dist, 'media', 'readme-hero.gif')), false, 'dist/media/readme-hero.gif exists');
  for (const p of pages()) {
    assert.doesNotMatch(p.html, /href="(?:https?:\/\/[^"/]+)?\/kit\/?["#?]/, `${p.url} links the kit`);
    assert.doesNotMatch(p.html, /(?:src|href)="\/media\/readme-hero\.gif/, `${p.url} uses the kit's README GIF`);
  }
  assert.ok(!sitemapLocs().some((loc) => new URL(loc).pathname.startsWith('/kit')), 'the sitemap lists the kit');
  assert.doesNotMatch(readFileSync(join(dist, 'llms.txt'), 'utf8'), /\/kit\b|readme-hero\.gif/, 'llms.txt names the kit');
});

test('the kit routes are injected under astro dev only', async () => {
  const { default: kitDevRoute } = await import('../src/dev/kit-route.mjs');
  const injected = (command) => {
    const routes = [];
    kitDevRoute().hooks['astro:config:setup']({ command, injectRoute: (r) => routes.push(r.pattern) });
    return routes.sort();
  };
  assert.deepEqual(injected('dev'), ['/kit', '/media/readme-hero.gif']);
  for (const command of ['build', 'preview', 'sync']) assert.deepEqual(injected(command), [], `astro ${command} injects the kit`);
  assert.match(readFileSync(join(SITE, 'astro.config.mjs'), 'utf8'), /^\s*kitDevRoute\(\),/m, 'astro.config.mjs does not register the kit integration');
});
