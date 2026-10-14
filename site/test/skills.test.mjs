// The skill records (R2): one per skills/<name>/SKILL.md folder, read from the tree, never from typed-in
// names or counts. The lead/portable split is checked against each SKILL.md's own
// metadata.triforge-consumer ("lead" for a lead workflow), which the site does not read.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { GROUPS } from '../src/data/groups.mjs';
import { getCounts } from '../src/lib/counts.mjs';
import { REPO } from '../src/lib/repo.mjs';
import { getSkills, skillGroups } from '../src/lib/skills.mjs';

const folders = readdirSync(join(REPO, 'skills'), { withFileTypes: true })
  .filter((d) => d.isDirectory() && existsSync(join(REPO, 'skills', d.name, 'SKILL.md')))
  .map((d) => d.name)
  .sort();
const skillText = (name) => readFileSync(join(REPO, 'skills', name, 'SKILL.md'), 'utf8');
// the SKILL.md prose: after the frontmatter, inline code removed
const prose = (name) => skillText(name).replace(/^---\n[\s\S]*?\n---\n/, '').replace(/`[^`]*`/g, '');
const field = (text, key) => {
  const raw = text.match(new RegExp(`^\\s*${key}: (.*)$`, 'm'))?.[1];
  return raw === undefined ? undefined : raw.startsWith('"') ? JSON.parse(raw) : raw;
};

test('the skill records equal the skill folders, and the lead/portable split equals the folder split', () => {
  const skills = getSkills();
  assert.deepEqual(skills.map((s) => s.name).sort(), folders);
  for (const skill of skills) {
    const consumer = field(skillText(skill.name), 'triforge-consumer');
    assert.equal(skill.lead, consumer === 'lead', `${skill.name}: lead is ${skill.lead}, its SKILL.md consumer is "${consumer}"`);
  }
  const counts = getCounts();
  assert.equal(counts.skills, folders.length);
  assert.equal(counts.leadSkills, folders.filter((name) => field(skillText(name), 'triforge-consumer') === 'lead').length);
  assert.equal(counts.leadSkills + counts.portableSkills, counts.skills);
});

test('each record carries its frontmatter, its path and a body without the frontmatter', () => {
  for (const skill of getSkills()) {
    const text = skillText(skill.name);
    assert.equal(skill.path, `skills/${skill.name}/SKILL.md`);
    assert.equal(skill.description, field(text, 'description'), skill.name);
    assert.equal(skill.argumentHint, field(text, 'argument-hint') ?? null, skill.name);
    assert.ok(skill.summary.length > 0, `${skill.name} has no summary`);
    assert.ok(!skill.body.startsWith('---'), `${skill.name} body keeps its frontmatter`);
    assert.ok(skill.body.length > 0 && text.endsWith(skill.body.split('\n').at(-1)), `${skill.name} body is not the SKILL.md tail`);
  }
});

test('skill bodies keep raw placeholders for the escape plugin and carry no relative links', () => {
  const skills = getSkills();
  const placeholders = skills.filter((s) => /<[a-z][^>]*\s[^>]*>/.test(prose(s.name)));
  assert.ok(placeholders.length > 0, 'no SKILL.md has a raw <placeholder> in prose; the escape plugin is untested here');
  for (const skill of placeholders) {
    for (const [tag] of prose(skill.name).matchAll(/<[a-z][^>]*\s[^>]*>/g)) {
      assert.ok(skill.body.includes(tag), `${skill.name} lost ${tag}`);
    }
  }
  for (const skill of skills) {
    const relative = [...skill.body.replace(/`[^`]*`/g, '').matchAll(/\]\(([^)\s]+)\)/g)].map((m) => m[1]).filter((t) => !/^(https?:|\/|#)/.test(t));
    assert.deepEqual(relative, [], `${skill.name} keeps relative links`);
  }
});

test('the summary is the row of the lead workflows table or the portable skills table', () => {
  const workflows = readFileSync(join(REPO, 'docs/workflows.md'), 'utf8');
  const portable = readFileSync(join(REPO, 'docs/skills.md'), 'utf8');
  for (const skill of getSkills()) {
    const table = skill.lead ? workflows : portable;
    const row = table.split('\n').find((line) => line.startsWith(`| [\`${skill.name}\`](../skills/${skill.name}/SKILL.md) |`));
    if (!row) {
      assert.equal(skill.summary, skill.description, `${skill.name} has no table row, so its summary is its description`);
      continue;
    }
    // the last cell, with links reduced to their text
    const last = row.replace(/\|\s*$/, '').split(/(?<!\\)\|/).at(-1).trim().replace(/\\\|/g, '|');
    assert.equal(skill.summary, last.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1'), skill.name);
  }
});

test('records come in catalog order: group by group, Portable last', () => {
  const keys = getSkills().map((s) => s.group.key);
  const order = skillGroups().map((g) => g.key);
  const seen = keys.filter((key, i) => key !== keys[i - 1]);
  assert.deepEqual(seen, order.filter((key) => keys.includes(key)));
  for (const group of GROUPS) {
    assert.deepEqual(getSkills().filter((s) => s.group.key === group.key).map((s) => s.name), group.skills, group.label);
  }
});
