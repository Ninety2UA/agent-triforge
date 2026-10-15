// The personas (KTD3): one record per personas/*.md, with its personas/manifest.toml entry and its
// docs/personas.md group. Expected values are read from those files here, by simpler means than the
// module uses.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { REPO } from '../src/lib/repo.mjs';
import { getPersonas, personaGroups, personasPage } from '../src/lib/personas.mjs';
import { resolveLink } from '../src/lib/routes.mjs';

const files = readdirSync(join(REPO, 'personas')).filter((f) => f.endsWith('.md')).map((f) => f.slice(0, -3)).sort();
const manifest = readFileSync(join(REPO, 'personas/manifest.toml'), 'utf8');
const doc = readFileSync(join(REPO, 'docs/personas.md'), 'utf8').split('\n');

// The "## " heading above the table row that links personas/<name>.md.
function headingOf(name) {
  const row = doc.findIndex((line) => line.startsWith('|') && line.includes(`](../personas/${name}.md)`));
  assert.ok(row !== -1, `docs/personas.md has no row for ${name}`);
  return doc.slice(0, row).reverse().find((line) => line.startsWith('## ')).slice(3);
}

function entry(name) {
  const block = manifest.split(`[personas.${name}]`)[1]?.split(/^\[/m)[0];
  assert.ok(block, `manifest has no [personas.${name}]`);
  const value = (key) => block.match(new RegExp(`^${key} = (.+)$`, 'm'))[1].trim();
  return { class: JSON.parse(value('class')), tier: JSON.parse(value('tier')), neverDowngrade: value('never_downgrade') === 'true', maxTurns: Number(value('max_turns')) };
}

test('the persona records equal the persona files, each with its manifest entry', () => {
  const personas = getPersonas();
  assert.deepEqual(personas.map((p) => p.name).sort(), files);
  for (const persona of personas) {
    const { class: cls, tier, neverDowngrade, maxTurns } = persona;
    assert.deepEqual({ class: cls, tier, neverDowngrade, maxTurns }, entry(persona.name), persona.name);
    assert.equal(persona.anchor, persona.name);
    assert.equal(persona.path, `personas/${persona.name}.md`);
    assert.equal(persona.body, readFileSync(join(REPO, persona.path), 'utf8'), `${persona.name}: the body is the prompt (it has no links to rewrite)`);
    assert.ok(persona.summary.length > 0, `${persona.name} has no summary`);
  }
});

test('each persona sits in the docs/personas.md group above its row, under an anchor without the count', () => {
  for (const persona of getPersonas()) {
    const heading = headingOf(persona.name);
    const label = heading.replace(/\s*\(\d+\)$/, '');
    assert.equal(persona.group.label, label, persona.name);
    assert.equal(persona.group.anchor, label.toLowerCase().replace(/[^a-z0-9 -]/g, '').replace(/ /g, '-'));
    // the persona's own link and its group's legacy anchor both land on the personas page
    assert.equal(resolveLink('docs/workflows.md', `../personas/${persona.name}.md`), `/skills/personas/#${persona.name}`);
  }
});

test('group counts are the personas each group holds, in docs/personas.md order', () => {
  const groups = personaGroups();
  const headings = doc.filter((line) => line.startsWith('## ')).map((line) => line.slice(3).replace(/\s*\(\d+\)$/, ''));
  assert.deepEqual(groups.map((g) => g.label), headings);
  for (const group of groups) assert.equal(group.count, getPersonas().filter((p) => p.group.key === group.key).length);
  assert.equal(groups.reduce((sum, g) => sum + g.count, 0), files.length);
});

test("the personas page takes docs/personas.md's first paragraph as its intro, links resolved", () => {
  const page = personasPage();
  assert.equal(page.href, '/skills/personas/');
  assert.ok(page.intro.length > 0);
  assert.ok(!/\]\((?!https?:|\/)/.test(page.intro), 'the intro keeps a relative link');
});
