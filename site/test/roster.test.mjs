// The roster: the CLIs equal the registry in scripts/lib/registry.sh, and every role's fallback chain
// ends at a core-trio member. Registry facts are read here with plain line matching, not with the
// module's literal parser.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { REPO } from '../src/lib/repo.mjs';
import { coreTrio, getClis, getRoles, parseRegistry } from '../src/lib/roster.mjs';

const CORE_TRIO = coreTrio();

const registry = readFileSync(join(REPO, 'scripts/lib/registry.sh'), 'utf8').split("_TRIFORGE_CLIS_PY='\n")[1].split("\n'\n")[0];
// Each CLI's block: from its 4-space-indented key to the next one.
const blocks = [...registry.matchAll(/^ {4}"([a-z]+)": \{\n([\s\S]*?)^ {4}\},?$/gm)].map(([, id, body]) => ({ id, body }));
const scalar = (body, key) => body.match(new RegExp(`^ {8}"${key}": (.+?),?(?:\\s+#.*)?$`, 'm'))?.[1];

test("the CLI ids equal the registry's ids, in its order", () => {
  assert.ok(blocks.length > 0, 'no CLI blocks found in the registry');
  assert.deepEqual(getClis().map((c) => c.id), blocks.map((b) => b.id));
});

test('core trio, egress, role limits, consent and lead come from the registry', () => {
  const clis = new Map(getClis().map((c) => [c.id, c]));
  assert.deepEqual(CORE_TRIO, blocks.filter((b) => scalar(b.body, 'tier') === '"core"').map((b) => b.id));
  for (const { id, body } of blocks) {
    const cli = clis.get(id);
    assert.equal(cli.core, scalar(body, 'tier') === '"core"', id);
    assert.equal(cli.egress, JSON.parse(scalar(body, 'egress')), id);
    const limit = JSON.parse(scalar(body, 'role_limit'));
    assert.deepEqual(cli.roles, limit.length ? limit : ['builder', 'reviewer', 'tester', 'analyst', 'documenter'], id);
    assert.deepEqual(cli.optInRoles, JSON.parse(scalar(body, 'opt_in_roles')), id);
    assert.equal(cli.consent, scalar(body, 'consent') === 'True', id);
    // a CLI can lead when its lead profile is not the empty {}
    assert.equal(cli.canLead, !/^ {8}"lead": \{\},?$/m.test(body), id);
  }
  assert.ok(getClis().some((c) => c.canLead) && getClis().some((c) => !c.canLead));
});

test('each CLI is named after its row in docs/compatibility.md', () => {
  const rows = readFileSync(join(REPO, 'docs/compatibility.md'), 'utf8').split('\n').filter((l) => /^\| [A-Z]/.test(l) && !l.startsWith('| CLI '));
  assert.equal(rows.length, getClis().length);
  for (const cli of getClis()) {
    const row = rows.find((r) => r.includes(`(\`${cli.binary}\``));
    assert.ok(row, `${cli.id}: no compatibility row for \`${cli.binary}\``);
    const cell = row.split('|')[1].trim();
    assert.ok(cell.startsWith(cli.name), `${cli.id}: "${cli.name}" is not the start of "${cell}"`);
    assert.ok(!cli.name.includes('(') && !cli.name.endsWith(' CLI'), cli.name);
  }
});

test("every role's fallback chain ends at a core-trio member", () => {
  const roles = getRoles();
  const template = readFileSync(join(REPO, 'templates/ops/roster.toml'), 'utf8');
  assert.deepEqual(roles.map((r) => r.role), [...template.matchAll(/^\[roles\.([a-z]+)\]$/gm)].map((m) => m[1]));
  const names = new Map(getClis().map((c) => [c.id, c.name]));
  for (const role of roles) {
    const chain = [role.cli, ...role.fallbacks.map((f) => f.cli)];
    assert.ok(CORE_TRIO.includes(chain.at(-1)), `${role.role}: the chain ${chain.join(' -> ')} ends outside the core trio`);
    assert.equal(role.cliName, names.get(role.cli));
    for (const f of role.fallbacks) assert.equal(f.cliName, names.get(f.cli));
  }
});

test('the registry reader handles comments, escaped quotes and nested dicts, and evaluates nothing', () => {
  const text = [
    "_TRIFORGE_CLIS_PY='",
    'CLIS = {',
    '    "a": {   # a comment',
    '        "x": "say \\"hi\\"",',
    '        "re": "^[0-9]\\\\.",',
    '        "n": 600, "on": True, "off": False, "none": None,',
    '        "list": ["p", "q"],',
    '        "lead": {},',
    '    },',
    '}',
    "'",
  ].join('\n');
  assert.deepEqual(parseRegistry(text), { a: { x: 'say "hi"', re: '^[0-9]\\.', n: 600, on: true, off: false, none: null, list: ['p', 'q'], lead: {} } });
  assert.throws(() => parseRegistry("_TRIFORGE_CLIS_PY='\nCLIS = { \"a\": __import__(\"os\") }\n'"), /cannot read|unexpected/);
});
