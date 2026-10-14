// The docs map (KTD4): which repo Markdown each Docs and Guides page is made of, in sidebar order, and
// where every heading of those sources lands on the site. Plain Node, no astro: imports. Links are not
// rewritten here; routes.mjs builds the route table on this map, and docs.mjs renders the pages.
//
// Every DOC_PAGES entry (scripts/validate-versions.sh) publishes. An entry with no mapping below gets
// /docs/<file name without .md>/, its own H1 as the title and its first paragraph as the intro, and
// joins the end of the Docs order, so a new docs page needs no site edit.
//
// A page is a list of parts:
//   { file }            a whole docs file: everything after its H1, less the intro paragraph, which
//                       becomes the page's intro. A section another page maps (below) is left out,
//                       with its heading and a pointer to that page.
//   { file, section }   one section of a docs file, rendered without its own heading; its first
//                       paragraph is the intro.
//   { readme }          one README section, rendered without its own heading. Never the intro.
// Headings shift so a rendered section's subsections become H2. Raw HTML image blocks
// (<p ...><img ...></p>) become Markdown images, so Astro's image pipeline handles them.
//
// Exports
//   DOCS_PAGES, GUIDE_PAGES   the explicit pages, in sidebar order
//   PERSONAS_PAGE             docs/personas.md feeds /skills/personas/
//   README_ROUTES             README sections that no page renders, and where links to them go
//                             (null: the link is removed)
//   docsMap(root?)            { pages, fileRoutes, anchors }:
//     pages       [{ slug, href, title, section, source, sources, parts, intro, imageBase }] in order (Docs,
//                 then Guides). parts: [{ source, text }] with each part's raw Markdown; intro: the raw
//                 first paragraph, or ''; source: the file the intro comes from (README.md#faq for the
//                 FAQ, null for a hand-written page); imageBase: the file the page renders as (image
//                 paths are relative to it).
//     fileRoutes  Map of docs file -> its page's href, one per DOC_PAGES entry
//     anchors     Map of source file -> Map of GitHub heading anchor -> site URL (null: removed;
//                 undefined: the README section has no page, so the link goes to GitHub)
import { basename } from 'node:path';

import { REPO, exists, read } from './repo.mjs';
import { personaGroupLabel, readDocPagesList } from './sources.mjs';
import { firstParagraph, githubSlug, htmlAnchors, mapOutsideFences, parseHeadings } from './text.mjs';

export const DOCS_PAGES = [
  { slug: 'getting-started', title: 'Getting started', parts: [{ readme: 'Getting started' }, { file: 'docs/installation.md' }] },
  { slug: 'how-it-works', title: 'How it works', parts: [{ file: 'docs/how-it-works.md' }] },
  { slug: 'workflows', title: 'Workflows', parts: [{ file: 'docs/workflows.md' }] },
  { slug: 'project-layout', title: 'Project layout', parts: [{ file: 'docs/project-layout.md' }] },
  { slug: 'portable-skills', title: 'Portable skills', parts: [{ file: 'docs/skills.md' }] },
  { slug: 'compatibility', title: 'Compatibility', parts: [{ file: 'docs/compatibility.md' }] },
  { slug: 'upgrading', title: 'Upgrading', parts: [{ file: 'docs/upgrading.md' }] },
  { slug: 'faq', title: 'FAQ', parts: [{ readme: 'FAQ' }] },
];

export const GUIDE_PAGES = [
  // hand-written (U6): only its route and title live here
  { slug: 'leases', title: 'Leases and cross-review', parts: [] },
  { slug: 'unattended-runs', title: 'Unattended runs', parts: [{ file: 'docs/unattended-runs.md' }] },
  { slug: 'team-builds', title: 'Team builds', parts: [{ file: 'docs/team-work.md' }] },
  { slug: 'models-and-effort', title: 'Models and effort', parts: [{ file: 'docs/models.md' }] },
  { slug: 'data-egress', title: 'Data egress', parts: [{ file: 'docs/how-it-works.md', section: 'Data egress and credentials' }] },
];

export const PERSONAS_PAGE = { file: 'docs/personas.md', href: '/skills/personas/' };

// The site has no page for the README's other sections: a link to one of them, or to anything under
// it, goes to GitHub. A heading named here that README.md no longer has stops the build.
export const README_ROUTES = [
  { heading: 'Why Agent Triforge', href: '/' },
  { heading: /^What's new\b/, href: '/changelog/' },
  { heading: 'Install', href: '/docs/getting-started/' },
  { heading: 'Documentation', href: null }, // the "← Agent Triforge" back-link of every docs page
  { heading: 'Release history', href: '/changelog/' },
];

const pageHref = (section, slug) => `/${section}/${slug}/`;

function imageBlocksToMarkdown(text) {
  return mapOutsideFences(text, (chunk) =>
    chunk.replace(/<p\b[^>]*>\s*<img\b([^>]*?)\/?>\s*<\/p>/g, (_, attrs) => {
      const attr = (name) => attrs.match(new RegExp(`\\b${name}="([^"]*)"`))?.[1] ?? '';
      return `![${attr('alt').replace(/[[\]]/g, '\\$&')}](${attr('src')})`;
    }),
  );
}

// One source file, parsed once per map: its lines (image blocks already converted) and headings.
function sourceOf(root, cache, file) {
  if (!cache.has(file)) {
    if (!exists(root, file)) throw new Error(`docs map: ${file} does not exist`);
    const text = imageBlocksToMarkdown(read(root, file));
    cache.set(file, { file, text, lines: text.split('\n'), headings: parseHeadings(text) });
  }
  return cache.get(file);
}

function findHeading(src, text, page) {
  const h = src.headings.find((x) => (text instanceof RegExp ? text.test(x.text) : x.text === text));
  if (!h) throw new Error(`docs map: page "${page}" needs the heading "${text}", which ${src.file} does not have`);
  return h;
}

/**
 * One part: its Markdown, the headings it emits (in order, each with the source anchor it stands for;
 * a stub is the kept heading of a section another page renders) and, when asked, its intro paragraph,
 * which the Markdown leaves out.
 */
function composePart(src, { from, to, shift, intro, skip }) {
  const out = [];
  const emitted = [];
  const introPara = intro ? firstParagraph(src.lines, from, src.headings.find((h) => h.line >= from && h.line < to)?.line ?? to) : null;
  for (let i = from; i < to; i++) {
    if (introPara && i >= introPara.start && i < introPara.end) continue;
    const h = src.headings.find((x) => x.line === i);
    if (!h) {
      out.push(src.lines[i]);
      continue;
    }
    const depth = Math.min(6, Math.max(2, h.depth + shift));
    out.push(`${'#'.repeat(depth)} ${h.text}`);
    const moved = skip.get(h.text);
    if (moved) {
      // the section lives on its own page: keep the heading, point there
      emitted.push({ slug: h.slug, stub: true });
      out.push('', `See [${moved.title}](${moved.href}).`, '');
      i = h.end - 1;
      continue;
    }
    emitted.push({ slug: h.slug });
  }
  return { text: out.join('\n').trim(), emitted, intro: introPara?.text ?? '' };
}

const maps = new Map();

/** @param {string} [root] */
export function docsMap(root = REPO) {
  if (!maps.has(root)) maps.set(root, buildDocsMap(root));
  return maps.get(root);
}

function buildDocsMap(root) {
  const cache = new Map();
  const listed = readDocPagesList(root);
  const mapped = new Set([...DOCS_PAGES, ...GUIDE_PAGES].flatMap((p) => p.parts.map((part) => part.file)).filter(Boolean));
  mapped.add(PERSONAS_PAGE.file);

  // A DOC_PAGES entry with no mapping: its own page at the end of the Docs order.
  const extra = listed
    .filter((file) => !mapped.has(file))
    .map((file) => {
      const h1 = sourceOf(root, cache, file).headings.find((h) => h.depth === 1);
      if (!h1) throw new Error(`docs map: ${file} is in DOC_PAGES but has no H1 to title its page`);
      return { slug: basename(file, '.md'), title: h1.text, parts: [{ file }] };
    });

  const specs = [
    ...[...DOCS_PAGES, ...extra].map((p) => ({ ...p, section: 'docs', href: pageHref('docs', p.slug) })),
    ...GUIDE_PAGES.map((p) => ({ ...p, section: 'guides', href: pageHref('guides', p.slug) })),
  ];

  // Sections a page maps on their own: the whole-file part of their file leaves them out.
  const sectionPages = new Map();
  for (const spec of specs) {
    for (const part of spec.parts) if (part.section) sectionPages.set(`${part.file}\n${part.section}`, spec);
  }

  const anchors = new Map();
  const anchorsOf = (file) => anchors.get(file) ?? anchors.set(file, new Map()).get(file);
  const fileRoutes = new Map();

  const pages = specs.map((spec) => {
    let intro = null;
    const parts = spec.parts.map((part) => {
      if (part.readme) {
        const src = sourceOf(root, cache, 'README.md');
        const h = findHeading(src, part.readme, spec.slug);
        anchorsOf('README.md').set(h.slug, spec.href);
        return { source: 'README.md', ...composePart(src, { from: h.line + 1, to: h.end, shift: 1 - h.depth, intro: false, skip: new Map() }) };
      }
      const src = sourceOf(root, cache, part.file);
      let range;
      if (part.section) {
        const h = findHeading(src, part.section, spec.slug);
        anchorsOf(part.file).set(h.slug, spec.href);
        range = { from: h.line + 1, to: h.end, shift: 1 - h.depth };
      } else {
        const h1 = src.headings.find((h) => h.depth === 1);
        if (h1) anchorsOf(part.file).set(h1.slug, spec.href);
        // everything above the H1 is the back-link to the README
        range = { from: h1 ? h1.line + 1 : 0, to: src.lines.length, shift: 0 };
        if (fileRoutes.has(part.file)) throw new Error(`docs map: ${part.file} is a whole page twice (${fileRoutes.get(part.file)} and ${spec.href})`);
        fileRoutes.set(part.file, spec.href);
      }
      const skip = new Map();
      if (!part.section) {
        for (const h of src.headings) {
          const owner = sectionPages.get(`${part.file}\n${h.text}`);
          if (owner) skip.set(h.text, owner);
        }
      }
      const composed = composePart(src, { ...range, intro: intro === null, skip });
      if (intro === null) intro = { source: part.section ? `${part.file}#${githubSlug(part.section)}` : part.file, text: composed.intro };
      return { source: part.file, ...composed };
    });

    // Where each emitted heading lands: the slug it gets on the composed page.
    const markdown = parts.map((p) => p.text).join('\n\n');
    const finals = parseHeadings(markdown);
    const emitted = parts.flatMap((p) => p.emitted.map((e) => ({ ...e, source: p.source })));
    if (finals.length !== emitted.length) throw new Error(`docs map: page "${spec.slug}" composed ${finals.length} headings, expected ${emitted.length}`);
    emitted.forEach((e, i) => {
      if (!e.stub) anchorsOf(e.source).set(e.slug, `${spec.href}#${finals[i].slug}`);
    });

    const first = spec.parts.find((p) => p.file) ?? spec.parts[0];
    const imageBase = first ? (first.file ?? 'README.md') : null;
    const readmePart = spec.parts.find((p) => p.readme);
    return {
      slug: spec.slug,
      href: spec.href,
      title: spec.title,
      section: spec.section,
      source: intro?.source ?? (readmePart ? `README.md#${githubSlug(readmePart.readme)}` : null),
      sources: spec.parts.map((p) => (p.readme ? `README.md#${githubSlug(p.readme)}` : p.section ? `${p.file}#${githubSlug(p.section)}` : p.file)),
      parts: parts.map(({ source, text }) => ({ source, text })),
      intro: intro?.text ?? '',
      imageBase,
    };
  });

  // The personas page: its group headings get anchors without the count, so a new persona does not
  // move them ("Review specialists (6)" -> #review-specialists).
  const personas = sourceOf(root, cache, PERSONAS_PAGE.file);
  fileRoutes.set(PERSONAS_PAGE.file, PERSONAS_PAGE.href);
  for (const h of personas.headings) {
    anchorsOf(PERSONAS_PAGE.file).set(h.slug, h.depth === 1 ? PERSONAS_PAGE.href : `${PERSONAS_PAGE.href}#${githubSlug(personaGroupLabel(h.text))}`);
  }

  readmeAnchors(sourceOf(root, cache, 'README.md'), anchorsOf('README.md'));
  return { pages, fileRoutes, anchors };
}

// README headings that no page part renders: the README_ROUTES entry of the heading or its nearest
// listed ancestor, else undefined (GitHub). A raw <a name> anchor goes where the heading after it goes.
function readmeAnchors(src, map) {
  const routed = new Map();
  for (const route of README_ROUTES) routed.set(findHeading(src, route.heading, 'README_ROUTES').line, route.href);
  const stack = [];
  for (const h of src.headings) {
    while (stack.length && stack.at(-1).depth >= h.depth) stack.pop();
    stack.push(h);
    if (map.has(h.slug)) continue;
    const owner = [...stack].reverse().find((x) => routed.has(x.line) || map.has(x.slug));
    map.set(h.slug, owner ? (routed.has(owner.line) ? routed.get(owner.line) : map.get(owner.slug)) : undefined);
  }
  for (const a of htmlAnchors(src.text)) {
    const next = src.headings.find((h) => h.line >= a.line);
    map.set(a.name, next ? map.get(next.slug) : undefined);
  }
}
