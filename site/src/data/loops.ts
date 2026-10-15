// The four loops the site plays and their words, and the film's text alternative. Every page that
// shows a loop (the home page, the guides, roster, sprint and the media kit) takes them from here, so a
// loop reads the same everywhere.

export interface LoopWords {
  /** file name under /media/ without extension: the .mp4 and its poster */
  name: string;
  /** names the loop on the Play button */
  short: string;
  /** what the loop shows, in plain words: the text alternative */
  label: string;
  /** the line under the figure */
  caption: string;
  /** its name in the media kit */
  title: string;
}

export const LOOP = {
  roster: {
    name: 'loop-roster',
    short: 'the roster loop',
    label: 'Loop: Claude Code leads and builds, Codex reviews and tests, Antigravity analyzes and documents. When Codex is missing, the others take its work, and then Codex leads instead.',
    caption: 'Default roles, the others covering for a missing agent, and Codex taking the lead',
    title: 'Roles and fallbacks',
  },
  lease: {
    name: 'loop-lease',
    short: 'the lease loop',
    label: 'Loop: a task gets its own workspace, Claude Code builds it, Codex reviews it, and it is merged onto the shared branch. Then Claude Code tries to review its own task and is refused.',
    caption: 'One task from its own workspace to the merge, then a self-review that is refused',
    title: "One task's life",
  },
  review: {
    name: 'loop-review',
    short: 'the review loop',
    label: 'Loop: five reviewers read the change at once, their findings are counted as critical, important and minor, the fixes go in, and on the second pass only minor findings are left, so it stops.',
    caption: 'Five reviewers at once, the fixes, and a second pass with only minor findings left',
    title: 'Reviews until findings converge',
  },
  unattended: {
    name: 'loop-unattended',
    short: 'the unattended loop',
    label: 'Loop: it runs on its own, one fresh lead session at a time, up to five. Each session first checks its records, and it stops once the sprint is finished and sends a notification.',
    caption: 'One fresh session at a time, each checking its records first, until the sprint is finished',
    title: 'Unattended runs',
  },
} satisfies Record<string, LoopWords>;

/** the film's text alternative, given its length in seconds */
export const filmLabel = (duration: number) =>
  `Film, ${Math.round(duration)} seconds, no sound: an example sprint that rate-limits a login endpoint, from the goal to the finished, reviewed work, chapter by chapter.`;

/** in the order the home page shows them */
export const LOOP_ORDER: LoopWords[] = [LOOP.roster, LOOP.lease, LOOP.review, LOOP.unattended];

/** The props a VideoFigure takes from a loop's words. */
export const figure = ({ name, short, label, caption }: Pick<LoopWords, 'name' | 'short' | 'label' | 'caption'>) => ({ name, short, label, caption });
