// llms.txt (https://llmstxt.org): the site's name and summary, then links to the home page, the main
// pages, every docs and guide page and every skill page with its one-line summary, all built from the
// repo's data, so a new or renamed skill or page changes it on the next build. Ported from Agent
// Blueprint's site. The dev-only media kit is never listed. Plain Node, no astro: imports.
//
// Exports
//   llmsTxt(nav, root?)   the file's text. `nav` is the header's sections ([{ label, href }], data/nav.ts):
//                         Skills, Roster, Sprint and Changelog take their address from it. Home comes
//                         first, then those pages and the personas page, then the Docs and Guides pages
//                         in reading order, then one list of skills per catalog group, in catalog order.
import { getCounts } from './counts.mjs';
import { sectionPages } from './docs.mjs';
import { personasPage } from './personas.mjs';
import { REPO } from './repo.mjs';
import { GH, RELEASED, SITE_URL, VERSION } from './site.mjs';
import { getSkills, skillGroups } from './skills.mjs';

const SUMMARY =
  'A multi-agent build framework: one coding CLI leads (Claude Code or Codex), the others build, review, test, ' +
  'analyze and document, and nothing merges until a different agent has reviewed it.';

// What each page holds, keyed by its header label.
const NOTES = {
  Skills: 'Every skill by group, with what it does and how to run it',
  Roster: 'Which coding agent takes which role, and who covers for a missing one',
  Sprint: 'The phases of one sprint, from planning to reviewed and tested work',
  Changelog: 'Every release, newest first',
};
const PERSONAS_NOTE = "The specialist prompts the lead hands work to, with each one's tools, model tier and turn budget";

/**
 * @param {readonly { label: string, href: string }[]} nav
 * @param {string} [root]
 */
export function llmsTxt(nav, root = REPO) {
  const link = (label, path, note) => `- [${label}](${SITE_URL}${path})${note ? `: ${note}` : ''}`;
  const page = (label) => {
    const item = nav.find((n) => n.label === label);
    if (!item) throw new Error(`llms.txt: the header has no "${label}" section (site/src/data/nav.ts)`);
    return link(label, item.href, NOTES[label]);
  };
  const counts = getCounts(root);
  const personas = personasPage(root);
  const skills = getSkills(root);
  const lines = [
    '# Agent Triforge',
    '',
    `> ${SUMMARY}`,
    '',
    `Version ${VERSION}, released ${RELEASED}. ${counts.skills} skills (${counts.leadSkills} lead workflows and ` +
      `${counts.portableSkills} portable skills), ${counts.personas} personas, ${counts.clis} coding CLIs. Source and install: ${GH}`,
    '',
    '## Pages',
    '',
    link('Home', '/', 'What Agent Triforge does, with a film of one sprint and the install commands'),
    page('Skills'),
    link(personas.title, personas.href, PERSONAS_NOTE),
    page('Roster'),
    page('Sprint'),
    page('Changelog'),
  ];
  for (const [heading, section] of [['Docs', 'docs'], ['Guides', 'guides']]) {
    lines.push('', `## ${heading}`, '', ...sectionPages(section, root).map((p) => link(p.title, p.href)));
  }
  for (const group of skillGroups(root)) {
    lines.push('', `## Skills: ${group.label}`, '');
    for (const skill of skills.filter((s) => s.group.key === group.key)) lines.push(link(skill.name, `/skills/${skill.name}/`, skill.summary));
  }
  return `${lines.join('\n')}\n`;
}
