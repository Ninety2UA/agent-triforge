// Where the repo is, and the plugin facts every page shares. Every data module reads repo files through
// these paths, so the site builds the same from site/ (astro, Vercel) and from the repo root
// (node --test). Plain Node, no astro: imports.
//
// Exports
//   findRepoRoot(start?)   the nearest folder at or above `start` holding .claude-plugin/plugin.json and README.md
//   REPO, SITE, PUBLIC     the repo root, site/ and site/public/
//   readPlugin(root?)      .claude-plugin/plugin.json, parsed
//   GH                     the plugin's `repository` URL without a trailing slash
//   VERSION                the plugin's `version`
//   read(root, path)       a repo file's text; `path` is repo-relative with forward slashes
//   exists(root, path), isDir(root, path)
import { existsSync, readFileSync, statSync } from 'node:fs';
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

/** @param {string} [root] */
export function readPlugin(root = REPO) {
  return JSON.parse(readFileSync(join(root, '.claude-plugin', 'plugin.json'), 'utf8'));
}

const plugin = readPlugin();
export const GH = String(plugin.repository).replace(/\/+$/, '');
export const VERSION = String(plugin.version);

/** @param {string} root @param {string} path */
export function read(root, path) {
  return readFileSync(join(root, path), 'utf8');
}

/** @param {string} root @param {string} path */
export function exists(root, path) {
  return existsSync(join(root, path));
}

/** @param {string} root @param {string} path */
export function isDir(root, path) {
  try {
    return statSync(join(root, path)).isDirectory();
  } catch {
    return false;
  }
}
