import { useEffect, useRef, useState } from 'react';
import { Sheet, SheetContent, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { buttonVariants } from '@/components/ui/button';
import type { NavItem } from '@/data/nav';
import { Icon } from './Icon';
import { LEAD_KEY } from '@/scripts/tabs';
import { requestSearch } from './search-event';

interface Props {
  items: NavItem[];
  install: string;
  repo: string;
}

// The header's menu below 1040 px: a shadcn Sheet that drops from the top. The trigger is a link to
// the footer's site map, so without JavaScript it still reaches every page; client:interaction holds
// the first press, hydrates, and replays it here, where it opens the sheet instead. Base UI traps
// focus, closes on Escape or a press outside, and returns focus to the trigger.
export default function MobileMenu({ items, install, repo }: Props) {
  const [open, setOpen] = useState(false);
  const trigger = useRef<HTMLAnchorElement>(null);
  const searchAfterClose = useRef(false);
  const [lead, setLead] = useState<string | null>(null);

  // the Install link follows the stored lead, as the header's does
  useEffect(() => {
    if (!open) return;
    try {
      setLead(localStorage.getItem(LEAD_KEY));
    } catch {
      setLead(null);
    }
  }, [open]);

  // the menu belongs to the narrow header; close it when the window widens past it
  useEffect(() => {
    if (!open) return;
    const wide = window.matchMedia('(min-width: 1041px)');
    const onChange = () => wide.matches && setOpen(false);
    wide.addEventListener('change', onChange);
    return () => wide.removeEventListener('change', onChange);
  }, [open]);

  return (
    <Sheet
      open={open}
      onOpenChange={setOpen}
      onOpenChangeComplete={(isOpen) => {
        // open the search palette only once the sheet has let go of focus
        if (!isOpen && searchAfterClose.current) {
          searchAfterClose.current = false;
          requestSearch(trigger.current);
        }
      }}
    >
      <SheetTrigger
        nativeButton={false}
        render={<a ref={trigger} href="#site-map" />}
        onClick={(e) => e.preventDefault()}
        className={buttonVariants({ variant: 'ghost', size: 'icon' })}
        aria-label={open ? 'Close the menu' : 'Menu'}
      >
        <Icon name={open ? 'x' : 'menu'} />
      </SheetTrigger>
      <SheetContent side="top" showCloseButton={false} className="mobile-menu" overlayClassName="mm-scrim">
        <SheetTitle className="sr-only">Menu</SheetTitle>
        <nav aria-label="Main">
          <ul>
            {items.map((i) => (
              <li key={i.href}>
                <a href={i.href} aria-current={i.current} onClick={() => setOpen(false)}>{i.label}</a>
              </li>
            ))}
          </ul>
        </nav>
        <div className="mm-actions">
          <a className={buttonVariants({ variant: 'default' })} href={lead === 'claude-code' || lead === 'codex' ? `${install}#${lead}` : install}>Install</a>
          <a className={buttonVariants({ variant: 'outline' })} href={repo}><Icon name="github" />GitHub</a>
          <button
            type="button"
            className={buttonVariants({ variant: 'outline' })}
            onClick={() => {
              searchAfterClose.current = true;
              setOpen(false);
            }}
          >
            <Icon name="search" />Search
          </button>
        </div>
      </SheetContent>
    </Sheet>
  );
}
