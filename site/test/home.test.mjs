// Checks on the built home page (site/dist/index.html): no pause control anywhere in the motion, the
// film's outline readable as chapter buttons, and the hero's Install link following the lead switch,
// driven through the real built markup with the real tab script.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

import { SITE } from '../src/lib/repo.mjs';
import { runClientScript } from './client-script.mjs';
import { page } from './dom.mjs';
import * as leads from '../src/data/leads.mjs';

const file = join(SITE, 'dist', 'index.html');
const skip = !existsSync(file) && 'site/dist is not built (run npm run build in site/)';
const html = () => readFileSync(file, 'utf8');

test('the home page has no pause or play toggle on the loops, the film or the dot field', { skip }, () => {
  const h = html();
  assert.doesNotMatch(h, /class="(field-pause|film-toggle|vplay)\b/, 'a pause toggle from the prototype is back');
  assert.doesNotMatch(h, /aria-label="Pause\b/i);
  // the only buttons in a figure are the Play fallbacks (shown only when nothing else starts a video)
  // and the film's chapters
  const figures = [...h.matchAll(/<figure[^>]*data-vfig[^>]*>([\s\S]*?)<\/figure>/g)].map((m) => m[1]);
  assert.ok(figures.length >= 6, `video figures: ${figures.length}`);
  for (const f of figures) {
    const buttons = [...f.matchAll(/<button\b[^>]*>/g)].map((m) => m[0]);
    for (const b of buttons) assert.ok(/class="vf-big"/.test(b) || /data-t="/.test(b), `unexpected control in a figure: ${b}`);
  }
});

test('the film lists its chapters as labelled buttons', { skip }, () => {
  const h = html();
  const film = h.match(/<figure class="fig film"[\s\S]*?<\/figure>/)?.[0] ?? '';
  const chapters = [...film.matchAll(/<button type="button" data-t="([\d.]+)">([^<]+)<span>/g)].map((m) => m[2]);
  const json = JSON.parse(readFileSync(join(SITE, 'public', 'media', 'film-chapters.json'), 'utf8')).map((c) => c.label);
  assert.deepEqual(chapters, json);
});

test('switching the hero to Codex makes the hero Install link end in #codex', { skip }, () => {
  const body = html().match(/<body>([\s\S]*)<\/body>/)[1].replace(/<script[\s\S]*?<\/script>/g, '');
  const p = page(body);
  const { initTabs } = runClientScript('scripts/tabs.ts', { imports: { '@/data/leads.mjs': leads } });
  initTabs(p.document, p.window);
  const install = () => p.document.querySelector('.hero [data-lead-href]').getAttribute('href');
  assert.equal(install(), '/docs/getting-started/');
  p.click(p.document.getElementById('hero-lead-tab-codex'));
  assert.equal(install(), '/docs/getting-started/#codex');
  assert.equal(p.document.getElementById('install-for-tab-codex').getAttribute('aria-selected'), 'true', 'the install section follows');
});
