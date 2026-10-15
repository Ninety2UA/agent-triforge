// HTML for the skill and persona pages, from text the repo already holds. Plain string functions, so
// node:test runs them too.
//
// Exports
//   escapeHtml(text)        text safe inside an element or a double-quoted attribute
//   inlineHtml(markdown)    one line of Markdown as HTML: `code` spans and [text](href) links (http(s),
//                           a site path or a fragment; any other link stays as written), the rest escaped.
//                           Code wraps only at a space: each word sits in <span class="nw"> (nowrap where
//                           skills.css loads), so --team or ops/.sprint-complete never breaks inside. A word
//                           longer than LONG_WORD characters may also break after a slash (<wbr>), so a
//                           long path cannot overflow a phone-width card; shorter ones stay whole, because
//                           a <wbr> puts a space into what a screen reader reads
//   skillBodyHtml(html)     a rendered SKILL.md for its page: the body's title (its h1) becomes an h2, a
//                           sibling of the sections under it, so the page keeps one h1; ids are kept,
//                           because links from the docs name them (/skills/at-build/#output)
//   promptHtml(html)        a rendered persona prompt inside its entry: headings move under the persona's
//                           h3 (h1 and h2 -> h4, h3 -> h5, deeper -> h6) and drop their ids, which repeat
//                           across prompts ("Output") and are not link targets (a persona's links land on
//                           #<name>)
// Both fit their tables to the column (docs/tables.mjs) and label their checklist items (docs/task-lists.mjs).

import { escapeHtml } from '../lib/text.mjs';
import { LONG_WORD, fitTables } from './docs/tables.mjs';
import { labelTaskItems } from './docs/task-lists.mjs';

export { escapeHtml };

const SAFE_HREF = /^(?:https?:\/\/|\/|#)/;


/** @param {string} code */
const codeHtml = (code) =>
  code
    .split(' ')
    .map((word) => (word.length > LONG_WORD ? word.split(/(?<=\/)/) : [word]).map((piece) => `<span class="nw">${escapeHtml(piece)}</span>`).join('<wbr>'))
    .join(' ');

/** @param {string} markdown */
export function inlineHtml(markdown) {
  const out = [];
  // a link (whose text may hold code), a code span, or one plain character
  const token = /\[((?:[^[\]`]|`[^`]*`)+)\]\(([^)\s]+)\)|`([^`]+)`|([\s\S])/g;
  for (const [whole, linkText, href, code, char] of markdown.matchAll(token)) {
    if (linkText !== undefined) out.push(SAFE_HREF.test(href) ? `<a href="${escapeHtml(href)}">${inlineHtml(linkText)}</a>` : escapeHtml(whole));
    else if (code !== undefined) out.push(`<code>${codeHtml(code)}</code>`);
    else out.push(escapeHtml(char));
  }
  return out.join('');
}

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
