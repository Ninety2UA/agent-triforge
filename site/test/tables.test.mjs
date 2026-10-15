// Tables fit their column (src/components/docs/tables.mjs): every cell knows its column's name, short
// code words stay whole, and the width at which a table turns into rows follows from its longest
// unbroken words. The thresholds are checked against docs.css, which needs one query per step.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { fitTables, minTableWidth, STACK_STEPS, LONG_WORD } from '../src/components/docs/tables.mjs';

const table = (head, ...rows) =>
  `<table><thead><tr>${head.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join('')}</tr>`).join('')}</tbody></table>`;

test('each cell carries its column name, and the table keeps its roles', () => {
  const out = fitTables(table(['Phase', 'What &amp; why'], ['0, Analyze', 'scan'], ['1', 'plan']));
  assert.match(out, /^<div class="table-wrap" data-stack="(\d+|always)"><table role="table"><thead role="rowgroup"><tr role="row"><th role="columnheader">Phase<\/th>/);
  assert.equal((out.match(/<td role="cell" data-label="Phase">/g) ?? []).length, 2);
  assert.equal((out.match(/<td role="cell" data-label="What &amp; why">/g) ?? []).length, 2, 'a label is the header text, escaped for the attribute');
  assert.match(out, /<\/table><\/div>$/);
});

test('a code word up to LONG_WORD characters stays whole; a longer one may break', () => {
  const short = 'learnings-researcher';
  const long = 'hooks/handlers/tool-failure-monitor.sh';
  assert.ok(short.length <= LONG_WORD && long.length > LONG_WORD);
  const out = fitTables(table(['Agent', 'File'], [`<code>${short}</code> + <code>x y</code>`, `<code>${long}</code>`]));
  assert.match(out, new RegExp(`<code><span class="nw">${short}</span></code>`));
  assert.match(out, /<code><span class="nw">x<\/span> <span class="nw">y<\/span><\/code>/);
  assert.match(out, new RegExp(`<code>${long.replace(/\./g, '\\.')}</code>`));
});

test('a nowrap word counts whole; the same word may break after its hyphen when it is not kept', () => {
  const kept = minTableWidth(table(['A'], ['<code><span class="nw">learnings-researcher</span></code>']));
  const loose = minTableWidth(table(['A'], ['<code>learnings-researcher</code>']));
  assert.ok(kept > loose, `${kept} > ${loose}`);
});

test('text touching across a tag is one unbreakable run', () => {
  const joined = minTableWidth(table(['A', 'B'], ['x', '<code>invoke_gemini</code>/<code>invoke_codex</code>']));
  const apart = minTableWidth(table(['A', 'B'], ['x', '<code>invoke_gemini</code> / <code>invoke_codex</code>']));
  assert.ok(joined > apart + 80, `${joined} vs ${apart}`);
});

test('a narrow table stacks only on a narrow column; a wide one stacks everywhere', () => {
  const step = (html) => html.match(/data-stack="([^"]+)"/)[1];
  assert.equal(step(fitTables(table(['A', 'B'], ['one', 'two']))), String(STACK_STEPS[0]));
  const wide = table(['A', 'B', 'C', 'D', 'E'], Array(5).fill('<code>a-twenty-character-wd</code>'));
  assert.equal(step(fitTables(wide)), 'always');
});

test('docs.css has a container query for every stack step', () => {
  const css = readFileSync(fileURLToPath(new URL('../src/styles/docs.css', import.meta.url)), 'utf8');
  for (const w of STACK_STEPS) {
    assert.match(css, new RegExp(`@container tbl \\(width < ${w}px\\) \\{ \\.table-wrap\\[data-stack="${w}"\\] > table \\{`), `no query for ${w}`);
  }
  assert.match(css, /\.table-wrap\[data-stack="always"\] > table \{/);
});

test('a checklist item with inline content is labelled by its own text; one holding a nested list is left alone', async () => {
  const { labelTaskItems } = await import('../src/components/docs/task-lists.mjs');
  const out = labelTaskItems('<ul class="contains-task-list"><li class="task-list-item"><input type="checkbox" disabled> Every task has a <code>role</code></li><li class="task-list-item"><input type="checkbox" checked disabled> Nested<ul><li>x</li></ul></li></ul>');
  assert.match(out, /<li class="task-list-item"><label><input type="checkbox" disabled> Every task has a <code>role<\/code><\/label><\/li>/);
  assert.match(out, /<li class="task-list-item"><input type="checkbox" checked disabled> Nested<ul>/);
});
