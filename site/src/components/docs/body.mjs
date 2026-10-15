// The Docs and Guides page bodies, before and after Astro renders them. Plain string work on the HTML
// the docs collection renders, so node:test can check each step without a build.
//
// Before render (the image pipeline reads these options):
//   withImageOptions(html)   turns every Markdown image into a <picture>: an AVIF source and a WebP
//                            <img>, both with a srcset at the widths the prose column shows (the WebP's
//                            largest candidate is always the original width, the full-size file). The
//                            page's first image is fetched first when it sits in the opening section
//                            (before the second H2), so it is in or near the first screen; the rest stay
//                            lazy.
// After render:
//   finishBody(html, { install })  links each picture to its full-size file (a picture
//                            alone in its paragraph becomes a <div class="img"> block), fits each table to the
//                            column (tables.mjs), and replaces a code block that only repeats a lead's
//                            install commands (already shown in the install tabs) with a link to that tab.
//   splitBeforeFirstH2(html)       [before, rest]: where a page slots a figure under its opening section.
//   splitAfterH2(html, id)   [before, rest]: where a page slots a figure under one section's heading.
// Page text:
//   introText(introHtml)     the intro paragraph's inner HTML, for a <p class="intro">
//   describe(markdown)       plain text for a meta description, cut at a sentence or word near 175
//                            characters ('' for no text)
//   firstParagraphText(html) the first <p> of rendered HTML as plain text

/** The width each image box shows at, for the browser's srcset choice (see docs.css .doc .img-full). */
export const IMAGE_SIZES = '(min-width: 1280px) 600px, (min-width: 820px) 734px, calc(100vw - 66px)';
// Widths for the WebP srcset. The last is a ceiling: Astro drops every width above the original and
// adds the original, so the largest candidate is always the full-size file. The AVIF source stops at
// twice the widest box, so the build never encodes a full-size AVIF.
export const IMAGE_WIDTHS = [400, 700, 1000, 1468, 100000];
export const AVIF_WIDTHS = [400, 700, 1000, 1468];

import { fitTables } from './tables.mjs';
import { labelTaskItems } from './task-lists.mjs';

const IMG = /<img\b([^>]*?)\s?__ASTRO_IMAGE_="([^"]+)"([^>]*)>/g;
// Astro's own decoding of the placeholder (content/runtime.js), and its inverse
const decodeAttr = (s) => s.replace(/&(?:#x22|quot);/g, '"').replace(/&(?:#x27|apos);/g, "'").replace(/&(?:amp|#x26|#38);/g, '&');
const encodeAttr = (s) => s.replace(/&/g, '&#x26;').replace(/"/g, '&#x22;').replace(/'/g, '&#x27;');
const placeholder = (props) => `__ASTRO_IMAGE_="${encodeAttr(JSON.stringify(props))}"`;

/** @param {string} html */
export function withImageOptions(html) {
  const h2s = [...html.matchAll(/<h2\b/g)].map((m) => m.index);
  const opening = h2s.length >= 2 ? h2s[1] : Infinity;
  let first = true;
  return html.replace(IMG, (_, before, json, after, offset) => {
    const props = JSON.parse(decodeAttr(json));
    const priority = first && offset < opening;
    first = false;
    const webp = { ...props, widths: IMAGE_WIDTHS, sizes: IMAGE_SIZES, ...(priority ? { priority: true } : {}) };
    // the source's own src is its narrowest candidate, already in its srcset
    const avif = { ...props, format: 'avif', width: AVIF_WIDTHS[0], widths: AVIF_WIDTHS, sizes: IMAGE_SIZES };
    return `<picture><source ${placeholder(avif)}><img${before} ${placeholder(webp)}${after}></picture>`;
  });
}

const attr = (tag, name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];
const decodeText = (s) =>
  s.replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n))).replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const textOf = (html) => decodeText(html.replace(/<[^>]*>/g, ''));

/**
 * @param {string} html
 * @param {{ install?: { id: string, label: string, lines: string[] }[] }} [options]
 */
export function finishBody(html, { install = [] } = {}) {
  // A picture from the pipeline opens its full-size file, the WebP <img>'s src. Its <source> keeps only
  // what a source takes (the pipeline wrote an image's attributes on it). A paragraph that holds
  // nothing but the picture becomes the picture's own block, as wide as the column.
  let out = html.replace(/<picture>\s*(<source\b[^>]*>)\s*(<img\b[^>]*>)\s*<\/picture>/g, (_, source, img) => {
    const keep = ['srcset', 'sizes'].map((n) => (attr(source, n) ? ` ${n}="${attr(source, n)}"` : '')).join('');
    return `<a class="img-full" href="${attr(img, 'src')}"><picture><source type="image/avif"${keep}>${img}</picture></a>`;
  });
  out = out.replace(/<p>\s*(<a class="img-full"[^>]*><picture>[\s\S]*?<\/picture><\/a>)\s*<\/p>/g, '<div class="img">$1</div>');
  out = labelTaskItems(fitTables(out));
  // a code block holding every command of a lead's install tab repeats that tab: link to it instead
  if (install.length) {
    out = out.replace(/<pre\b[^>]*>[\s\S]*?<\/pre>/g, (pre) => {
      const lines = textOf(pre).split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
      const tab = install.find((t) => t.lines.length && t.lines.every((l) => lines.includes(l)));
      return tab ? `<p class="see-tab">Copy them from the <a href="#${tab.id}">${tab.label}</a> tab at the top of this page.</p>` : pre;
    });
  }
  return out;
}

/** @param {string} html */
export function splitBeforeFirstH2(html) {
  const i = html.search(/<h2\b/);
  return i === -1 ? [html, ''] : [html.slice(0, i), html.slice(i)];
}

/**
 * [before, rest] split right after the H2 with this id; throws when the page has no such heading.
 * @param {string} html
 * @param {string} id
 */
export function splitAfterH2(html, id) {
  const m = new RegExp(`<h2\\b[^>]*\\sid="${id}"[^>]*>[\\s\\S]*?</h2>`).exec(html);
  if (!m) throw new Error(`docs body: no H2 with id "${id}" to put the figure under`);
  const i = m.index + m[0].length;
  return [html.slice(0, i), html.slice(i)];
}

/** @param {string} introHtml  the rendered intro, one <p> */
export function introText(introHtml) {
  return introHtml.trim().replace(/^<p>([\s\S]*)<\/p>$/, '$1');
}

const LIMIT = 175;
/** @param {string} markdown  inline Markdown (an intro paragraph) */
export function describe(markdown) {
  // code spans keep their text as written (an underscore or asterisk in them is not emphasis)
  const code = [];
  const plain = markdown
    .replace(/`([^`]*)`/g, (_, c) => `\u0000${code.push(c) - 1}\u0000`)
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/(\*\*|__|\*|_)(?=\S)([\s\S]*?\S)\1(?![\w*])/g, '$2')
    .replace(/<[^>]*>/g, '')
    .replace(/\s*\([^()]*\)/g, '')
    .replace(/\u0000(\d+)\u0000/g, (_, i) => code[Number(i)])
    .replace(/\s+/g, ' ')
    .trim();
  return cut(plain);
}

/** @param {string} html */
export function firstParagraphText(html) {
  const p = html.match(/<p>([\s\S]*?)<\/p>/);
  return p ? cut(textOf(p[1]).replace(/\s+/g, ' ').trim()) : '';
}

function cut(text) {
  if (text.length <= LIMIT) return text;
  // whole sentences when they fill at least half the room, else whole words and an ellipsis
  const sentences = [...text.slice(0, LIMIT + 1).matchAll(/[.!?](?=\s)/g)].map((m) => m.index + 1);
  const end = sentences.at(-1);
  if (end && end >= LIMIT / 2) return text.slice(0, end);
  const words = text.slice(0, LIMIT).replace(/\s+\S*$/, '').replace(/[,;:(\s]+$/, '');
  return `${words}…`;
}
