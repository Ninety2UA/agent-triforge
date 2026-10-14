import { useEffect, useRef, useSyncExternalStore } from 'react';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';
import { InputGroup, InputGroupAddon, InputGroupInput } from '@/components/ui/input-group';
import { Icon } from './Icon';
import { ALL, initCatalog } from './skill-filter.mjs';

// The catalog filter's controls: the search box (on /skills/) and the group chips (shadcn ToggleGroup,
// one value at a time). The cards, the count and the empty state are static HTML outside React; the
// plain controller in skill-filter.mjs changes them, so the island only draws its controls and passes
// what the reader does to the controller. It hydrates on first use (client:interaction): focusing the
// search box, which "/" does, is a first use. Whatever was typed before it hydrated is picked up then.

export interface FilterGroup {
  key: string;
  label: string;
  count: number;
}
interface Props {
  groups: FilterGroup[];
  /** the number of cards; the All chip's count */
  total: number;
  /** show the search box */
  search?: boolean;
}

type State = { q: string; group: string };
const START: State = { q: '', group: ALL };
const catalog = () => initCatalog(document, window);
const subscribe = (fn: () => void) => catalog()?.subscribe(fn) ?? (() => {});
const snapshot = (): State => catalog()?.getState() ?? START;

export default function SkillFilter({ groups, total, search = false }: Props) {
  // the server and the hydrating render see every card; the controller's state follows at once
  const state = useSyncExternalStore(subscribe, snapshot, () => START);
  const box = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const typed = box.current?.value ?? '';
    if (typed !== snapshot().q) catalog()?.setQuery(typed);
  }, []);

  return (
    <div className="sf" data-pagefind-ignore>
      {search && (
        <InputGroup className="sf-field">
          <InputGroupAddon className="sf-icon">
            <Icon name="search" />
          </InputGroupAddon>
          <InputGroupInput
            ref={box}
            id="skill-q"
            data-filter-q=""
            type="search"
            className="sf-input"
            placeholder="Search by name or what it does"
            aria-label="Search the skills"
            aria-keyshortcuts="/"
            aria-controls="skill-cards"
            autoComplete="off"
            spellCheck={false}
            defaultValue=""
            onInput={(e) => catalog()?.setQuery(e.currentTarget.value)}
            onKeyDown={(e) => {
              if (catalog()?.key(e.key)) e.preventDefault();
            }}
          />
          <InputGroupAddon align="inline-end" className="sf-key" aria-hidden="true">
            <kbd>/</kbd>
          </InputGroupAddon>
        </InputGroup>
      )}
      <ToggleGroup
        aria-label="Filter by group"
        value={[state.group]}
        onValueChange={(v: string[]) => catalog()?.setGroup(v[0] ?? ALL)}
        spacing={1}
        className="chips"
      >
        <ToggleGroupItem value={ALL} data-group-chip={ALL}>
          All<span className="font-medium tabular-nums opacity-75">{total}</span>
        </ToggleGroupItem>
        {groups.map((g) => (
          <ToggleGroupItem key={g.key} value={g.key} data-group-chip={g.key}>
            {g.label}<span className="font-medium tabular-nums opacity-75">{g.count}</span>
          </ToggleGroupItem>
        ))}
      </ToggleGroup>
    </div>
  );
}
