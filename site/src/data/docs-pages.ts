// Hand-written words for the Docs and Guides pages (R3). Every other word on those pages comes from the
// repo through the docs map. A description is written here only for a page whose source has no intro
// paragraph to describe it; the loops are the home page's, with the same text alternative and caption
// (components/home/Lease.astro and Unattended.astro).

/** Meta descriptions for pages whose source opens without a paragraph. */
export const DESCRIPTIONS: Record<string, string> = {
  upgrading: 'Moving a project from Triforge 3.x to 4: the at- workflow names, AGENTS.md in place of CLAUDE.md, personas, and how to roll back to 3.3.3.',
  faq: 'Short answers about Agent Triforge: existing projects, which CLIs and skills you need, personas, runs with nobody watching, updates and moving from 3.x.',
};

export interface Loop {
  name: string;
  short: string;
  label: string;
  caption: string;
  /** the id of the H2 the loop sits under; without one it sits under the opening section */
  under?: string;
}

/** The loop a page shows, by page slug. The lease loop opens the section it shows, so on a phone it
 *  starts below the first screen and its player loads after the page has painted. */
export const LOOPS: Record<string, Loop> = {
  leases: {
    under: 'one-task-start-to-finish',
    name: 'loop-lease',
    short: 'the lease loop',
    label: 'Loop: a task gets its own workspace, Claude Code builds it, Codex reviews it, and it is merged onto the shared branch. Then Claude Code tries to review its own task and is refused.',
    caption: 'One task from its own workspace to the merge, then a self-review that is refused',
  },
  'unattended-runs': {
    name: 'loop-unattended',
    short: 'the unattended loop',
    label: 'Loop: it runs on its own, one fresh lead session at a time, up to five. Each session first checks its records, and it stops once the sprint is finished and sends a notification.',
    caption: 'One fresh session at a time, each checking its records first, until the sprint is finished',
  },
};
