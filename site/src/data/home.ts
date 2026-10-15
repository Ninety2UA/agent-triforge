// The home page's hand-written copy: the headline, the install tabs and the sprint phases. Phases 0 to 6
// are fixed text (KTD17); every skill and persona named here is checked against the repo by the site
// gate, so a rename fails the build instead of shipping a dead name.
import { INSTALL, SKILLS_ONLY } from './content';
import { getCounts } from '@/lib/counts.mjs';
import { numberWord } from '@/lib/numbers.mjs';
import type { InstallTab } from '@/components/InstallTabs.astro';
import { LEAD_TABS } from './leads.mjs';
import { escapeRegExp } from '@/lib/text.mjs';

export const H1 = 'Put Claude Code, Codex and Antigravity on one team.';
export const LEDE = 'One agent leads. The others build, review and test, and nothing merges until a different agent has checked it.';

export const heroTabs: InstallTab[] = [
  { ...LEAD_TABS[0], blocks: [{ lines: INSTALL.claude, label: 'Copy the Claude Code install commands' }] },
  { ...LEAD_TABS[1], blocks: [{ lines: INSTALL.codex, label: 'Copy the Codex install commands' }] },
];

export const installTabs: InstallTab[] = [
  { id: 'claude-code', label: 'Claude Code leads', lead: 'claude-code', blocks: [{ lines: INSTALL.claude, label: 'Copy the Claude Code install commands' }],
    note: 'Add `--scope project` to the install line to share it with your team.' },
  { id: 'codex', label: 'Codex leads', lead: 'codex', blocks: [{ lines: INSTALL.codex, label: 'Copy the Codex install commands' }],
    note: 'A Codex lead also needs a trust entry you add by hand to `~/.codex/config.toml`. `/at-setup` prints it and never writes it.',
    art: { label: 'The trust entry, with your project path', text: '[projects."/abs/path"]\ntrust_level = "trusted"' } },
  { id: 'skills-only', label: 'Skills only', blocks: SKILLS_ONLY.map((s) => ({ lines: s.lines, label: `Copy the ${s.cli} command` })),
    note: `The ${numberWord(getCounts().portableSkills)} portable skills only, for ${SKILLS_ONLY.map((s) => s.cli.replace(/ CLI$/, '')).join(' or ')}: no lead workflows, hooks or agents.` },
];

export const PHASES = [
  {
    "n": "Pre",
    "short": "Search",
    "title": "Search what earlier sprints learned",
    "body": "Before anything is planned, the learnings-researcher persona searches the notes earlier sprints left behind.",
    "rows": [
      {
        "k": "Persona",
        "v": [
          "learnings-researcher"
        ]
      },
      {
        "k": "Reads",
        "v": [
          "ops/solutions/",
          "ops/decisions/"
        ]
      }
    ],
    "who": "The lead starts it."
  },
  {
    "n": "0",
    "short": "Analyze",
    "title": "Map the codebase",
    "body": "Antigravity, in the analyst role, maps structure, data flow and interfaces. It is skipped when the codebase has not changed or the fix is small.",
    "rows": [
      {
        "k": "Skill",
        "v": [
          "codebase-mapping"
        ]
      },
      {
        "k": "Writes",
        "v": [
          "ops/ARCHITECTURE.md"
        ]
      }
    ],
    "who": "Analyst: Antigravity, falling back to Claude Code."
  },
  {
    "n": "1",
    "short": "Plan",
    "title": "Turn the goal into tasks",
    "body": "The lead writes tasks in waves and traces how each can fail. In Phase 1.1 it brings you the 3 riskiest assumptions to confirm.",
    "rows": [
      {
        "k": "Skills",
        "v": [
          "at-plan",
          "writing-plans",
          "shadow-path-tracing"
        ]
      },
      {
        "k": "Writes",
        "v": [
          "ops/TASKS.md"
        ]
      }
    ],
    "who": "The lead, with you on the assumptions."
  },
  {
    "n": "1.5",
    "short": "Validate",
    "title": "Check the plan before building",
    "body": "plan-checker reviews the plan until it approves, three rounds at most. If the plan passes 15 tasks, scope-cutting can cut it by value.",
    "rows": [
      {
        "k": "Persona",
        "v": [
          "plan-checker"
        ]
      },
      {
        "k": "Skill",
        "v": [
          "scope-cutting"
        ]
      }
    ],
    "who": "plan-checker, never moved to a smaller model."
  },
  {
    "n": "2",
    "short": "Build",
    "title": "Build, review, merge",
    "body": "Each task gets its own worktree. A builder writes it, a pinned reviewer from a different roster member checks it, and the lead squash-merges its own copy. integration-verifier runs between waves.",
    "rows": [
      {
        "k": "Skills",
        "v": [
          "at-build",
          "wave-orchestration"
        ]
      },
      {
        "k": "Writes",
        "v": [
          "ops/leases.toml",
          "ops/CHANGELOG.md"
        ]
      }
    ],
    "who": "Builder: Claude Code. Reviewer: Codex."
  },
  {
    "n": "3+4",
    "short": "Review",
    "title": "Review in parallel until it converges",
    "body": "In at-ship, five lanes review at once: Antigravity, Codex, security-sentinel, performance-oracle and code-simplicity-reviewer. findings-synthesizer merges them; fixes loop at most 3 cycles.",
    "rows": [
      {
        "k": "Skills",
        "v": [
          "at-review",
          "review-synthesis",
          "iterative-refinement"
        ]
      },
      {
        "k": "Writes",
        "v": [
          "ops/REVIEW_*.md"
        ]
      }
    ],
    "who": "Reviewer lanes from the roster, plus the specialist personas."
  },
  {
    "n": "5",
    "short": "Test",
    "title": "Failing test first, then green",
    "body": "test-gap-analyzer finds the untested paths. The tester writes the failing test first, and fixes run until the suite passes.",
    "rows": [
      {
        "k": "Skill",
        "v": [
          "at-test"
        ]
      },
      {
        "k": "Writes",
        "v": [
          "ops/TEST_RESULTS.md"
        ]
      }
    ],
    "who": "Tester: Codex, falling back to Claude Code."
  },
  {
    "n": "6",
    "short": "Wrap",
    "title": "Write it down, then mark it done",
    "body": "What the sprint learned goes to ops/solutions/, review files to ops/archive/, the checkpoint to ops/STATE.md. ops/.sprint-complete is created last, after the checklist passes.",
    "rows": [
      {
        "k": "Skills",
        "v": [
          "at-wrap",
          "knowledge-compounding",
          "verification-before-completion",
          "session-continuity"
        ]
      },
      {
        "k": "Writes",
        "v": [
          "ops/STATE.md",
          "ops/.sprint-complete"
        ]
      }
    ],
    "who": "The lead."
  }
];

export const phaseLabel = (n: string) => (n === 'Pre' ? 'Pre-plan' : n.includes('+') ? `Phases ${n.replace('+', ' and ')}` : `Phase ${n}`);

// Skill, persona and file names inside phase copy are set as code.
const CODE_TOKENS = ['learnings-researcher', 'plan-checker', 'integration-verifier', 'security-sentinel', 'performance-oracle', 'code-simplicity-reviewer',
  'findings-synthesizer', 'test-gap-analyzer', 'scope-cutting', 'at-ship', 'ops/solutions/', 'ops/archive/', 'ops/STATE.md', 'ops/.sprint-complete'];
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
export const withCode = (s: string) => {
  let out = esc(s);
  for (const t of CODE_TOKENS) out = out.replace(new RegExp(`(?<![\\w/.-])${escapeRegExp(t)}(?![\\w-])`, 'g'), `<code>${t}</code>`);
  return out;
};
