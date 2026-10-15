// What the site reads from README.md: the install commands, the FAQ, sections and the release history.
// Expected commands are built from .claude-plugin/plugin.json, so a README that drifts from the
// plugin's own repository and name fails here.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { faq, installCommands, readmeSection, releaseTable } from '../src/lib/readme.mjs';
import { REPO } from '../src/lib/repo.mjs';
import { GH } from '../src/lib/repo.mjs';

const README = readFileSync(join(REPO, 'README.md'), 'utf8');
const PLUGIN = JSON.parse(readFileSync(join(REPO, '.claude-plugin/plugin.json'), 'utf8'));
const GITHUB = GH;
const SLUG = new URL(GITHUB).pathname.slice(1); // owner/repo
const ID = `${PLUGIN.name}@${PLUGIN.name}`;

// The lines of the README between "## <title>" and the next "## ", read without the module.
const rawSection = (title) => README.split(`\n## ${title}\n`)[1].split(/\n## /)[0];

test("the install commands are the README install block's, exactly", () => {
  const { claude, codex } = installCommands();
  assert.deepEqual(claude, [`claude plugin marketplace add ${GITHUB}`, `claude plugin install ${ID}`]);
  assert.deepEqual(codex, [`codex plugin marketplace add ${SLUG}`, `codex plugin add ${ID}`]);
  const fence = rawSection('Install').split('```bash\n')[1].split('\n```')[0];
  const lines = fence.split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  assert.deepEqual([...claude, ...codex], lines);
});

test('the skills-only installs come from the Devin and Pi table of docs/installation.md', () => {
  const { skillsOnly } = installCommands();
  const install = readFileSync(join(REPO, 'docs/installation.md'), 'utf8');
  const rows = install.split('\n## Portable skills in Devin and Pi\n')[1].split('\n## ')[0].split('\n').filter((l) => /^\| (?!Harness|---)/.test(l));
  assert.deepEqual(skillsOnly.map((s) => s.cli), rows.map((row) => row.split('|')[1].trim()));
  for (const { cli, lines, invoke } of skillsOnly) {
    assert.equal(lines.length, 1, `${cli}: ${lines.join(' / ')}`);
    const binary = cli.split(' ')[0].toLowerCase();
    assert.ok(lines[0].startsWith(`${binary} `), `${cli}: ${lines[0]}`);
    assert.ok(lines[0].includes(SLUG), `${cli}: ${lines[0]} does not name ${SLUG}`);
    assert.ok(install.includes(`\`${lines[0]}\``), `${cli}: ${lines[0]} is not in the table`);
    assert.match(invoke, /<name>/);
  }
});

test('the FAQ is every <details> question of the README, with each link resolved', () => {
  const items = faq();
  const questions = [...rawSection('FAQ').matchAll(/<summary><strong>(.*?)<\/strong><\/summary>/g)].map((m) => m[1]);
  assert.deepEqual(items.map((i) => i.question), questions);
  for (const item of items) {
    assert.match(item.anchor, /^[a-z0-9-]+$/);
    for (const [, href] of item.answer.matchAll(/href="([^"]+)"/g)) assert.match(href, /^(https?:|\/)/, `${item.question}: ${href}`);
  }
  const existing = items.find((i) => i.answer.includes('/docs/getting-started/#installation'));
  assert.ok(existing, 'the docs/installation.md#installation link did not resolve to the getting started page');
});

test('a README section comes without its heading, links resolved', () => {
  const section = readmeSection('Getting started');
  assert.ok(!section.startsWith('## '));
  assert.ok(section.includes('(/docs/getting-started/#prerequisites)'));
  assert.ok(section.includes('### Typical session flow'));
  assert.throws(() => readmeSection('No such section'), /README\.md: section "No such section" not found/);
});

test('the release table is the README release history, newest first, one row per notes file', () => {
  const rows = releaseTable();
  const raw = rawSection('Release history').split('\n').filter((l) => /^\| \[/.test(l));
  assert.equal(rows.length, raw.length);
  rows.forEach((row, i) => {
    assert.ok(raw[i].includes(`](${row.file})`), `${row.file} is not row ${i + 1}`);
    assert.ok(raw[i].includes(`| ${row.date} |`) && raw[i].includes(`| ${row.summary} |`));
    if (row.version) assert.ok(raw[i].startsWith(`| [v${row.version}]`));
  });
  assert.equal(new Set(rows.map((r) => r.file)).size, rows.length);
});
