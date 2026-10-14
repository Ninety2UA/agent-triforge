// Where the repo is. Every data module reads repo files through these paths, so the site builds the
// same from site/ (astro, Vercel) and from the repo root (node --test). Plain Node, no astro: imports.
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

/** The nearest folder at or above `start` holding .claude-plugin/plugin.json and README.md. */
export function findRepoRoot(start = process.cwd()) {
  for (let dir = start; ; dir = dirname(dir)) {
    if (existsSync(join(dir, '.claude-plugin', 'plugin.json')) && existsSync(join(dir, 'README.md'))) return dir;
    if (dirname(dir) === dir) throw new Error(`no Agent Triforge repo at or above ${start}`);
  }
}

export const REPO = findRepoRoot();
export const SITE = join(REPO, 'site');
export const PUBLIC = join(SITE, 'public');
