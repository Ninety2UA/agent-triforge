// The escape plugin (ported from Agent Blueprint's site): raw HTML in a SKILL.md or a persona prompt
// renders as text, everywhere else it stays HTML.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

import escapeSkillHtmlIntegration, { escapeSkillHtml, isPersonaFile, isSkillFile } from '../src/lib/markdown/escape-skill-html.mjs';

const dirs = { skillsDir: join('/repo', 'skills'), personasDir: join('/repo', 'personas') };
const url = (...parts) => pathToFileURL(join('/repo', ...parts));
const factoryCtx = (fileURL) => ({ fileURL, sourceFormat: 'markdown', source: '', data: {} });
// the visitor context: only parent() is read
const visitCtx = (parent) => ({ parent: () => parent });

test('the plugin runs for skills/<name>/SKILL.md and personas/<name>.md only', () => {
  assert.equal(isSkillFile(url('skills', 'at-wrap', 'SKILL.md'), dirs.skillsDir), true);
  assert.equal(isSkillFile(url('skills', 'at-wrap', 'references', 'claude.md'), dirs.skillsDir), false);
  assert.equal(isSkillFile(url('site', 'skills', 'at-wrap', 'SKILL.md'), dirs.skillsDir), false);
  assert.equal(isSkillFile(undefined, dirs.skillsDir), false);
  assert.equal(isPersonaFile(url('personas', 'research-synthesizer.md'), dirs.personasDir), true);
  assert.equal(isPersonaFile(url('personas', 'manifest.toml'), dirs.personasDir), false);
  const factory = escapeSkillHtml(dirs);
  for (const file of [url('README.md'), url('docs', 'workflows.md'), url('docs', 'releases', 'v4.1.1.md'), undefined]) {
    assert.equal(factory(factoryCtx(file)), null, String(file));
  }
});

test('inline raw HTML in a SKILL.md paragraph becomes text, so <file or diff> stays visible', () => {
  const plugin = escapeSkillHtml(dirs)(factoryCtx(url('skills', 'at-wrap', 'SKILL.md')));
  assert.deepEqual(plugin.html({ type: 'html', value: '<base-branch>' }, visitCtx({ type: 'paragraph' })), { type: 'text', value: '<base-branch>' });
  const block = plugin.html({ type: 'html', value: '<details>\n<summary>x</summary>' }, visitCtx({ type: 'root' }));
  assert.deepEqual(block, { type: 'paragraph', children: [{ type: 'text', value: '<details>\n<summary>x</summary>' }] });
});

test('the integration adds the plugin to the Satteri processor and refuses any other processor', () => {
  const options = { mdastPlugins: [], hastPlugins: [], features: {} };
  escapeSkillHtmlIntegration(dirs).hooks['astro:config:setup']({ config: { markdown: { processor: { name: 'satteri', options } } } });
  assert.equal(options.mdastPlugins.length, 1);
  const other = { markdown: { processor: { name: 'unified', options: {} } } };
  assert.throws(() => escapeSkillHtmlIntegration(dirs).hooks['astro:config:setup']({ config: other }), /satteri/i);
});

test('rendered with Satteri, a placeholder and a command flag survive in a SKILL.md, and HTML stays HTML elsewhere', async () => {
  const { markdownToHtml } = await import('satteri');
  const factory = escapeSkillHtml(dirs);
  const render = (md, file) =>
    markdownToHtml(md, { mdastPlugins: [() => factory(factoryCtx(file))], hastPlugins: [], fileURL: file, features: { gfm: true, smartPunctuation: true } }).html;
  const skill = url('skills', 'at-wrap', 'SKILL.md');
  const out = render('Recoverable from <file or diff>; run node --prof, between 1–2 runs.', skill);
  assert.match(out, /&lt;file or diff&gt;/);
  assert.match(out, /node --prof/);
  assert.match(out, /1–2 runs/);
  assert.match(render('<details><summary>Q</summary></details>', url('README.md')), /<details>/);
});
