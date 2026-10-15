// The route table (KTD2): every link the site generates from a repo file goes through resolveLink, so
// a link means the same thing on every page. Plain Node, no astro: imports.
//
// Sources and their routes:
//   docs pages and guides     docs-map.mjs: each docs file and README section, heading by heading
//   docs/personas.md          /skills/personas/, its groups at #<group> (the heading without its count)
//   personas/<name>.md        /skills/personas/#<name>
//   skills/<name>/SKILL.md    /skills/<name>/, its headings at #<anchor>
//   docs/releases/<note>.md   /changelog/#<release anchor>; docs/releases/ itself is /changelog/
//   README.md                 /, its sections where docs-map.mjs sends them
// Any other repo path goes to GitHub, tree/main for a folder and blob/main for a file. A link written
// in a release note goes to GitHub at that release's tag (blob/v<version>/), or at main for an untagged
// version or an unversioned note, as scripts/release-notes.sh does for the GitHub release.
//
// Each relative link resolves against its own source file, in Markdown and in raw HTML (href, src)
// alike; fenced code and inline code are left alone. A link to a path that is not in the repo, or an
// anchor that matches no heading of its target, throws naming the source file and the link.
//
// Exports
//   githubUrl(repoPath, { ref = 'main', root }?)   the GitHub URL of a repo path, "#anchor" kept
//   resolveLink(fromRepoPath, href, { version, root }?)   a site path, an absolute URL, or null when the
//                                    link is to be removed (the README's Documentation section). Absolute
//                                    URLs and site paths come back as they are. version: the release whose
//                                    tag a release note's links use (default: read from the note's header).
//   resolveImage(fromRepoPath, src, { imageBase, root }?)   an image path relative to imageBase (the file
//                                    the Markdown renders as; default the source itself), "./" prefixed
//   rewriteLinks(text, fromRepoPath, { version, imageBase, root }?)   the Markdown or HTML with every link
//                                    and image resolved; a removed link keeps its text
//   headingAnchors(markdown)         the anchors a link into that Markdown may name (text.mjs)
//   routeTable(root?)                Map of repo path -> { href, anchors: Map<anchor, url | null | undefined> }
import { posix } from 'node:path';

import { docsMap, PERSONAS_PAGE } from './docs-map.mjs';
import { GH, REPO, exists, isDir, read } from './repo.mjs';
import { listPersonaNames, listReleaseNotes, listSkillFolders, releaseRef } from './sources.mjs';
import { headingAnchors, mapOutsideFences, maskCode, parseHeadings } from './text.mjs';

export { headingAnchors };

const ABSOLUTE = /^(?:[a-z][a-z0-9+.-]*:|\/)/i;

/**
 * @param {string} repoPath
 * @param {{ ref?: string, root?: string }} [options]
 */
export function githubUrl(repoPath, { ref = 'main', root = REPO } = {}) {
  const [path, fragment] = splitHash(repoPath);
  const clean = path.replace(/^\.\//, '').replace(/\/+$/, '');
  const kind = path.endsWith('/') || isDir(root, clean) ? 'tree' : 'blob';
  return `${GH}/${kind}/${ref}/${clean}${fragment ? `#${fragment}` : ''}`;
}

function splitHash(href) {
  const i = href.indexOf('#');
  return i === -1 ? [href, ''] : [href.slice(0, i), href.slice(i + 1)];
}

const tables = new Map();

/** @param {string} [root] */
export function routeTable(root = REPO) {
  if (tables.has(root)) return tables.get(root);
  const table = new Map();
  const { fileRoutes, anchors } = docsMap(root);

  for (const [file, href] of fileRoutes) table.set(file, { href, anchors: anchors.get(file) ?? new Map() });
  table.set('README.md', { href: '/', anchors: anchors.get('README.md') });

  // Every heading of a page-sized source lands on that page; a skill keeps its own anchors.
  const whole = (file, href, inner) => {
    const map = new Map();
    for (const h of parseHeadings(read(root, file))) map.set(h.slug, inner ? `${href}#${h.slug}` : href);
    table.set(file, { href, anchors: map });
  };
  for (const name of listSkillFolders(root)) whole(`skills/${name}/SKILL.md`, `/skills/${name}/`, true);
  for (const name of listPersonaNames(root)) whole(`personas/${name}.md`, `${PERSONAS_PAGE.href}#${name}`, false);
  for (const note of listReleaseNotes(root)) whole(note.file, `/changelog/#${note.anchor}`, false);
  table.set('docs/releases', { href: '/changelog/', anchors: new Map() });

  tables.set(root, table);
  return table;
}

function release(root, from) {
  return listReleaseNotes(root).find((note) => note.file === from);
}

/**
 * @param {string} from  the repo path of the file the link is written in
 * @param {string} href
 * @param {{ version?: string | null, root?: string }} [options]
 * @returns {string | null}
 */
export function resolveLink(from, href, { version, root = REPO } = {}) {
  if (ABSOLUTE.test(href)) return href;
  const [path, fragment] = splitHash(href);
  const target = path ? posix.normalize(posix.join(posix.dirname(from), path)) : from;
  if (target.startsWith('../') || target === '..') throw new Error(`${from}: the link "${href}" leaves the repository`);
  const clean = target.replace(/\/+$/, '') || '.';
  const hash = fragment ? `#${fragment}` : '';

  const note = version !== undefined ? { ref: releaseRef(version) } : release(root, from);
  if (note) return githubUrl(`${clean}${path.endsWith('/') ? '/' : ''}${hash}`, { ref: note.ref, root });

  const route = routeTable(root).get(clean);
  if (route) {
    if (!fragment) return route.href;
    if (!route.anchors.has(fragment)) throw new Error(`${from}: the link "${href}" names #${fragment}, which matches no heading of ${clean}`);
    const url = route.anchors.get(fragment);
    return url === undefined ? githubUrl(`${clean}${hash}`, { root }) : url;
  }

  if (!exists(root, clean)) throw new Error(`${from}: the link "${href}" points at ${clean}, which is not in the repository`);
  if (fragment && clean.endsWith('.md') && !headingAnchors(read(root, clean)).has(fragment)) {
    throw new Error(`${from}: the link "${href}" names #${fragment}, which matches no heading of ${clean}`);
  }
  return githubUrl(`${clean}${path.endsWith('/') ? '/' : ''}${hash}`, { root });
}

/**
 * @param {string} from
 * @param {string} src
 * @param {{ imageBase?: string, root?: string }} [options]
 */
export function resolveImage(from, src, { imageBase = from, root = REPO } = {}) {
  if (ABSOLUTE.test(src)) return src;
  const target = posix.normalize(posix.join(posix.dirname(from), src));
  if (!exists(root, target)) throw new Error(`${from}: the image "${src}" points at ${target}, which is not in the repository`);
  const rel = posix.relative(posix.dirname(imageBase), target);
  return rel.startsWith('.') ? rel : `./${rel}`;
}

// [label](target) or [label](target "title"), the title kept as written
const MD_LINK = /(!?)\[((?:[^[\]]|\[[^\]]*\])*)\]\(([^)\s]+)((?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?)\)/g;
// a reference definition, [id]: target "title"
const MD_DEFINITION = /^(\s{0,3}\[[^\]]+\]:\s*)(\S+)(.*)$/;
const HTML_A = /<a\b([^>]*?)\bhref="([^"]*)"([^>]*)>([\s\S]*?)<\/a>/g;
const HTML_SRC = /(<(?:img|source)\b[^>]*?\bsrc=")([^"]*)(")/g;

/**
 * @param {string} text  Markdown, raw HTML, or both
 * @param {string} from
 * @param {{ version?: string | null, imageBase?: string, root?: string }} [options]
 */
export function rewriteLinks(text, from, options = {}) {
  const link = (href) => resolveLink(from, href, options);
  const image = (src) => resolveImage(from, src, options);
  return mapOutsideFences(text, (chunk) =>
    chunk
      .split('\n')
      .map((line) => {
        const { text: masked, restore } = maskCode(line);
        const out = masked
          .replace(MD_LINK, (_, bang, label, target, title) => {
            if (bang) return `![${label}](${image(target)}${title})`;
            const url = link(target);
            return url === null ? label : `[${label}](${url}${title})`;
          })
          .replace(MD_DEFINITION, (_, open, target, rest) => {
            const url = link(target);
            // a definition for a link that does not publish (the README back-link) goes with it
            return url === null ? '' : `${open}${url}${rest}`;
          })
          .replace(HTML_A, (_, before, href, after, inner) => {
            const url = link(href);
            return url === null ? inner : `<a${before}href="${url}"${after}>${inner}</a>`;
          })
          .replace(HTML_SRC, (_, open, src, close) => `${open}${image(src)}${close}`);
        return restore(out);
      })
      .join('\n'),
  );
}
