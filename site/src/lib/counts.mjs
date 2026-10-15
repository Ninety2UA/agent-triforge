// The counts the pages state (KTD17), each from the data the pages render, so a count and the list it
// counts cannot differ. Pages wrap each one in a data-claim element that the site gate checks. Phases,
// quality gates, review lanes and fix cycles are prose, not counts, and are not here.
//
// Exports
//   getCounts(root?)  { skills, leadSkills, portableSkills, personas, clis, roles, releases }; releases
//                     counts every changelog entry, the unversioned notes included
import { getPersonas } from './personas.mjs';
import { getReleases } from './releases.mjs';
import { REPO } from './repo.mjs';
import { getClis, getRoles } from './roster.mjs';
import { getSkills } from './skills.mjs';

/** @param {string} [root] */
export function getCounts(root = REPO) {
  const skills = getSkills(root);
  return {
    skills: skills.length,
    leadSkills: skills.filter((s) => s.lead).length,
    portableSkills: skills.filter((s) => !s.lead).length,
    personas: getPersonas(root).length,
    clis: getClis(root).length,
    roles: getRoles(root).length,
    releases: getReleases(root).length,
  };
}
