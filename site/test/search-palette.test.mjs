// Tests for the plain rules behind the Cmd-K palette in site/src/components/search/: which key
// presses open it (shortcut.mjs), how Pagefind results are grouped by section, and how a
// Pagefind excerpt (escaped text with <mark> around the matches) becomes the text parts the
// palette renders (results.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { excerptParts, groupResults } from '../src/components/search/results.mjs';
import { shortcutAction } from '../src/components/search/shortcut.mjs';

const key = (k, extra = {}) => ({ key: k, metaKey: false, ctrlKey: false, altKey: false, defaultPrevented: false, ...extra });

test('Cmd-K and Ctrl-K toggle the palette from anywhere, even while typing in a field', () => {
  assert.equal(shortcutAction(key('k', { metaKey: true }), { typing: false }), 'toggle');
  assert.equal(shortcutAction(key('k', { ctrlKey: true }), { typing: false }), 'toggle');
  assert.equal(shortcutAction(key('K', { metaKey: true }), { typing: false }), 'toggle');
  assert.equal(shortcutAction(key('k', { metaKey: true }), { typing: true }), 'toggle');
});

test('a plain k, an Alt chord and a press another handler already took do nothing', () => {
  assert.equal(shortcutAction(key('k'), { typing: false }), null);
  assert.equal(shortcutAction(key('k', { metaKey: true, altKey: true }), { typing: false }), null);
  assert.equal(shortcutAction(key('k', { metaKey: true, defaultPrevented: true }), { typing: false }), null);
});

test('"/" opens the palette only outside text fields, with no modifier, when no one else took it', () => {
  assert.equal(shortcutAction(key('/'), { typing: false }), 'open');
  assert.equal(shortcutAction(key('/'), { typing: true }), null);
  // the skills catalog's own "/" handler calls preventDefault() to focus its search box
  assert.equal(shortcutAction(key('/', { defaultPrevented: true }), { typing: false }), null);
  assert.equal(shortcutAction(key('/', { metaKey: true }), { typing: false }), null);
  assert.equal(shortcutAction(key('/', { ctrlKey: true }), { typing: false }), null);
});

test('groupResults keeps rank order inside a section and orders sections by their best result', () => {
  const page = (url, section) => ({ url, title: url, excerpt: '', section });
  const groups = groupResults([
    page('/skills/at-review/', 'Skills'),
    page('/docs/faq/', 'Docs'),
    page('/skills/at-ship/', 'Skills'),
    page('/', 'Pages'),
    page('/docs/how-it-works/', 'Docs'),
  ]);
  assert.deepEqual(
    groups.map((g) => [g.section, g.pages.map((p) => p.url)]),
    [
      ['Skills', ['/skills/at-review/', '/skills/at-ship/']],
      ['Docs', ['/docs/faq/', '/docs/how-it-works/']],
      ['Pages', ['/']],
    ],
  );
});

test('a result without a section filter is grouped under Pages', () => {
  const groups = groupResults([{ url: '/changelog/', title: 'Changelog', excerpt: '', section: undefined }]);
  assert.deepEqual(groups.map((g) => g.section), ['Pages']);
});

test('excerptParts splits on <mark> and decodes the entities Pagefind escaped', () => {
  assert.deepEqual(excerptParts('Merge back to <mark>&lt;base-branch&gt;</mark> locally &amp; push'), [
    { text: 'Merge back to ', mark: false },
    { text: '<base-branch>', mark: true },
    { text: ' locally & push', mark: false },
  ]);
});

test('excerptParts marks the rest of a cut-off excerpt whose <mark> never closes', () => {
  assert.deepEqual(excerptParts('bash install.sh --only <mark>cursor-agent'), [
    { text: 'bash install.sh --only ', mark: false },
    { text: 'cursor-agent', mark: true },
  ]);
});

test('excerptParts drops any other tag and decodes quotes and numeric entities', () => {
  assert.deepEqual(excerptParts('<b>say</b> &quot;hi&quot; &#39;there&#39; &#x2F;'), [{ text: `say "hi" 'there' /`, mark: false }]);
  assert.deepEqual(excerptParts(''), []);
});
