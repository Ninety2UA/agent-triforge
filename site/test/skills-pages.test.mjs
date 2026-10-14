// The skills catalog, the skill pages and the personas page (U5). The filter and the "/" shortcut run
// as plain modules against a linkedom page; the checks on the built pages skip, and say so, when
// site/dist is missing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

import { SITE } from '../src/lib/repo.mjs';
import { getSkills } from '../src/lib/skills.mjs';
import { getPersonas, personaGroups } from '../src/lib/personas.mjs';
import { invocation, parseInvocations, portableInvocations } from '../src/lib/portable.mjs';
import { ALL, initCatalog, matches, readState } from '../src/components/skill-filter.mjs';
import { inlineHtml, promptHtml, skillBodyHtml } from '../src/components/skill-html.mjs';
import { shortcutAction } from '../src/components/search/shortcut.mjs';
import { page } from './dom.mjs';

const dist = join(SITE, 'dist');
const skip = !existsSync(join(dist, 'index.html')) && 'site/dist is not built (run npm run build in site/)';
const built = (path) => readFileSync(join(dist, path), 'utf8');
// The bare Codex form, built from parts so no tracked file under site/ carries it (validate-versions
// sweeps site/ for it): Codex attaches a plugin skill only as $agent-triforge:at-<name>.
const DOLLAR = String.fromCharCode(36);
const bare = (name) => DOLLAR + name;

// ---- the portable invocation forms (src/lib/portable.mjs) ----

const SAMPLE = 'Each harness invokes a skill in its own form: Claude `/name` · agy `agy --add-dir "$PWD" -p "/name"` (headless expansion; `agy -p "/skills"` lists them without a model call) · Codex `$name` · Kimi `/skill:name` (live verification pending `kimi login`).';

test('portable: the invocation sentence parses into one form per harness, notes kept without their brackets', () => {
  assert.deepEqual(parseInvocations(`# Skills\n\n${SAMPLE}\n`, 'docs/skills.md'), [
    { harness: 'Claude', form: '/name', note: '' },
    { harness: 'agy', form: 'agy --add-dir "$PWD" -p "/name"', note: 'headless expansion; `agy -p "/skills"` lists them without a model call' },
    { harness: 'Codex', form: `${DOLLAR}name`, note: '' },
    { harness: 'Kimi', form: '/skill:name', note: 'live verification pending `kimi login`' },
  ]);
  assert.throws(() => parseInvocations('# Skills\n\nNo sentence here.\n', 'docs/skills.md'), /docs\/skills\.md.*Each harness invokes/);
});

test('portable: a form names the skill in place of its placeholder, and only there', () => {
  assert.equal(invocation('/name', 'wave-orchestration'), '/wave-orchestration');
  assert.equal(invocation('agy --add-dir "$PWD" -p "/name"', 'scope-cutting'), 'agy --add-dir "$PWD" -p "/scope-cutting"');
  assert.equal(invocation('/skill:name', 'review-synthesis'), '/skill:review-synthesis');
});

test('portable: every harness in docs/skills.md maps to a roster CLI, the two leads marked', () => {
  const forms = portableInvocations();
  assert.ok(forms.length >= 2, `forms: ${forms.length}`);
  const byName = new Map(forms.map((f) => [f.name, f]));
  assert.equal(byName.get('Claude Code')?.lead, 'claude-code');
  assert.equal(byName.get('Codex')?.lead, 'codex');
  assert.equal(invocation(byName.get('Codex').form, 'wave-orchestration'), `${DOLLAR}wave-orchestration`);
  for (const f of forms) assert.match(f.form, /\bname\b/, `${f.name}: a form with no placeholder`);
  assert.equal(new Set(forms.map((f) => f.id)).size, forms.length, 'tab ids are unique');
});

// ---- the HTML helpers (src/components/skill-html.mjs) ----

test('inline Markdown: code spans and links render, everything else is escaped text', () => {
  assert.equal(inlineHtml('Writes `ops/TASKS.md` <b>now</b> & [docs](/docs/x/)'),
    'Writes <code><span class="nw">ops/TASKS.md</span></code> &lt;b&gt;now&lt;/b&gt; &amp; <a href="/docs/x/">docs</a>');
  // a path too long for a phone-width card may break after a slash; a short one never does, so a
  // screen reader reads it as one word
  assert.equal(inlineHtml('`ops/RESEARCH_ANTIGRAVITY_NOTES.md`'), '<code><span class="nw">ops/</span><wbr><span class="nw">RESEARCH_ANTIGRAVITY_NOTES.md</span></code>');
  assert.equal(inlineHtml('[`personas/`](https://github.com/x/y)'), '<a href="https://github.com/x/y"><code><span class="nw">personas/</span></code></a>');
  // code wraps at a space, never inside a flag
  assert.equal(inlineHtml('`--team <x>`'), '<code><span class="nw">--team</span> <span class="nw">&lt;x&gt;</span></code>');
  assert.equal(inlineHtml('[bad](javascript:alert(1))'), '[bad](javascript:alert(1))', 'only http(s), root and fragment links become links');
});

test('a SKILL.md body: its title becomes an h2 under the page h1, the other headings keep their level and id', () => {
  const html = '<h1 id="ship">Ship</h1><p>x</p><h2 id="output">Output</h2><h3 id="a">A</h3>';
  assert.equal(skillBodyHtml(html), '<h2 id="ship">Ship</h2><p>x</p><h2 id="output">Output</h2><h3 id="a">A</h3>');
});

test('a persona prompt: headings sit under the persona h3 and lose their ids, so two prompts never share one', () => {
  const html = '<h2 id="output">Output</h2><h3 id="rules">Rules</h3><h4 id="x">X</h4>';
  assert.equal(promptHtml(html), '<h4>Output</h4><h5>Rules</h5><h6>X</h6>');
});

// ---- the catalog filter (src/components/skill-filter.mjs) ----

const CARDS = [
  { name: 'at-review', group: 'review', label: 'Review', text: 'at-review review phases 3 and 4' },
  { name: 'at-build', group: 'build', label: 'Build', text: 'at-build build waves, cross-review, merge' },
  { name: 'at-setup', group: 'setup', label: 'Setup', text: 'at-setup setup guided project setup' },
  { name: 'review-synthesis', group: 'portable', label: 'Portable', text: 'review-synthesis portable merge findings' },
  { name: 'scope-cutting', group: 'portable', label: 'Portable', text: 'scope-cutting portable cut scope' },
];
// The markup the catalog renders (index.astro, SkillCard.astro, SkillFilter.tsx), reduced to what the
// filter reads.
function catalog({ search = true, readUrl = true } = {}) {
  return `<div data-catalog${readUrl ? ' data-read-url' : ''}>
    ${search ? '<input type="search" id="skill-q" data-filter-q>' : ''}
    <div role="group">${[ALL, 'review', 'build', 'setup', 'portable'].map((g) => `<button type="button" tabindex="-1" data-group-chip="${g}" aria-pressed="${g === ALL}">${g}</button>`).join('')}</div>
    <p class="count"><span data-count>${CARDS.length}</span> of ${CARDS.length}</p>
    <ul class="cards">${CARDS.map((c) => `<li class="card" data-skill-card data-group="${c.group}" data-group-label="${c.label}" data-text="${c.text}"><a href="/skills/${c.name}/">${c.name}</a></li>`).join('')}</ul>
    <div data-empty hidden><p data-empty-text></p><button type="button" data-filter-clear>Show every skill</button></div>
  </div><input type="text" id="elsewhere">`;
}
const shown = (doc) => [...doc.querySelectorAll('[data-skill-card]')].filter((c) => !c.hasAttribute('hidden')).map((c) => c.querySelector('a').textContent);
const count = (doc) => doc.querySelector('[data-count]').textContent;
const pressed = (doc) => [...doc.querySelectorAll('[data-group-chip]')].filter((c) => c.getAttribute('aria-pressed') === 'true').map((c) => c.dataset.groupChip);

test('filter: a card matches when it is in the group and its text holds every word typed', () => {
  const card = { group: 'review', text: 'at-review review phases 3 and 4' };
  assert.equal(matches(card, { q: '', group: ALL }), true);
  assert.equal(matches(card, { q: ' Review  PHASES ', group: ALL }), true);
  assert.equal(matches(card, { q: 'review merge', group: ALL }), false);
  assert.equal(matches(card, { q: 'review', group: 'build' }), false);
  // a word matches from the start of a word: "cut" finds scope-cutting, not "execution"
  assert.equal(matches({ group: 'portable', text: 'wave-orchestration parallel execution' }, { q: 'cut', group: ALL }), false);
  assert.equal(matches({ group: 'portable', text: 'scope-cutting cut scope' }, { q: 'cut', group: ALL }), true);
  // the command as typed in a session finds the skill
  assert.equal(matches(card, { q: '/at-review', group: ALL }), true);
});

test('filter: typing "review" shows only the matching cards and updates "N of total"', () => {
  const p = page(catalog());
  const c = initCatalog(p.document, p.window);
  c.setQuery('review');
  assert.deepEqual(shown(p.document), ['at-review', 'at-build', 'review-synthesis']);
  assert.equal(count(p.document), '3');
  assert.equal(p.document.querySelector('[data-empty]').hasAttribute('hidden'), true);
});

test('filter: Esc clears the search and shows every card; with nothing typed it is left to the page', () => {
  const p = page(catalog());
  const c = initCatalog(p.document, p.window);
  const input = p.document.getElementById('skill-q');
  input.value = 'review';
  c.setQuery('review');
  assert.equal(c.key('Escape'), true, 'Esc with a search is handled');
  assert.equal(input.value, '');
  assert.equal(shown(p.document).length, CARDS.length);
  assert.equal(count(p.document), String(CARDS.length));
  assert.equal(c.key('Escape'), false, 'Esc on an empty search is not taken');
});

test('filter: a chip with no matches after a search shows the empty state; its button restores every card', () => {
  const p = page(catalog());
  const c = initCatalog(p.document, p.window);
  let focused = false;
  p.document.getElementById('skill-q').focus = () => (focused = true);
  c.setQuery('review');
  c.setGroup('setup');
  assert.deepEqual(shown(p.document), []);
  assert.equal(count(p.document), '0');
  const empty = p.document.querySelector('[data-empty]');
  assert.equal(empty.hasAttribute('hidden'), false);
  assert.equal(empty.querySelector('[data-empty-text]').textContent, 'No skill in Setup matches “review”.');
  assert.deepEqual(pressed(p.document), ['setup'], 'the chips show the group, before and after hydration');
  p.click(empty.querySelector('[data-filter-clear]'));
  assert.equal(shown(p.document).length, CARDS.length);
  assert.equal(empty.hasAttribute('hidden'), true);
  assert.deepEqual(pressed(p.document), [ALL]);
  assert.deepEqual(c.getState(), { q: '', group: ALL });
  assert.equal(focused, true, 'focus moves to the search box, not to the hidden button');
});

test('filter: subscribers hear every change, so the chips island follows a clear made outside it', () => {
  const p = page(catalog());
  const c = initCatalog(p.document, p.window);
  const seen = [];
  const stop = c.subscribe(() => seen.push(c.getState().group));
  c.setGroup('build');
  c.clear();
  stop();
  c.setGroup('review');
  assert.deepEqual(seen, ['build', ALL]);
});

test('filter: ?q= and ?group= apply on load (the search fallback links to /skills/?q=); an unknown group is ignored', () => {
  assert.deepEqual(readState('?q=cut&group=portable', ['portable']), { q: 'cut', group: 'portable' });
  assert.deepEqual(readState('?group=nope', ['portable']), { q: '', group: ALL });
  const p = page(catalog());
  p.window.location.search = '?q=merge&group=portable';
  initCatalog(p.document, p.window);
  assert.deepEqual(shown(p.document), ['review-synthesis']);
  assert.equal(p.document.getElementById('skill-q').value, 'merge');
  assert.deepEqual(pressed(p.document), ['portable']);
  // the home page's featured cards do not read the address
  const home = page(catalog({ search: false, readUrl: false }));
  home.window.location.search = '?group=portable';
  initCatalog(home.document, home.window);
  assert.equal(shown(home.document).length, CARDS.length);
});

test('filter: before the chips island hydrates, the first chip is in the Tab order (Base UI renders every chip at tabindex -1)', () => {
  const p = page(catalog({ search: false, readUrl: false }));
  initCatalog(p.document, p.window);
  assert.deepEqual([...p.document.querySelectorAll('[data-group-chip]')].map((c) => c.getAttribute('tabindex')), ['0', '-1', '-1', '-1', '-1']);
  // once hydrated, Base UI keeps one chip at 0; a later start leaves its choice alone
  const q = page(catalog({ search: false, readUrl: false }).replace('tabindex="-1" data-group-chip="build"', 'tabindex="0" data-group-chip="build"'));
  initCatalog(q.document, q.window);
  assert.deepEqual([...q.document.querySelectorAll('[tabindex="0"]')].map((c) => c.dataset.groupChip), ['build']);
});

test('filter: one controller per page, whichever of the page script and the island starts first', () => {
  const p = page(catalog());
  assert.equal(initCatalog(p.document, p.window), initCatalog(p.document, p.window));
  assert.equal(initCatalog(page('<p>no catalog</p>').document, p.window), null);
});

// ---- "/" on /skills/ ----

function slash(target, init = {}) {
  const e = new target.ownerDocument.defaultView.Event('keydown', { bubbles: true, cancelable: true });
  Object.assign(e, { key: '/', metaKey: false, ctrlKey: false, altKey: false, ...init });
  target.dispatchEvent(e);
  return e;
}

test('"/" on the catalog focuses its search box and does not open the palette; inside a text field it types', () => {
  const p = page(catalog());
  initCatalog(p.document, p.window);
  let focused = 0;
  p.document.getElementById('skill-q').focus = () => (focused += 1);
  const onPage = slash(p.document.querySelector('.count'));
  assert.equal(onPage.defaultPrevented, true);
  assert.equal(focused, 1, 'the search box took focus');
  assert.equal(shortcutAction(onPage, { typing: false }), null, 'the palette loader leaves a taken "/" alone');

  const inField = slash(p.document.getElementById('elsewhere'));
  assert.equal(inField.defaultPrevented, false);
  assert.equal(focused, 1);
  const withModifier = slash(p.document.querySelector('.count'), { metaKey: true });
  assert.equal(withModifier.defaultPrevented, false);
  // the home page's filter has no search box, so "/" still opens the palette there
  const home = page(catalog({ search: false, readUrl: false }));
  initCatalog(home.document, home.window);
  assert.equal(slash(home.document.querySelector('.count')).defaultPrevented, false);
});

// ---- the built pages ----

// the labels of the Skills and Personas links that carry aria-current="page"
const switchCurrent = (html) =>
  [...(html.match(/<nav class="cat-switch"[\s\S]*?<\/nav>/)?.[0] ?? '').matchAll(/<a[^>]*aria-current="page"[^>]*>([^<]+)/g)].map((m) => m[1]);

test('each skill folder has exactly one built page, and no SKILL.md is copied into the build', { skip }, () => {
  const names = getSkills().map((s) => s.name).sort();
  const pages = readdirSync(join(dist, 'skills')).filter((d) => d !== 'personas' && statSync(join(dist, 'skills', d)).isDirectory()).sort();
  assert.deepEqual(pages, names);
  for (const name of names) assert.ok(existsSync(join(dist, 'skills', name, 'index.html')), `no page for ${name}`);
  const copies = [];
  const walk = (dir) => {
    for (const f of readdirSync(dir)) {
      const path = join(dir, f);
      if (statSync(path).isDirectory()) walk(path);
      else if (f === 'SKILL.md') copies.push(relative(dist, path));
    }
  };
  walk(dist);
  assert.deepEqual(copies, []);
});

test('the catalog carries every skill as a static card, in catalog order, with its group', { skip }, () => {
  const html = built('skills/index.html');
  const cards = [...html.matchAll(/<li[^>]*data-skill-card[^>]*data-group="([^"]+)"[^>]*>[\s\S]*?href="\/skills\/([^/]+)\/"/g)].map((m) => [m[2], m[1]]);
  assert.deepEqual(cards, getSkills().map((s) => [s.name, s.group.key]));
  assert.match(html, /<a[^>]*href="\/skills\/personas\/"/, 'the Personas link');
  assert.deepEqual(switchCurrent(html), ['Skills'], 'Skills is the current link of the two');
  assert.match(html, /data-pagefind-filter="section:Skills"/);
});

test('a Codex invocation renders as $agent-triforge:at-<name>, never in the bare form', { skip }, () => {
  const html = built('skills/at-ship/index.html');
  assert.ok(html.includes(`${DOLLAR}agent-triforge:at-ship`), 'the Codex tab names the skill with its plugin');
  assert.ok(html.includes('/at-ship'), 'the Claude Code tab');
  for (const skill of getSkills()) {
    const page = built(`skills/${skill.name}/index.html`);
    assert.ok(!page.includes(bare('at-')), `skills/${skill.name}: a bare Codex form`);
  }
  assert.ok(!built('skills/index.html').includes(bare('at-')), 'the catalog: a bare Codex form');
});

test('a portable skill page runs it in each harness, the leads first-class', { skip }, () => {
  const html = built('skills/wave-orchestration/index.html');
  for (const f of portableInvocations()) {
    const cmd = invocation(f.form, 'wave-orchestration').replace(/"/g, '&quot;').replace(/&quot;/g, '"');
    assert.ok(html.includes(`>${f.name}</button>`), `${f.name}: no tab`);
    assert.ok(html.includes(`data-copy="${invocation(f.form, 'wave-orchestration').replace(/&/g, '&amp;').replace(/"/g, '&quot;')}"`), `${f.name}: no copyable ${cmd}`);
  }
  assert.match(html, /data-lead="codex"/);
});

test('a skill page has a breadcrumb back to the catalog and its group, kept out of search', { skip }, () => {
  const html = built('skills/at-ship/index.html');
  const crumbs = html.match(/<nav[^>]*aria-label="Breadcrumb"[^>]*>[\s\S]*?<\/nav>/)?.[0] ?? '';
  assert.match(crumbs, /data-pagefind-ignore/);
  assert.match(crumbs, /href="\/skills\/"/);
  assert.match(crumbs, /href="\/skills\/\?group=full-sprint"/);
  assert.match(html, /data-pagefind-filter="section:Skills"/);
});

test('a skill body shows raw placeholders such as <file or diff> as text', { skip }, () => {
  const html = built('skills/at-wrap/index.html');
  assert.ok(html.includes('&lt;file or diff&gt;'), 'at-wrap: <file or diff> is visible text');
  assert.ok(!/<file or diff>/.test(html), 'at-wrap: <file or diff> must not reach the page as markup');
});

test('the personas page: one anchor per persona and per group, and the legacy count anchor lands on its group', { skip }, () => {
  const html = built('skills/personas/index.html');
  for (const p of getPersonas()) assert.match(html, new RegExp(`\\sid="${p.name}"`), `#${p.name}`);
  assert.match(html, /\sid="security-sentinel"/);
  for (const g of personaGroups()) {
    const legacy = html.match(new RegExp(`<section[^>]*\\sid="${g.anchor}-${g.count}"[^>]*>([\\s\\S]*?)</section>`));
    assert.ok(legacy, `#${g.anchor}-${g.count}: no element`);
    assert.match(legacy[1], new RegExp(`<h2[^>]*\\sid="${g.anchor}"`), `#${g.anchor}-${g.count} does not hold the group heading`);
  }
  assert.match(html, /\sid="review-specialists-6"/);
  assert.match(html, /data-pagefind-filter="section:Personas"/);
  assert.deepEqual(switchCurrent(html), ['Personas'], 'Personas is the current link of the two');
});
