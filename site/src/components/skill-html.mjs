// HTML for the skill and persona pages, from text the repo already holds. Plain string functions, so
// node:test runs them too.
//
// Exports
//   escapeHtml(text)        text safe inside an element or a double-quoted attribute
//   inlineHtml(markdown)    one line of Markdown as HTML (lib/inline-html.mjs)
//   skillBodyHtml(html)     a rendered SKILL.md for its page: the body's title (its h1) becomes an h2, a
//                           sibling of the sections under it, so the page keeps one h1; ids are kept,
//                           because links from the docs name them (/skills/at-build/#output)
//   promptHtml(html)        a rendered persona prompt inside its entry: headings move under the persona's
//                           h3 (h1 and h2 -> h4, h3 -> h5, deeper -> h6) and drop their ids, which repeat
//                           across prompts ("Output") and are not link targets (a persona's links land on
//                           #<name>)
// Both fit their tables to the column (docs/tables.mjs) and label their checklist items (docs/task-lists.mjs).

import { escapeHtml } from '../lib/text.mjs';
import { inlineHtml } from '../lib/inline-html.mjs';
import { fitTables } from './docs/tables.mjs';
import { labelTaskItems } from './docs/task-lists.mjs';

export { escapeHtml, inlineHtml };

/** @param {string} html */
export function skillBodyHtml(html) {
  return labelTaskItems(fitTables(html.replace(/<(\/?)h1\b/g, '<$1h2')));
}

/** @param {string} html */
export function promptHtml(html) {
  const level = (/** @type {string} */ d) => Math.min(6, Math.max(4, Number(d) + 2));
  return labelTaskItems(fitTables(html
    .replace(/<h([1-6])\b([^>]*)>/g, (_, d, attrs) => `<h${level(d)}${attrs.replace(/\s+id="[^"]*"/, '')}>`)
    .replace(/<\/h([1-6])>/g, (_, d) => `</h${level(d)}>`)));
}
