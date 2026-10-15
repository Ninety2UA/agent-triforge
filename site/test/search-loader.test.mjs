// Tests for the Cmd-K palette's loader (site/src/components/search/loader.ts) while its first
// load is pending: keys typed meanwhile wait for the palette, Escape gives the keyboard back at
// once, and a chunk that fails to load shows a notice linking to the catalog search and is
// retried on the next press. The loader
// runs against a fake window and document; the palette's chunk is a deferred import.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import * as shortcut from '../src/components/search/shortcut.mjs';
import { deferred, fakeTarget, runClientScript, settle } from './client-script.mjs';

class FakeElement {
  constructor(tag) {
    this.tag = tag;
    this.isContentEditable = false;
  }
  closest(selector) {
    return selector.split(',').some((s) => s.trim() === this.tag) ? this : null;
  }
}

function loaderPage() {
  const win = fakeTarget();
  const field = new FakeElement('input');
  const live = { textContent: '' };
  // the notice the loader shows when the palette cannot load
  const notes = [];
  const created = (tag) => {
    const el = { tag, id: '', className: '', attrs: {}, href: '', textContent: '', children: [] };
    el.setAttribute = (k, v) => (el.attrs[k] = v);
    el.replaceChildren = (...kids) => (el.children = kids);
    return el;
  };
  const body = Object.assign(new FakeElement('body'), { append: (el) => notes.push(el) });
  const doc = fakeTarget({
    activeElement: field,
    body,
    createElement: created,
    getElementById: (id) => (id === 'live' ? live : notes.find((n) => n.id === id) ?? null),
  });
  const chunks = [];
  runClientScript('components/search/loader.ts', {
    imports: {
      '../search-event': { OPEN_SEARCH_EVENT: 'triforge:open-search' },
      './pagefind': { loadIndex: () => Promise.resolve() },
      './shortcut.mjs': shortcut,
    },
    globals: {
      addEventListener: win.addEventListener,
      removeEventListener: win.removeEventListener,
      document: doc,
      HTMLElement: FakeElement,
      __import(spec) {
        assert.equal(spec, './mount');
        const chunk = deferred();
        chunks.push(chunk);
        return chunk.promise;
      },
    },
  });
  const opened = [];
  const palette = {
    openPalette: (returnFocus, typed = '') => opened.push({ returnFocus, typed }),
    togglePalette: (returnFocus) => opened.push({ returnFocus, typed: '' }),
  };
  const key = (k, mods = {}) =>
    win.fire('keydown', { key: k, metaKey: false, ctrlKey: false, altKey: false, isComposing: false, target: field, ...mods });
  return { win, field, live, notes, chunks, opened, palette, key };
}

test('keys typed while the palette first loads go into its search box when it opens', async () => {
  const p = loaderPage();
  p.key('k', { metaKey: true });
  assert.equal(p.chunks.length, 1);
  for (const k of ['r', 'e', 'x', 'Backspace', 'v']) assert.equal(p.key(k).defaultPrevented, true, `${k} is held for the palette`);
  p.chunks[0].resolve(p.palette);
  await settle();
  assert.deepEqual(p.opened, [{ returnFocus: p.field, typed: 'rev' }]);
  assert.equal(p.key('y').defaultPrevented, false, 'the keyboard is released once the palette is open');
});

test('Escape while the palette first loads cancels the open and gives typing back to the focused field at once', async () => {
  const p = loaderPage();
  p.key('k', { metaKey: true });
  assert.equal(p.key('Escape').defaultPrevented, true);
  const x = p.key('x');
  assert.equal(x.defaultPrevented, false, 'a key typed after Escape reaches the field');
  assert.equal(x.stopped, false);
  assert.equal(p.key('Backspace').defaultPrevented, false);
  p.chunks[0].resolve(p.palette);
  await settle();
  assert.deepEqual(p.opened, [], 'a cancelled open stays cancelled');
  p.key('k', { metaKey: true });
  assert.equal(p.opened.length, 1, 'the next Cmd-K opens the loaded palette');
});

test('asking again after Escape, while the first load is still pending, opens the palette when it arrives', async () => {
  const p = loaderPage();
  p.key('k', { metaKey: true });
  p.key('Escape');
  p.key('k', { metaKey: true });
  assert.equal(p.chunks.length, 1, 'the pending load is reused');
  assert.equal(p.key('a').defaultPrevented, true);
  p.chunks[0].resolve(p.palette);
  await settle();
  assert.deepEqual(p.opened, [{ returnFocus: p.field, typed: 'a' }]);
});

test('a palette chunk that fails to load is announced, releases the keyboard and is retried on the next press', async () => {
  const p = loaderPage();
  const unhandled = [];
  const onUnhandled = (reason) => unhandled.push(reason);
  process.on('unhandledRejection', onUnhandled);
  try {
    p.key('k', { metaKey: true });
    p.key('r');
    p.chunks[0].reject(new TypeError('Failed to fetch dynamically imported module'));
    await settle();
    await settle();
    assert.deepEqual(unhandled, [], 'nothing rejects unhandled');
    assert.match(p.live.textContent, /^Search could not load/);
    assert.equal(p.notes.length, 1, 'a visible notice');
    assert.equal(p.notes[0].attrs.role, 'alert');
    const link = p.notes[0].children.find((c) => typeof c === 'object');
    assert.equal(link.href, '/skills/?q=r', 'the notice links to the catalog search with what was typed');
    assert.equal(p.key('x').defaultPrevented, false, 'typing reaches the field again');
    assert.deepEqual(p.opened, []);

    p.key('k', { metaKey: true });
    assert.equal(p.chunks.length, 2, 'the next press loads the chunk again');
    p.chunks[1].resolve(p.palette);
    await settle();
    assert.equal(p.opened.length, 1);
  } finally {
    process.off('unhandledRejection', onUnhandled);
  }
});
