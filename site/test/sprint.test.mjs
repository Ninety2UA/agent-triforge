// The sprint page's repo facts (site/src/lib/sprint.mjs): the phase table and the quality gates from
// docs/workflows.md, the convergence modes from the iterative-refinement skill and the completion
// checklist from at-ship's completion-gating reference. Each is read from its table or list, links go
// through the route table, and a missing table stops the build naming the file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { REPO } from '../src/lib/repo.mjs';
import { completionChecklist, convergenceModes, parsePipeline, qualityGates, sprintPhases } from '../src/lib/sprint.mjs';
import { inlineHtml } from '../src/lib/inline-html.mjs';

const workflows = readFileSync(join(REPO, 'docs/workflows.md'), 'utf8');
// the rows of the first table after a heading, by plain line matching
const rowsAfter = (text, heading) => {
  const lines = text.split('\n');
  const at = lines.findIndex((l) => l.startsWith(heading));
  const start = lines.findIndex((l, i) => i > at && l.startsWith('|'));
  const out = [];
  for (let i = start + 2; lines[i]?.startsWith('|'); i++) out.push(lines[i]);
  return out;
};

test('the phases are the Sprint Pipeline rows of docs/workflows.md, in order', () => {
  const rows = rowsAfter(workflows, '## Sprint Pipeline');
  const phases = sprintPhases();
  assert.equal(phases.length, rows.length);
  phases.forEach((p, i) => assert.ok(rows[i].startsWith(`| ${p.label} |`), `row ${i}: ${p.label}`));
  assert.deepEqual(phases.map((p) => p.id), ['phase-0', 'pre-plan', 'phase-1', 'phase-1-1', 'phase-1-5', 'phase-2', 'phase-3-and-4', 'phase-5', 'phase-6']);
  const build = phases.find((p) => p.id === 'phase-2');
  assert.equal(build.number, '2');
  assert.equal(build.name, 'Build');
  assert.deepEqual(build.workflows, ['at-build']);
  const pre = phases.find((p) => p.id === 'pre-plan');
  assert.equal(pre.number, '');
  assert.equal(pre.name, 'Pre-plan');
});

test('phase cells render their code and resolve their links through the route table', () => {
  const analyze = sprintPhases().find((p) => p.id === 'phase-0');
  assert.match(analyze.agentsHtml, /<a href="\/skills\/codebase-mapping\/"><code><span class="nw">codebase-mapping<\/span><\/code><\/a>/);
  assert.match(analyze.workflowsHtml, /<a href="\/skills\/at-plan\/"><code><span class="nw">at-plan<\/span><\/code><\/a>/);
  for (const p of sprintPhases()) {
    for (const html of [p.happensHtml, p.agentsHtml, p.workflowsHtml]) {
      assert.ok(!/\]\(|\.\.\/|SKILL\.md/.test(html), `${p.label}: an unresolved link in ${html}`);
    }
  }
});

test('the quality gates are the rows of the Quality Gates table', () => {
  const rows = rowsAfter(workflows, '## Quality Gates');
  const gates = qualityGates();
  assert.equal(gates.length, rows.length);
  gates.forEach((g, i) => assert.ok(rows[i].startsWith(`| ${g.number}, ${g.name} |`), rows[i]));
  assert.ok(gates.every((g) => g.rule && g.enforcedByHtml));
});

test('the convergence modes are fast, standard and deep, standard the default', () => {
  const modes = convergenceModes();
  assert.deepEqual(modes.map((m) => m.mode), ['fast', 'standard', 'deep']);
  assert.deepEqual(modes.filter((m) => m.isDefault).map((m) => m.mode), ['standard']);
  assert.equal(modes[0].exit, 'P1 count = 0');
  // the flag at-ship takes names the same modes
  const ship = readFileSync(join(REPO, 'skills/at-ship/SKILL.md'), 'utf8');
  assert.ok(ship.includes(`--convergence ${modes.map((m) => m.mode).join('|')}`));
});

test('the completion checklist is the numbered list of completion-gating.md', () => {
  const items = completionChecklist();
  const text = readFileSync(join(REPO, 'skills/at-ship/references/completion-gating.md'), 'utf8');
  assert.equal(items.length, text.split('\n').filter((l) => /^\d+\. /.test(l)).length);
  assert.match(items.at(-1), /<code><span class="nw">ops\/.sprint-complete<\/span><\/code>/);
});

test('inlineHtml escapes text and renders code spans and links, with code inside a link label', () => {
  assert.equal(inlineHtml('a < b & `x<y>` [`at-ship`](/skills/at-ship/) [docs](https://x.test/a?b=1&c)'),
    'a &lt; b &amp; <code><span class="nw">x&lt;y&gt;</span></code> <a href="/skills/at-ship/"><code><span class="nw">at-ship</span></code></a> <a href="https://x.test/a?b=1&amp;c">docs</a>');
});

test('a missing table stops the build, naming the file', () => {
  assert.throws(() => parsePipeline('# Workflow\n\nNo table here.\n', 'docs/workflows.md'), /docs\/workflows\.md: no table under "## Sprint Pipeline/);
});
