import { useEffect, useId, useRef, useState } from 'react';
import { cn } from 'cn';

import { Command, CommandDialog, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';
import { DialogClose } from '@/components/ui/dialog';
import { loadIndex, type PagefindInstance } from './pagefind';
import { excerptParts, groupResults, type Page } from './results.mjs';

// The Cmd-K palette: shadcn's Command (cmdk) in a Dialog (Base UI), searching every page
// through Pagefind. The loader (loader.ts) fetches this module on the first Cmd-K, Ctrl-K,
// "/" or search button press, and mount.tsx renders it. The popup and its state mount on
// each open, so each open starts fresh: the first one with whatever was typed while the
// palette was loading.
//
// Keyboard: the arrows move the active option (wrapping), Enter opens it, Escape closes
// the palette and focus goes back to the element that opened it. The selection is
// controlled here, so each new set of results starts on its best match; command.tsx keeps
// aria-activedescendant on the input naming that option.

interface SiteResults {
  query: string;
  total: number;
  groups: { section: string; pages: Page[] }[];
}

// how many pages one query shows; each costs a small Pagefind fragment request
const SHOWN = 12;

async function searchSite(index: PagefindInstance, query: string): Promise<SiteResults> {
  const { results } = await index.search(query);
  const pages = await Promise.all(
    results.slice(0, SHOWN).map(async (result) => {
      const data = await result.data();
      return { url: data.url, title: data.meta.title ?? data.url, excerpt: data.excerpt, section: data.filters.section?.[0] };
    }),
  );
  return { query, total: results.length, groups: groupResults(pages) };
}

interface Props {
  open: boolean;
  onOpenChange(open: boolean): void;
  /** where focus goes when the palette closes; null keeps Base UI's default */
  returnFocus: HTMLElement | null;
  /** what was typed between the shortcut and the palette's first render */
  initialQuery: string;
}

export default function CommandPalette({ open, onOpenChange, returnFocus, initialQuery }: Props) {
  return (
    <CommandDialog
      open={open}
      onOpenChange={onOpenChange}
      title="Search the site"
      description="Results update as you type. The arrow keys move, Enter opens the result, Escape closes."
      finalFocus={() => (returnFocus?.isConnected ? returnFocus : true)}
    >
      <PaletteBody initialQuery={initialQuery} onClose={() => onOpenChange(false)} />
    </CommandDialog>
  );
}

function PaletteBody({ initialQuery, onClose }: { initialQuery: string; onClose(): void }) {
  const [query, setQuery] = useState(initialQuery);
  const [index, setIndex] = useState<PagefindInstance | null>(null);
  const [failed, setFailed] = useState(false);
  const [results, setResults] = useState<SiteResults | null>(null);
  const [active, setActive] = useState('');
  const list = useRef<HTMLDivElement>(null);

  useEffect(() => {
    let live = true;
    loadIndex().then(
      (instance) => live && setIndex(instance),
      () => live && setFailed(true),
    );
    return () => {
      live = false;
    };
  }, []);

  const q = query.trim();
  useEffect(() => {
    if (!index || !q) return;
    let live = true;
    // a short pause lets fast typing settle, so a query fetches result fragments only once
    const timer = setTimeout(() => {
      searchSite(index, q).then(
        (found) => {
          if (!live) return;
          setResults(found);
          setActive(found.groups[0]?.pages[0]?.url ?? '');
          if (list.current) list.current.scrollTop = 0;
        },
        () => live && setFailed(true),
      );
    }, 80);
    return () => {
      live = false;
      clearTimeout(timer);
    };
  }, [index, q]);

  // The last results stay up while the next query runs, so the list does not flicker.
  // Until the first results arrive, the index is still loading: Pagefind's init() can
  // resolve before its files are in, and the first search waits for them.
  const shown = q && results ? results : null;
  const status = () => {
    if (failed) return 'Search could not load. Check the connection, then open it again.';
    if (!index || (q && !results)) return 'Loading the search index…';
    if (!q) return 'Type a skill name, a command or a topic.';
    if (shown?.total === 0) return `No results for “${shown.query}”. Try a skill name such as review or plan.`;
    return null;
  };
  const message = status();
  const count = shown && shown.total > 0 ? shown.total : 0;
  const shownCount = shown ? shown.groups.reduce((n, g) => n + g.pages.length, 0) : 0;

  const go = (url: string) => {
    onClose();
    location.assign(url);
  };

  return (
    <Command label="Search the site" shouldFilter={false} loop vimBindings={false} value={active} onValueChange={setActive}>
      <CommandInput
        value={query}
        onValueChange={setQuery}
        placeholder="Search skills, docs and guides"
        after={
          <DialogClose
            aria-label="Close search (esc)"
            className="grid min-h-6 min-w-6 shrink-0 cursor-pointer place-items-center border-0 bg-transparent p-0"
          >
            <kbd>esc</kbd>
          </DialogClose>
        }
      />
      <div role="status">
        {message ? (
          <p className="px-4 py-7 text-center text-[0.9375rem] text-muted-foreground">{message}</p>
        ) : count ? (
          <span className="sr-only">{count === 1 ? '1 result' : `${count} results`}</span>
        ) : null}
      </div>
      <CommandList ref={list} label="Results" className={cn(!shownCount && 'hidden')}>
        {shown?.groups.map((group) => (
          <CommandGroup key={group.section} heading={group.section}>
            {group.pages.map((page) => (
              <Result key={page.url} page={page} onSelect={go} />
            ))}
          </CommandGroup>
        ))}
      </CommandList>
      <div className="flex justify-between gap-3 border-t border-border px-3.5 py-2.5 font-mono text-xs text-muted-foreground">
        <span>{count ? (shownCount < count ? `${shownCount} of ${count} results` : `${count} result${count === 1 ? '' : 's'}`) : ''}</span>
        {/* key hints only where there is a keyboard row to spare; phones show the count alone */}
        <span className="hidden sm:inline">Enter to open · arrows to move</span>
      </div>
    </Command>
  );
}

// a skill's own page, whose title is the skill name, set in mono like everywhere else
const SKILL_PAGE = /^\/skills\/[^/]+\/$/;

// One page: its title names the option, the excerpt (matches in ink) describes it. The
// excerpt stays out of the name (aria-hidden) and is read as the description, so a screen
// reader says the title first and voice control matches the title as shown.
function Result({ page, onSelect }: { page: Page; onSelect(url: string): void }) {
  const excerpt = useId();
  const mono = SKILL_PAGE.test(page.url);
  return (
    <CommandItem value={page.url} onSelect={onSelect} aria-describedby={excerpt} className="grid items-start gap-0.5">
      <span className={cn('truncate font-[560] text-foreground', mono ? 'font-mono text-sm' : 'text-[0.9375rem]')}>
        {page.title}
      </span>
      <span
        id={excerpt}
        aria-hidden="true"
        className="line-clamp-2 text-[0.8125rem] leading-snug text-muted-foreground [&_mark]:bg-transparent [&_mark]:font-semibold [&_mark]:text-foreground"
      >
        {excerptParts(page.excerpt).map((part, i) => (part.mark ? <mark key={i}>{part.text}</mark> : part.text))}
      </span>
    </CommandItem>
  );
}
