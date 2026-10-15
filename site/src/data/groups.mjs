// The skill catalog's groups (KTD5, R4), in catalog order. Each lead skill (an at- folder under
// skills/) is listed in exactly one group; the build fails naming any lead skill with no group or
// two. Portable skills (no at- prefix) group as Portable on their own and are never listed here.
// A new lead skill needs one line here, and nothing else on the site.
//
// The groups and their members come from the approved site facts (FACTS.md, "Skills"). The order
// inside a group is the order the catalog shows.

/** @typedef {{ key: string, label: string, skills: string[] }} SkillGroup */

/** @type {SkillGroup[]} */
export const GROUPS = [
  { key: 'full-sprint', label: 'Full sprint', skills: ['at-ship', 'at-coordinate'] },
  { key: 'plan', label: 'Plan', skills: ['at-plan'] },
  { key: 'build', label: 'Build', skills: ['at-build'] },
  { key: 'review', label: 'Review', skills: ['at-review'] },
  { key: 'test', label: 'Test', skills: ['at-test'] },
  { key: 'wrap', label: 'Wrap', skills: ['at-wrap'] },
  { key: 'session', label: 'Session', skills: ['at-pause', 'at-resume'] },
  { key: 'knowledge', label: 'Knowledge', skills: ['at-compound'] },
  { key: 'utility', label: 'Utility', skills: ['at-quick', 'at-debug', 'at-deep-research', 'at-analyze', 'at-status', 'at-resolve-pr'] },
  { key: 'setup', label: 'Setup', skills: ['at-setup'] },
];

/** The group every portable skill belongs to; always last in the catalog. */
export const PORTABLE = { key: 'portable', label: 'Portable' };

/** Lead workflows carry this folder-name prefix. */
export const LEAD_PREFIX = 'at-';
