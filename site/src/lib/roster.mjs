// The roster: the five roles from templates/ops/roster.toml and the eight CLIs, read as text from the
// CLI registry in scripts/lib/registry.sh (never run) and the table in docs/compatibility.md. Plain
// Node, no astro: imports.
//
// The registry is the CLI list: ids, core or optional, the provider that sees the code (egress), the
// roles a CLI may take, consent, and whether it can lead (a non-empty `lead` profile: Claude Code and
// Codex). docs/compatibility.md gives each CLI's display name (its CLI cell without the binary and a
// trailing " CLI": "Devin CLI (`devin`)" -> "Devin"), floor, tested version and READY probe; the rows
// join on the binary. A registry CLI with no compatibility row, or a row with no registry CLI, stops
// the build naming it.
//
// Exports
//   ROLE_NAMES               the five roles, in roster order
//   parseRegistry(text)      the registry's CLIS dict, from the Python literal in _TRIFORGE_CLIS_PY
//   getClis(root?)           [{ id, name, tier: 'core' | 'optional', core, binary, egress, provider, model,
//                            roles, optInRoles, consent, canLead, floor, tested, probe }] in registry order.
//                            roles: the roles it may take (all five unless the registry limits them);
//                            optInRoles: roles it takes only after a separate opt-in (Devin: builder);
//                            consent: it joins only with the user's recorded consent; provider: egress up
//                            to its first comma or parenthesis ("Zhipu / Z.ai").
//   CORE_TRIO                the core-tier ids, in registry order
//   getRoles(root?)          [{ role, cli, cliName, model, effort, fallbacks: [{ cli, cliName }] }] in the
//                            template's order; model '' means the CLI's own default
import { REPO, read } from './repo.mjs';
import { codeSpans, parseTables, parseToml } from './text.mjs';

export const ROLE_NAMES = ['builder', 'reviewer', 'tester', 'analyst', 'documenter'];

// ---- A reader for the Python literal the registry holds: dicts, lists, strings, numbers,
// True/False/None and # comments. Strings use the escapes JSON shares with Python.
function tokenize(text, where) {
  const tokens = [];
  const re = /\s+|#[^\n]*|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?)|(True|False|None)|([{}[\]:,=])|([A-Za-z_][A-Za-z0-9_]*)/y;
  let m;
  while (re.lastIndex < text.length) {
    const at = re.lastIndex;
    if (!(m = re.exec(text))) throw new Error(`${where}: cannot read the registry at "${text.slice(at, at + 30)}"`);
    if (m[1]) tokens.push({ value: JSON.parse(m[1]) });
    else if (m[2]) tokens.push({ value: Number(m[2]) });
    else if (m[3]) tokens.push({ value: { True: true, False: false, None: null }[m[3]] });
    else if (m[4]) tokens.push({ punct: m[4] });
    else if (m[5]) tokens.push({ name: m[5] });
  }
  return tokens;
}

function parseLiteral(tokens, where) {
  let i = 0;
  const expect = (punct) => {
    if (tokens[i]?.punct !== punct) throw new Error(`${where}: expected "${punct}" in the registry`);
    i++;
  };
  const value = () => {
    const t = tokens[i];
    if (t?.punct === '{') {
      i++;
      const obj = {};
      while (tokens[i]?.punct !== '}') {
        const key = value();
        expect(':');
        obj[key] = value();
        if (tokens[i]?.punct === ',') i++;
      }
      i++;
      return obj;
    }
    if (t?.punct === '[') {
      i++;
      const list = [];
      while (tokens[i]?.punct !== ']') {
        list.push(value());
        if (tokens[i]?.punct === ',') i++;
      }
      i++;
      return list;
    }
    if (t && 'value' in t) {
      i++;
      return t.value;
    }
    throw new Error(`${where}: unexpected token in the registry`);
  };
  if (tokens[i]?.name !== 'CLIS') throw new Error(`${where}: the registry does not start with CLIS = {...}`);
  i++;
  expect('=');
  return value();
}

/** @param {string} text  scripts/lib/registry.sh */
export function parseRegistry(text, where = 'scripts/lib/registry.sh') {
  const m = text.match(/^_TRIFORGE_CLIS_PY='\n([\s\S]*?)\n'$/m);
  if (!m) throw new Error(`${where}: no _TRIFORGE_CLIS_PY='...' block`);
  return parseLiteral(tokenize(m[1], where), where);
}

const cache = new Map();

/** @param {string} [root] */
export function getClis(root = REPO) {
  if (cache.has(root)) return cache.get(root);
  const registry = parseRegistry(read(root, 'scripts/lib/registry.sh'));
  const file = 'docs/compatibility.md';
  const table = parseTables(read(root, file).split('\n')).find((t) => t.header[0] === 'CLI');
  if (!table) throw new Error(`${file}: no table headed "CLI"`);
  const col = (name) => table.header.findIndex((h) => h.startsWith(name));
  const [floor, tested, probe] = [col('Floor'), col('Tested'), col('READY')];
  const rows = table.rows.map((cells) => ({ cells, binary: codeSpans(cells[0])[0] }));

  const problems = [];
  const clis = Object.entries(registry).map(([id, cli]) => {
    const row = rows.find((r) => r.binary === cli.binary);
    if (!row) {
      problems.push(`the registry CLI "${id}" (binary ${cli.binary}) has no row in ${file}`);
      return null;
    }
    const limit = Array.isArray(cli.role_limit) && cli.role_limit.length ? cli.role_limit : ROLE_NAMES;
    return {
      id,
      name: row.cells[0].replace(/\s*\(.*$/, '').replace(/ CLI$/, '').trim(),
      tier: cli.tier === 'core' ? 'core' : 'optional',
      core: cli.tier === 'core',
      binary: cli.binary,
      egress: cli.egress,
      provider: String(cli.egress).split(/\s*[,(]/)[0].trim(),
      model: cli.model,
      roles: ROLE_NAMES.filter((r) => limit.includes(r)),
      optInRoles: cli.opt_in_roles ?? [],
      consent: cli.consent === true,
      canLead: Boolean(cli.lead && Object.keys(cli.lead).length),
      floor: floor === -1 ? '' : row.cells[floor],
      tested: tested === -1 ? '' : row.cells[tested],
      probe: probe === -1 ? '' : (codeSpans(row.cells[probe])[0] ?? ''),
    };
  });
  for (const row of rows) {
    if (!Object.values(registry).some((cli) => cli.binary === row.binary)) problems.push(`${file} lists "${row.cells[0]}", which is not in the registry`);
  }
  if (problems.length) throw new Error(`CLIs:\n  ${problems.join('\n  ')}`);
  cache.set(root, clis);
  return clis;
}

export const CORE_TRIO = getClis().filter((c) => c.core).map((c) => c.id);

/** @param {string} [root] */
export function getRoles(root = REPO) {
  const file = 'templates/ops/roster.toml';
  const roles = parseToml(read(root, file), file).roles ?? {};
  const names = new Map(getClis(root).map((c) => [c.id, c.name]));
  const nameOf = (id) => {
    if (!names.has(id)) throw new Error(`${file}: "${id}" is not a CLI in the registry`);
    return names.get(id);
  };
  return Object.entries(roles).map(([role, r]) => ({
    role,
    cli: r.cli,
    cliName: nameOf(r.cli),
    model: r.model ?? '',
    effort: r.effort ?? '',
    fallbacks: (r.fallbacks ?? []).map((cli) => ({ cli, cliName: nameOf(cli) })),
  }));
}
