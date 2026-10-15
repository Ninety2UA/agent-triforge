// The Docs and Guides pages with their content, from the docs map (docs-map.mjs) with every link
// resolved through routes.mjs. Plain Node, no astro: imports.
//
// Exports
//   docPages(root?)        [{ slug, href, title, section: 'docs' | 'guides', source, sources, intro, body,
//                          imageBase }] in sidebar order, Docs first. source is the file the intro comes
//                          from (README.md#faq for the FAQ, null for a hand-written guide); sources lists
//                          every part ("README.md#getting-started", "docs/installation.md",
//                          "docs/how-it-works.md#data-egress-and-credentials"). intro is the first
//                          paragraph as Markdown ('' when there is none); body the rest of the page as
//                          Markdown, '' for a hand-written guide. Image paths in body are relative to
//                          imageBase, the repo file to render it as (the fileURL Astro resolves them from).
//   sectionPages(section, root?)  [{ slug, href, title }] of 'docs' or 'guides', for sidebars and the footer
import { docsMap } from './docs-map.mjs';
import { REPO } from './repo.mjs';
import { rewriteLinks } from './routes.mjs';

const cache = new Map();

/** @param {string} [root] */
export function docPages(root = REPO) {
  if (cache.has(root)) return cache.get(root);
  const pages = docsMap(root).pages.map((page) => {
    const options = { root, imageBase: page.imageBase ?? undefined };
    const introSource = page.source?.split('#')[0];
    return {
      slug: page.slug,
      href: page.href,
      title: page.title,
      section: page.section,
      source: page.source,
      sources: page.sources,
      intro: page.intro ? rewriteLinks(page.intro, introSource, options) : '',
      body: page.parts.map((part) => rewriteLinks(part.text, part.source, options)).join('\n\n'),
      imageBase: page.imageBase,
    };
  });
  cache.set(root, pages);
  return pages;
}

/**
 * @param {'docs' | 'guides'} section
 * @param {string} [root]
 */
export function sectionPages(section, root = REPO) {
  return docsMap(root)
    .pages.filter((page) => page.section === section)
    .map(({ slug, href, title }) => ({ slug, href, title }));
}
