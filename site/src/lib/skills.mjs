// The skills: one record per skills/<name>/SKILL.md, with its catalog group and its one-line summary.
// Plain Node, no astro: imports.
//
// Lead workflows are the folders with the at- prefix; every other folder is a portable skill. The
// summary is the skill's row in the "Lead workflows reference" table of docs/workflows.md or in the
// portable-skills table of docs/skills.md, with links reduced to their text (a card is itself a link);
// a skill in neither table falls back to its frontmatter description, so a new skill still publishes.
//
// Exports
//   groupSkills(names, groups?)   Map of skill name -> { key, label }. Throws, naming every offender, when
//                                 a lead skill is in no group or in two, when a portable skill is listed in
//                                 a group (it belongs to Portable), or when a group lists a skill that has no
//                                 folder.
//   getSkills(root?)              [{ name, lead, group: { key, label }, description, summary, argumentHint,
//                                 body, path }] in catalog order (group order, then the order inside the
//                                 group; portable skills in docs/skills.md table order). body is the SKILL.md
//                                 text after the frontmatter with every link already resolved through
//                                 routes.mjs; render it with the SKILL.md path as fileURL so
//                                 markdown/escape-skill-html.mjs keeps raw text such as <base-branch> visible.
//                                 path is "skills/<name>/SKILL.md".
//   skillGroups(root?)            [{ key, label, count }] in catalog order, Portable last.
import { GROUPS, LEAD_PREFIX, PORTABLE } from '../data/groups.mjs';
import { REPO, read } from './repo.mjs';
import { rewriteLinks } from './routes.mjs';
import { listSkillFolders } from './sources.mjs';
import { parseHeadings, parseTables, plainInline, readFrontmatter, splitFrontmatter } from './text.mjs';

/**
 * @param {string[]} names
 * @param {import('../data/groups.mjs').SkillGroup[]} [groups]
 * @returns {Map<string, { key: string, label: string }>}
 */
export function groupSkills(names, groups = GROUPS) {
  const problems = [];
  const where = 'site/src/data/groups.mjs';
  const known = new Set(names);
  for (const group of groups) {
    for (const skill of group.skills) if (!known.has(skill)) problems.push(`${where} lists "${skill}" in ${group.label}, but skills/${skill}/SKILL.md does not exist`);
  }
  const out = new Map();
  for (const name of names) {
    const homes = groups.filter((g) => g.skills.includes(name));
    if (!name.startsWith(LEAD_PREFIX)) {
      if (homes.length) problems.push(`portable skill "${name}" is listed in ${homes.map((g) => g.label).join(' and ')}; portable skills group as ${PORTABLE.label} without an entry`);
      out.set(name, { key: PORTABLE.key, label: PORTABLE.label });
    } else if (homes.length === 0) {
      problems.push(`lead skill "${name}" has no catalog group: add it to one group in ${where}`);
    } else if (homes.length > 1) {
      problems.push(`lead skill "${name}" is in two groups or more (${homes.map((g) => g.label).join(', ')}): keep it in one in ${where}`);
    } else {
      out.set(name, { key: homes[0].key, label: homes[0].label });
    }
  }
  if (problems.length) throw new Error(`skill catalog groups:\n  ${problems.join('\n  ')}`);
  return out;
}

// name -> summary, from the first table of a section whose first column links each skill's SKILL.md.
function tableSummaries(root, file, heading, firstColumn) {
  const text = read(root, file);
  const lines = text.split('\n');
  const section = heading ? parseHeadings(text).find((h) => h.text === heading) : null;
  if (heading && !section) throw new Error(`${file}: no "${heading}" section for the skill summaries`);
  const table = parseTables(section ? lines.slice(section.line + 1, section.end) : lines).find((t) => t.header[0] === firstColumn);
  if (!table) throw new Error(`${file}: no table headed "${firstColumn}" for the skill summaries`);
  const out = new Map();
  for (const cells of table.rows) {
    const name = cells[0].match(/\]\((?:\.\.\/)?skills\/([^/)]+)\/SKILL\.md\)/)?.[1];
    if (name) out.set(name, plainInline(cells[cells.length - 1]));
  }
  return out;
}

const cache = new Map();

/** @param {string} [root] */
export function getSkills(root = REPO) {
  if (cache.has(root)) return cache.get(root);
  const folders = listSkillFolders(root);
  const groups = groupSkills(folders);
  const leadRows = tableSummaries(root, 'docs/workflows.md', 'Lead workflows reference', 'Lead workflow');
  const portableRows = tableSummaries(root, 'docs/skills.md', null, 'Skill');
  const portableOrder = [...portableRows.keys()];

  const rank = (name) => {
    const g = GROUPS.findIndex((x) => x.skills.includes(name));
    if (g !== -1) return [g, GROUPS[g].skills.indexOf(name), name];
    const p = portableOrder.indexOf(name);
    return [GROUPS.length, p === -1 ? portableOrder.length : p, name];
  };
  const byRank = (a, b) => {
    const [ra, rb] = [rank(a), rank(b)];
    return ra[0] - rb[0] || ra[1] - rb[1] || ra[2].localeCompare(rb[2]);
  };

  const skills = [...folders].sort(byRank).map((name) => {
    const path = `skills/${name}/SKILL.md`;
    const text = read(root, path);
    const meta = readFrontmatter(text, path);
    const lead = name.startsWith(LEAD_PREFIX);
    return {
      name,
      lead,
      group: groups.get(name),
      description: String(meta.description ?? ''),
      summary: (lead ? leadRows : portableRows).get(name) ?? String(meta.description ?? ''),
      argumentHint: meta['argument-hint'] ? String(meta['argument-hint']) : null,
      body: rewriteLinks(splitFrontmatter(text).body.replace(/^\n+/, ''), path, { root }),
      path,
    };
  });
  cache.set(root, skills);
  return skills;
}

/** @param {string} [root] */
export function skillGroups(root = REPO) {
  const skills = getSkills(root);
  return [...GROUPS, PORTABLE].map(({ key, label }) => ({ key, label, count: skills.filter((s) => s.group.key === key).length }));
}
