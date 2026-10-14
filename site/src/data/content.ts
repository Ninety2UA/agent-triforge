// The home page's data: repo facts from the data modules (src/lib) and the hand-written phrasing around
// them. Names, groups, providers, roles, fallbacks, install commands and counts come from the repo; the
// home page's short descriptions are written by hand (the home copy is hand-written), keyed by name, and
// a featured skill or persona that is no longer in the repo fails the build. A CLI added to the registry
// shows up with a sentence generated from its roles. Anything that moves (the dot field) uses plain
// words: no code, paths, config or ids.
import { installCommands } from '@/lib/readme.mjs';
import { getClis, getRoles } from '@/lib/roster.mjs';
import { getSkills } from '@/lib/skills.mjs';
import { getPersonas } from '@/lib/personas.mjs';
import { numberWord } from '@/lib/numbers.mjs';

export { GH } from '@/lib/site.mjs';

const install = installCommands();
export const INSTALL = { claude: install.claude, codex: install.codex };
export const SKILLS_ONLY = install.skillsOnly;

// What each core CLI does on the team by default, in a few words.
const CLI_WORDS: Record<string, string> = {
  claude: 'Leads by default and builds.',
  antigravity: 'Maps the codebase and writes docs.',
  codex: 'Reviews and tests. Can lead.',
};
const list = (words: string[]) => (words.length < 2 ? words.join('') : `${words.slice(0, -1).join(', ')} or ${words[words.length - 1]}`);
const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

// core members first, then the optional ones in registry order, with a member that needs your consent last
const ordered = getClis().map((c, i) => ({ c, i })).sort((a, b) => Number(b.c.core) - Number(a.c.core) || Number(a.c.consent) - Number(b.c.consent) || a.i - b.i).map(({ c }) => c);
export const CLIS = ordered.map((c) => {
  const via = c.egress.match(/\b(?:through|via) ([A-Z][\w.]+)/)?.[1];
  const roles = c.roles.length === 5 ? 'Any role.' : `${cap(list(c.roles))}${c.consent ? ', after your consent' : ''}.`;
  return { id: c.id, name: c.name, core: c.core, roles: CLI_WORDS[c.id] ?? roles, provider: via ? `${c.provider} via ${via}` : c.provider };
});

// What each role does, in a few words.
const ROLE_WORDS: Record<string, string> = {
  builder: 'Writes the code for a task',
  reviewer: "Reviews every task it didn't build",
  tester: 'Writes the failing test first',
  analyst: 'Maps the codebase before planning',
  documenter: 'Writes the documentation',
};
export const ROLES = getRoles().map((r) => ({
  role: r.role,
  does: ROLE_WORDS[r.role] ?? cap(r.role),
  cli: r.cliName,
  fallback: r.fallbacks.map((f) => f.cliName).join(', then '),
}));

// The skills the home page features: what each does and when to reach for it.
const FEATURED_WORDS: Record<string, [summary: string, use: string]> = {
  'at-ship': ['One sprint on its own: analyze, plan, build, review, test, wrap, then mark it complete.', 'Use it when a scoped goal should ship in one run.'],
  'at-coordinate': ['The plain Phase 0 to 6 cycle that coordinate.sh drives, session after session.', 'Use it for the same sprint without convergence or team flags.'],
  'at-plan': ['Turns a goal into ops/TASKS.md with waves, failure paths and a plan-checker verdict.', 'Use it when you want to read the plan before anything is built.'],
  'at-build': ['Builds tasks in waves, pins a reviewer to each and merges what passes.', 'Use it when ops/TASKS.md holds assigned tasks.'],
  'at-review': ['Review lanes from the roster plus specialist reviewers, merged into one report.', 'Use it when built tasks need Phase 3 and 4 review.'],
  'at-test': ['Finds untested paths, gets tests from the roster tester, fixes until green.', 'Use it when changed code needs Phase 5 testing.'],
  'at-wrap': ['Records what was learned, archives review files, writes STATE.md, marks completion.', 'Use it when a sprint or a session ends.'],
  'at-quick': ['A test-first change with a self-review and no swarm.', 'Use it for fewer than 3 files with no shared interface or protected path.'],
  'at-debug': ['Reproduce, find the root cause with evidence, fix, write it down.', 'Use it when a bug report or an error needs a cause.'],
  'wave-orchestration': ['Leases, pinned cross-review and merges in wave order.', 'Use it when a validated plan has two or more tasks.'],
  'verification-before-completion': ['Fresh evidence behind every claim that something is done.', 'Use it before calling anything done.'],
  'knowledge-compounding': ['Writes a note only when a future agent would repeat the mistake without it.', 'Use it when a task ends with something learned.'],
};
const skills = new Map(getSkills().map((s) => [s.name, s]));
export const FEATURED = Object.entries(FEATURED_WORDS).map(([name, [summary, use]]) => {
  const s = skills.get(name);
  if (!s) throw new Error(`site/src/data/content.ts: the featured skill ${name} is not in skills/`);
  return { name, group: s.group.key, groupLabel: s.group.label, lead: s.lead, summary, use };
});

// The specialist reviewers /at-ship runs, in plain words.
const PERSONA_WORDS: Record<string, string> = {
  'security-sentinel': 'Reviews for security and nothing else: OWASP-class issues, in depth.',
  'performance-oracle': 'Finds bottlenecks and scaling problems, such as nested loops over the same data.',
  'code-simplicity-reviewer': 'Flags complexity the change does not need, like an interface with one implementation.',
  'findings-synthesizer': 'Reads every review file, removes duplicates, sets confidence tiers and writes one report.',
  'plan-checker': 'Checks the plan before anything is built, and keeps checking until it approves.',
};
const personas = new Map(getPersonas().map((p) => [p.name, p]));
export const PERSONAS = Object.entries(PERSONA_WORDS).map(([name, what]) => {
  const p = personas.get(name);
  if (!p) throw new Error(`site/src/data/content.ts: the featured persona ${name} is not in personas/`);
  return { name, anchor: p.anchor, what, neverDowngraded: p.neverDowngrade };
});

// The dot field's captions, one per step of its story, in the film's order.
const core = CLIS.filter((c) => c.core).map((c) => c.name);
const optional = CLIS.length - core.length;
export const FIELD_CAPS = [
  `${numberWord(CLIS.length, { capital: true })} coding agents. ${core.slice(0, -1).join(', ')} and ${core[core.length - 1]} are always on the team; the other ${numberWord(optional)} join when you add them.`,
  'You give the lead a goal. Here Claude Code leads.',
  'The lead splits the goal into tasks, each in its own workspace.',
  'Claude Code builds task 1.',
  "Codex reviews task 1. It didn't write it.",
  'The lead merges task 1 onto the shared branch.',
  'Claude Code builds task 2.',
  "Claude Code tries to review its own task. An agent can't review its own work.",
  'Codex reviews task 2 instead.',
  "The lead merges task 2. Every change was reviewed by an agent that didn't write it.",
];
