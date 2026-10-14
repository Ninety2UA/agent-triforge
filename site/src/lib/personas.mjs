// The personas (KTD3): one record per personas/<name>.md, joined with its entry in
// personas/manifest.toml and its group row in docs/personas.md. Plain Node, no astro: imports.
//
// The personas page is /skills/personas/: one anchor per persona (#<name>) and per group (#<group>,
// the docs/personas.md heading without its count). A persona file with no manifest entry or no group
// row, or a row or entry with no file, stops the build naming it.
//
// Exports
//   getPersonas(root?)    [{ name, anchor, group: { key, label, anchor }, summary, class, tier,
//                         neverDowngrade, maxTurns, body, path }] in docs/personas.md order. summary is
//                         the row's last cell with links reduced to their text; body the prompt with
//                         links resolved through routes.mjs (render it with `path` as fileURL so raw
//                         text such as <agent> stays visible).
//   personaGroups(root?)  [{ key, label, anchor, count }] in docs/personas.md order
//   personasPage(root?)   { href, title, intro }: the page's title and the first paragraph of
//                         docs/personas.md, links resolved
import { PERSONAS_PAGE } from './docs-map.mjs';
import { REPO, read } from './repo.mjs';
import { rewriteLinks } from './routes.mjs';
import { listPersonaNames, readPersonaGroups } from './sources.mjs';
import { firstParagraph, parseHeadings, parseToml, plainInline } from './text.mjs';

const cache = new Map();

/** @param {string} [root] */
export function getPersonas(root = REPO) {
  if (cache.has(root)) return cache.get(root);
  const manifestFile = 'personas/manifest.toml';
  const manifest = parseToml(read(root, manifestFile), manifestFile).personas ?? {};
  const groups = readPersonaGroups(root);
  const files = new Set(listPersonaNames(root));
  const rows = groups.flatMap((group) => group.rows.map((row) => ({ ...row, group })));

  const problems = [];
  for (const name of files) {
    if (!rows.some((r) => r.name === name)) problems.push(`personas/${name}.md is in no group table of docs/personas.md`);
    if (!manifest[name]) problems.push(`personas/${name}.md has no [personas.${name}] entry in ${manifestFile}`);
  }
  for (const row of rows) if (!files.has(row.name)) problems.push(`docs/personas.md lists ${row.name}, but personas/${row.name}.md does not exist`);
  if (problems.length) throw new Error(`personas:\n  ${problems.join('\n  ')}`);

  const personas = rows.map(({ name, summary, group }) => {
    const path = `personas/${name}.md`;
    const entry = manifest[name];
    return {
      name,
      anchor: name,
      group: { key: group.key, label: group.label, anchor: group.anchor },
      summary: plainInline(summary),
      class: String(entry.class),
      tier: String(entry.tier),
      neverDowngrade: entry.never_downgrade === true,
      maxTurns: Number(entry.max_turns),
      body: rewriteLinks(read(root, path), path, { root }),
      path,
    };
  });
  cache.set(root, personas);
  return personas;
}

/** @param {string} [root] */
export function personaGroups(root = REPO) {
  const personas = getPersonas(root);
  return readPersonaGroups(root).map(({ key, label, anchor }) => ({ key, label, anchor, count: personas.filter((p) => p.group.key === key).length }));
}

/** @param {string} [root] */
export function personasPage(root = REPO) {
  const text = read(root, PERSONAS_PAGE.file);
  const h1 = parseHeadings(text).find((h) => h.depth === 1);
  const lines = text.split('\n');
  const intro = firstParagraph(lines, h1 ? h1.line + 1 : 0);
  return {
    href: PERSONAS_PAGE.href,
    title: h1?.text ?? 'Personas',
    intro: intro ? rewriteLinks(intro.text, PERSONAS_PAGE.file, { root }) : '',
  };
}
