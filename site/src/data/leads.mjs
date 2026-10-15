// The CLIs that can lead, as the site names them: the lead tabs' ids and labels, and the value a
// reader's choice is stored under (scripts/tabs.ts). Plain JavaScript, so the build's .mjs readers,
// the client scripts and node:test import the same list.
//
//   LEADS          ['claude-code', 'codex'], in tab order
//   LEAD_NAMES     { 'claude-code': 'Claude Code', codex: 'Codex' }
//   LEAD_TABS      [{ id, label, lead }] for a lead tab group: "Claude Code leads", then "Codex leads"
//   isLead(value)  true for one of LEADS

export const LEADS = /** @type {const} */ (['claude-code', 'codex']);
export const LEAD_NAMES = { 'claude-code': 'Claude Code', codex: 'Codex' };
export const LEAD_TABS = LEADS.map((lead) => ({ id: lead, label: `${LEAD_NAMES[lead]} leads`, lead }));

/** @param {unknown} value */
export const isLead = (value) => LEADS.includes(/** @type {any} */ (value));
