// The inventory of repo sources the site publishes: which skills, personas, release notes and docs
// pages exist, and what identifies each one. No link rewriting here, so the route table (routes.mjs)
// can build on it, and the modules that render content (skills.mjs, personas.mjs, releases.mjs,
// docs.mjs) can build on both. Plain Node, no astro: imports.
//
// Exports
//   listSkillFolders(root)       sorted folder names under skills/ that hold a SKILL.md
//   listPersonaNames(root)       sorted names of personas/*.md
//   personaGroupLabel(heading)   a docs/personas.md group heading without its "(N)" count
//   readPersonaGroups(root)      the groups of docs/personas.md: [{ key, label, anchor, slug, rows }], one per
//                                H2 with a table. label is the heading without its "(N)" count, key and
//                                anchor its slug ("Review specialists (6)" -> "review-specialists"), slug
//                                the heading's own GitHub anchor. rows: [{ name, summary }], name from the
//                                row's personas/<name>.md link, summary the last cell.
//   readDocPagesList(root)       DOC_PAGES from scripts/validate-versions.sh, read as text (never run)
//   UNTAGGED                     release versions that have no git tag
//   releaseRef(version)          the git ref a release note's links point at: v<version>, or main for an
//                                untagged version or an unversioned note
//   releaseAnchor(note)          "v4-1-1" for 4.1.1; the date ("2026-04-02") for an unversioned note
//   parseReleaseHeader(line, file)  { date, version, title } from "# <YYYY-MM-DD> — v<version>: <title>"
//                                or "# <YYYY-MM-DD> — <title>": split on the first " — ", then an optional
//                                "v<version>: "; the title's first letter capitalized, as
//                                scripts/release-notes.sh --title does
//   compareVersions(a, b)        semver order, for sort()
//   orderReleases(notes)         newest first: versioned notes by version, each unversioned note placed by
//                                its date, after every versioned note of the same date or later
//   listReleaseNotes(root)       orderReleases over docs/releases/*.md: [{ file, date, version, title, anchor, ref }]
import { readdirSync } from 'node:fs';
import { join } from 'node:path';

import { exists, read } from './repo.mjs';
import { capitalize, githubSlug, parseHeadings, parseTables } from './text.mjs';

export function listSkillFolders(root) {
  return readdirSync(join(root, 'skills'), { withFileTypes: true })
    .filter((d) => d.isDirectory() && exists(root, `skills/${d.name}/SKILL.md`))
    .map((d) => d.name)
    .sort();
}

export function listPersonaNames(root) {
  return readdirSync(join(root, 'personas'))
    .filter((f) => f.endsWith('.md'))
    .map((f) => f.slice(0, -3))
    .sort();
}

/** A persona group's heading without its count: "Review specialists (6)" -> "Review specialists". */
export function personaGroupLabel(heading) {
  return heading.replace(/\s*\(\d+\)\s*$/, '');
}

export function readPersonaGroups(root) {
  const file = 'docs/personas.md';
  const text = read(root, file);
  const lines = text.split('\n');
  const groups = [];
  for (const h of parseHeadings(text).filter((h) => h.depth === 2)) {
    const table = parseTables(lines.slice(h.line + 1, h.end))[0];
    if (!table) continue;
    const label = personaGroupLabel(h.text);
    const key = githubSlug(label);
    const rows = table.rows.map((cells) => {
      const name = cells[0].match(/\]\((?:\.\.\/)?personas\/([^/)#]+)\.md\)/)?.[1];
      if (!name) throw new Error(`${file} "${h.text}": the row "${cells[0]}" does not link to a personas/<name>.md file`);
      return { name, summary: cells[cells.length - 1] };
    });
    groups.push({ key, label, anchor: key, slug: h.slug, rows });
  }
  if (!groups.length) throw new Error(`${file}: no persona group (an H2 with a table)`);
  return groups;
}

export function readDocPagesList(root) {
  const file = 'scripts/validate-versions.sh';
  const m = read(root, file).match(/^DOC_PAGES='([^']*)'/m);
  if (!m) throw new Error(`${file}: no DOC_PAGES='...' line`);
  return m[1].split(/\s+/).filter(Boolean);
}

// Versions whose notes were written but never tagged (git tag: no v2.4.0, v2.4.2 or v2.4.3). Vercel's
// shallow clone has no tags, so the build cannot ask git; tests keep this list honest.
export const UNTAGGED = ['2.4.0', '2.4.2', '2.4.3'];

/** @param {string | null} version */
export function releaseRef(version) {
  return version && !UNTAGGED.includes(version) ? `v${version}` : 'main';
}

/** @param {{ version: string | null, date: string }} note */
export function releaseAnchor({ version, date }) {
  return version ? `v${version.replace(/\./g, '-')}` : date;
}

export function parseReleaseHeader(line, file) {
  const m = line.match(/^# (.+?) — (.+)$/);
  const date = m?.[1].trim();
  if (!m || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    throw new Error(`${file}: the first line is not "# <YYYY-MM-DD> — v<version>: <title>" or "# <YYYY-MM-DD> — <title>"`);
  }
  const versioned = m[2].match(/^v(\d+\.\d+\.\d+): (.*)$/);
  const title = (versioned ? versioned[2] : m[2]).trim();
  return { date, version: versioned ? versioned[1] : null, title: capitalize(title) };
}

export function compareVersions(a, b) {
  const pa = a.split('.').map(Number);
  const pb = b.split('.').map(Number);
  for (let i = 0; i < 3; i++) if (pa[i] !== pb[i]) return pa[i] - pb[i];
  return 0;
}

/**
 * @template {{ version: string | null, date: string }} T
 * @param {T[]} notes
 * @returns {T[]}
 */
export function orderReleases(notes) {
  const out = notes.filter((n) => n.version).sort((a, b) => compareVersions(b.version, a.version));
  const loose = notes.filter((n) => !n.version).sort((a, b) => b.date.localeCompare(a.date));
  for (const note of loose) {
    const at = out.findIndex((n) => n.date < note.date);
    out.splice(at === -1 ? out.length : at, 0, note);
  }
  return out;
}

const releaseCache = new Map();

export function listReleaseNotes(root) {
  if (releaseCache.has(root)) return releaseCache.get(root);
  const notes = readdirSync(join(root, 'docs', 'releases'))
    .filter((f) => f.endsWith('.md'))
    .map((f) => {
      const file = `docs/releases/${f}`;
      const header = parseReleaseHeader(read(root, file).split('\n')[0], file);
      return { file, ...header, anchor: releaseAnchor(header), ref: releaseRef(header.version) };
    });
  const seen = new Map();
  for (const note of notes) {
    // two notes with one anchor would send a link to the wrong release
    if (seen.has(note.anchor)) throw new Error(`${note.file} and ${seen.get(note.anchor)} share the changelog anchor "${note.anchor}"`);
    seen.set(note.anchor, note.file);
  }
  const ordered = orderReleases(notes);
  releaseCache.set(root, ordered);
  return ordered;
}
