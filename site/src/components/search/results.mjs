// results.mjs: how the Cmd-K palette shows Pagefind results. Plain JavaScript with no DOM, so
// site/test/search-palette.test.mjs imports it directly.
//
//   groupResults(pages)  ranked pages grouped by section; a section sits where its best page
//                        ranks, so the first option is always the best match.
//   excerptParts(html)   a Pagefind excerpt (escaped text, <mark> around the matches) as
//                        [{ text, mark }], for rendering without innerHTML.

/** @typedef {{ url: string, title: string, excerpt: string, section: string | undefined }} Page */

/** Pages with no section filter (a page type added without one) still show, under this name. */
export const DEFAULT_SECTION = 'Pages';

/**
 * @param {Page[]} pages  in rank order
 * @returns {{ section: string, pages: Page[] }[]}
 */
export function groupResults(pages) {
  /** @type {Map<string, Page[]>} */
  const groups = new Map();
  for (const page of pages) {
    const section = page.section || DEFAULT_SECTION;
    const list = groups.get(section);
    if (list) list.push(page);
    else groups.set(section, [page]);
  }
  return [...groups].map(([section, list]) => ({ section, pages: list }));
}

/** @type {Record<string, string>} */
const ENTITIES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' };

/** @param {string} text */
const decode = (text) =>
  text.replace(/&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi, (whole, name) => {
    if (name[0] === '#') {
      const code = name[1] === 'x' || name[1] === 'X' ? parseInt(name.slice(2), 16) : parseInt(name.slice(1), 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : whole;
    }
    return ENTITIES[name.toLowerCase()] ?? whole;
  });

/**
 * @param {string} html
 * @returns {{ text: string, mark: boolean }[]}
 */
export function excerptParts(html) {
  /** @type {{ text: string, mark: boolean }[]} */
  const parts = [];
  let mark = false;
  for (const piece of html.split(/(<\/?mark>)/i)) {
    if (/^<mark>$/i.test(piece)) mark = true;
    else if (/^<\/mark>$/i.test(piece)) mark = false;
    else {
      const text = decode(piece.replace(/<[^>]*>/g, ''));
      if (text) parts.push({ text, mark });
    }
  }
  return parts;
}
