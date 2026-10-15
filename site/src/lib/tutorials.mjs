// The tutorials: their reading order and names, and the strict reader for a tutorial's Markdown
// (site/src/content/tutorials/<slug>.md). Plain Node, no astro: imports; tested in
// site/test/tutorials.test.mjs. The tutorials collection (content.config.ts) renders each Markdown part
// and the page (pages/tutorials/[slug].astro) lays the steps out. Ported from Agent Blueprint's
// tutorial loader, with lead tabs in place of its recorded-run facts: these tutorials are written
// from the docs, not recorded.
//
// A tutorial file is written like this:
//
//   ---
//   description: the page's meta description, one line
//   ---
//
//   Intro (Markdown, no H2).
//
//   ## A step's title
//
//   Skills: `at-one`, `two`            optional: the step's skill chips, each linking to its page
//
//   Markdown with ```prompt blocks (typed into the lead's session) and ```bash blocks (run in a
//   terminal); each becomes a copyable command. Other fences stay Markdown.
//
//   #### Claude Code leads             optional, where the leads differ: both, in this order, each
//   #### Codex leads                   with its own Markdown and at least one command. They become
//                                      tabs that follow the reader's stored lead.
//
//   ### What happens
//   ### Why it matters
//   ### Checkpoint                     all three, in this order, none empty
//
//   ## Recap                           last: what each workflow or skill produced
//
// The frontmatter is plain `key: value` lines, not YAML. Headings and blocks inside fenced code are
// text, not structure.
//
// Exports
//   TUTORIALS                 [{ slug, title }] in reading order: every tutorial the site will have.
//   tutorialPages()           [{ slug, href, title }] for all of them, for the header and the footer.
//   writtenTutorials(root?)   the same, for the tutorials that have a content file: the pages that build
//                             and the ones the Tutorials sidebar lists.
//   parseTutorial(text, file) { meta, intro, steps, recap }. meta is { description }; intro and recap are
//                             Markdown; each step is { title, id, skills, common, tabs, happens, why,
//                             checkpoint, markdown }: common is the paste area before any lead tab, tabs
//                             is null or [{ lead, label, segments }] for Claude Code then Codex, and a
//                             segment is { kind: 'md', md } or { kind: 'cmd', lang: 'prompt' | 'bash', text }.
//                             markdown is the step's own text from its heading on. Throws naming the file
//                             (and the step) when the text does not follow the form above.
//   skillTokens(text, names)  the skills `text` names in code: `name`, `/name ...` or
//                             `$agent-triforge:name ...`, each once, in order of first mention.
import { existsSync } from 'node:fs';
import { join } from 'node:path';

import { REPO } from './repo.mjs';
import { githubSlug } from './text.mjs';
import { LEAD_TABS } from '../data/leads.mjs';

export const TUTORIALS = [
  { slug: 'first-sprint', title: 'Your first sprint' },
  { slug: 'supervised-sprint', title: 'A supervised sprint' },
  { slug: 'unattended-run', title: 'An unattended run' },
];

export function tutorialPages() {
  return TUTORIALS.map(({ slug, title }) => ({ slug, href: `/tutorials/${slug}/`, title }));
}

/** @param {string} [root] */
export function writtenTutorials(root = REPO) {
  return tutorialPages().filter(({ slug }) => existsSync(join(root, 'site', 'src', 'content', 'tutorials', `${slug}.md`)));
}

const META = ['description'];
const PARTS = [
  ['What happens', 'happens'],
  ['Why it matters', 'why'],
  ['Checkpoint', 'checkpoint'],
];
const COMMANDS = new Set(['prompt', 'bash']);
const FENCE_OPEN = /^(`{3,}|~{3,})\s*([\w-]*)/;

// The fence open after `line`, given the one open before it (null when none).
function fenceAfter(line, open) {
  if (open) {
    const close = line.trim().match(/^(`{3,}|~{3,})$/);
    return close && close[1][0] === open[0] && close[1].length >= open.length ? null : open;
  }
  return line.match(FENCE_OPEN)?.[1] ?? null;
}

// Lines split at headings that start with `prefix`, outside fenced code: [{ heading, lines }], the
// first chunk (before any such heading) with heading null.
function splitAt(lines, prefix) {
  const chunks = [{ heading: null, lines: [] }];
  let fence = null;
  for (const line of lines) {
    if (!fence && line.startsWith(prefix)) chunks.push({ heading: line.slice(prefix.length).trim(), lines: [] });
    else chunks.at(-1).lines.push(line);
    fence = fenceAfter(line, fence);
  }
  return chunks;
}

// Lines as text, without the blank lines at either end.
function text(lines) {
  const out = [...lines];
  while (out.length && !out[0].trim()) out.shift();
  while (out.length && !out.at(-1).trim()) out.pop();
  return out.join('\n');
}

// A paste area: Markdown runs and the ```prompt and ```bash blocks between them.
function segments(lines) {
  const out = [];
  let md = [];
  const flush = () => {
    if (text(md)) out.push({ kind: 'md', md: text(md) });
    md = [];
  };
  for (let i = 0; i < lines.length; i++) {
    const open = lines[i].match(FENCE_OPEN);
    if (!open) {
      md.push(lines[i]);
      continue;
    }
    const body = [];
    let j = i + 1;
    while (j < lines.length && fenceAfter(lines[j], open[1])) body.push(lines[j++]);
    if (COMMANDS.has(open[2])) {
      flush();
      out.push({ kind: 'cmd', lang: open[2], text: body.join('\n') });
    } else {
      md.push(...lines.slice(i, j + 1));
    }
    i = j;
  }
  flush();
  return out;
}

const hasCommand = (segs) => segs.some((s) => s.kind === 'cmd' && s.text.trim());

/**
 * @param {string} source
 * @param {string} file
 */
export function parseTutorial(source, file) {
  const fail = (message) => {
    throw new Error(`${file}: ${message}`);
  };
  const front = source.match(/^---\n([\s\S]*?)\n?---\n/);
  if (!front) fail('no frontmatter; the file starts with a --- block of key: value lines');
  const meta = {};
  for (const line of front[1].split('\n').filter((l) => l.trim())) {
    const m = line.match(/^([a-z]+): (\S.*)$/);
    if (!m || !META.includes(m[1])) fail(`frontmatter line "${line}" is not "key: value" with a key of ${META.join(', ')}`);
    meta[m[1]] = m[2].trim();
  }
  const missing = META.filter((key) => !(key in meta));
  if (missing.length) fail(`the frontmatter has no ${missing.join(', ')}`);

  const [intro, ...sections] = splitAt(source.slice(front[0].length).split('\n'), '## ');
  const recapAt = sections.findIndex((s) => s.heading === 'Recap');
  if (recapAt === -1) fail('no "## Recap" section');
  if (recapAt !== sections.length - 1) fail('"## Recap" is not the last section');
  if (recapAt === 0) fail('no steps before "## Recap"');

  const steps = sections.slice(0, recapAt).map(({ heading: title, lines }) => {
    const where = `step "${title}"`;
    const body = [...lines];
    while (body.length && !body[0].trim()) body.shift();
    let skills = [];
    const chips = body[0]?.match(/^Skills: (.*)$/);
    if (chips) {
      if (!/^`[^`]+`(?:, `[^`]+`)*$/.test(chips[1].trim())) fail(`${where}: the Skills line is not a comma-separated list of skill names in backticks`);
      skills = [...chips[1].matchAll(/`([^`]+)`/g)].map((s) => s[1]);
      body.shift();
    }

    const [paste, ...parts] = splitAt(body, '### ');
    const headings = parts.map((p) => p.heading);
    const expected = PARTS.map(([heading]) => heading);
    if (headings.join('|') !== expected.join('|')) {
      fail(`${where} has the parts ${headings.join(', ') || '(none)'}; it needs ${expected.join(', ')}, in that order`);
    }

    const [common, ...leadChunks] = splitAt(paste.lines, '#### ');
    let tabs = null;
    if (leadChunks.length) {
      const labels = leadChunks.map((c) => c.heading);
      if (labels.join('|') !== LEAD_TABS.map((l) => l.label).join('|')) {
        fail(`${where} has the lead tabs ${labels.join(', ')}; lead tabs are ${LEAD_TABS.map((l) => l.label).join(', ')}, both, in that order`);
      }
      tabs = LEAD_TABS.map(({ lead, label }, i) => {
        const segs = segments(leadChunks[i].lines);
        if (!hasCommand(segs)) fail(`${where}: the "${label}" tab has no \`\`\`prompt or \`\`\`bash block to paste`);
        return { lead, label, segments: segs };
      });
    }
    const commonSegs = segments(common.lines);
    if (!tabs && !hasCommand(commonSegs)) fail(`${where} has no \`\`\`prompt or \`\`\`bash block to paste`);

    const step = { title, id: githubSlug(title), skills, common: commonSegs, tabs };
    parts.forEach((part, i) => {
      const value = text(part.lines);
      if (!value) fail(`${where}: "${PARTS[i][0]}" is empty`);
      step[PARTS[i][1]] = value;
    });
    step.markdown = [`## ${title}`, ...lines].join('\n');
    return step;
  });

  const ids = steps.map((s) => s.id);
  const repeated = ids.find((id, i) => ids.indexOf(id) !== i || ['overview', 'recap'].includes(id));
  if (repeated) fail(`two headings would share the anchor #${repeated}; give the step another title`);

  return { meta, intro: text(intro.lines), steps, recap: text(sections[recapAt].lines) };
}

/**
 * @param {string} markdown
 * @param {string[]} names  every skill name
 */
export function skillTokens(markdown, names) {
  const known = new Set(names);
  const found = [];
  for (const [, span] of markdown.matchAll(/`([^`\n]+)`/g)) {
    for (const [, name] of span.matchAll(/(?:^|[\s(])(?:\/|\$agent-triforge:)?([a-z][a-z0-9-]*)(?=$|[\s)])/g)) {
      if (known.has(name) && !found.includes(name)) found.push(name);
    }
  }
  return found;
}
