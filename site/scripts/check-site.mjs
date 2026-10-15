#!/usr/bin/env node
// check-site.mjs: the built-site gate. `npm run build` runs it after `astro build`, so a broken promise
// fails the Vercel deploy and the CI site job instead of shipping. It checks site/dist against the repo:
//
//   pages      one page per skill folder and per DOC_PAGES entry, and no page for a skill that is gone
//   claims     every element with data-claim="<kind>" states the repo's value: the first number in its
//              text, a numeral or a number word ("seventeen"). Text without data-claim makes no claim.
//   links      every root-relative href, src, poster and srcset candidate resolves to a file in the build
//              (a path ending in / means its index.html), no URL is a bare relative path, a fragment on a
//              site page names an id on that page, and every redirect in vercel.json lands on a page
//   meta       every page has a title, a description and a canonical link (404.html needs no canonical)
//   no SKILL   no SKILL.md is copied into the build
//   origins    no page loads a script, stylesheet, font, image or video from another origin
//   tokens     every skill token in the hand-written sources (/at-x, $agent-triforge:at-x, `at-x`) names a
//              skill that exists
//   counts     no literal count sits beside a counted noun in site/src (counts render from data); in the
//              motion compositions under site/motion/src the counts and CLI names match the repo
//
// Usage: node scripts/check-site.mjs [dist]   (dist defaults to site/dist)
// Exit codes: 0 the build matches the repo · 1 problems found (each printed, naming the file) ·
// 2 the build or a ground-truth source is missing.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { extname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { REPO, SITE } from '../src/lib/repo.mjs';
import { SITE_URL } from '../src/lib/site.mjs';
import { decodeEntities } from '../src/lib/text.mjs';

const NUMBER_WORDS = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen',
  'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty', 'fifty'];
const TENS = { twenty: 20, thirty: 30, forty: 40, fifty: 50 };

/** "seventeen" -> 17, "twenty-seven" -> 27, "27" -> 27; null when the text holds no number */
export function firstNumber(text) {
  const m = text.match(new RegExp(`(?<![\\w.])(\\d+|(?:${NUMBER_WORDS.join('|')})(?:[- ](?:${NUMBER_WORDS.slice(1, 10).join('|')}))?)(?![\\w.])`, 'i'));
  if (!m) return null;
  const word = m[1].toLowerCase();
  if (/^\d+$/.test(word)) return Number(word);
  const [a, b] = word.split(/[- ]/);
  const value = (w) => TENS[w] ?? NUMBER_WORDS.indexOf(w);
  return b ? value(a) + value(b) : value(a);
}

const decode = decodeEntities;
const attr = (tag, name) => {
  const m = tag.match(new RegExp(`\\s${name}=(?:"([^"]*)"|'([^']*)'|([^\\s>]+))`));
  return m ? decode(m[1] ?? m[2] ?? m[3]) : undefined;
};

/** Every HTML page in the build, by URL path, skipping Astro's and Pagefind's asset folders. */
export function readPages(dist) {
  const out = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) {
        if (dir === dist && ['_astro', 'pagefind', 'media', 'brand'].includes(name)) continue;
        walk(path);
      } else if (name.endsWith('.html')) {
        const rel = relative(dist, path).split(sep).join('/');
        const url = rel === 'index.html' ? '/' : rel.endsWith('/index.html') ? `/${rel.slice(0, -'index.html'.length)}` : `/${rel}`;
        out.push({ url, file: rel, html: readFileSync(path, 'utf8') });
      }
    }
  };
  walk(dist);
  return out;
}

const ids = (html) => new Set([...html.matchAll(/\sid="([^"]+)"/g)].map((m) => decode(m[1])));

/** The file a root-relative URL path serves from the build, or null. */
function target(dist, path) {
  const clean = decodeURIComponent(path.split('#')[0].split('?')[0]);
  const file = join(dist, clean.endsWith('/') ? `${clean}index.html` : clean);
  if (!file.startsWith(dist)) return null;
  return existsSync(file) && statSync(file).isFile() ? file : null;
}

// ---- the checks; each returns a list of problems, every one naming a file ----

// Every URL a tag makes the browser fetch or follow: href, src, poster and each srcset candidate.
const srcsetUrls = (value) => (value ?? '').split(',').map((c) => c.trim().split(/\s+/)[0]).filter(Boolean);
const urlsOf = (tag) => [
  ...['href', 'src', 'poster'].map((name) => [name, attr(tag, name)]),
  ...srcsetUrls(attr(tag, 'srcset')).map((url) => ['srcset', url]),
].filter(([, value]) => value);

// A URL the site writes: root-relative, a fragment, or one with a scheme (https:, mailto:, data:). A bare
// relative path ("models.md") resolves against the page's own folder, which is never what the repo meant.
const isRelativeUrl = (url) => !/^(?:\/|#|[a-z][a-z0-9+.-]*:)/i.test(url);

export function checkLinks(dist, pages) {
  const problems = [];
  const byFile = new Map(pages.map((p) => [join(dist, p.file), p]));
  for (const p of pages) {
    for (const [tag] of p.html.matchAll(/<(?:a|link|img|script|source|video|iframe)\b[^>]*>/g)) {
      for (const [name, value] of urlsOf(tag)) {
        if (isRelativeUrl(value)) {
          problems.push(`${p.file}: ${name}="${value}" is a relative URL; links on the site are root-relative`);
          continue;
        }
        if (!value.startsWith('/') || value.startsWith('//')) continue;
        const file = target(dist, value);
        if (!file) {
          problems.push(`${p.file}: ${name}="${value}" has no file in the build`);
          continue;
        }
        const hash = value.includes('#') ? value.slice(value.indexOf('#') + 1) : '';
        const page = byFile.get(file);
        if (hash && page && !ids(page.html).has(decodeURIComponent(hash))) problems.push(`${p.file}: ${name}="${value}" names no id on ${page.file}`);
      }
    }
    // in-page fragments
    for (const [, hash] of p.html.matchAll(/<a\b[^>]*\shref="#([^"]+)"/g)) {
      if (!ids(p.html).has(decodeURIComponent(decode(hash)))) problems.push(`${p.file}: href="#${hash}" names no id on the page`);
    }
  }
  return problems;
}

/** Every redirect lands on a page of the build. */
export function checkRedirects(dist, redirects) {
  return redirects
    .filter((r) => !target(dist, r.destination))
    .map((r) => `vercel.json: the redirect from ${r.source} goes to ${r.destination}, which has no page`);
}

export function checkMeta(pages) {
  const problems = [];
  for (const p of pages) {
    if (!/<title>[^<]+<\/title>/.test(p.html)) problems.push(`${p.file}: no <title>`);
    if (!/<meta name="description" content="[^"]+"/.test(p.html)) problems.push(`${p.file}: no meta description`);
    const canonical = /<link rel="canonical" href="[^"]+"/.test(p.html);
    if (p.file === '404.html' && canonical) problems.push('404.html: has a canonical link');
    if (p.file !== '404.html' && !canonical) problems.push(`${p.file}: no canonical link`);
  }
  return problems;
}

export function checkNoSkillFiles(dist) {
  const problems = [];
  const walk = (dir) => {
    for (const name of readdirSync(dir)) {
      const path = join(dir, name);
      if (statSync(path).isDirectory()) walk(path);
      else if (name === 'SKILL.md') problems.push(`${relative(dist, path)}: a SKILL.md was copied into the build`);
    }
  };
  walk(dist);
  return problems;
}

export function checkOrigins(pages) {
  const origin = new URL(SITE_URL).origin;
  const problems = [];
  const foreign = (url) => /^(https?:)?\/\//.test(url) && new URL(url, SITE_URL).origin !== origin;
  for (const p of pages) {
    for (const [tag, name] of p.html.matchAll(/<(script|img|video|source|iframe|audio|embed)\b[^>]*>/g)) {
      for (const [, url] of urlsOf(tag)) if (foreign(url)) problems.push(`${p.file}: <${name}> from ${url}`);
    }
    for (const [tag] of p.html.matchAll(/<link\b[^>]*>/g)) {
      const rel = (attr(tag, 'rel') ?? '').toLowerCase().split(/\s+/);
      const href = attr(tag, 'href');
      if (href && foreign(href) && rel.some((r) => ['stylesheet', 'preload', 'modulepreload', 'preconnect', 'dns-prefetch', 'icon'].includes(r))) {
        problems.push(`${p.file}: <link rel="${rel.join(' ')}"> to ${href}`);
      }
    }
    for (const [, url] of p.html.matchAll(/url\(\s*["']?([^"')]+)["']?\s*\)/g)) if (foreign(url)) problems.push(`${p.file}: CSS url(${url})`);
    for (const [, url] of p.html.matchAll(/@import\s+(?:url\()?["']([^"']+)["']/g)) if (foreign(url)) problems.push(`${p.file}: CSS @import ${url}`);
  }
  return problems;
}

/** Every element with data-claim="<kind>" states truth[kind]. */
export function checkClaims(pages, truth) {
  const problems = [];
  for (const p of pages) {
    for (const m of p.html.matchAll(/<([a-z0-9]+)\b[^>]*\sdata-claim="([^"]+)"[^>]*>([\s\S]*?)<\/\1>/g)) {
      const [, , kind, inner] = m;
      if (!(kind in truth)) {
        problems.push(`${p.file}: data-claim="${kind}" is not a known count (${Object.keys(truth).join(', ')})`);
        continue;
      }
      const text = decode(inner.replace(/<[^>]*>/g, ''));
      const n = firstNumber(text);
      if (n !== truth[kind]) problems.push(`${p.file}: data-claim="${kind}" says "${text.trim()}", the repo has ${truth[kind]}`);
    }
  }
  return problems;
}

/** One page per expected path, and no skill page for a skill that is gone. */
export function checkPages(dist, { skills, docRoutes }) {
  const problems = [];
  for (const name of skills) if (!target(dist, `/skills/${name}/`)) problems.push(`skills/${name}: no page at /skills/${name}/`);
  for (const { source, href } of docRoutes) if (!target(dist, href)) problems.push(`${source}: no page at ${href}`);
  const skillsDir = join(dist, 'skills');
  if (existsSync(skillsDir)) {
    for (const name of readdirSync(skillsDir)) {
      if (name === 'personas' || !statSync(join(skillsDir, name)).isDirectory()) continue;
      if (!skills.includes(name)) problems.push(`skills/${name}/index.html: a page for a skill that is not in skills/`);
    }
  }
  return problems;
}

// Files written by hand (not generated from the repo): the components, pages, data and hand-written
// content under site/src. Generated data modules (src/lib) are left out.
function handWritten() {
  const out = [];
  const walk = (dir) => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, e.name);
      if (e.isDirectory()) {
        if (p === join(SITE, 'src', 'lib')) continue;
        walk(p);
      } else if (['.astro', '.ts', '.tsx', '.mjs', '.md', '.mdx', '.json'].includes(extname(e.name))) out.push(p);
    }
  };
  walk(join(SITE, 'src'));
  return out;
}

/** Every skill token in the hand-written sources names a skill that exists. */
export function checkSkillTokens(skills, files = handWritten()) {
  const problems = [];
  const known = new Set(skills);
  const forms = [/(?<![\w/.-])\/(at-[a-z0-9-]+)/g, /\$agent-triforge:(at-[a-z0-9-]+)/g, /`(at-[a-z0-9-]+)`/g, /<code>\/?(at-[a-z0-9-]+)/g, /['"](at-[a-z0-9-]+)['"]/g];
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    for (const re of forms) {
      for (const m of text.matchAll(re)) {
        const name = m[1].replace(/-+$/, '');
        if (!known.has(name)) {
          const line = text.slice(0, m.index).split('\n').length;
          problems.push(`${relative(REPO, file)}:${line}: "${m[0]}" names no skill in skills/`);
        }
      }
    }
  }
  return problems;
}

const COUNTED = '(?:lead\\s+)?(?:skills|workflows|personas|CLIs|coding\\s+agents|agents|roles|releases)';
/** No literal count beside a counted noun in the hand-written site sources. */
export function checkLiteralCounts(files = handWritten()) {
  const problems = [];
  const re = new RegExp(`(?<![\\w{.-])(\\d+|${NUMBER_WORDS.slice(2).join('|')})(?:[- ](?:${NUMBER_WORDS.slice(1, 10).join('|')}))?\\s+(?:portable\\s+)?${COUNTED}\\b`, 'gi');
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    for (const m of text.matchAll(re)) {
      const line = text.slice(0, m.index).split('\n').length;
      problems.push(`${relative(REPO, file)}:${line}: "${m[0]}" is a literal count; render it from data in a data-claim element`);
    }
  }
  return problems;
}

/** In the motion compositions, counts beside counted nouns and CLI names match the repo. */
export function checkMotion(truth, cliNames, dir = join(SITE, 'motion', 'src')) {
  const problems = [];
  if (!existsSync(dir)) return problems;
  const nouns = { skills: 'skills', personas: 'personas', clis: '(?:CLIs|coding\\s+agents|agents)', roles: 'roles' };
  for (const name of readdirSync(dir).filter((f) => f.endsWith('.html'))) {
    const text = readFileSync(join(dir, name), 'utf8').replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, (s) => s.replace(/[^\n]/g, ' '));
    const visible = text.replace(/<[^>]*>/g, ' ');
    for (const [kind, noun] of Object.entries(nouns)) {
      const re = new RegExp(`(?<![\\w.])(\\d+|${NUMBER_WORDS.join('|')})(?:[- ](?:${NUMBER_WORDS.slice(1, 10).join('|')}))?\\s+(?:\\w+\\s+)?${noun}\\b`, 'gi');
      for (const m of visible.matchAll(re)) {
        const n = firstNumber(m[0]);
        if (n !== null && truth[kind] !== undefined && n !== truth[kind]) {
          problems.push(`site/motion/src/${name}: "${m[0].replace(/\s+/g, ' ')}" but the repo has ${truth[kind]}: fix and re-render the composition`);
        }
      }
    }
    // a product name that is not one of the registry's CLIs (a renamed or dropped member)
    const known = new Set(cliNames);
    for (const candidate of ['Gemini CLI', 'Claude Code', 'Codex', 'Antigravity', 'OpenCode', 'Kimi Code', 'Cursor', 'Grok Build', 'Devin']) {
      if (visible.includes(candidate) && !known.has(candidate)) problems.push(`site/motion/src/${name}: names "${candidate}", which is not a CLI in scripts/lib/registry.sh`);
    }
  }
  return problems;
}

/** Runs every check; truth carries the repo's skills, docs routes, counts and CLI names. */
export function checkSite(dist, truth) {
  if (!existsSync(join(dist, 'index.html'))) throw Object.assign(new Error(`${dist}: no build (run astro build first)`), { code: 2 });
  const pages = readPages(dist);
  return [
    ...checkPages(dist, truth),
    ...checkClaims(pages, truth.counts),
    ...checkLinks(dist, pages),
    ...checkRedirects(dist, truth.redirects ?? []),
    ...checkMeta(pages),
    ...checkNoSkillFiles(dist),
    ...checkOrigins(pages),
    ...checkSkillTokens(truth.skills),
    ...checkLiteralCounts(),
    ...checkMotion(truth.counts, truth.cliNames),
  ];
}

// the repo's side of every check, from the same data modules the pages are built from
export async function repoTruth() {
  const { getSkills } = await import('../src/lib/skills.mjs');
  const { docPages } = await import('../src/lib/docs.mjs');
  const { getCounts } = await import('../src/lib/counts.mjs');
  const { getClis } = await import('../src/lib/roster.mjs');
  return {
    skills: getSkills().map((s) => s.name),
    docRoutes: docPages().map((d) => ({ source: d.source, href: d.href })),
    counts: getCounts(),
    cliNames: getClis().map((c) => c.name),
    redirects: JSON.parse(readFileSync(join(SITE, 'vercel.json'), 'utf8')).redirects ?? [],
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const dist = process.argv[2] ? join(process.cwd(), process.argv[2]) : join(SITE, 'dist');
  try {
    const problems = checkSite(dist, await repoTruth());
    if (problems.length) {
      for (const p of problems) console.error(`check-site: ${p}`);
      console.error(`check-site: FAIL (${problems.length} problem${problems.length === 1 ? '' : 's'})`);
      process.exit(1);
    }
    console.log(`check-site: ok (${readPages(dist).length} pages)`);
  } catch (error) {
    console.error(`check-site: ${error.message}`);
    process.exit(error.code === 2 ? 2 : 1);
  }
}
