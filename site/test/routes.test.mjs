// The route table (KTD2): each relative link resolves against its own source file, in Markdown and in
// raw HTML, code is left alone, and a link to nothing stops the build naming the file. Expected GitHub
// URLs are built from .claude-plugin/plugin.json, skill folders read from the tree.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { REPO } from '../src/lib/repo.mjs';
import { githubUrl, resolveLink, rewriteLinks } from '../src/lib/routes.mjs';

const GITHUB = JSON.parse(readFileSync(join(REPO, '.claude-plugin/plugin.json'), 'utf8')).repository.replace(/\/$/, '');
const WORKFLOWS = 'docs/workflows.md';

test('links written in docs/workflows.md resolve to their site pages', () => {
  assert.equal(resolveLink(WORKFLOWS, '../skills/at-ship/SKILL.md'), '/skills/at-ship/');
  assert.equal(resolveLink(WORKFLOWS, '../personas/security-sentinel.md'), '/skills/personas/#security-sentinel');
  assert.equal(resolveLink(WORKFLOWS, 'team-work.md#review-swarm-at-review'), '/guides/team-builds/#review-swarm-at-review');
  assert.equal(resolveLink(WORKFLOWS, '../README.md#faq'), '/docs/faq/');
  assert.equal(resolveLink(WORKFLOWS, '../README.md#recent-changes'), '/changelog/');
  // the back-link to the README's Documentation section has no place on the site
  assert.equal(resolveLink(WORKFLOWS, '../README.md#documentation'), null);
});

test('a removed link keeps its text, in Markdown and in raw HTML', () => {
  assert.equal(rewriteLinks('[← Agent Triforge](../README.md#documentation)', WORKFLOWS), '← Agent Triforge');
  assert.equal(rewriteLinks('see <a href="#documentation">the docs</a>', 'README.md'), 'see the docs');
});

test('the persona group anchor drops its count, so the legacy #review-specialists-6 still lands', () => {
  assert.equal(resolveLink(WORKFLOWS, 'personas.md#review-specialists-6'), '/skills/personas/#review-specialists');
});

test("a skill's references/ file resolves to GitHub blob/main; a folder to tree/main", () => {
  const skills = readdirSync(join(REPO, 'skills')).filter((name) => existsSync(join(REPO, 'skills', name, 'references', 'claude.md')));
  assert.ok(skills.length > 0, 'no skill has references/claude.md');
  for (const name of skills) {
    assert.equal(resolveLink(`skills/${name}/SKILL.md`, 'references/claude.md'), `${GITHUB}/blob/main/skills/${name}/references/claude.md`);
  }
  assert.equal(resolveLink(WORKFLOWS, '../skills/'), `${GITHUB}/tree/main/skills`);
  assert.equal(githubUrl('ops/solutions/'), `${GITHUB}/tree/main/ops/solutions`);
  assert.equal(resolveLink(WORKFLOWS, '../ops/STATE.md'), `${GITHUB}/blob/main/ops/STATE.md`);
});

test('a link inside fenced code or inline code is left unchanged', () => {
  const link = '[at-ship](../skills/at-ship/SKILL.md)';
  const source = ['```markdown', link, '```', '', link, '', `Write \`${link}\` to link a skill.`].join('\n');
  const out = rewriteLinks(source, WORKFLOWS).split('\n');
  assert.equal(out[1], link, 'fenced code changed');
  assert.equal(out[4], '[at-ship](/skills/at-ship/)', 'prose link not rewritten');
  assert.equal(out[6], `Write \`${link}\` to link a skill.`, 'inline code changed');
  // a link whose label is code is still a link
  assert.equal(rewriteLinks('[`at-ship`](../skills/at-ship/SKILL.md)', WORKFLOWS), '[`at-ship`](/skills/at-ship/)');
});

test("the README FAQ's raw-HTML links resolve against the repo root", () => {
  assert.equal(resolveLink('README.md', 'docs/installation.md#installation'), '/docs/getting-started/#installation');
  const faq = '<a href="docs/installation.md#installation">Installation</a> and <a href="skills/at-setup/SKILL.md"><code>at-setup</code></a>';
  assert.equal(
    rewriteLinks(faq, 'README.md'),
    '<a href="/docs/getting-started/#installation">Installation</a> and <a href="/skills/at-setup/"><code>at-setup</code></a>',
  );
});

test('an anchor that matches no heading throws, naming the file and the anchor', () => {
  assert.throws(() => resolveLink(WORKFLOWS, 'team-work.md#no-such-heading'), /docs\/workflows\.md.*#no-such-heading/);
  assert.throws(() => resolveLink(WORKFLOWS, '../README.md#no-such-heading'), /docs\/workflows\.md.*#no-such-heading/);
  // a file the site does not publish is checked too, before it goes to GitHub
  assert.throws(() => resolveLink('skills/at-build/SKILL.md', 'references/claude.md#no-such-heading'), /skills\/at-build\/SKILL\.md.*#no-such-heading/);
});

test('a link to a path that is not in the repository throws, naming the file', () => {
  assert.throws(() => resolveLink(WORKFLOWS, '../ops/NO-SUCH-FILE.md'), /docs\/workflows\.md.*ops\/NO-SUCH-FILE\.md.*not in the repository/);
  assert.throws(() => rewriteLinks('<img src="images/no-such.png">', WORKFLOWS), /docs\/workflows\.md.*images\/no-such\.png/);
});

test('absolute URLs and site paths pass through', () => {
  assert.equal(resolveLink(WORKFLOWS, 'https://github.com/openai/codex'), 'https://github.com/openai/codex');
  assert.equal(resolveLink(WORKFLOWS, '/guides/data-egress/'), '/guides/data-egress/');
});
