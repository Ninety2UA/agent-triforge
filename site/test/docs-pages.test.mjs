// The Docs and Guides pages (U6): the body helpers in components/docs/body.mjs, then the built pages in
// site/dist. Built-page tests skip with a message when site/dist is missing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { REPO, SITE } from '../src/lib/repo.mjs';
import { docsMap } from '../src/lib/docs-map.mjs';
import { docPages } from '../src/lib/docs.mjs';
import { readDocPagesList } from '../src/lib/sources.mjs';
import { describe, finishBody, splitAfterH2, splitBeforeFirstH2, withImageOptions } from '../src/components/docs/body.mjs';
import { runClientScript } from './client-script.mjs';
import { page } from './dom.mjs';

const DIST = join(SITE, 'dist');
const skip = !existsSync(join(DIST, 'index.html')) && 'site/dist is not built (run npm run build in site/)';
const built = (href) => join(DIST, href, 'index.html');
const html = (href) => readFileSync(built(href), 'utf8');
const article = (h) => h.match(/<article\b[^>]*>([\s\S]*?)<\/article>/)?.[1] ?? '';
const decode = (s) => s.replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16))).replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
  .replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const text = (s) => decode(s.replace(/<[^>]*>/g, '')).replace(/\s+/g, ' ').trim();
const placeholder = (props) => `<img __ASTRO_IMAGE_="${JSON.stringify(props).replace(/"/g, '&#x22;')}">`;
const propsOf = (out) => [...out.matchAll(/__ASTRO_IMAGE_="([^"]+)"/g)].map((m) => JSON.parse(m[1].replace(/&#x22;/g, '"').replace(/&#x27;/g, "'").replace(/&#x26;/g, '&')));

// ---- body helpers ----

test('each image becomes an AVIF source and a WebP img; the first gets priority only before the second H2', () => {
  const early = withImageOptions(`<p>${placeholder({ src: './a.png', alt: 'A', index: 0 })}</p><h2 id="x">X</h2>${placeholder({ src: './b.png', alt: 'B', index: 0 })}<h2 id="y">Y</h2>`);
  assert.match(early, /^<p><picture><source __ASTRO_IMAGE_="[^"]+"><img __ASTRO_IMAGE_="[^"]+"><\/picture><\/p>/);
  const [aAvif, a, bAvif, b] = propsOf(early);
  assert.equal(a.priority, true);
  assert.equal(b.priority, undefined, 'only the first image');
  assert.equal(aAvif.priority, undefined, 'the source carries no loading hints');
  for (const p of [a, b]) {
    assert.equal(p.format, undefined, 'the img is the default WebP');
    assert.ok(p.widths.length > 1 && p.sizes, 'a srcset at display widths');
    assert.ok(p.widths.at(-1) >= 10000, 'the ceiling width makes the original the largest candidate');
  }
  for (const p of [aAvif, bAvif]) {
    assert.equal(p.format, 'avif');
    assert.equal(p.sizes, a.sizes);
    assert.ok(p.widths.at(-1) < 10000, 'no full-size AVIF');
  }
  const late = withImageOptions(`<h2 id="x">X</h2><p>t</p><h2 id="y">Y</h2>${placeholder({ src: './a.png', alt: 'A', index: 0 })}`);
  assert.equal(propsOf(late)[1].priority, undefined, 'an image after the opening section stays lazy');
});

test('finishBody links images to their full-size file and fits tables to the column', () => {
  const out = finishBody([
    '<p><picture><source alt="D" sizes="S" loading="lazy" width="400" height="200" src="/_astro/d_400.avif" srcset="/_astro/d_400.avif 400w, /_astro/d_700.avif 700w">'
      + '<img alt="D" width="1760" height="900" src="/_astro/d_full.webp" srcset="/_astro/d_400.webp 400w, /_astro/d_full.webp 1760w"></picture></p>',
    '<table><thead><tr><th>Layer</th><th>Guards <code>x</code></th></tr></thead><tbody><tr><td>a</td><td>b</td></tr></tbody></table>',
    '<pre class="astro-code"><code><span># Claude Code ≥ 2.1.277 — the first build</span></code></pre>',
  ].join('\n'));
  assert.match(out, /2\.1\.277 — the first build/, 'a code block is left as the repo wrote it');
  assert.match(out, /<div class="img"><a class="img-full" href="\/_astro\/d_full\.webp"><picture><source type="image\/avif" srcset="\/_astro\/d_400\.avif 400w, \/_astro\/d_700\.avif 700w" sizes="S"><img [^>]*><\/picture><\/a><\/div>/);
  assert.match(out, /<div class="table-wrap" data-stack="\d+"><table role="table">/);
});

test('a code block holding a lead tab\'s install commands becomes a link to that tab', () => {
  const install = [
    { id: 'claude-code', label: 'Claude Code leads', lines: ['claude plugin marketplace add X', 'claude plugin install Y'] },
    { id: 'codex', label: 'Codex leads', lines: ['codex plugin add Y'] },
  ];
  const block = (lines) => `<pre class="astro-code" tabindex="0"><code>${lines.map((l) => `<span class="line"><span>${l}</span></span>`).join('\n')}</code></pre>`;
  const out = finishBody([
    block(['# Register once', 'claude plugin marketplace add X', '', '# User scope', 'claude plugin install Y', 'claude plugin install Y --scope project']),
    block(['codex plugin add Y']),
    block(['claude plugin marketplace update agent-triforge']),
  ].join('\n'), { install });
  assert.match(out, /<a href="#claude-code">Claude Code leads<\/a>/);
  assert.match(out, /<a href="#codex">Codex leads<\/a>/);
  assert.equal((out.match(/<pre\b/g) ?? []).length, 1, 'the update block stays');
  assert.match(out, /marketplace update/);
});

test('splitBeforeFirstH2, splitAfterH2 and describe', () => {
  assert.deepEqual(splitBeforeFirstH2('<p>a</p><h2 id="b">B</h2><p>c</p>'), ['<p>a</p>', '<h2 id="b">B</h2><p>c</p>']);
  assert.deepEqual(splitBeforeFirstH2('<p>a</p>'), ['<p>a</p>', '']);
  assert.deepEqual(splitAfterH2('<h2 id="a">A</h2><p>x</p><h2 id="b">B <code>c</code></h2><ol>', 'b'), ['<h2 id="a">A</h2><p>x</p><h2 id="b">B <code>c</code></h2>', '<ol>']);
  assert.throws(() => splitAfterH2('<h2 id="a">A</h2>', 'gone'), /no H2 with id "gone"/);
  assert.equal(describe('Run [`at-ship`](/skills/at-ship/) **now** (or later).'), 'Run at-ship now.');
  assert.equal(describe('A `DONE_WITH_CONCERNS` report and `ops/*-record.md` *stay* as written.'), 'A DONE_WITH_CONCERNS report and ops/*-record.md stay as written.');
  const long = describe(`${'word '.repeat(60)}end.`);
  assert.ok(long.length <= 176 && long.endsWith('…'), long);
});

// ---- built pages ----

test('every DOC_PAGES file has exactly one built page, and every docs and guides page is built', { skip }, (t) => {
  const { fileRoutes } = docsMap();
  const pages = docPages();
  for (const file of readDocPagesList(REPO)) {
    const href = fileRoutes.get(file);
    assert.ok(href, `${file} has no route`);
    const owners = pages.filter((p) => p.sources.includes(file));
    if (href.startsWith('/docs/') || href.startsWith('/guides/')) {
      assert.equal(owners.length, 1, `${file} is the whole of ${owners.length} pages`);
      assert.equal(owners[0].href, href);
      assert.ok(existsSync(built(href)), `${file}: no page at ${href}`);
    } else if (existsSync(join(DIST, href.split('/')[1]))) {
      assert.ok(existsSync(built(href)), `${file}: no page at ${href}`);
    } else {
      t.diagnostic(`${file} publishes at ${href}, a section this build does not have yet`);
    }
  }
  const expected = new Set(pages.map((p) => p.href));
  for (const section of ['docs', 'guides']) {
    for (const slug of readdirSync(join(DIST, section))) assert.ok(expected.has(`/${section}/${slug}/`), `/${section}/${slug}/ is built but not in the docs map`);
  }
  for (const href of expected) assert.ok(existsSync(built(href)), `no page at ${href}`);
});

test('titles and descriptions are the page title plus the site name, and unique', { skip }, () => {
  const titles = new Set();
  const descriptions = new Set();
  for (const p of docPages()) {
    const h = html(p.href);
    const title = decode(h.match(/<title>([^<]*)<\/title>/)[1]);
    const description = decode(h.match(/<meta name="description" content="([^"]*)"/)[1]);
    assert.equal(title, `${p.title} · Agent Triforge`);
    assert.ok(description.length > 40 && description.length <= 180, `${p.href}: description of ${description.length} characters`);
    assert.ok(!titles.has(title) && !descriptions.has(description), `${p.href}: title or description repeats`);
    titles.add(title);
    descriptions.add(description);
    assert.match(h, /data-pagefind-filter="section:(Docs|Guides)"/);
  }
});

test('/docs/getting-started/#codex opens the Codex tab', { skip }, () => {
  const body = html('/docs/getting-started/').match(/<body>([\s\S]*)<\/body>/)[1].replace(/<script[\s\S]*?<\/script>/g, '');
  for (const [hash, id] of [['#codex', 'codex'], ['#claude-code', 'claude-code'], ['#skills-only', 'skills-only']]) {
    const p = page(body, { hash });
    runClientScript('scripts/tabs.ts').initTabs(p.document, p.window);
    for (const other of ['claude-code', 'codex', 'skills-only']) {
      assert.equal(p.document.getElementById(other).hidden, other !== id, `${hash}: panel ${other}`);
    }
    assert.equal(p.document.getElementById(p.document.getElementById(id).getAttribute('aria-labelledby')).getAttribute('aria-selected'), 'true');
  }
});

test('getting started shows each lead\'s install commands once, in the tabs', { skip }, async () => {
  const h = article(html('/docs/getting-started/'));
  const panels = h.match(/<div role="tabpanel"[\s\S]*?(?=<div role="tabpanel"|<p>From nothing)/g)?.join('') ?? '';
  const rest = h.replace(panels, '');
  const { installCommands } = await import('../src/lib/readme.mjs');
  const commands = installCommands();
  for (const lines of [commands.claude, commands.codex]) {
    for (const line of lines) assert.ok(text(panels).includes(line), `the tabs show ${line}`);
    // a block with every one of a lead's install commands repeats the tab (the update block shares one line)
    const blocks = [...rest.matchAll(/<pre\b[\s\S]*?<\/pre>/g)].filter((m) => lines.every((l) => decode(m[0].replace(/<[^>]*>/g, '')).includes(l)));
    assert.equal(blocks.length, 0, `the body repeats ${lines.join(' / ')} in a code block`);
  }
  assert.match(rest, /<a href="#claude-code">Claude Code leads<\/a>/);
  assert.match(rest, /<a href="#codex">Codex leads<\/a>/);
});

test('the comment lines in docs/installation.md\'s code blocks are not headings on the built page', { skip }, () => {
  const source = readFileSync(join(REPO, 'docs', 'installation.md'), 'utf8').split('\n');
  const comments = [];
  let inFence = false;
  for (const line of source) {
    if (/^\s*```/.test(line)) inFence = !inFence;
    else if (inFence && /^\s*#/.test(line)) comments.push(line.trim().replace(/^#+\s*/, ''));
  }
  assert.ok(comments.length >= 5, 'the installation page has commented code blocks');
  const headings = [...html('/docs/getting-started/').matchAll(/<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1>/g)].map((m) => text(m[2]));
  for (const c of comments) assert.ok(!headings.includes(text(c)), `"${c}" became a heading`);
  assert.deepEqual(headings.filter((h) => /^(Prerequisites|Installation|Update)$/.test(h)), ['Prerequisites', 'Installation', 'Update']);
});

test('/docs/how-it-works/ links to /guides/data-egress/ in place of the egress section', { skip }, () => {
  const h = article(html('/docs/how-it-works/'));
  assert.match(h, /<a href="\/guides\/data-egress\/">/);
  assert.ok(!text(h).includes('Each dispatched CLI sends its task prompt'), 'the egress section is repeated');
  assert.ok(text(article(html('/guides/data-egress/'))).includes('Each dispatched CLI sends its task prompt'));
});

test('every docs image has width, height and alt text, links to its full-size file, and at most one is fetched first', { skip }, () => {
  let diagrams = 0;
  for (const p of docPages()) {
    const h = article(html(p.href));
    const imgs = [...h.matchAll(/<img\b[^>]*>/g)].map((m) => m[0]);
    for (const img of imgs) {
      assert.match(img, /\swidth="\d+"/, `${p.href}: ${img}`);
      assert.match(img, /\sheight="\d+"/, `${p.href}: ${img}`);
      assert.match(img, /\salt="/, `${p.href}: ${img}`);
      if (/class="vf-poster"/.test(img)) continue; // a loop's poster: the video carries the label
      assert.match(img, /\salt="[^"]{12,}"/, `${p.href}: a diagram needs real alt text: ${img}`);
      diagrams++;
    }
    const linked = [...h.matchAll(/<a class="img-full" href="([^"]+)"><picture><source type="image\/avif" srcset="([^"]+)" sizes="[^"]+">(<img\b[^>]*>)<\/picture><\/a>/g)];
    assert.equal(linked.length, imgs.filter((i) => !/class="vf-poster"/.test(i)).length, `${p.href}: every diagram is a linked picture with an AVIF source`);
    for (const [, href, avif, img] of linked) {
      assert.ok(avif.split(', ').every((c) => /\.avif \d+w$/.test(c)), `${p.href}: ${avif}`);
      const candidates = img.match(/srcset="([^"]+)"/)[1].split(', ').map((c) => c.split(' ')).map(([url, w]) => ({ url, w: parseInt(w, 10) }));
      const largest = candidates.reduce((a, b) => (b.w > a.w ? b : a));
      assert.equal(href, largest.url, `${p.href}: the link is the full-size file`);
      assert.equal(String(largest.w), img.match(/\swidth="(\d+)"/)[1]);
    }
    const first = imgs.filter((i) => /fetchpriority="high"/.test(i));
    assert.ok(first.length <= 1, `${p.href}: ${first.length} images fetched first`);
    if (first.length) assert.doesNotMatch(first[0], /loading="lazy"/);
  }
  assert.ok(diagrams >= 10, `diagrams found: ${diagrams}`);
  for (const href of ['/guides/unattended-runs/', '/guides/models-and-effort/']) {
    const img = article(html(href)).match(/<img\b[^>]*>/)[0];
    assert.match(img, /fetchpriority="high"/, `${href} opens with its diagram, fetched first`);
  }
});

test('inline code on the built pages keeps straight punctuation (the FAQ\'s --allow-full-access)', { skip }, () => {
  for (const p of docPages()) {
    const prose = article(html(p.href)).replace(/<pre\b[\s\S]*?<\/pre>/g, '');
    for (const [, inner] of prose.matchAll(/<code\b[^>]*>([\s\S]*?)<\/code>/g)) {
      assert.doesNotMatch(text(inner), /[–—](?=[A-Za-z])|[“”‘’]/, `${p.href}: typographer punctuation in code: ${text(inner)}`);
    }
  }
  assert.match(html('/docs/faq/'), /<code>--allow-full-access<\/code>/);
});

test('the leases guide shows its loop under one task\'s life, the unattended-runs guide under its opening', { skip }, () => {
  const leases = article(html('/guides/leases/'));
  assert.match(leases, /^\s*<h1>Leases and cross-review<\/h1>\s*<p class="intro">/);
  const fig = leases.indexOf('id="fig-loop-lease"');
  const section = leases.indexOf('id="one-task-start-to-finish"');
  assert.ok(section > 0 && fig > section && fig < leases.indexOf('<ol', section), 'the lease loop opens the section on one task\'s life');
  const un = article(html('/guides/unattended-runs/'));
  const diagram = un.indexOf('<div class="img">');
  const loop = un.indexOf('id="fig-loop-unattended"');
  assert.ok(diagram > 0 && diagram < loop && loop < un.indexOf('<h2'), 'diagram, then the loop, then the first section');
});
