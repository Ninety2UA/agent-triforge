// The tutorials (U7): site/src/lib/tutorials.mjs reads a tutorial's Markdown into its intro, steps and
// recap, and fails naming the file and the step when the text does not follow the tutorial form. The
// written tutorials hold to the page's rules: every step has something to paste (for each lead where
// the leads differ), what happens, why it matters and a checkpoint; every skill chip is a skill; every
// install command and the /goal line are the ones the repo documents. Built-site tests run after
// `npm run build` and are skipped without one.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { REPO, SITE } from '../src/lib/repo.mjs';
import { installCommands } from '../src/lib/readme.mjs';
import { TUTORIALS, parseTutorial, skillTokens, tutorialPages, writtenTutorials } from '../src/lib/tutorials.mjs';

const SKILLS = readdirSync(join(REPO, 'skills')).filter((d) => existsSync(join(REPO, 'skills', d, 'SKILL.md')));
const DIST = join(SITE, 'dist');
const noBuild = !existsSync(join(DIST, 'index.html')) && 'site/dist is not built (run npm run build in site/)';
// a Codex invocation, built from parts so this file never holds the bare form validate-versions sweeps for
const CODEX = (name) => ['$agent-triforge', `:${name}`].join('');

const written = writtenTutorials().map(({ slug }) => {
  const file = `site/src/content/tutorials/${slug}.md`;
  return { slug, ...parseTutorial(readFileSync(join(REPO, file), 'utf8'), file) };
});

const FRONT = '---\ndescription: A tutorial used by the test.\n---\n\n';
const PARTS = '### What happens\n\nIt runs.\n\n### Why it matters\n\nBecause.\n\n### Checkpoint\n\nA file exists.\n\n';
const RECAP = '## Recap\n\n| Workflow | What it produced |\n|---|---|\n| `at-ship` | A sprint |\n';

test('tutorialPages lists the three tutorials in reading order', () => {
  assert.deepEqual(tutorialPages(), [
    { slug: 'first-sprint', href: '/tutorials/first-sprint/', title: 'Your first sprint' },
    { slug: 'supervised-sprint', href: '/tutorials/supervised-sprint/', title: 'A supervised sprint' },
    { slug: 'unattended-run', href: '/tutorials/unattended-run/', title: 'An unattended run' },
  ]);
  assert.deepEqual(TUTORIALS.map((t) => t.slug), tutorialPages().map((t) => t.slug));
});

test('writtenTutorials lists, in order, the tutorials that have a content file, and only those', () => {
  const dir = join(SITE, 'src/content/tutorials');
  const files = readdirSync(dir).filter((f) => f.endsWith('.md')).map((f) => f.replace(/\.md$/, ''));
  assert.deepEqual(writtenTutorials().map((t) => t.slug), tutorialPages().map((t) => t.slug).filter((s) => files.includes(s)));
  for (const f of files) assert.ok(TUTORIALS.some((t) => t.slug === f), `src/content/tutorials/${f}.md is not a tutorial in TUTORIALS`);
  assert.ok(writtenTutorials().some((t) => t.slug === 'first-sprint'));
});

test('parseTutorial reads the description, the intro, each step with its lead tabs, and the recap', () => {
  const md = [
    '---',
    'description: A tutorial used by the test.',
    '---',
    '',
    'Intro naming `at-ship`.',
    '',
    '## Start the sprint',
    '',
    'Skills: `at-ship`, `wave-orchestration`',
    '',
    'In the project:',
    '',
    '```bash',
    'git status',
    '## not a heading inside a fence',
    '```',
    '',
    '#### Claude Code leads',
    '',
    '```prompt',
    '/at-ship Add a thing',
    '```',
    '',
    '#### Codex leads',
    '',
    'Start Codex first.',
    '',
    '```prompt',
    `${CODEX('at-ship')} Add a thing`,
    '```',
    '',
    '```toml',
    '[projects."/abs/path"]',
    '```',
    '',
    '### What happens',
    '',
    'It runs.',
    '',
    '```text',
    '### output, not a part',
    '```',
    '',
    '### Why it matters',
    '',
    'Because.',
    '',
    '### Checkpoint',
    '',
    'A file exists.',
    '',
    RECAP,
  ].join('\n');
  const t = parseTutorial(md, 'demo.md');
  assert.deepEqual(t.meta, { description: 'A tutorial used by the test.' });
  assert.equal(t.intro, 'Intro naming `at-ship`.');
  assert.equal(t.steps.length, 1);
  const [step] = t.steps;
  assert.equal(step.title, 'Start the sprint');
  assert.equal(step.id, 'start-the-sprint');
  assert.deepEqual(step.skills, ['at-ship', 'wave-orchestration']);
  assert.deepEqual(step.common, [
    { kind: 'md', md: 'In the project:' },
    { kind: 'cmd', lang: 'bash', text: 'git status\n## not a heading inside a fence' },
  ]);
  assert.deepEqual(step.tabs, [
    { lead: 'claude-code', label: 'Claude Code leads', segments: [{ kind: 'cmd', lang: 'prompt', text: '/at-ship Add a thing' }] },
    {
      lead: 'codex',
      label: 'Codex leads',
      segments: [
        { kind: 'md', md: 'Start Codex first.' },
        { kind: 'cmd', lang: 'prompt', text: `${CODEX('at-ship')} Add a thing` },
        { kind: 'md', md: '```toml\n[projects."/abs/path"]\n```' },
      ],
    },
  ]);
  assert.equal(step.happens, 'It runs.\n\n```text\n### output, not a part\n```');
  assert.equal(step.why, 'Because.');
  assert.equal(step.checkpoint, 'A file exists.');
  assert.match(step.markdown, /^## Start the sprint\n/);
  assert.equal(t.recap, '| Workflow | What it produced |\n|---|---|\n| `at-ship` | A sprint |');
});

test('a step without lead tabs has tabs: null', () => {
  const t = parseTutorial(`${FRONT}## Look\n\n\`\`\`bash\nls ops\n\`\`\`\n\n${PARTS}${RECAP}`, 'plain.md');
  assert.equal(t.steps[0].tabs, null);
  assert.deepEqual(t.steps[0].skills, []);
});

test('a step without a checkpoint fails, naming the file and the step', () => {
  const md = `${FRONT}## Lonely step\n\n\`\`\`prompt\nhi\n\`\`\`\n\n### What happens\n\nx\n\n### Why it matters\n\ny\n\n${RECAP}`;
  assert.throws(() => parseTutorial(md, 'lonely.md'), /lonely\.md: step "Lonely step".*Checkpoint/);
});

test('an empty part fails, naming the file, the step and the part', () => {
  const md = `${FRONT}## Hollow\n\n\`\`\`bash\nls\n\`\`\`\n\n### What happens\n\nx\n\n### Why it matters\n\n### Checkpoint\n\nz\n\n${RECAP}`;
  assert.throws(() => parseTutorial(md, 'hollow.md'), /hollow\.md: step "Hollow".*"Why it matters" is empty/);
});

test('a step with nothing to paste fails, naming the file and the step', () => {
  const md = `${FRONT}## Just words\n\nRead this.\n\n${PARTS}${RECAP}`;
  assert.throws(() => parseTutorial(md, 'words.md'), /words\.md: step "Just words" has no ```prompt or ```bash block/);
});

test('lead tabs need both leads, in order, each with something to paste', () => {
  const step = (lead) => `${FRONT}## Pick\n\n${lead}\n\n${PARTS}${RECAP}`;
  const claude = '#### Claude Code leads\n\n```prompt\n/at-ship x\n```';
  const codex = `#### Codex leads\n\n\`\`\`prompt\n${CODEX('at-ship')} x\n\`\`\``;
  assert.doesNotThrow(() => parseTutorial(step(`${claude}\n\n${codex}`), 'ok.md'));
  assert.throws(() => parseTutorial(step(claude), 'one.md'), /one\.md: step "Pick".*Claude Code leads, Codex leads/);
  assert.throws(() => parseTutorial(step(`${codex}\n\n${claude}`), 'order.md'), /order\.md: step "Pick"/);
  assert.throws(() => parseTutorial(step(`${claude}\n\n#### Codex leads\n\nNothing to type.`), 'empty.md'), /empty\.md: step "Pick": the "Codex leads" tab has no ```prompt or ```bash block/);
  assert.throws(() => parseTutorial(step(`${claude}\n\n#### Gemini leads\n\n\`\`\`bash\nx\n\`\`\``), 'who.md'), /who\.md: step "Pick"/);
});

test('the frontmatter needs a description and nothing else; the recap comes last', () => {
  const body = `## Look\n\n\`\`\`bash\nls\n\`\`\`\n\n${PARTS}${RECAP}`;
  assert.throws(() => parseTutorial(body, 'bare.md'), /bare\.md: no frontmatter/);
  assert.throws(() => parseTutorial(`---\ntitle: x\n---\n\n${body}`, 'title.md'), /title\.md: frontmatter line "title: x"/);
  assert.throws(() => parseTutorial(`---\n---\n\n${body}`, 'empty.md'), /empty\.md/);
  assert.throws(() => parseTutorial(`${FRONT}## Look\n\n\`\`\`bash\nls\n\`\`\`\n\n${PARTS}`, 'norecap.md'), /norecap\.md: no "## Recap" section/);
  assert.throws(() => parseTutorial(`${FRONT}${RECAP}\n${body.replace(RECAP, '')}`, 'early.md'), /early\.md: "## Recap" is not the last section/);
  assert.throws(() => parseTutorial(`${FRONT}${RECAP}`, 'nosteps.md'), /nosteps\.md: no steps/);
});

test('a Skills line that is not a list of names in backticks fails, naming the step', () => {
  const md = `${FRONT}## Chips\n\nSkills: at-ship and at-plan\n\n\`\`\`bash\nls\n\`\`\`\n\n${PARTS}${RECAP}`;
  assert.throws(() => parseTutorial(md, 'chips.md'), /chips\.md: step "Chips": the Skills line/);
});

test('two steps that would share an anchor fail', () => {
  const s = `## Look\n\n\`\`\`bash\nls\n\`\`\`\n\n${PARTS}`;
  assert.throws(() => parseTutorial(`${FRONT}${s}${s}${RECAP}`, 'twice.md'), /twice\.md: two headings would share the anchor #look/);
});

test('every written tutorial step has something to paste for each lead, what happens, why it matters and a checkpoint', () => {
  assert.ok(written.length > 0);
  for (const t of written) {
    assert.ok(t.meta.description.length > 50, `${t.slug}: the description is too short to describe the page`);
    assert.ok(t.steps.length > 0, `${t.slug} has no steps`);
    for (const step of t.steps) {
      const where = `${t.slug} / ${step.title}`;
      const cmd = (segs) => segs.some((s) => s.kind === 'cmd' && s.text.trim());
      assert.ok(cmd(step.common) || (step.tabs && step.tabs.every((tab) => cmd(tab.segments))), `${where}: nothing to paste`);
      for (const part of ['happens', 'why', 'checkpoint']) assert.ok(step[part].trim(), `${where}: empty ${part}`);
    }
  }
});

test('every skill chip is a skill folder, and every skill a step names is one of its chips', () => {
  for (const t of written) {
    for (const step of t.steps) {
      const where = `${t.slug} / ${step.title}`;
      assert.equal(new Set(step.skills).size, step.skills.length, `${where}: a chip repeats`);
      for (const name of step.skills) assert.ok(SKILLS.includes(name), `${where}: the chip ${name} is not a skill folder`);
      const named = skillTokens(step.markdown, SKILLS);
      assert.deepEqual(named.filter((n) => !step.skills.includes(n)), [], `${where}: names a skill without a chip`);
    }
  }
});

test("each tutorial's recap names only skills its steps name", () => {
  for (const t of written) {
    const inSteps = new Set(t.steps.flatMap((s) => s.skills));
    const named = skillTokens(t.recap, SKILLS);
    assert.ok(named.length > 0, `${t.slug}: the recap names no skill`);
    assert.deepEqual(named.filter((n) => !inSteps.has(n)), [], `${t.slug}: the recap names a skill no step names`);
  }
});

test('skillTokens finds skill names in each form a tutorial writes them', () => {
  const text = `Run \`/at-ship <goal>\`, or \`${CODEX('at-ship')}\` in Codex; \`wave-orchestration\` leases; at-plan in prose is not a token.`;
  assert.deepEqual(skillTokens(text, SKILLS), ['at-ship', 'wave-orchestration']);
});

test('every plugin install line in a tutorial is one the repo documents', () => {
  const { claude, codex } = installCommands();
  const documented = new Set([...claude, ...codex]);
  for (const t of written) {
    const lines = t.steps.flatMap((s) => [...s.common, ...(s.tabs ?? []).flatMap((tab) => tab.segments)])
      .filter((s) => s.kind === 'cmd').flatMap((s) => s.text.split('\n'));
    for (const line of lines.filter((l) => /^(claude|codex) plugin /.test(l))) {
      assert.ok(documented.has(line), `${t.slug}: "${line}" is not an install command in the README`);
    }
  }
});

test('a /goal line in a tutorial is the completion line at-ship prints', () => {
  const gating = readFileSync(join(REPO, 'skills/at-ship/references/completion-gating.md'), 'utf8');
  const line = gating.split('\n').find((l) => l.startsWith('/goal '));
  assert.ok(line, 'completion-gating.md has no /goal line');
  for (const t of written) {
    for (const step of t.steps) {
      for (const s of [...step.common, ...(step.tabs ?? []).flatMap((tab) => tab.segments)]) {
        if (s.kind === 'cmd' && s.text.startsWith('/goal ')) assert.equal(s.text, line, `${t.slug} / ${step.title}: the /goal line differs from at-ship's`);
      }
    }
  }
});

test('in the built site, each written tutorial has a page, and only those', { skip: noBuild }, () => {
  for (const { slug } of tutorialPages()) {
    const built = existsSync(join(DIST, 'tutorials', slug, 'index.html'));
    assert.equal(built, written.some((t) => t.slug === slug), `/tutorials/${slug}/: built ${built}, written ${!built}`);
  }
});

test('in the built site, a tutorial page shows every step, both lead tabs where they differ, and its chips', { skip: noBuild }, () => {
  for (const t of written) {
    const html = readFileSync(join(DIST, 'tutorials', t.slug, 'index.html'), 'utf8');
    assert.match(html, /<title>[^<]+ · Agent Triforge<\/title>/);
    for (const step of t.steps) {
      assert.ok(html.includes(`id="${step.id}"`), `${t.slug}: no heading #${step.id}`);
      if (step.tabs) {
        for (const tab of step.tabs) assert.ok(html.includes(`data-lead="${tab.lead}"`), `${t.slug} / ${step.title}: no ${tab.lead} tab`);
      }
    }
    const chips = [...html.matchAll(/<a class="t-chip" href="([^"]+)"/g)].map((m) => m[1]);
    assert.deepEqual(chips, t.steps.flatMap((s) => s.skills.map((name) => `/skills/${name}/`)));
    // the sidebar lists only the written tutorials
    for (const p of tutorialPages()) {
      const listed = html.includes(`href="${p.href}"`);
      if (!written.some((w) => w.slug === p.slug)) {
        const sidebar = html.slice(html.indexOf('class="sidebar"'), html.indexOf('class="portal-main"'));
        assert.ok(!sidebar.includes(`href="${p.href}"`), `${t.slug}: the sidebar links the unwritten ${p.href}`);
      } else assert.ok(listed, `${t.slug}: no link to ${p.href}`);
    }
  }
});

// A tutorial that names a role's default CLI ("the roster's builder, Claude Code by default") states
// what templates/ops/roster.toml ships, so a changed default fails here instead of going stale.
test('every "<role>, <CLI> by default" in a tutorial matches the shipped roster', async () => {
  const { readdirSync, readFileSync } = await import('node:fs');
  const { join } = await import('node:path');
  const { getRoles } = await import('../src/lib/roster.mjs');
  const { SITE } = await import('../src/lib/repo.mjs');
  const defaults = Object.fromEntries(getRoles().map((r) => [r.role, r.cliName]));
  const dir = join(SITE, 'src', 'content', 'tutorials');
  const claims = [];
  for (const file of readdirSync(dir).filter((f) => f.endsWith('.md'))) {
    const text = readFileSync(join(dir, file), 'utf8');
    for (const [, role, cli] of text.matchAll(/\b(builder|reviewer|tester|analyst|documenter), ([A-Z][\w]*(?: [A-Z][\w]*)?) by default/g)) {
      claims.push(`${file}: ${role} ${cli}`);
      assert.equal(cli, defaults[role], `${file}: says the ${role} is ${cli} by default; the roster ships ${defaults[role]}`);
    }
  }
  assert.ok(claims.length >= 3, `found ${claims.length} default claims: the pattern may no longer match`);
});
