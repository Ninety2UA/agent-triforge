// site/scripts/ignore-build.sh, Vercel's ignored build step: it builds (exit 1) unless no input of the
// site changed since the last deployment, and it fails open. Each case runs the real script in a
// throwaway git repository shaped like this one.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { SITE } from '../src/lib/repo.mjs';

const SCRIPT = join(SITE, 'scripts', 'ignore-build.sh');

function repo() {
  const dir = mkdtempSync(join(tmpdir(), 'ignore-build-'));
  const git = (...args) => execFileSync('git', ['-c', 'user.email=t@example.com', '-c', 'user.name=t', '-c', 'commit.gpgsign=false', ...args], { cwd: dir, encoding: 'utf8' }).trim();
  const write = (path, text) => {
    mkdirSync(join(dir, path, '..'), { recursive: true });
    writeFileSync(join(dir, path), text);
  };
  git('init', '-q');
  for (const p of ['site/package.json', 'skills/at-ship/SKILL.md', 'docs/models.md', 'README.md', 'hooks/hooks.json']) write(p, 'one\n');
  git('add', '-A');
  git('commit', '-qm', 'base');
  const base = git('rev-parse', 'HEAD');
  const change = (path) => {
    write(path, 'two\n');
    git('add', '-A');
    git('commit', '-qm', `change ${path}`);
  };
  // Vercel runs the step from the project's root directory, site/
  const run = (env) => spawnSync('bash', [SCRIPT], { cwd: join(dir, 'site'), env: { PATH: process.env.PATH, ...env }, encoding: 'utf8' });
  return { dir, base, change, run, done: () => rmSync(dir, { recursive: true, force: true }) };
}

test('ignore-build builds when there is no previous deployment, or its commit is not in the clone', () => {
  const r = repo();
  try {
    assert.equal(r.run({}).status, 1);
    assert.equal(r.run({ VERCEL_GIT_PREVIOUS_SHA: '' }).status, 1);
    assert.equal(r.run({ VERCEL_GIT_PREVIOUS_SHA: '0123456789abcdef0123456789abcdef01234567' }).status, 1);
  } finally {
    r.done();
  }
});

test('ignore-build skips the build when only a path outside its inputs changed', () => {
  const r = repo();
  try {
    r.change('hooks/hooks.json');
    const out = r.run({ VERCEL_GIT_PREVIOUS_SHA: r.base });
    assert.equal(out.status, 0, out.stdout);
  } finally {
    r.done();
  }
});

test('ignore-build builds when a skill, a docs page or the site changed', () => {
  for (const path of ['skills/at-ship/SKILL.md', 'docs/models.md', 'site/package.json']) {
    const r = repo();
    try {
      r.change(path);
      assert.equal(r.run({ VERCEL_GIT_PREVIOUS_SHA: r.base }).status, 1, path);
    } finally {
      r.done();
    }
  }
});
