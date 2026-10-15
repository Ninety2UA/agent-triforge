// One line of Markdown as HTML: the renderer for every short repo-sourced or hand-written string the
// site sets inline (skill summaries, sprint table cells, home phase bodies, install notes). Plain
// string work, so node:test runs it too.
//
//   inlineHtml(markdown)  `code` spans and [text](href) links (http(s), a site path or a fragment; any
//                         other link stays as written), the rest escaped. Code wraps only at a space:
//                         each word sits in <span class="nw"> (nowrap where a page's styles say so), so
//                         --team or ops/.sprint-complete never breaks inside. A word longer than
//                         LONG_WORD characters may also break after a slash (<wbr>), so a long path
//                         cannot overflow a phone-width card; shorter ones stay whole, because a <wbr>
//                         puts a space into what a screen reader reads
//   LONG_WORD             that length, shared with the tables (components/docs/tables.mjs)

import { escapeHtml } from './text.mjs';

/** A code word longer than this may break after a hyphen or a slash; a shorter one stays whole. */
export const LONG_WORD = 24;

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
