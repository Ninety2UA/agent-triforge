// A docs-style section's reading order: its sidebar and each page's previous and next link, from one
// ordered list. Docs, Guides and Tutorials each pass their pages here, so the three sections share one
// rule for order, the current page and the ends of the list.
//
//   sectionOrder(pages)   pages: [{ slug, label, href }] in reading order.
//     order()             the pages.
//     sidebar(slug)       the pages for SidebarNav, with `current: true` on page `slug`.
//     neighbors(slug)     { prev, next } as { label, href }, undefined at either end.
//                         Throws naming the slug when it is not a page of the section.

/** @typedef {{ slug: string, label: string, href: string }} SectionPage */

/** @param {SectionPage[]} pages */
export function sectionOrder(pages) {
  const order = () => pages;
  const sidebar = (slug) => pages.map(({ label, href, slug: s }) => ({ label, href, ...(s === slug ? { current: true } : {}) }));
  const neighbors = (slug) => {
    const i = pages.findIndex((p) => p.slug === slug);
    if (i === -1) throw new Error(`section-order: "${slug}" is not a page of this section`);
    const link = (p) => (p ? { label: p.label, href: p.href } : undefined);
    return { prev: link(pages[i - 1]), next: link(pages[i + 1]) };
  };
  return { order, sidebar, neighbors };
}
