// Tests for the site's small browser scripts, each run in plain Node against fakes (client-script.mjs)
// or a linkedom page (dom.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { fakeTarget, runClientScript, settle } from './client-script.mjs';
import { page } from './dom.mjs';
import * as leads from '../src/data/leads.mjs';

// ---- tabs (site/src/scripts/tabs.ts) ----

const { initTabs, LEAD_KEY } = runClientScript('scripts/tabs.ts', { imports: { '@/data/leads.mjs': leads } });

// The markup Tabs.astro renders: one tab list, one panel per item, the first selected.
// hashTarget groups use the bare item id as the panel id, so #codex opens the Codex tab.
function tabs(id, items, { hashTarget = false } = {}) {
  const panelId = (item) => (hashTarget ? item.id : `${id}-${item.id}`);
  return `<div data-tabs id="${id}">
    <div role="tablist" aria-label="${id}">${items
      .map((item, i) => `<button type="button" role="tab" id="${id}-tab-${item.id}" aria-controls="${panelId(item)}" aria-selected="${i === 0}" tabindex="${i === 0 ? 0 : -1}"${i === 0 ? ' data-active=""' : ''}${item.lead ? ` data-lead="${item.lead}"` : ''}>${item.id}</button>`)
      .join('')}</div>
    ${items.map((item, i) => `<div role="tabpanel" id="${panelId(item)}" aria-labelledby="${id}-tab-${item.id}"${i === 0 ? '' : ' hidden'}>${item.body ?? item.id}</div>`).join('')}
  </div>`;
}
const LEADS = [
  { id: 'claude-code', lead: 'claude-code' },
  { id: 'codex', lead: 'codex' },
  { id: 'skills-only', body: '<h2 id="portable-skills-in-devin-and-pi">Devin and Pi</h2>' },
];
const install = `<a data-lead-href="/docs/getting-started/" href="/docs/getting-started/">Install</a>`;
const selected = (doc, groupId) => [...doc.querySelectorAll(`#${groupId} [role="tab"]`)].filter((t) => t.getAttribute('aria-selected') === 'true').map((t) => t.textContent);
const shown = (doc, groupId) => [...doc.querySelectorAll(`#${groupId} [role="tabpanel"]`)].filter((p) => !p.hasAttribute('hidden')).map((p) => p.id);

test('tabs: a page loaded with #codex selects the Codex panel', () => {
  const p = page(tabs('gs', LEADS, { hashTarget: true }), { hash: '#codex' });
  initTabs(p.document, p.window);
  assert.deepEqual(selected(p.document, 'gs'), ['codex']);
  assert.deepEqual(shown(p.document, 'gs'), ['codex']);
});

test('tabs: a hashchange to #skills-only selects that panel', () => {
  const p = page(tabs('gs', LEADS, { hashTarget: true }));
  initTabs(p.document, p.window);
  p.navigate('#skills-only');
  assert.deepEqual(selected(p.document, 'gs'), ['skills-only']);
  assert.deepEqual(shown(p.document, 'gs'), ['skills-only']);
});

test('tabs: a link to a heading inside a hidden panel opens that panel', () => {
  const p = page(tabs('gs', LEADS, { hashTarget: true }), { hash: '#portable-skills-in-devin-and-pi' });
  initTabs(p.document, p.window);
  assert.deepEqual(shown(p.document, 'gs'), ['skills-only']);
});

test('tabs: a stored lead of "codex" selects Codex in every lead tab group on a page with no hash', () => {
  const p = page(tabs('hero', LEADS.slice(0, 2)) + tabs('inst', LEADS) + install, { stored: { [LEAD_KEY]: 'codex' } });
  initTabs(p.document, p.window);
  assert.deepEqual(selected(p.document, 'hero'), ['codex']);
  assert.deepEqual(selected(p.document, 'inst'), ['codex']);
  assert.equal(p.document.querySelector('[data-lead-href]').getAttribute('href'), '/docs/getting-started/#codex');
});

test('tabs: choosing a lead stores it and applies it to every lead group and Install link', () => {
  const p = page(tabs('hero', LEADS.slice(0, 2)) + tabs('inst', LEADS) + install);
  initTabs(p.document, p.window);
  p.click(p.document.getElementById('hero-tab-codex'));
  assert.equal(p.stored[LEAD_KEY], 'codex');
  assert.deepEqual(selected(p.document, 'inst'), ['codex']);
  assert.equal(p.document.querySelector('[data-lead-href]').getAttribute('href'), '/docs/getting-started/#codex');
  // "Skills only" is not a lead: choosing it changes nothing else
  p.click(p.document.getElementById('inst-tab-skills-only'));
  assert.equal(p.stored[LEAD_KEY], 'codex');
  assert.deepEqual(selected(p.document, 'hero'), ['codex']);
});

test('tabs: when storage throws, the first tab stays selected and nothing errors', () => {
  const p = page(tabs('hero', LEADS.slice(0, 2)) + install, { storageThrows: true });
  assert.doesNotThrow(() => initTabs(p.document, p.window));
  assert.deepEqual(selected(p.document, 'hero'), ['claude-code']);
  assert.doesNotThrow(() => p.click(p.document.getElementById('hero-tab-codex')));
  assert.deepEqual(selected(p.document, 'hero'), ['codex']);
});

test('tabs: Right selects the next tab and focuses it, End the last; only the selected tab is in the Tab order', () => {
  const p = page(tabs('gs', LEADS, { hashTarget: true }));
  initTabs(p.document, p.window);
  const [first, second, last] = p.document.querySelectorAll('#gs [role="tab"]');
  const focused = [];
  [first, second, last].forEach((t) => (t.focus = () => focused.push(t.textContent)));
  assert.equal(p.key(first, 'ArrowRight').defaultPrevented, true);
  assert.deepEqual(selected(p.document, 'gs'), ['codex']);
  assert.deepEqual(focused, ['codex']);
  p.key(second, 'End');
  assert.deepEqual(selected(p.document, 'gs'), ['skills-only']);
  assert.deepEqual([first, second, last].map((t) => t.getAttribute('tabindex')), ['-1', '-1', '0']);
  p.key(last, 'Home');
  assert.deepEqual(selected(p.document, 'gs'), ['claude-code']);
  p.key(first, 'ArrowLeft');
  assert.deepEqual(selected(p.document, 'gs'), ['skills-only'], 'Left wraps from the first tab to the last');
});

test('tabs: a malformed hash names no panel and changes nothing', () => {
  const p = page(tabs('gs', LEADS, { hashTarget: true }), { hash: '#%E0%A4%A' });
  assert.doesNotThrow(() => initTabs(p.document, p.window));
  assert.deepEqual(selected(p.document, 'gs'), ['claude-code']);
});

// ---- copy (site/src/scripts/copy.ts) ----

const { initCopy } = runClientScript('scripts/copy.ts');

const cmd = `<div data-slot="input-group" data-cmd><pre data-slot="input-group-control"><code><span class="ln"><span class="p">$ </span>claude plugin install agent-triforge@agent-triforge</span></code></pre>
  <div data-slot="input-group-addon"><button type="button" class="copy" data-copy="claude plugin install agent-triforge@agent-triforge" aria-label="Copy the install command"><span class="copy-label">Copy</span></button></div></div>`;

function copyPage({ writeText, execCommand, platform } = {}) {
  const p = page(cmd, { platform });
  p.window.navigator.clipboard = writeText ? { writeText } : undefined;
  p.document.execCommand = execCommand ?? (() => false);
  initCopy(p.document, p.window);
  const btn = p.document.querySelector('.copy');
  return { ...p, btn, label: () => btn.querySelector('.copy-label').textContent, live: () => p.document.getElementById('live').textContent };
}

test('copy: when the clipboard write succeeds the button says "Copied"', async () => {
  const written = [];
  const c = copyPage({ writeText: async (t) => written.push(t) });
  c.click(c.btn);
  await settle();
  assert.deepEqual(written, ['claude plugin install agent-triforge@agent-triforge']);
  assert.equal(c.label(), 'Copied');
  assert.match(c.live(), /Copied/);
});

test('copy: when both clipboard paths fail, it says so, selects the command and tells the reader to press ⌘C', async () => {
  const c = copyPage({ writeText: async () => Promise.reject(new Error('NotAllowedError')), execCommand: () => false });
  c.click(c.btn);
  await settle();
  assert.equal(c.label(), 'Copy failed');
  assert.equal(c.selection.ranges.length, 1, 'the command text is selected');
  assert.match(c.live(), /Press ⌘C/);
});

test('copy: off a Mac the instruction is Ctrl+C', async () => {
  const c = copyPage({ writeText: async () => Promise.reject(new Error('denied')), execCommand: () => false, platform: 'Win32' });
  c.click(c.btn);
  await settle();
  assert.match(c.live(), /Press Ctrl\+C/);
});

test('copy: with no clipboard API, the legacy command copies and reports success', async () => {
  const c = copyPage({ writeText: null, execCommand: (name) => name === 'copy' });
  c.click(c.btn);
  await settle();
  assert.equal(c.label(), 'Copied');
});

// ---- theme (site/src/scripts/theme.ts) ----

const { THEME_INIT, THEME_KEY, initThemeToggle } = runClientScript('scripts/theme.ts');

function storage(initial = {}, { throws = false } = {}) {
  const data = { ...initial };
  const fail = () => {
    throw new DOMException('denied', 'SecurityError');
  };
  return {
    data,
    getItem: (k) => (throws ? fail() : (data[k] ?? null)),
    setItem: (k, v) => (throws ? fail() : (data[k] = String(v))),
  };
}

function runInit({ stored, throws = false, systemDark = false }) {
  const documentElement = { dataset: {} };
  const localStorage = storage(stored ? { [THEME_KEY]: stored } : {}, { throws });
  const matchMedia = (q) => ({ matches: q === '(prefers-color-scheme: dark)' && systemDark });
  new Function('document', 'localStorage', 'matchMedia', THEME_INIT)({ documentElement }, localStorage, matchMedia);
  return documentElement.dataset.theme;
}

test('the inline theme script applies a stored "dark" before first paint, over a light system preference', () => {
  assert.equal(runInit({ stored: 'dark', systemDark: false }), 'dark');
  assert.equal(runInit({ stored: 'light', systemDark: true }), 'light');
});

test('the inline theme script follows the system preference when nothing valid is stored', () => {
  assert.equal(runInit({ systemDark: true }), 'dark');
  assert.equal(runInit({ systemDark: false }), 'light');
  assert.equal(runInit({ stored: 'sepia', systemDark: true }), 'dark');
});

test('the inline theme script falls back to the system preference when storage throws', () => {
  assert.equal(runInit({ throws: true, systemDark: true }), 'dark');
  assert.equal(runInit({ throws: true, systemDark: false }), 'light');
});

function toggleEnv({ theme = 'light', throws = false } = {}) {
  const root = { dataset: { theme } };
  const button = fakeTarget({ attrs: {}, setAttribute(k, v) { this.attrs[k] = v; } });
  const events = [];
  const doc = { documentElement: root, querySelectorAll: () => [button], dispatchEvent: (e) => events.push(e.type) };
  const localStorage = storage({}, { throws });
  const { initThemeToggle: init } = runClientScript('scripts/theme.ts', {
    globals: { localStorage, CustomEvent: class { constructor(type) { this.type = type; } } },
  });
  init(doc);
  return { root, button, events, localStorage };
}

test('the theme toggle flips data-theme, stores the choice and tells the page', () => {
  const env = toggleEnv({ theme: 'light' });
  assert.equal(env.button.attrs['aria-pressed'], 'false');
  env.button.fire('click');
  assert.equal(env.root.dataset.theme, 'dark');
  assert.equal(env.localStorage.data[THEME_KEY], 'dark');
  assert.equal(env.button.attrs['aria-pressed'], 'true');
  assert.deepEqual(env.events, ['themechange']);
  env.button.fire('click');
  assert.equal(env.root.dataset.theme, 'light');
  assert.equal(env.localStorage.data[THEME_KEY], 'light');
});

test('the theme toggle still switches when storage throws', () => {
  const env = toggleEnv({ theme: 'dark', throws: true });
  assert.doesNotThrow(() => env.button.fire('click'));
  assert.equal(env.root.dataset.theme, 'light');
  assert.equal(env.button.attrs['aria-pressed'], 'false');
});


// ---- video figures (site/src/scripts/video.ts) ----

const { initVideos } = runClientScript('scripts/video.ts');

// The markup VideoFigure.astro and FilmPlayer.astro render, reduced to what the script reads.
const loopFig = `<figure class="fig" data-vfig><div class="vid"><img class="vf-poster" alt="" loading="lazy">
  <video muted playsinline loop preload="none" controls aria-label="Loop"><source src="/media/loop-lease.mp4" type="video/mp4"></video>
  <button class="vf-big" type="button" data-label="the lease loop" aria-label="Play the lease loop"><span>Play</span></button></div></figure>`;
const filmFig = `<figure class="fig film" data-vfig data-film data-duration="55"><div class="vid"><img class="vf-poster" alt="">
  <video muted playsinline preload="none" controls aria-label="Film"><source src="/media/film.mp4" type="video/mp4"></video>
  <button class="vf-big" type="button" data-label="the film" aria-label="Play the film"><span>Play</span></button></div>
  <div class="film-bar"><div class="film-dots" role="slider" tabindex="0" aria-label="Film position" aria-valuemin="0" aria-valuemax="55" aria-valuenow="0"></div><span class="film-time">0:00 / 0:55</span></div>
  <ol class="chapters"><li><button type="button" data-t="0">Goal</button></li><li><button type="button" data-t="19.4">Review</button></li></ol></figure>`;

// A page with one or more figures; each video gets a media API whose play() the test settles.
function videoPage(body, { reduced = false } = {}) {
  const p = page(body);
  const observers = [];
  p.window.matchMedia = (q) => ({ matches: reduced && q === '(prefers-reduced-motion: reduce)', addEventListener() {} });
  p.window.IntersectionObserver = class {
    constructor(cb) { this.cb = cb; observers.push(this); }
    observe(el) { this.el = el; }
  };
  p.window.innerHeight = 800;
  p.window.requestAnimationFrame = () => 0;
  p.window.cancelAnimationFrame = () => {};
  const Ev = p.window.Event;
  const videos = [...p.document.querySelectorAll('video')].map((v) => {
    const calls = [];
    let next = null;
    Object.assign(v, {
      paused: true, ended: false, currentTime: 0, duration: 55, preload: 'none',
      play() {
        calls.push('play');
        const settle = next ?? { resolve: true };
        next = null;
        if (settle.reject) return Promise.reject(settle.reject);
        v.paused = false;
        v.dispatchEvent(new Ev('play'));
        v.dispatchEvent(new Ev('playing'));
        return Promise.resolve();
      },
      pause() { calls.push('pause'); v.paused = true; v.dispatchEvent(new Ev('pause')); },
    });
    return { v, calls, refuseNext(err) { next = { reject: err }; } };
  });
  initVideos(p.document, p.window);
  // shows the figure: the observer reports it fully on screen
  const show = (i = 0, ratio = 1) => {
    const o = observers[i];
    o.cb([{ isIntersecting: ratio > 0, intersectionRatio: ratio, intersectionRect: { height: 400 * ratio }, rootBounds: { height: 800 }, target: o.el }]);
  };
  const fig = (i = 0) => p.document.querySelectorAll('[data-vfig]')[i];
  return { ...p, videos, show, fig };
}
const err = (name) => Object.assign(new Error(name), { name });

test('video: a loop plays once half visible and pauses off screen; no control pauses it', async () => {
  const p = videoPage(loopFig);
  assert.equal(p.videos[0].v.hasAttribute('controls'), false, 'the native controls go once the script runs');
  p.show(0, 0.3);
  assert.deepEqual(p.videos[0].calls, []);
  p.show(0, 0.6);
  await settle();
  assert.deepEqual(p.videos[0].calls, ['play']);
  assert.equal(p.fig().classList.contains('show-big'), false);
  p.show(0, 0);
  assert.deepEqual(p.videos[0].calls, ['play', 'pause']);
});

test('video: when play() is refused, the Play button appears, and pressing it plays', async () => {
  const p = videoPage(loopFig);
  p.videos[0].refuseNext(err('NotAllowedError'));
  p.show();
  await settle();
  assert.equal(p.fig().classList.contains('show-big'), true);
  p.click(p.fig().querySelector('.vf-big'));
  await settle();
  assert.equal(p.videos[0].v.paused, false);
  assert.equal(p.fig().classList.contains('show-big'), false);
});

test('video: when the video fails to load, the poster stays and the Play button appears', () => {
  const p = videoPage(loopFig);
  p.videos[0].v.querySelector('source').dispatchEvent(new p.window.Event('error'));
  assert.equal(p.fig().classList.contains('show-big'), true);
  assert.equal(p.fig().classList.contains('is-started'), false, 'the poster stays in front');
});

test('video: under reduced motion nothing starts on becoming visible; a chapter press seeks and plays', async () => {
  const p = videoPage(loopFig + filmFig, { reduced: true });
  p.show(0);
  p.show(1);
  await settle();
  assert.deepEqual(p.videos.map((x) => x.calls), [[], []]);
  assert.equal(p.fig(0).classList.contains('show-big'), true, 'the loop offers Play');
  const review = p.fig(1).querySelectorAll('.chapters button')[1];
  p.click(review);
  await settle();
  assert.ok(Math.abs(p.videos[1].v.currentTime - 19.4) < 0.05, `seeked to ${p.videos[1].v.currentTime}`);
  assert.deepEqual(p.videos[1].calls, ['play']);
});

test('video: the film plays once; at its end the button offers a replay from the start', async () => {
  const p = videoPage(filmFig);
  const { v } = p.videos[0];
  assert.equal(v.hasAttribute('loop'), false);
  p.show();
  await settle();
  v.ended = true;
  v.paused = true;
  v.dispatchEvent(new p.window.Event('ended'));
  const big = p.fig().querySelector('.vf-big');
  assert.equal(p.fig().classList.contains('show-big'), true);
  assert.equal(big.getAttribute('aria-label'), 'Replay the film');
  p.click(big);
  await settle();
  assert.equal(v.currentTime, 0);
  assert.equal(v.paused, false);
});
