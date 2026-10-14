import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import Command from './Command';

export interface InstallTab {
  id: string;
  label: string;
  blocks: { lines: string[]; label: string }[];
  /** a short note under the commands; `backticks` mark code */
  note?: string;
  /** a real file fragment shown under the note */
  art?: { label: string; text: string };
}

const withCode = (s: string) => s.split('`').map((part, i) => (i % 2 ? <code key={i}>{part}</code> : part));

interface Props { tabs: InstallTab[]; ariaLabel: string; className?: string }

// The lead switch and the install tabs: shadcn Tabs on Base UI. Arrow keys move and select;
// every panel stays mounted, so all commands are in the static HTML.
export default function InstallTabs({ tabs, ariaLabel, className }: Props) {
  return (
    <Tabs defaultValue={tabs[0].id} className={className}>
      <TabsList aria-label={ariaLabel}>
        {tabs.map((t) => <TabsTrigger key={t.id} value={t.id}>{t.label}</TabsTrigger>)}
      </TabsList>
      {tabs.map((t) => (
        <TabsContent key={t.id} value={t.id} className="install-panel">
          {t.blocks.map((b, i) => <Command key={i} lines={b.lines} label={b.label} />)}
          {t.note && <p className="note">{withCode(t.note)}</p>}
          {t.art && <div className="art" data-ui><span className="lbl">{t.art.label}</span><pre>{t.art.text}</pre></div>}
        </TabsContent>
      ))}
    </Tabs>
  );
}
