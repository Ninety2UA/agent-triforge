// The site's sections, in header order. `href` is where the item goes; `section` is the path prefix
// that marks it current on every page under it. Tutorials, Guides and Docs have no index page, so
// those items open the section's first page (vercel.json sends the bare section path there too).
export const NAV = [
  { label: 'Skills', href: '/skills/', section: '/skills/' },
  { label: 'Roster', href: '/roster/', section: '/roster/' },
  { label: 'Sprint', href: '/sprint/', section: '/sprint/' },
  { label: 'Tutorials', href: '/tutorials/first-sprint/', section: '/tutorials/' },
  { label: 'Guides', href: '/guides/leases/', section: '/guides/' },
  { label: 'Docs', href: '/docs/getting-started/', section: '/docs/' },
  { label: 'Changelog', href: '/changelog/', section: '/changelog/' },
] as const;

/** The install tabs' page; the Install buttons add #claude-code or #codex for the stored lead. */
export const INSTALL_HREF = '/docs/getting-started/';

export interface NavItem {
  label: string;
  href: string;
  /** "page" on the item's own page, "true" anywhere else in its section */
  current?: 'page' | 'true';
}

/** The nav items with the current section marked for this path. */
export function navItems(pathname: string): NavItem[] {
  const path = pathname.endsWith('/') ? pathname : `${pathname}/`;
  return NAV.map(({ label, href, section }) => ({
    label,
    href,
    current: path === href ? 'page' : path.startsWith(section) ? 'true' : undefined,
  }));
}
