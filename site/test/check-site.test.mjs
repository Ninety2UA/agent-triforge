// The site gate (site/scripts/check-site.mjs) on seeded faults: each case builds a tiny site folder (or
// a source file) with one broken promise and expects the gate to name it. The real build passing the
// gate is checked by `npm run build` itself, which runs the gate.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import { checkClaims, checkLinks, checkMeta, checkRedirects, checkMotion, checkOrigins, checkPages, checkSkillTokens, checkLiteralCounts, firstNumber, readPages } from '../scripts/check-site.mjs';

const page = (body, { title = 'A page', canonical = 'https://agent-triforge.dbenger.com/x/' } = {}) =>
  `<!doctype html><html><head><title>${title}</title><meta name="description" content="d">${canonical ? `<link rel="canonical" href="${canonical}">` : ''}</head><body>${body}</body></html>`;

function site(files) {
  const dir = mkdtempSync(join(tmpdir(), 'check-site-'));
  for (const [path, text] of Object.entries(files)) {
    mkdirSync(dirname(join(dir, path)), { recursive: true });
    writeFileSync(join(dir, path), text);
  }
  return { dir, pages: () => readPages(dir), done: () => rmSync(dir, { recursive: true, force: true }) };
}

test('a page linking /skills/at-nope/ fails, naming the page', () => {
  const s = site({
    'index.html': page('<a href="/skills/at-ship/">ship</a><a href="/skills/at-nope/">nope</a>'),
    'skills/at-ship/index.html': page('<h1 id="top">at-ship</h1>'),
  });
  try {
    const problems = checkLinks(s.dir, s.pages());
    assert.equal(problems.length, 1, problems.join('\n'));
    assert.match(problems[0], /^index\.html: href="\/skills\/at-nope\/"/);
  } finally {
    s.done();
  }
});

test('a fragment that names no id on its target page fails', () => {
  const s = site({
    'index.html': page('<a href="/docs/faq/#nope">faq</a><a href="/docs/faq/#top">ok</a>'),
    'docs/faq/index.html': page('<h1 id="top">FAQ</h1>'),
  });
  try {
    assert.deepEqual(checkLinks(s.dir, s.pages()), ['index.html: href="/docs/faq/#nope" names no id on docs/faq/index.html']);
  } finally {
    s.done();
  }
});

test('a data-claim that reads one fewer than the repo fails; words and numerals both count', () => {
  const s = site({ 'index.html': page('<p><span data-claim="skills">26</span> skills, <span data-claim="leadSkills">Seventeen</span> workflows</p>') });
  try {
    const problems = checkClaims(s.pages(), { skills: 27, leadSkills: 17 });
    assert.deepEqual(problems, ['index.html: data-claim="skills" says "26", the repo has 27']);
  } finally {
    s.done();
  }
  assert.equal(firstNumber('twenty-seven skills'), 27);
  assert.equal(firstNumber('Ten'), 10);
});

test('a script or stylesheet from another origin fails', () => {
  const s = site({
    'index.html': page('<script src="https://cdn.example.com/x.js"></script><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=X"><script src="/_astro/ok.js"></script>'),
  });
  try {
    const problems = checkOrigins(s.pages());
    assert.equal(problems.length, 2, problems.join('\n'));
    assert.match(problems[0], /<script> from https:\/\/cdn\.example\.com/);
    assert.match(problems[1], /fonts\.googleapis\.com/);
  } finally {
    s.done();
  }
});

test('a page without a canonical link fails, and the 404 must not have one', () => {
  const s = site({ 'index.html': page('', { canonical: '' }), '404.html': page('', { canonical: 'https://agent-triforge.dbenger.com/404/' }) });
  try {
    assert.deepEqual(checkMeta(s.pages()).sort(), ['404.html: has a canonical link', 'index.html: no canonical link']);
  } finally {
    s.done();
  }
});

test('a redirect to a page that is not in the build fails', () => {
  const s = site({ 'docs/getting-started/index.html': page('') });
  try {
    const redirects = [{ source: '/docs{/}?', destination: '/docs/getting-started/' }, { source: '/guides{/}?', destination: '/guides/leases/' }];
    assert.deepEqual(checkRedirects(s.dir, redirects), ['vercel.json: the redirect from /guides{/}? goes to /guides/leases/, which has no page']);
  } finally {
    s.done();
  }
});

test('a missing skill page and a page for a skill that is gone both fail', () => {
  const s = site({ 'index.html': page(''), 'skills/at-old/index.html': page(''), 'docs/faq/index.html': page('') });
  try {
    const problems = checkPages(s.dir, { skills: ['at-ship'], docRoutes: [{ source: 'README.md#faq', href: '/docs/faq/' }] });
    assert.deepEqual(problems, ['skills/at-ship: no page at /skills/at-ship/', 'skills/at-old/index.html: a page for a skill that is not in skills/']);
  } finally {
    s.done();
  }
});

test('hand-written text naming /at-nonexistent fails, naming the file and line', () => {
  const s = site({ 'tutorial.md': 'Run `/at-ship` first.\nThen run /at-nonexistent and $agent-triforge:at-nope.\n' });
  try {
    const problems = checkSkillTokens(['at-ship'], [join(s.dir, 'tutorial.md')]);
    assert.equal(problems.length, 2, problems.join('\n'));
    assert.match(problems[0], /tutorial\.md:2: "\/at-nonexistent" names no skill/);
    assert.match(problems[1], /tutorial\.md:2: "\$agent-triforge:at-nope" names no skill/);
  } finally {
    s.done();
  }
});

test('a literal count beside a counted noun in site sources fails; a rendered claim does not', () => {
  const s = site({ 'Section.astro': '<h2>Browse the 27 skills</h2>\n<p>All <Claim kind="skills" /> skills, nineteen personas.</p>\n' });
  try {
    const problems = checkLiteralCounts([join(s.dir, 'Section.astro')]);
    assert.equal(problems.length, 2, problems.join('\n'));
    assert.match(problems[0], /Section\.astro:1: "27 skills"/);
    assert.match(problems[1], /Section\.astro:2: "nineteen personas"/);
  } finally {
    s.done();
  }
});

test('a motion composition whose count or CLI name differs from the repo fails, naming the composition', () => {
  const s = site({ 'loop.html': '<div class="cap">Seven coding agents work together.</div><p>Gemini CLI analyzes.</p><p>Codex reviews.</p>' });
  try {
    const problems = checkMotion({ clis: 8 }, ['Claude Code', 'Codex', 'Antigravity'], s.dir);
    assert.equal(problems.length, 2, problems.join('\n'));
    assert.match(problems[0], /loop\.html: "Seven coding agents" but the repo has 8/);
    assert.match(problems[1], /loop\.html: names "Gemini CLI"/);
  } finally {
    s.done();
  }
});
