// The changelog: one entry per docs/releases/*.md, newest first. Plain Node, no astro: imports.
//
// The header "# <YYYY-MM-DD> — v<version>: <title>" (or "# <YYYY-MM-DD> — <title>" for the two
// unversioned notes) is split on its first " — ", so a title with more dashes stays whole. Versioned
// notes are ordered by version; an unversioned note sits by its date, below the versioned notes of the
// same day, and its anchor is its date. Links in a note go to GitHub at the release's tag, or at main
// for an untagged version (UNTAGGED) or an unversioned note (routes.mjs).
//
// Exports
//   getReleases(root?)   [{ version, date, title, anchor, file, ref, body, summary }]: version without
//                        the "v" (null for an unversioned note); anchor "v4-1-1" or the date; ref the git
//                        ref its links use; body the note after its header with links resolved; summary
//                        the README release-history row for the note, or its title when the README has
//                        no row for it
//   and, from sources.mjs: parseReleaseHeader, orderReleases, releaseAnchor, releaseRef, compareVersions, UNTAGGED
import { releaseTable } from './readme.mjs';
import { REPO, read } from './repo.mjs';
import { rewriteLinks } from './routes.mjs';
import { listReleaseNotes } from './sources.mjs';

export { UNTAGGED, compareVersions, orderReleases, parseReleaseHeader, releaseAnchor, releaseRef } from './sources.mjs';

const cache = new Map();

/** @param {string} [root] */
export function getReleases(root = REPO) {
  if (cache.has(root)) return cache.get(root);
  const rows = releaseTable(root);
  const releases = listReleaseNotes(root).map((note) => {
    const body = read(root, note.file).split('\n').slice(1).join('\n').trim();
    return {
      version: note.version,
      date: note.date,
      title: note.title,
      anchor: note.anchor,
      file: note.file,
      ref: note.ref,
      body: rewriteLinks(body, note.file, { root, version: note.version }),
      summary: rows.find((row) => row.file === note.file)?.summary ?? note.title,
    };
  });
  cache.set(root, releases);
  return releases;
}
