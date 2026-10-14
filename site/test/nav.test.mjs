// The header's current-section marking (site/src/data/nav.ts) and the reading order of a
// docs-style section (site/src/lib/section-order.mjs).
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { navItems } from '../src/data/nav.ts';
import { sectionOrder } from '../src/lib/section-order.mjs';

const current = (path) => Object.fromEntries(navItems(path).filter((i) => i.current).map((i) => [i.label, i.current]));

test('a skill page marks Skills as the current section', () => {
  assert.deepEqual(current('/skills/at-ship/'), { Skills: 'true' });
  assert.deepEqual(current('/skills/personas/'), { Skills: 'true' });
  assert.deepEqual(current('/skills/'), { Skills: 'page' });
});

test('a docs page marks Docs, and its first page marks it as the page itself', () => {
  assert.deepEqual(current('/docs/faq/'), { Docs: 'true' });
  assert.deepEqual(current('/docs/getting-started/'), { Docs: 'page' });
  assert.deepEqual(current('/docs/faq'), { Docs: 'true' }, 'a path without its trailing slash');
});

test('the home page and the 404 mark no section', () => {
  assert.deepEqual(current('/'), {});
  assert.deepEqual(current('/404/'), {});
});

const docs = sectionOrder([
  { slug: 'getting-started', label: 'Getting started', href: '/docs/getting-started/' },
  { slug: 'how-it-works', label: 'How it works', href: '/docs/how-it-works/' },
  { slug: 'faq', label: 'FAQ', href: '/docs/faq/' },
]);

test('the first page has no previous link and the last has no next link', () => {
  assert.deepEqual(docs.neighbors('getting-started'), { prev: undefined, next: { label: 'How it works', href: '/docs/how-it-works/' } });
  assert.deepEqual(docs.neighbors('how-it-works'), {
    prev: { label: 'Getting started', href: '/docs/getting-started/' },
    next: { label: 'FAQ', href: '/docs/faq/' },
  });
  assert.deepEqual(docs.neighbors('faq'), { prev: { label: 'How it works', href: '/docs/how-it-works/' }, next: undefined });
});

test('the sidebar marks the current page, and an unknown page throws naming it', () => {
  assert.deepEqual(docs.sidebar('faq').filter((i) => i.current).map((i) => i.label), ['FAQ']);
  assert.throws(() => docs.neighbors('nope'), /"nope"/);
});
