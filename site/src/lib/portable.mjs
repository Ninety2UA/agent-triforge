// How each CLI runs a portable skill, read from docs/skills.md (R2): the sentence in "Portable skills
// across the ... CLIs" that starts "Each harness invokes a skill in its own form:" and lists one form
// per harness, separated by " · ", each a code span with `name` standing for the skill and an optional
// note after it. A harness the sentence gains shows up on every portable skill page on the next build.
// Plain Node, no astro: imports.
//
// Exports
//   parseInvocations(markdown, file)  [{ harness, form, note }] in the sentence's order; note is the
//                                     Markdown after the code span, its brackets and final period
//                                     removed. Throws naming the file when the sentence is missing or a
//                                     form has no `name` placeholder.
//   portableInvocations(root?)        the same forms joined with the roster: [{ id, name, lead, form,
//                                     note }]. name is the CLI's registry name (Claude -> Claude Code,
//                                     agy -> Antigravity), lead 'claude-code' or 'codex' for a CLI that
//                                     can lead (the key Tabs.astro shares across pages), else null; id is
//                                     the lead key or the registry id, unique per form.
//   invocation(form, skill)           the form with the skill's name in place of `name`
import { REPO, read } from './repo.mjs';
import { getClis } from './roster.mjs';

const FILE = 'docs/skills.md';
const LEAD_IN = 'Each harness invokes a skill in its own form:';
const PLACEHOLDER = /\bname\b/;

/**
 * @param {string} markdown
 * @param {string} file
 * @returns {{ harness: string, form: string, note: string }[]}
 */
export function parseInvocations(markdown, file) {
  const line = markdown.split('\n').find((l) => l.startsWith(LEAD_IN));
  if (!line) throw new Error(`${file}: no line starting "${LEAD_IN}" to read the portable invocation forms from`);
  return line
    .slice(LEAD_IN.length)
    .trim()
    .split(' · ')
    .map((part) => {
      const m = part.trim().match(/^([^`]+?)\s+`([^`]+)`\s*(.*)$/);
      if (!m) throw new Error(`${file}: "${part.trim()}" is not "<harness> \`<form>\` <note>"`);
      const [, harness, form, rest] = m;
      if (!PLACEHOLDER.test(form)) throw new Error(`${file}: the ${harness} form "${form}" has no \`name\` placeholder`);
      const note = rest.trim().replace(/\.$/, '').replace(/^\((.*)\)$/, '$1').trim();
      return { harness, form, note };
    });
}

/** @param {string} form @param {string} skill */
export function invocation(form, skill) {
  return form.replace(PLACEHOLDER, skill);
}

const LEADS = { claude: 'claude-code', codex: 'codex' };

/** @param {string} [root] */
export function portableInvocations(root = REPO) {
  const clis = getClis(root);
  return parseInvocations(read(root, FILE), FILE).map(({ harness, form, note }) => {
    const h = harness.toLowerCase();
    const cli = clis.find((c) => c.id === h || c.binary === h || c.name.toLowerCase() === h || c.name.toLowerCase().startsWith(`${h} `));
    const lead = cli && cli.canLead ? (LEADS[/** @type {'claude' | 'codex'} */ (cli.id)] ?? null) : null;
    return { id: lead ?? cli?.id ?? h.replace(/[^a-z0-9]+/g, '-'), name: cli?.name ?? harness, lead, form, note };
  });
}
