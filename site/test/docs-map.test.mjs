// The docs map (KTD4): every DOC_PAGES entry publishes exactly once, an unmapped entry publishes by
// itself, and the generated pages carry no README back-link and no relative link.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, posix } from 'node:path';

import { docPages, sectionPages } from '../src/lib/docs.mjs';
import { docsMap, PERSONAS_PAGE } from '../src/lib/docs-map.mjs';
import { REPO } from '../src/lib/repo.mjs';
import { resolveLink } from '../src/lib/routes.mjs';
import { parseHeadings } from '../src/lib/text.mjs';

const VALIDATOR = 'scripts/validate-versions.sh';
const docPagesList = (root = REPO) => readFileSync(join(root, VALIDATOR), 'utf8').match(/^DOC_PAGES='([^']*)'/m)[1].split(/\s+/).filter(Boolean);

test('every DOC_PAGES entry has exactly one route, and only DOC_PAGES entries are whole pages', () => {
  const listed = docPagesList();
  assert.ok(listed.length > 0);
  const { pages, fileRoutes } = docsMap();
  for (const file of listed) {
    const whole = pages.filter((p) => p.sources.includes(file));
    const homes = whole.length + (file === PERSONAS_PAGE.file ? 1 : 0);
    assert.equal(homes, 1, `${file} is the whole of ${homes} pages`);
    assert.ok(fileRoutes.has(file), `${file} has no route`);
  }
  assert.deepEqual([...fileRoutes.keys()].sort(), [...listed].sort());
});

test('pages that never publish: plans, brainstorms, the rule inventory, review findings and the design doc', () => {
  const sources = docsMap().pages.flatMap((p) => p.sources);
  for (const source of sources) {
    assert.ok(!/^docs\/(plans|brainstorms|residual-review-findings)\/|^docs\/rule-inventory\.md|^docs\/agent-triforge\.md/.test(source), source);
  }
  assert.match(resolveLink('docs/how-it-works.md', 'agent-triforge.md'), /^https:\/\/github\.com\/.+\/blob\/main\/docs\/agent-triforge\.md$/);
});

test('the Docs and Guides orders are the planned ones', () => {
  assert.deepEqual(
    sectionPages('docs').map((p) => [p.href, p.title]),
    [
      ['/docs/getting-started/', 'Getting started'],
      ['/docs/how-it-works/', 'How it works'],
      ['/docs/workflows/', 'Workflows'],
      ['/docs/project-layout/', 'Project layout'],
      ['/docs/portable-skills/', 'Portable skills'],
      ['/docs/compatibility/', 'Compatibility'],
      ['/docs/upgrading/', 'Upgrading'],
      ['/docs/faq/', 'FAQ'],
    ],
  );
  assert.deepEqual(
    sectionPages('guides').map((p) => [p.href, p.title]),
    [
      ['/guides/leases/', 'Leases and cross-review'],
      ['/guides/unattended-runs/', 'Unattended runs'],
      ['/guides/team-builds/', 'Team builds'],
      ['/guides/models-and-effort/', 'Models and effort'],
      ['/guides/data-egress/', 'Data egress'],
    ],
  );
});

test('a DOC_PAGES entry with no mapping gets /docs/<file name>/, its H1 as the title and its first paragraph as the intro', () => {
  const root = mkdtempSync(join(tmpdir(), 'triforge-docs-map-'));
  try {
    for (const path of ['README.md', '.claude-plugin', 'skills', 'personas', 'docs/releases']) cpSync(join(REPO, path), join(root, path), { recursive: true });
    for (const file of readdirSync(join(REPO, 'docs')).filter((f) => f.endsWith('.md'))) cpSync(join(REPO, 'docs', file), join(root, 'docs', file));
    mkdirSync(join(root, 'scripts'));
    const validator = readFileSync(join(REPO, VALIDATOR), 'utf8').replace(/^DOC_PAGES='([^']*)'/m, "DOC_PAGES='$1 docs/new-topic.md'");
    writeFileSync(join(root, VALIDATOR), validator);
    writeFileSync(
      join(root, 'docs/new-topic.md'),
      '[← Agent Triforge](../README.md#documentation)\n\n# A new topic\n\nWhat this page covers, in one paragraph.\n\n## First part\n\nBody text.\n',
    );

    const { pages, fileRoutes } = docsMap(root);
    const page = pages.find((p) => p.sources.includes('docs/new-topic.md'));
    assert.ok(page, 'the new DOC_PAGES entry has no page');
    assert.equal(page.href, '/docs/new-topic/');
    assert.equal(page.section, 'docs');
    assert.equal(page.title, 'A new topic');
    assert.equal(page.intro, 'What this page covers, in one paragraph.');
    assert.equal(page.parts.map((p) => p.text).join('\n\n'), '## First part\n\nBody text.');
    assert.equal(fileRoutes.get('docs/new-topic.md'), '/docs/new-topic/');
    // it joins the end of the Docs order, before the Guides
    const docs = pages.filter((p) => p.section === 'docs');
    assert.equal(docs.at(-1), page);
    assert.equal(resolveLink('docs/workflows.md', 'new-topic.md#first-part', { root }), '/docs/new-topic/#first-part');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('no generated page keeps the README back-link or a relative link, and every image resolves', () => {
  for (const page of docPages()) {
    for (const text of [page.intro, page.body]) {
      assert.ok(!text.includes('README.md#documentation') && !text.includes('← Agent Triforge'), `${page.slug} keeps the back-link`);
      const prose = text.replace(/```[\s\S]*?```/g, '').replace(/`[^`]*`/g, '');
      for (const [, bang, target] of prose.matchAll(/(!?)\[(?:\\.|[^\]\\])*\]\(([^)\s]+)\)/g)) {
        if (bang) {
          assert.ok(existsSync(join(REPO, posix.dirname(page.imageBase), target)), `${page.slug}: image ${target} is not next to ${page.imageBase}`);
        } else {
          assert.match(target, /^(https?:|\/)/, `${page.slug}: relative link ${target}`);
        }
      }
      for (const [, target] of prose.matchAll(/\bhref="([^"]+)"/g)) assert.match(target, /^(https?:|\/)/, `${page.slug}: relative href ${target}`);
    }
  }
});

test('every route into a docs page names a heading the composed page has', () => {
  const pages = new Map(docPages().map((p) => [p.href, new Set(parseHeadings(p.body).map((h) => h.slug))]));
  const { anchors } = docsMap();
  let checked = 0;
  for (const [file, map] of anchors) {
    for (const url of map.values()) {
      if (typeof url !== 'string' || !url.includes('#')) continue;
      const [href, slug] = url.split('#');
      if (!pages.has(href)) continue;
      checked++;
      assert.ok(pages.get(href).has(slug), `${file}: ${url} names no heading of the page`);
    }
  }
  assert.ok(checked > 0);
});

test('getting started joins the README steps and the install guide; data egress moves to its own guide', () => {
  const page = (slug) => docPages().find((p) => p.slug === slug);
  const start = page('getting-started');
  assert.deepEqual(start.sources, ['README.md#getting-started', 'docs/installation.md']);
  const headings = parseHeadings(start.body).map((h) => h.text);
  assert.ok(headings.includes('Typical session flow') && headings.includes('Prerequisites'), headings.join(', '));
  assert.equal(resolveLink('README.md', '#typical-session-flow'), '/docs/getting-started/#typical-session-flow');

  const egress = page('data-egress');
  const how = page('how-it-works');
  const section = readFileSync(join(REPO, 'docs/how-it-works.md'), 'utf8').split('## Data egress and credentials\n')[1].trim();
  const firstSentence = section.split('. ')[0];
  assert.ok(egress.intro.startsWith(firstSentence), 'the guide intro is the section’s first paragraph');
  assert.ok(!how.body.includes(firstSentence), 'how it works repeats the data egress section');
  assert.match(how.body, /\(\/guides\/data-egress\/\)/);
  assert.equal(resolveLink('docs/models.md', 'how-it-works.md#data-egress-and-credentials'), '/guides/data-egress/');
});
