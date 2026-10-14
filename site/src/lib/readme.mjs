// What the site reads from README.md (and the install table of docs/installation.md): the install
// commands, the FAQ, any section, and the release-history table. Plain Node, no astro: imports.
// Every reader throws naming the README section (or file) when what it reads is missing.
//
// Exports
//   readmeSection(heading, root?)  the section's Markdown without its own heading, links resolved
//                                  through routes.mjs from README.md
//   installCommands(root?)         { claude: string[], codex: string[], skillsOnly: [{ cli, lines, invoke }] }.
//                                  claude and codex: the command lines of the first fenced block under
//                                  "Install", grouped by the comment above them ("# Claude Code leads",
//                                  "# Codex leads"), exactly as written. skillsOnly: the "Portable skills in
//                                  Devin and Pi" table of docs/installation.md, one entry per row: cli is the
//                                  Harness cell, lines the Install cell's commands (its code spans with a
//                                  space, outside parentheses, which hold the alternatives), invoke the
//                                  Invoke cell's form ("/skill:<name>").
//   faq(root?)                     [{ question, anchor, answer }] from the <details> blocks under "FAQ";
//                                  answer is the block's Markdown and HTML with links resolved
//   releaseTable(root?)            [{ version, date, file, summary }] from the "Release history" table,
//                                  newest first; version without the "v", null for an unversioned row;
//                                  file the repo path the row links to
import { REPO, read } from './repo.mjs';
import { rewriteLinks } from './routes.mjs';
import { codeSpans, fenceStep, githubSlug, maskCode, parseHeadings, parseTables } from './text.mjs';

function sectionLines(root, file, heading) {
  const text = read(root, file);
  const h = parseHeadings(text).find((x) => x.text === heading);
  if (!h) throw new Error(`${file}: section "${heading}" not found`);
  return text.split('\n').slice(h.line + 1, h.end);
}

/**
 * @param {string} heading
 * @param {string} [root]
 */
export function readmeSection(heading, root = REPO) {
  return rewriteLinks(sectionLines(root, 'README.md', heading).join('\n').trim(), 'README.md', { root });
}

// The lines inside the first fenced block.
function firstFence(lines, where) {
  let fence = null;
  let inside = false;
  const body = [];
  for (const line of lines) {
    const opening = fence === null;
    fence = fenceStep(line, fence).fence;
    if (!inside) {
      inside = opening && fence !== null;
    } else if (fence === null) {
      return body;
    } else {
      body.push(line);
    }
  }
  throw new Error(`${where}: no closed fenced code block`);
}

/** @param {string} [root] */
export function installCommands(root = REPO) {
  const where = 'README.md "Install"';
  const groups = { claude: [], codex: [] };
  let current = null;
  for (const line of firstFence(sectionLines(root, 'README.md', 'Install'), where)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (trimmed.startsWith('#')) {
      current = /\bcodex\b/i.test(trimmed) ? 'codex' : /\bclaude\b/i.test(trimmed) ? 'claude' : null;
      continue;
    }
    if (!current) throw new Error(`${where}: the command "${trimmed}" has no "# Claude Code leads" or "# Codex leads" comment above it`);
    groups[current].push(trimmed);
  }
  for (const [lead, lines] of Object.entries(groups)) if (!lines.length) throw new Error(`${where}: the install block has no ${lead} commands`);

  const file = 'docs/installation.md';
  const table = parseTables(sectionLines(root, file, 'Portable skills in Devin and Pi')).find((t) => t.header[0] === 'Harness');
  if (!table) throw new Error(`${file} "Portable skills in Devin and Pi": no table headed "Harness"`);
  const col = (name) => {
    const i = table.header.indexOf(name);
    if (i === -1) throw new Error(`${file} "Portable skills in Devin and Pi": the table has no "${name}" column`);
    return i;
  };
  const [install, invoke] = [col('Install'), col('Invoke')];
  const skillsOnly = table.rows.map((cells) => {
    const { text, restore } = maskCode(cells[install]);
    const lines = codeSpans(restore(text.replace(/\([^()]*\)/g, ''))).filter((span) => /\s/.test(span));
    if (!lines.length) throw new Error(`${file}: the ${cells[0]} row has no install command`);
    return { cli: cells[0], lines, invoke: codeSpans(cells[invoke])[0] ?? '' };
  });
  return { ...groups, skillsOnly };
}

/** @param {string} [root] */
export function faq(root = REPO) {
  const text = sectionLines(root, 'README.md', 'FAQ').join('\n');
  const items = [...text.matchAll(/<details>\s*<summary>([\s\S]*?)<\/summary>([\s\S]*?)<\/details>/g)].map(([, summary, answer]) => {
    const question = summary.replace(/<[^>]+>/g, '').trim();
    return { question, anchor: githubSlug(question), answer: rewriteLinks(answer.trim(), 'README.md', { root }) };
  });
  if (!items.length) throw new Error('README.md "FAQ": no <details> question');
  return items;
}

/** @param {string} [root] */
export function releaseTable(root = REPO) {
  const where = 'README.md "Release history"';
  const table = parseTables(sectionLines(root, 'README.md', 'Release history')).find((t) => t.header.join(' | ') === 'Version | Date | Summary');
  if (!table) throw new Error(`${where}: no "Version | Date | Summary" table`);
  return table.rows.map(([cell, date, summary]) => {
    const link = cell.match(/^\[([^\]]+)\]\(([^)\s]+)\)$/);
    if (!link) throw new Error(`${where}: the Version cell "${cell}" is not a single link to the notes file`);
    const version = link[1].match(/^v(\d+\.\d+\.\d+)$/)?.[1] ?? null;
    return { version, date, file: link[2].replace(/^\.\//, ''), summary };
  });
}
