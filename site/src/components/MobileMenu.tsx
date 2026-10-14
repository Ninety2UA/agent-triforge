import { useEffect, useState } from 'react';
import { Sheet, SheetContent, SheetTitle, SheetTrigger } from '@/components/ui/sheet';
import { buttonVariants } from '@/components/ui/button';
import { Icon } from './Icon';

interface Props { items: { label: string; href: string }[]; install: string; repo: string }

// The header's menu below 1040 px: a shadcn Sheet that drops from the top. Base UI traps focus,
// closes on Escape or a press outside, and returns focus to the button.
export default function MobileMenu({ items, install, repo }: Props) {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!open) return;
    const wide = window.matchMedia('(min-width: 1041px)');
    const onChange = () => wide.matches && setOpen(false);
    wide.addEventListener('change', onChange);
    return () => wide.removeEventListener('change', onChange);
  }, [open]);
  return (
    <Sheet open={open} onOpenChange={setOpen}>
      <SheetTrigger className={buttonVariants({ variant: 'ghost', size: 'icon' })} aria-label={open ? 'Close the menu' : 'Open the menu'}>
        <Icon name={open ? 'x' : 'menu'} />
      </SheetTrigger>
      <SheetContent side="top" showCloseButton={false} className="mobile-menu">
        <SheetTitle className="sr-only">Menu</SheetTitle>
        <nav aria-label="Mobile">
          <ul>
            {items.map((i) => <li key={i.href}><a href={i.href} onClick={() => setOpen(false)}>{i.label}</a></li>)}
            <li><a href={repo}>GitHub</a></li>
          </ul>
        </nav>
        <a className={buttonVariants({ variant: 'default' })} href={install}>Install</a>
      </SheetContent>
    </Sheet>
  );
}
