// Facts for the copy, from FACTS.md only. Anything that moves (the dot field, the reviewer bench)
// uses plain words: no code, paths, config or ids.

export const GH = 'https://github.com/Ninety2UA/agent-triforge';

export const NAV = [{"label": "Skills", "href": "/skills/"}, {"label": "Roster", "href": "/roster/"}, {"label": "Sprint", "href": "/sprint/"}, {"label": "Tutorials", "href": "/tutorials/"}, {"label": "Guides", "href": "/guides/"}, {"label": "Docs", "href": "/docs/"}, {"label": "Changelog", "href": "/changelog/"}];

export const INSTALL = {
  "claude": [
    "claude plugin marketplace add https://github.com/Ninety2UA/agent-triforge",
    "claude plugin install agent-triforge@agent-triforge"
  ],
  "codex": [
    "codex plugin marketplace add Ninety2UA/agent-triforge",
    "codex plugin add agent-triforge@agent-triforge"
  ]
};

export const CLIS = [
  {
    "name": "Claude Code",
    "tier": "core",
    "roles": "Leads by default and builds.",
    "provider": "Anthropic"
  },
  {
    "name": "Antigravity",
    "tier": "core",
    "roles": "Maps the codebase and writes docs.",
    "provider": "Google"
  },
  {
    "name": "Codex",
    "tier": "core",
    "roles": "Reviews and tests. Can lead.",
    "provider": "OpenAI"
  },
  {
    "name": "OpenCode",
    "tier": "opt",
    "roles": "Any role.",
    "provider": "Zhipu (Z.ai) via OpenRouter"
  },
  {
    "name": "Kimi Code",
    "tier": "opt",
    "roles": "Any role.",
    "provider": "Moonshot"
  },
  {
    "name": "Cursor",
    "tier": "opt",
    "roles": "Any role.",
    "provider": "xAI via Cursor"
  },
  {
    "name": "Grok Build",
    "tier": "opt",
    "roles": "Builder, reviewer or analyst.",
    "provider": "xAI"
  },
  {
    "name": "Devin",
    "tier": "opt",
    "roles": "Reviewer or analyst, after your consent.",
    "provider": "Cognition"
  }
];

export const ROLES = [
  {
    "role": "builder",
    "does": "Writes the code for a task",
    "cli": "Claude Code",
    "fallback": "Codex, then Antigravity"
  },
  {
    "role": "reviewer",
    "does": "Reviews every task it didn't build",
    "cli": "Codex",
    "fallback": "Antigravity, then Claude Code"
  },
  {
    "role": "tester",
    "does": "Writes the failing test first",
    "cli": "Codex",
    "fallback": "Claude Code"
  },
  {
    "role": "analyst",
    "does": "Maps the codebase before planning",
    "cli": "Antigravity",
    "fallback": "Claude Code"
  },
  {
    "role": "documenter",
    "does": "Writes the documentation",
    "cli": "Antigravity",
    "fallback": "Claude Code"
  }
];

export const LEAD_SKILLS = ["at-ship", "at-coordinate", "at-plan", "at-build", "at-review", "at-test", "at-wrap", "at-quick", "at-debug", "at-deep-research", "at-analyze", "at-status", "at-pause", "at-resume", "at-compound", "at-resolve-pr", "at-setup"];

export const PORTABLE = ["codebase-mapping", "writing-plans", "shadow-path-tracing", "wave-orchestration", "iterative-refinement", "review-synthesis", "verification-before-completion", "knowledge-compounding", "session-continuity", "scope-cutting"];

export const FEATURED = [
  {
    "name": "at-ship",
    "group": "sprint",
    "groupLabel": "Full sprint",
    "lead": true,
    "summary": "One sprint on its own: analyze, plan, build, review, test, wrap, then mark it complete.",
    "use": "Use it when a scoped goal should ship in one run."
  },
  {
    "name": "at-coordinate",
    "group": "sprint",
    "groupLabel": "Full sprint",
    "lead": true,
    "summary": "The plain Phase 0 to 6 cycle that coordinate.sh drives, session after session.",
    "use": "Use it for the same sprint without convergence or team flags."
  },
  {
    "name": "at-plan",
    "group": "plan",
    "groupLabel": "Plan",
    "lead": true,
    "summary": "Turns a goal into ops/TASKS.md with waves, failure paths and a plan-checker verdict.",
    "use": "Use it when you want to read the plan before anything is built."
  },
  {
    "name": "at-build",
    "group": "build",
    "groupLabel": "Build",
    "lead": true,
    "summary": "Builds tasks in waves, pins a reviewer to each and merges what passes.",
    "use": "Use it when ops/TASKS.md holds assigned tasks."
  },
  {
    "name": "at-review",
    "group": "review",
    "groupLabel": "Review",
    "lead": true,
    "summary": "Review lanes from the roster plus specialist reviewers, merged into one report.",
    "use": "Use it when built tasks need Phase 3 and 4 review."
  },
  {
    "name": "at-test",
    "group": "test",
    "groupLabel": "Test",
    "lead": true,
    "summary": "Finds untested paths, gets tests from the roster tester, fixes until green.",
    "use": "Use it when changed code needs Phase 5 testing."
  },
  {
    "name": "at-wrap",
    "group": "wrap",
    "groupLabel": "Wrap",
    "lead": true,
    "summary": "Records what was learned, archives review files, writes STATE.md, marks completion.",
    "use": "Use it when a sprint or a session ends."
  },
  {
    "name": "at-quick",
    "group": "utility",
    "groupLabel": "Utility",
    "lead": true,
    "summary": "A test-first change with a self-review and no swarm.",
    "use": "Use it for fewer than 3 files with no shared interface or protected path."
  },
  {
    "name": "at-debug",
    "group": "utility",
    "groupLabel": "Utility",
    "lead": true,
    "summary": "Reproduce, find the root cause with evidence, fix, write it down.",
    "use": "Use it when a bug report or an error needs a cause."
  },
  {
    "name": "wave-orchestration",
    "group": "portable",
    "groupLabel": "Phase 2",
    "lead": false,
    "summary": "Leases, pinned cross-review and merges in wave order.",
    "use": "Use it when a validated plan has two or more tasks."
  },
  {
    "name": "verification-before-completion",
    "group": "portable",
    "groupLabel": "Every role",
    "lead": false,
    "summary": "Fresh evidence behind every claim that something is done.",
    "use": "Use it before calling anything done."
  },
  {
    "name": "knowledge-compounding",
    "group": "portable",
    "groupLabel": "Phase 6",
    "lead": false,
    "summary": "Writes a note only when a future agent would repeat the mistake without it.",
    "use": "Use it when a task ends with something learned."
  }
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
    "who": "Reviewer lanes from the roster, plus three personas."
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

export const PERSONAS = [
  {
    "name": "security-sentinel",
    "what": "Reviews for security and nothing else: OWASP-class issues, in depth.",
    "neverDowngraded": true
  },
  {
    "name": "performance-oracle",
    "what": "Finds bottlenecks and scaling problems, such as nested loops over the same data.",
    "neverDowngraded": false
  },
  {
    "name": "code-simplicity-reviewer",
    "what": "Flags complexity the change does not need, like an interface with one implementation.",
    "neverDowngraded": false
  },
  {
    "name": "findings-synthesizer",
    "what": "Reads every review file, removes duplicates, sets confidence tiers and writes one report.",
    "neverDowngraded": true
  },
  {
    "name": "plan-checker",
    "what": "Checks the plan before anything is built, and keeps checking until it approves.",
    "neverDowngraded": true
  }
];

export const FIELD_CAPS = [
  "Eight coding agents. Claude Code, Antigravity and Codex are always on the team; the other five join when you add them.",
  "You give the lead a goal. Here Claude Code leads.",
  "The lead splits the goal into tasks, each in its own workspace.",
  "Claude Code builds task 1.",
  "Codex reviews task 1. It didn't write it.",
  "The lead merges task 1 onto the shared branch.",
  "Claude Code builds task 2.",
  "Claude Code tries to review its own task. An agent can't review its own work.",
  "Codex reviews task 2 instead.",
  "The lead merges task 2. Every change was reviewed by an agent that didn't write it."
];
