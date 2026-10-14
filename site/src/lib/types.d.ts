// The shapes the data modules return, for TypeScript pages and components. The modules are plain
// JavaScript (shared with node:test); each <module>.d.mts beside one types its exports from here.

export interface Group { key: string; label: string }
export interface Skill {
  name: string;
  lead: boolean;
  group: Group;
  description: string;
  /** one line from the docs tables, plain text */
  summary: string;
  argumentHint: string | null;
  /** the SKILL.md body after its frontmatter, links resolved */
  body: string;
  /** repo-relative, e.g. skills/at-ship/SKILL.md */
  path: string;
}
export interface SkillGroup extends Group { count: number }

export interface PersonaGroup extends Group { anchor: string }
export interface Persona {
  name: string;
  anchor: string;
  group: PersonaGroup;
  summary: string;
  class: string;
  tier: string;
  neverDowngrade: boolean;
  maxTurns: number;
  body: string;
  path: string;
}

export interface Cli {
  id: string;
  name: string;
  tier: 'core' | 'optional';
  core: boolean;
  binary: string;
  egress: string;
  provider: string;
  model: string;
  roles: string[];
  optInRoles: string[];
  consent: boolean;
  canLead: boolean;
  floor: string;
  tested: string;
  probe: string;
}
export interface Role {
  role: string;
  cli: string;
  cliName: string;
  model: string;
  effort: string;
  fallbacks: { cli: string; cliName: string }[];
}

export interface DocPage {
  slug: string;
  href: string;
  title: string;
  section: 'docs' | 'guides';
  source: string | null;
  sources: string[];
  intro: string;
  body: string;
  imageBase: string | null;
}
export interface SectionPage { slug: string; href: string; title: string }

export interface Release {
  version: string | null;
  date: string;
  title: string;
  anchor: string;
  file: string;
  ref: string;
  body: string;
  summary: string;
}

export interface Counts { skills: number; leadSkills: number; portableSkills: number; personas: number; clis: number; roles: number; releases: number }
