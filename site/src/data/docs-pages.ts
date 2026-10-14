// Hand-written words for the Docs and Guides pages (R3). Every other word on those pages comes from the
// repo through the docs map. A description is written here only for a page whose source has no intro
// paragraph to describe it. The loops and their words come from data/loops.ts.
import { LOOP, figure } from './loops';

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
  leases: { ...figure(LOOP.lease), under: 'one-task-start-to-finish' },
  'unattended-runs': figure(LOOP.unattended),
};
