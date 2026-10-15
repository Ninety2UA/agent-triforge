// Text formats the data modules read: Markdown headings, sections, paragraphs and tables, SKILL.md
// frontmatter and the small TOML subset the repo's manifests use. Plain Node, no astro: imports, no
// repository paths: every function takes the text and, where it can fail, a `where` that the error
// names, so a repo edit that breaks the site says which file to look at.
//
// Exports
//   githubSlug(text)               GitHub's heading anchor ("Review specialists (6)" -> "review-specialists-6");
//                                  Astro gives rendered headings the same ids.
//   fenceStep(line, fence)         fenced-code tracking, one line at a time: { fence, code }.
//   mapOutsideFences(text, fn)     `text` with fn applied to each run of lines outside fenced code.
//   maskCode(line)                 { text, restore }: the line with its inline code spans replaced by
//                                  placeholders, and the function that puts them back.
//   parseHeadings(markdown)        [{ depth, text, slug, line, end }] for every ATX heading outside fenced
//                                  code; `slug` carries GitHub's -1, -2 suffix for repeats, `line` is the
//                                  0-based line index and `end` the index where the heading's section stops.
//   htmlAnchors(markdown)          [{ name, line }] for each <a name="..."> or <a id="..."> outside code.
//   headingAnchors(markdown)       Set of every anchor a link into this Markdown may name: heading slugs
//                                  and raw HTML anchors.
//   firstParagraph(lines, from, to)  { text, start, end } of the first prose paragraph in lines[from, to)
//                                  (not a heading, HTML block, list, table, quote or fence), or null.
//   splitRow(line), parseTables(lines)  GitHub tables: [{ header, rows, line }], cells trimmed, \| unescaped.
//   codeSpans(text)                the contents of the inline code spans in `text`.
//   plainInline(markdown)          inline Markdown with each link reduced to its label (code spans kept).
//   readFrontmatter(text, where)   SKILL.md frontmatter: top-level scalars and one level of nested scalars.
//   splitFrontmatter(text)         { frontmatter, body }: the raw block and the text after it.
//   parseToml(text, where)         the TOML the repo's manifests use: [a.b] tables and one-line
//                                  key = "string" | 'literal' | true | false | integer | ["a", "b"].

/** @param {string} text  the text with its first letter in upper case */
export const capitalize = (text) => text.charAt(0).toUpperCase() + text.slice(1);

/**
 * "a, b and c" ("or" with conjunction "or"); one word alone; '' for none
 * @param {string[]} words
 * @param {string} [conjunction]
 */
export const joinWords = (words, conjunction = 'and') =>
  words.length < 2 ? words.join('') : `${words.slice(0, -1).join(', ')} ${conjunction} ${words[words.length - 1]}`;

/** @param {string} text  the text as a literal inside a RegExp */
export const escapeRegExp = (text) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const FENCE = /^\s*(`{3,}|~{3,})/;
const HEADING = /^(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$/;

export function githubSlug(text) {
  return text
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{M}\p{N}\p{Pc} -]/gu, '')
    .replace(/ /g, '-');
}

// `code` is true for fence lines and the lines between them.
export function fenceStep(line, fence) {
  const open = line.match(FENCE);
  if (!open) return { fence, code: fence !== null };
  if (fence === null) return { fence: open[1][0], code: true };
  const closes = open[1][0] === fence && line.trim().replace(/[`~]/g, '') === '';
  return { fence: closes ? null : fence, code: true };
}

export function mapOutsideFences(text, fn) {
  const out = [];
  let run = [];
  let fence = null;
  const flush = () => {
    if (run.length) out.push(...fn(run.join('\n')).split('\n'));
    run = [];
  };
  for (const line of text.split('\n')) {
    const step = fenceStep(line, fence);
    fence = step.fence;
    if (step.code) {
      flush();
      out.push(line);
    } else {
      run.push(line);
    }
  }
  flush();
  return out.join('\n');
}

// Inline code: a run of backticks, the shortest text, the same run again.
const CODE_SPAN = /(`+)(?!`)([\s\S]*?[^`])\1(?!`)/g;

export function maskCode(line) {
  const spans = [];
  const text = line.replace(CODE_SPAN, (span) => `\u0000${spans.push(span) - 1}\u0000`);
  const restore = (masked) => masked.replace(/\u0000(\d+)\u0000/g, (_, i) => spans[Number(i)]);
  return { text, restore };
}

export function parseHeadings(markdown) {
  const lines = markdown.split('\n');
  const headings = [];
  const seen = new Map();
  let fence = null;
  lines.forEach((line, index) => {
    const step = fenceStep(line, fence);
    fence = step.fence;
    if (step.code) return;
    const m = line.match(HEADING);
    if (!m) return;
    const text = m[2];
    const base = githubSlug(text);
    const count = seen.get(base) ?? 0;
    seen.set(base, count + 1);
    headings.push({ depth: m[1].length, text, slug: count ? `${base}-${count}` : base, line: index });
  });
  headings.forEach((h, i) => {
    const next = headings.slice(i + 1).find((n) => n.depth <= h.depth);
    h.end = next ? next.line : lines.length;
  });
  return headings;
}

export function htmlAnchors(markdown) {
  const anchors = [];
  let fence = null;
  markdown.split('\n').forEach((line, index) => {
    const step = fenceStep(line, fence);
    fence = step.fence;
    if (step.code) return;
    for (const m of maskCode(line).text.matchAll(/<a\b[^>]*?\b(?:name|id)="([^"]+)"/g)) anchors.push({ name: m[1], line: index });
  });
  return anchors;
}

export function headingAnchors(markdown) {
  return new Set([...parseHeadings(markdown).map((h) => h.slug), ...htmlAnchors(markdown).map((a) => a.name)]);
}

// A paragraph's first line, when it is not prose: a heading, an HTML block, an image, a list item,
// a table row, a quote or a fence.
const NOT_PROSE = /^\s*(#{1,6}\s|<|!\[|[-*+]\s|\d+[.)]\s|\||>|```|~~~)/;

export function firstParagraph(lines, from = 0, to = lines.length) {
  for (let i = from; i < to; i++) {
    if (!lines[i].trim()) continue;
    let end = i;
    while (end < to && lines[end].trim()) end++;
    if (!NOT_PROSE.test(lines[i])) return { text: lines.slice(i, end).join('\n'), start: i, end };
    i = end;
  }
  return null;
}

export function splitRow(line) {
  return line
    .trim()
    .replace(/^\|/, '')
    .replace(/(?<!\\)\|$/, '')
    .split(/(?<!\\)\|/)
    .map((cell) => cell.trim().replace(/\\\|/g, '|'));
}

const DELIMITER = /^\s*\|?[\s|:-]+\|?\s*$/;

export function parseTables(lines) {
  const tables = [];
  let fence = null;
  for (let i = 0; i < lines.length; i++) {
    const step = fenceStep(lines[i], fence);
    fence = step.fence;
    if (step.code) continue;
    if (!lines[i].trim().startsWith('|') || !DELIMITER.test(lines[i + 1] ?? '') || !lines[i + 1].includes('-')) continue;
    const header = splitRow(lines[i]);
    const rows = [];
    let j = i + 2;
    for (; j < lines.length && lines[j].trim().startsWith('|'); j++) rows.push(splitRow(lines[j]));
    tables.push({ header, rows, line: i });
    i = j - 1;
  }
  return tables;
}

export function codeSpans(text) {
  return [...text.matchAll(CODE_SPAN)].map((m) => m[2].trim());
}

export function plainInline(markdown) {
  const { text, restore } = maskCode(markdown);
  return restore(text.replace(/!?\[((?:[^[\]]|\[[^\]]*\])*)\]\([^)\s]*\)/g, '$1'));
}

function scalar(raw, where) {
  if (raw.startsWith('"')) return JSON.parse(raw);
  if (raw.startsWith("'")) return raw.slice(1, -1).replace(/''/g, "'");
  if (/^[|>]/.test(raw)) throw new Error(`${where}: block scalars are not read here; write the value on one line`);
  if (raw === 'true' || raw === 'false') return raw === 'true';
  return raw;
}

export function splitFrontmatter(text) {
  const block = text.match(/^---\n([\s\S]*?)\n---\n?/);
  if (!block) return { frontmatter: null, body: text };
  return { frontmatter: block[1], body: text.slice(block[0].length) };
}

// Top-level scalars and one level of nested scalars, one per line; comment lines are skipped.
export function readFrontmatter(text, where) {
  const { frontmatter } = splitFrontmatter(text);
  if (frontmatter === null) throw new Error(`${where}: no frontmatter`);
  const data = {};
  let parent = null;
  for (const line of frontmatter.split('\n')) {
    if (!line.trim() || line.trim().startsWith('#')) continue;
    const m = line.match(/^(\s*)([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!m) throw new Error(`${where} frontmatter: cannot read line "${line}"`);
    const [, indent, key, raw] = m;
    if (indent) {
      if (!parent) throw new Error(`${where} frontmatter: indented line "${line}" has no parent key`);
      data[parent][key] = scalar(raw, where);
    } else if (raw === '') {
      data[key] = {};
      parent = key;
    } else {
      data[key] = scalar(raw, where);
      parent = null;
    }
  }
  return data;
}

// A TOML value on one line, then an optional comment.
const TOML_VALUE = /^("(?:[^"\\]|\\.)*"|'[^']*'|true|false|-?\d+|\[[^\]]*\])\s*(?:#.*)?$/;

function tomlValue(raw, where) {
  if (raw.startsWith('"')) return JSON.parse(raw);
  if (raw.startsWith("'")) return raw.slice(1, -1);
  if (raw === 'true' || raw === 'false') return raw === 'true';
  if (raw.startsWith('[')) {
    const items = raw.slice(1, -1).match(/"(?:[^"\\]|\\.)*"|'[^']*'/g) ?? [];
    return items.map((item) => tomlValue(item, where));
  }
  return Number(raw);
}

export function parseToml(text, where) {
  const data = {};
  let table = data;
  text.split('\n').forEach((line, index) => {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) return;
    const header = trimmed.match(/^\[([A-Za-z0-9_.-]+)\]\s*(?:#.*)?$/);
    if (header) {
      table = data;
      for (const key of header[1].split('.')) table = table[key] ??= {};
      return;
    }
    const pair = trimmed.match(/^([A-Za-z0-9_-]+)\s*=\s*(.*)$/);
    const value = pair?.[2].match(TOML_VALUE);
    if (!pair || !value) throw new Error(`${where}:${index + 1}: cannot read "${trimmed}"`);
    table[pair[1]] = tomlValue(value[1], where);
  });
  return data;
}
