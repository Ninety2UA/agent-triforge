// The changelog (R2): release-note headers, order, anchors, and where their links go. Untagged versions
// are a static list (Vercel's clone has no tags), checked here against `git tag` when tags are present.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

import { releaseTable } from '../src/lib/readme.mjs';
import { getReleases, orderReleases, parseReleaseHeader, UNTAGGED } from '../src/lib/releases.mjs';
import { REPO } from '../src/lib/repo.mjs';
import { RELEASED, VERSION } from '../src/lib/site.mjs';

const GITHUB = JSON.parse(readFileSync(join(REPO, '.claude-plugin/plugin.json'), 'utf8')).repository.replace(/\/$/, '');
const notes = readdirSync(join(REPO, 'docs/releases')).filter((f) => f.endsWith('.md'));
const header = (file) => readFileSync(join(REPO, 'docs/releases', file), 'utf8').split('\n')[0];

test('a title with more dashes parses whole: the header splits on its first " — " and its "v<version>: "', () => {
  const raw = header('v2.4.0.md');
  assert.ok(raw.split(' — ').length > 2, 'the v2.4.0 header no longer has extra dashes; pick another note');
  const parsed = parseReleaseHeader(raw, 'docs/releases/v2.4.0.md');
  const title = raw.slice(raw.indexOf(': ') + 2);
  assert.deepEqual(parsed, { date: raw.slice(2, 12), version: '2.4.0', title: title[0].toUpperCase() + title.slice(1) });
  assert.deepEqual(parseReleaseHeader('# 2026-01-02 — v9.8.7: one — two — three', 'x.md'), { date: '2026-01-02', version: '9.8.7', title: 'One — two — three' });
  assert.deepEqual(parseReleaseHeader('# 2026-01-02 — An unversioned note — with a dash', 'x.md'), { date: '2026-01-02', version: null, title: 'An unversioned note — with a dash' });
  assert.throws(() => parseReleaseHeader('# v1.2.3: no date', 'docs/releases/bad.md'), /docs\/releases\/bad\.md/);
});

test('every note publishes; an unversioned note gets its date as its anchor, a versioned one v<x-y-z>', () => {
  const releases = getReleases();
  assert.deepEqual(releases.map((r) => r.file).sort(), notes.map((f) => `docs/releases/${f}`).sort());
  for (const release of releases) {
    if (release.version) {
      assert.equal(release.anchor, `v${release.version.replace(/\./g, '-')}`);
      assert.equal(release.file, `docs/releases/v${release.version}.md`);
    } else {
      assert.equal(release.anchor, release.date);
    }
  }
  assert.ok(releases.some((r) => !r.version), 'no unversioned note left to test');
  assert.equal(new Set(releases.map((r) => r.anchor)).size, releases.length, 'two notes share an anchor');
});

test('notes on the same date are ordered by version; an unversioned note follows the versioned notes of its date', () => {
  const synthetic = [
    { version: '1.0.0', date: '2026-01-01' },
    { version: null, date: '2026-01-02' },
    { version: '1.1.0', date: '2026-01-02' },
    { version: '1.2.0', date: '2026-01-02' },
    { version: '1.10.0', date: '2026-02-01' },
    { version: null, date: '2025-12-31' },
  ];
  assert.deepEqual(
    orderReleases(synthetic).map((n) => n.version ?? n.date),
    ['1.10.0', '1.2.0', '1.1.0', '2026-01-02', '1.0.0', '2025-12-31'],
  );
  // the real notes: the order the README release history lists them in
  assert.deepEqual(getReleases().map((r) => r.file), releaseTable().map((r) => r.file));
});

test("an untagged version's links point at blob/main, a tagged version's at blob/v<version>", () => {
  const releases = getReleases();
  const linksOf = (text) => [...text.matchAll(new RegExp(`${GITHUB}/(?:blob|tree)/([^/]+)/`, 'g'))].map((m) => m[1]);
  let tagged = 0;
  let untagged = 0;
  for (const release of releases) {
    const refs = new Set(linksOf(release.body));
    const raw = readFileSync(join(REPO, release.file), 'utf8');
    const relative = (raw.match(/\]\(\.\.\/\.\.\//g) ?? []).length;
    if (!relative) continue;
    const expected = release.version && !UNTAGGED.includes(release.version) ? `v${release.version}` : 'main';
    assert.ok(refs.has(expected), `${release.file}: no link at ${expected}`);
    // a GitHub URL the note already wrote out stays as written
    const at = (text) => linksOf(text).filter((ref) => ref === expected).length;
    assert.equal(at(release.body) - at(raw), relative, `${release.file}: not every relative link went to ${expected}`);
    if (expected === 'main') untagged++;
    else tagged++;
  }
  assert.ok(tagged > 0 && untagged > 0, `tagged ${tagged}, untagged ${untagged}`);
  assert.ok(!releases.some((r) => /\]\(\.\.\//.test(r.body)), 'a note keeps a relative link');
});

test('the untagged list matches git tags', (t) => {
  let tags;
  try {
    tags = execFileSync('git', ['-C', REPO, 'tag', '--list', 'v*'], { encoding: 'utf8' }).split('\n').filter(Boolean);
  } catch {
    tags = [];
  }
  if (!tags.length) {
    t.skip('git has no tags here (a shallow clone); UNTAGGED is checked where tags exist');
    return;
  }
  const versions = getReleases().filter((r) => r.version).map((r) => r.version);
  const missing = versions.filter((v) => !tags.includes(`v${v}`));
  assert.deepEqual([...UNTAGGED].sort(), missing.sort());
});

test('each note carries its README summary; RELEASED and VERSION come from the newest note and plugin.json', () => {
  const rows = new Map(releaseTable().map((r) => [r.file, r.summary]));
  for (const release of getReleases()) assert.equal(release.summary, rows.get(release.file) ?? release.title, release.file);
  const newest = getReleases()[0];
  assert.equal(RELEASED, newest.date);
  assert.equal(VERSION, JSON.parse(readFileSync(join(REPO, '.claude-plugin/plugin.json'), 'utf8')).version);
  assert.equal(newest.version, VERSION, 'the newest note is not the plugin version');
});
