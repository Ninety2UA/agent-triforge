import { useEffect, useState } from 'react';
import { CommandDialog, CommandEmpty, CommandGroup, CommandInput, CommandItem, CommandList } from '@/components/ui/command';

export interface Entry { title: string; kind: string; href: string }

interface Props {
  open: boolean;
  entries: Entry[];
  initialQuery: string;
  returnFocus: HTMLElement | null;
  onOpenChange: (open: boolean) => void;
}

// The ⌘K palette: shadcn Command in a Dialog, over the 27 skills and the site's pages.
// Loaded only when someone asks for search (loader.ts).
export default function CommandPalette({ open, entries, initialQuery, returnFocus, onOpenChange }: Props) {
  const [query, setQuery] = useState(initialQuery);
  useEffect(() => { if (open) setQuery(initialQuery); }, [open, initialQuery]);
  const kinds = [...new Set(entries.map((e) => e.kind))];
  return (
    <CommandDialog open={open} onOpenChange={onOpenChange} title="Search" description="Search the 27 skills and the site's pages" finalFocus={() => (returnFocus?.isConnected ? returnFocus : true)}>
      <CommandInput value={query} onValueChange={setQuery} placeholder="Search 27 skills and the docs" />
      <CommandList>
        <CommandEmpty>Nothing matches. Esc closes the search.</CommandEmpty>
        {kinds.map((k) => (
          <CommandGroup key={k} heading={k}>
            {entries.filter((e) => e.kind === k).map((e) => (
              <CommandItem key={e.href} value={`${e.title} ${e.kind}`} onSelect={() => { window.location.href = e.href; }}>
                <span className="font-mono text-[0.8125rem]">{e.title}</span>
              </CommandItem>
            ))}
          </CommandGroup>
        ))}
      </CommandList>
    </CommandDialog>
  );
}
