// The sprint page's repo facts, read from the tables and lists that state them. Plain Node, no astro:
// imports; tested in site/test/sprint.test.mjs. The page's hand-written words sit in
// pages/sprint.astro, keyed by the phase ids below, and the page stops the build when a phase has none.
//
//   docs/workflows.md                               the Sprint Pipeline table (one row per phase) and the
//                                                   Quality Gates table
//   skills/iterative-refinement/SKILL.md            the Convergence modes table
//   skills/at-ship/references/completion-gating.md  the completion checklist (its numbered list)
//
// Cells are Markdown; links resolve through the route table (routes.mjs) against their own file, and
// cellHtml renders the code spans and links. A table or list that is missing stops the build naming
// the file.
//
// Exports
//   parsePipeline(text, where)    the Sprint Pipeline rows as raw cells: [{ phase, happens, agents, workflows }]
//   sprintPhases(root?)           [{ id, label, number, name, happensHtml, agentsHtml, workflowsHtml, workflows }]
//                                 in table order. label: the Phase cell ("0, Analyze"); number: "0", "1.5",
//                                 "3 and 4", or "" for Pre-plan; id: phase-0, phase-1-5, phase-3-and-4,
//                                 pre-plan; workflows: the lead workflow names its last cell links.
//   qualityGates(root?)           [{ number, name, enforcedByHtml, rule }]
//   convergenceModes(root?)       [{ mode, exit, use, isDefault }]: mode is the flag value (fast, standard,
//                                 deep), exit the exit criteria as the skill writes them
//   completionChecklist(root?)    the checklist items, as inline HTML
//   cellHtml(markdown)            one line of Markdown as HTML: text escaped, code spans and links rendered
import { REPO, read } from './repo.mjs';
import { rewriteLinks } from './routes.mjs';
import { codeSpans, escapeHtml, githubSlug, parseHeadings, parseTables } from './text.mjs';

const WORKFLOWS = 'docs/workflows.md';
const REFINEMENT = 'skills/iterative-refinement/SKILL.md';
const GATING = 'skills/at-ship/references/completion-gating.md';

const esc = escapeHtml;
const CODE = /(`+)([\s\S]*?[^`])\1(?!`)/g;
const code = (s) => {
  let out = '';
  let at = 0;
  for (const m of s.matchAll(CODE)) {
    out += esc(s.slice(at, m.index)) + `<code>${esc(m[2].trim())}</code>`;
    at = m.index + m[0].length;
  }
  return out + esc(s.slice(at));
};

/** @param {string} markdown */
export function cellHtml(markdown) {
  const LINK = /\[((?:[^[\]]|\[[^\]]*\])*)\]\(([^)\s]+)\)/g;
  let out = '';
  let at = 0;
  for (const m of markdown.matchAll(LINK)) {
    out += code(markdown.slice(at, m.index)) + `<a href="${esc(m[2])}">${code(m[1])}</a>`;
    at = m.index + m[0].length;
  }
  return out + code(markdown.slice(at));
}

// The first table in the section under the heading that starts with `heading` (without its #s).
function tableUnder(text, heading, where) {
  const lines = text.split('\n');
  const h = parseHeadings(text).find((x) => x.text.startsWith(heading));
  const table = h && parseTables(lines).find((t) => t.line > h.line && t.line < h.end);
  if (!table) throw new Error(`${where}: no table under "${'#'.repeat(h?.depth ?? 2)} ${heading}"`);
  return table;
}

/** @param {string} text @param {string} where */
export function parsePipeline(text, where = WORKFLOWS) {
  const table = tableUnder(text, 'Sprint Pipeline', where);
  if (table.header.length !== 4) throw new Error(`${where}: the Sprint Pipeline table has ${table.header.length} columns; the site reads Phase, What happens, Agents, Lead workflow`);
  return table.rows.map(([phase, happens, agents, workflows]) => ({ phase, happens, agents, workflows }));
}

const cache = new Map();
const once = (key, make) => {
  if (!cache.has(key)) cache.set(key, make());
  return cache.get(key);
};

/** @param {string} [root] */
export function sprintPhases(root = REPO) {
  return once(`phases:${root}`, () => {
    const cell = (md) => cellHtml(rewriteLinks(md, WORKFLOWS, { root }));
    return parsePipeline(read(root, WORKFLOWS)).map((row) => {
      const m = row.phase.match(/^([\d.]+(?: and [\d.]+)?), (.+)$/);
      const number = m ? m[1] : '';
      const name = m ? m[2] : row.phase;
      return {
        id: number ? `phase-${githubSlug(number.replace(/\./g, ' '))}` : githubSlug(name),
        label: row.phase,
        number,
        name,
        happensHtml: cell(row.happens),
        agentsHtml: cell(row.agents),
        workflowsHtml: cell(row.workflows),
        workflows: codeSpans(row.workflows),
      };
    });
  });
}

/** @param {string} [root] */
export function qualityGates(root = REPO) {
  return once(`gates:${root}`, () => {
    const table = tableUnder(read(root, WORKFLOWS), 'Quality Gates', WORKFLOWS);
    return table.rows.map(([gate, enforcedBy, rule]) => {
      const m = gate.match(/^(\d+), (.+)$/);
      if (!m) throw new Error(`${WORKFLOWS}: the quality gate "${gate}" is not "<number>, <name>"`);
      return { number: m[1], name: m[2], enforcedByHtml: cellHtml(rewriteLinks(enforcedBy, WORKFLOWS, { root })), rule };
    });
  });
}

/** @param {string} [root] */
export function convergenceModes(root = REPO) {
  return once(`modes:${root}`, () => {
    const table = tableUnder(read(root, REFINEMENT), 'Convergence modes', REFINEMENT);
    return table.rows.map(([mode, exit, use]) => ({
      mode: mode.toLowerCase(),
      exit,
      use: use.replace(/\s*\(default\)\s*/i, ''),
      isDefault: /\(default\)/i.test(use),
    }));
  });
}

/** @param {string} [root] */
export function completionChecklist(root = REPO) {
  return once(`checklist:${root}`, () => {
    const items = read(root, GATING).split('\n').filter((l) => /^\d+\. /.test(l)).map((l) => cellHtml(l.replace(/^\d+\. /, '')));
    if (!items.length) throw new Error(`${GATING}: no numbered checklist`);
    return items;
  });
}
