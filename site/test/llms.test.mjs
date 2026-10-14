// /llms.txt (https://llmstxt.org), built from the data layer (site/src/lib/llms.mjs): the site's name and
// summary, then a link to the home page, every docs and guide page, every skill page with its summary,
// the personas page, the roster, the sprint page and the changelog, all on the production origin. The
// dev-only media kit never appears.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { NAV } from '../src/data/nav.ts';
import { sectionPages } from '../src/lib/docs.mjs';
import { llmsTxt } from '../src/lib/llms.mjs';
import { personasPage } from '../src/lib/personas.mjs';
import { SITE } from '../src/lib/repo.mjs';
import { SITE_URL, VERSION } from '../src/lib/site.mjs';
import { getSkills } from '../src/lib/skills.mjs';

const text = llmsTxt(NAV);
const lines = text.split('\n');
/** every "- [label](url)" line, by URL */
const links = new Map(lines.map((l) => l.match(/^- \[([^\]]+)\]\(([^)]+)\)(?:: (.+))?$/)).filter(Boolean).map((m) => [m[2], { label: m[1], note: m[3] }]));
const at = (path) => `${SITE_URL}${path}`;

test('it opens with the name, a one-line summary and the version', () => {
  assert.equal(lines[0], '# Agent Triforge');
  assert.equal(lines[1], '');
  assert.match(lines[2], /^> \S.{40,}$/, 'the summary line');
  assert.ok(text.includes(`Version ${VERSION}`), `no "Version ${VERSION}"`);
  assert.ok(text.endsWith('\n') && !text.endsWith('\n\n'), 'one newline at the end');
});

test('every skill page is listed once, with its summary', () => {
  for (const skill of getSkills()) {
    const link = links.get(at(`/skills/${skill.name}/`));
    assert.ok(link, `no link to /skills/${skill.name}/`);
    assert.equal(link.note, skill.summary, `${skill.name}: summary`);
  }
  const listed = lines.filter((l) => l.includes(`](${at('/skills/')}`) && !l.includes(`](${at('/skills/')})`) && !l.includes(personasPage().href));
  assert.equal(listed.length, getSkills().length, 'skill links');
});

test('every docs and guide page is listed', () => {
  for (const section of ['docs', 'guides']) {
    const pages = sectionPages(section);
    assert.ok(pages.length > 0, `no ${section} pages`);
    for (const page of pages) assert.equal(links.get(at(page.href))?.label, page.title, `${section}: ${page.href}`);
  }
});

test('the home page, the skills, the personas, the roster, the sprint page and the changelog are listed', () => {
  for (const path of ['/', '/skills/', personasPage().href, '/roster/', '/sprint/', '/changelog/']) assert.ok(links.has(at(path)), `no link to ${path}`);
});

test('every link is on the production origin and listed once; the media kit is not', () => {
  const urls = lines.filter((l) => l.startsWith('- [')).map((l) => l.match(/\]\(([^)]+)\)/)[1]);
  assert.equal(new Set(urls).size, urls.length, 'a URL is listed twice');
  for (const url of urls) assert.equal(new URL(url).origin, SITE_URL, url);
  assert.doesNotMatch(text, /\/kit\b|readme-hero\.gif/);
});

const built = join(SITE, 'dist', 'llms.txt');
test('the build serves the same text at /llms.txt', { skip: !existsSync(built) && 'site/dist is not built (run npm run build in site/)' }, () => {
  assert.equal(readFileSync(built, 'utf8'), text);
});
