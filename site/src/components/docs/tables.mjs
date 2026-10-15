// Tables in rendered Markdown (docs, guides, skills, persona prompts, tutorials, release notes), set so
// that no reader scrolls sideways. Plain string work, so node:test checks it without a build.
//
//   fitTables(html)   puts each <table> in a <div class="table-wrap" data-stack="W">, which docs.css
//                     makes a size container. Code in a cell wraps only at a space: each word up to
//                     LONG_WORD characters sits in <span class="nw"> (nowrap), so at-build or
//                     learnings-researcher never splits at its hyphen; a longer word may break after
//                     one. A table needs at least the width of the longest unbroken piece in each column.
//                     minTableWidth estimates that; W is the first step of STACK_STEPS that clears it
//                     with MARGIN to spare, or "always" past the last. While the box is at least W wide the table
//                     keeps its columns; narrower, each row becomes a block of its cells, each cell
//                     under its column's name (data-label). The explicit roles keep a stacked table a
//                     table to a screen reader, which display: block would undo.
//   minTableWidth(tableHtml)   that estimate in CSS pixels, from the fonts' measured advance widths at
//                     the table's type sizes (docs.css). It ignores kerning, so it can miss by a few
//                     pixels either way; MARGIN covers that.

/** Container widths (px) at which a table may switch to rows; docs.css has one query per step. */
export const STACK_STEPS = [320, 360, 400, 440, 480, 520, 560, 600, 640, 680, 720];
const MARGIN = 12;

// Familjen Grotesk at 400 and 15px, the advance of each character from space to "~" (measured in the
// browser); other characters count as OTHER. Bold text is BOLD times wider, header cells (500, 13px)
// HEAD times, and Sometype Mono in a code span (0.86em) advances CODE per character.
const ASCII = [3, 5.5, 6.4, 9, 8.5, 12.8, 10.1, 3.8, 5.2, 5.2, 5.6, 8.5, 3, 4.5, 3, 5.2, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5, 4.1, 4.1, 8.5, 8.5, 8.5, 7.2, 12.4, 9, 8.8, 9.2, 9.6, 8.1, 7.8, 9.9, 10, 3.8, 3.8, 8.6, 7.5, 12.9, 10.2, 9.9, 8.6, 9.9, 8.8, 8.5, 8.6, 9.8, 9, 13.5, 8.9, 8, 8.9, 5.2, 5, 5.2, 8.5, 9, 7.5, 8.2, 8.2, 7.4, 8.2, 7.6, 4.4, 8.1, 8.1, 3.5, 3.5, 7.5, 3.5, 12.2, 8.1, 7.9, 8.2, 8.2, 5.2, 6.8, 4.4, 8.1, 7.1, 11.2, 7, 7.1, 6.9, 5.2, 4.5, 5.2, 8.5];
const OTHER = 13.5;
const BOLD = 1.03;
const HEAD = 0.88;
const CODE = 7.48;
const CODE_PAD = 10; // a code span's padding
const CELL_PAD = 14; // each cell's right padding
const FIRST_MIN = 112.5; // the first column's min-width, 7.5em

/** A code word longer than this may break after a hyphen; a shorter one stays whole. */
export const LONG_WORD = 24;

const decode = (s) =>
  s.replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n))).replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
const textOf = (html) => decode(html.replace(/<[^>]*>/g, '')).trim();
const attrText = (s) => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;');
const glyph = (ch) => ASCII[ch.charCodeAt(0) - 32] ?? OTHER;

// The widest run of a cell that cannot break, walked as one stream so that text touching across a tag
// (`a`/`b`, two code spans joined by a slash) counts as one word. A run breaks at a space and after a
// hyphen, except inside a nowrap word (keepWords); each code span adds its padding.
function longestPiece(cellHtml) {
  let max = 0;
  let run = 0;
  let code = false;
  let bold = 0;
  let nw = false;
  const end = () => {
    max = Math.max(max, run);
    run = 0;
  };
  for (const [, tag, text] of cellHtml.matchAll(/(<[^>]*>)|([^<]+)/g)) {
    if (tag) {
      if (/^<code\b/.test(tag)) (code = true), (run += CODE_PAD / 2);
      else if (tag === '</code>') (code = false), (run += CODE_PAD / 2);
      else if (/^<(strong|b)\b/.test(tag)) bold++;
      else if (/^<\/(strong|b)>/.test(tag)) bold--;
      else if (tag === '<span class="nw">') nw = true;
      else if (tag === '</span>') nw = false;
      else if (/^<br\b/.test(tag)) end();
      continue;
    }
    for (const ch of decode(text)) {
      if (/\s/.test(ch)) {
        end();
        continue;
      }
      run += code ? CODE : glyph(ch) * (bold ? BOLD : 1);
      if (ch === '-' && !nw) end();
    }
  }
  end();
  return max;
}

/** @param {string} tableHtml */
export function minTableWidth(tableHtml) {
  const rows = [...tableHtml.matchAll(/<tr\b[^>]*>([\s\S]*?)<\/tr>/g)].map(([, row]) =>
    [...row.matchAll(/<(t[hd])\b[^>]*>([\s\S]*?)<\/t[hd]>/g)].map(([, tag, cell]) => longestPiece(cell) * (tag === 'th' ? HEAD : 1)),
  );
  const cols = Math.max(0, ...rows.map((r) => r.length));
  let width = 0;
  for (let i = 0; i < cols; i++) {
    const col = Math.max(...rows.map((r) => r[i] ?? 0));
    width += (i === 0 ? Math.max(col, FIRST_MIN) : col) + CELL_PAD;
  }
  return Math.round(width);
}

// a code span's words, each up to LONG_WORD characters in a nowrap span (entities count as one character)
const keepWords = (code) =>
  code.split(' ').map((w) => (w && decode(w).length <= LONG_WORD ? `<span class="nw">${w}</span>` : w)).join(' ');

/** @param {string} html */
export function fitTables(html) {
  return html.replace(/<table>([\s\S]*?)<\/table>/g, (_, inner) => {
    const head = inner.match(/<thead>([\s\S]*?)<\/thead>/)?.[1] ?? '';
    const labels = [...head.matchAll(/<th\b[^>]*>([\s\S]*?)<\/th>/g)].map((m) => textOf(m[1]));
    const rows = inner
      .replace(/<code>([^<]*)<\/code>/g, (_, code) => `<code>${keepWords(code)}</code>`)
      .replace(/<(thead|tbody)>/g, '<$1 role="rowgroup">')
      .replace(/<tr>/g, '<tr role="row">')
      .replace(/<th\b/g, '<th role="columnheader"')
      .replace(/<tbody role="rowgroup">[\s\S]*?<\/tbody>/g, (body) =>
        body.replace(/<tr role="row">([\s\S]*?)<\/tr>/g, (_, row) => {
          let i = 0;
          const cells = row.replace(/<td\b/g, () => {
            const label = labels[i++];
            return label ? `<td role="cell" data-label="${attrText(label)}"` : '<td role="cell"';
          });
          return `<tr role="row">${cells}</tr>`;
        }),
      );
    // measured after keepWords, which decides where code may break
    const need = minTableWidth(rows) + MARGIN;
    const stack = STACK_STEPS.find((w) => w >= need) ?? 'always';
    return `<div class="table-wrap" data-stack="${stack}"><table role="table">${rows}</table></div>`;
  });
}
