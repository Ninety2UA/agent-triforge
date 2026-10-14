// The skill catalog's groups (R4, KTD5): every lead skill in exactly one group of
// site/src/data/groups.mjs, portable skills in Portable. The validator is tested on made-up inputs,
// then the real groups file is checked against the real skills/ tree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { GROUPS, LEAD_PREFIX, PORTABLE } from '../src/data/groups.mjs';
import { REPO } from '../src/lib/repo.mjs';
import { groupSkills, skillGroups } from '../src/lib/skills.mjs';

const lead = (name) => `${LEAD_PREFIX}${name}`;
const fakeGroups = [
  { key: 'one', label: 'One', skills: [lead('alpha'), lead('beta')] },
  { key: 'two', label: 'Two', skills: [lead('gamma')] },
];

test('each lead skill gets its one group and each portable skill lands in Portable', () => {
  const groups = groupSkills([lead('alpha'), lead('beta'), lead('gamma'), 'mapping', 'refinement'], fakeGroups);
  assert.deepEqual(groups.get(lead('alpha')), { key: 'one', label: 'One' });
  assert.deepEqual(groups.get(lead('gamma')), { key: 'two', label: 'Two' });
  assert.deepEqual(groups.get('mapping'), PORTABLE);
  assert.deepEqual(groups.get('refinement'), PORTABLE);
});

test('a lead skill missing from the groups fails the build, naming the skill', () => {
  assert.throws(() => groupSkills([lead('alpha'), lead('beta'), lead('gamma'), lead('delta')], fakeGroups), new RegExp(`${lead('delta')}.*no catalog group`));
});

test('a lead skill listed in two groups fails the build, naming the skill and both groups', () => {
  const twice = [...fakeGroups, { key: 'three', label: 'Three', skills: [lead('beta')] }];
  assert.throws(() => groupSkills([lead('alpha'), lead('beta'), lead('gamma')], twice), new RegExp(`${lead('beta')}.*two groups.*One.*Three|${lead('beta')}.*One.*Three`));
});

test('a portable skill listed in a group fails the build: it already belongs to Portable', () => {
  const listed = [...fakeGroups, { key: 'three', label: 'Three', skills: ['mapping'] }];
  assert.throws(() => groupSkills([lead('alpha'), lead('beta'), lead('gamma'), 'mapping'], listed), /mapping/);
});

test('every skill folder in the repo has exactly one group, and the catalog order ends in Portable', () => {
  const folders = readdirSync(join(REPO, 'skills'), { withFileTypes: true })
    .filter((d) => d.isDirectory() && existsSync(join(REPO, 'skills', d.name, 'SKILL.md')))
    .map((d) => d.name);
  const groups = groupSkills(folders);
  assert.equal(groups.size, folders.length);
  for (const name of folders) {
    const expected = name.startsWith(LEAD_PREFIX) ? GROUPS.filter((g) => g.skills.includes(name)).map(({ key, label }) => ({ key, label })) : [PORTABLE];
    assert.deepEqual([groups.get(name)], expected, name);
  }
  const order = skillGroups();
  assert.deepEqual(order.map((g) => g.key), [...GROUPS.map((g) => g.key), PORTABLE.key]);
  assert.equal(order.reduce((sum, g) => sum + g.count, 0), folders.length);
  assert.equal(order.at(-1).count, folders.filter((n) => !n.startsWith(LEAD_PREFIX)).length);
});
