import { useState } from 'react';
import { ToggleGroup, ToggleGroupItem } from '@/components/ui/toggle-group';
import { Badge } from '@/components/ui/badge';

export interface Skill { name: string; group: string; groupLabel: string; lead: boolean; summary: string; use: string }

const CODE = /(ops\/TASKS\.md|coordinate\.sh|plan-checker|STATE\.md)/g;
function withCode(text: string) {
  return text.split(CODE).map((part, i) => (i % 2 ? <code key={i}>{part}</code> : part));
}

// Filter chips (shadcn ToggleGroup, one value at a time) over the featured skill cards.
export default function SkillFilter({ skills }: { skills: Skill[] }) {
  const groups: { key: string; label: string; n: number }[] = [{ key: 'all', label: 'All', n: skills.length }];
  for (const s of skills) {
    if (!groups.some((g) => g.key === s.group)) {
      groups.push({ key: s.group, label: s.group === 'portable' ? 'Portable' : s.groupLabel, n: skills.filter((x) => x.group === s.group).length });
    }
  }
  const [value, setValue] = useState<string[]>(['all']);
  const current = value[0] ?? 'all';
  const shown = skills.filter((s) => current === 'all' || s.group === current);
  return (
    <div>
      <ToggleGroup aria-label="Filter by group" value={value} onValueChange={(v: string[]) => setValue(v.length ? v : ['all'])} spacing={1} className="chips">
        {groups.map((g) => (
          <ToggleGroupItem key={g.key} value={g.key}>{g.label}<span className="font-medium tabular-nums opacity-75">{g.n}</span></ToggleGroupItem>
        ))}
      </ToggleGroup>
      <p className="count" aria-live="polite">Showing {shown.length} of {skills.length} featured skills</p>
      <ul className="cards">
        {skills.map((s) => (
          <li key={s.name} className="card" hidden={!shown.includes(s)}>
            <div className="meta">
              <Badge variant="secondary">{s.groupLabel}</Badge>
              <Badge variant={s.lead ? 'default' : 'secondary'}>{s.lead ? 'lead' : 'portable'}</Badge>
            </div>
            <h3><a href={`/skills/${s.name}/`}><code>{s.name}</code></a></h3>
            <p>{withCode(s.summary)}</p>
            <p className="use">{withCode(s.use)}</p>
          </li>
        ))}
      </ul>
    </div>
  );
}
