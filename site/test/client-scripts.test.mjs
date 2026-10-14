// Tests for the site's small browser scripts, each run in plain Node against fakes (client-script.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { fakeTarget, runClientScript } from './client-script.mjs';

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

assert.equal(typeof initThemeToggle, 'function');
