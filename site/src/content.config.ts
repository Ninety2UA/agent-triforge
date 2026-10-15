// Content collections generated from the repo at build time (R2, KTD2). Nothing is copied into site/:
// each loader reads the repo files in place through the plain data modules in src/lib, which have
// already resolved every link through the route table (routes.mjs). Pages render an entry with
// Astro's render(entry), which gives <Content /> and the headings.
//
//   skills    one entry per skills/<name>/SKILL.md, id = the folder name. data: name, lead, group,
//             description, summary, argumentHint, path. Rendered with the SKILL.md as its file, so the
//             escape-skill-html plugin keeps raw text such as <base-branch> visible.
//   docs      one entry per Docs and Guides page of the docs map (docs-map.mjs) that has repo content,
//             id = the page slug (unique across Docs and Guides; the hand-written leases guide has no
//             entry). data: slug, href, title, section, source, sources, intro (Markdown) and introHtml.
//             Images go through Astro's image pipeline: their paths are relative to the page's
//             imageBase file, which is the fileURL the page renders from.
//   personas  one entry per personas/<name>.md, id = the persona name. data: name, anchor, group,
//             summary, class, tier, neverDowngrade, maxTurns, path. Rendered like a skill, raw text kept.
//   releases  one entry per docs/releases/*.md, id = its changelog anchor ("v4-1-1", or the date of an
//             unversioned note). data: version (null when unversioned), date, title, anchor, file, ref,
//             summary; the body is the note after its header, links pointing at GitHub at the
//             release's tag (or main).
//
// The order of getCollection() is not the page order: pages take their order from the data modules
// (getSkills, docPages, getPersonas, getReleases).

import { defineCollection } from 'astro:content';
import { glob, type Loader } from 'astro/loaders';
import { z } from 'astro/zod';
import { readFileSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { LEADS } from './data/leads.mjs';
import { docPages } from './lib/docs.mjs';
import { getPersonas } from './lib/personas.mjs';
import { getReleases } from './lib/releases.mjs';
import { REPO } from './lib/repo.mjs';
import { getSkills } from './lib/skills.mjs';
import { parseTutorial, writtenTutorials, type TutorialSegment } from './lib/tutorials.mjs';

const fileURL = (repoPath: string) => pathToFileURL(join(REPO, repoPath));
const filePathFrom = (configRoot: URL, repoPath: string) => relative(fileURLToPath(configRoot), join(REPO, repoPath)).split(sep).join('/');

const group = z.object({ key: z.string(), label: z.string() });

// A loader for repo records that carry a Markdown body (skills, personas, release notes): each record is
// stored under its id, with its body rendered from its own file so links and images resolve from there.
const repoLoader = <T extends { body: string }>(name: string, records: () => T[], id: (r: Omit<T, 'body'>) => string, path: (r: Omit<T, 'body'>) => string): Loader => ({
  name,
  async load({ config, store, parseData, renderMarkdown }) {
    store.clear();
    for (const { body, ...record } of records()) {
      const data = await parseData({ id: id(record), data: record });
      const rendered = await renderMarkdown(body, { fileURL: fileURL(path(record)) });
      store.set({ id: id(record), data, body, filePath: filePathFrom(config.root, path(record)), rendered });
    }
  },
});

const skills = defineCollection({
  loader: repoLoader('triforge-skills', getSkills, (s) => s.name, (s) => s.path),
  schema: z.object({
    name: z.string(),
    lead: z.boolean(),
    group,
    description: z.string(),
    summary: z.string(),
    argumentHint: z.string().nullable(),
    path: z.string(),
  }),
});

const docs = defineCollection({
  loader: {
    name: 'triforge-docs',
    async load({ config, store, parseData, renderMarkdown }) {
      store.clear();
      for (const page of docPages()) {
        if (!page.imageBase) continue; // a hand-written page: its content lives in src/content
        const { body, imageBase, ...meta } = page;
        const base = { fileURL: fileURL(imageBase) };
        const introHtml = meta.intro ? (await renderMarkdown(meta.intro, base)).html : '';
        const data = await parseData({ id: page.slug, data: { ...meta, introHtml } });
        const rendered = await renderMarkdown(body, base);
        store.set({
          id: page.slug,
          data,
          body,
          filePath: filePathFrom(config.root, imageBase),
          rendered,
          assetImports: rendered.metadata?.imagePaths,
        });
      }
    },
  },
  schema: z.object({
    slug: z.string(),
    href: z.string(),
    title: z.string(),
    section: z.enum(['docs', 'guides']),
    source: z.string().nullable(),
    sources: z.array(z.string()),
    intro: z.string(),
    introHtml: z.string(),
  }),
});

const personas = defineCollection({
  loader: repoLoader('triforge-personas', getPersonas, (p) => p.name, (p) => p.path),
  schema: z.object({
    name: z.string(),
    anchor: z.string(),
    group: group.extend({ anchor: z.string() }),
    summary: z.string(),
    class: z.string(),
    tier: z.string(),
    neverDowngrade: z.boolean(),
    maxTurns: z.number(),
    path: z.string(),
  }),
});

const releases = defineCollection({
  loader: repoLoader('triforge-releases', getReleases, (r) => r.anchor, (r) => r.file),
  schema: z.object({
    version: z.string().nullable(),
    date: z.string(),
    title: z.string(),
    anchor: z.string(),
    file: z.string(),
    ref: z.string(),
    summary: z.string(),
  }),
});

// tutorials  one entry per written tutorial (lib/tutorials.mjs writtenTutorials(): a TUTORIALS slug with
//            src/content/tutorials/<slug>.md), id = the slug, read by parseTutorial, which stops the build
//            naming the file and the step when the text does not follow the tutorial form. data: title,
//            href, description, and intro, steps and recap with every Markdown part rendered to HTML. A
//            step is { title, id, skills, common, tabs, happens, why, checkpoint }; common and each tab's
//            segments are lists of { kind: 'md', html } and { kind: 'cmd', lang, text } (a command to
//            paste); tabs is null or the Claude Code and Codex versions of the paste area.
const segment = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('md'), html: z.string() }),
  z.object({ kind: z.literal('cmd'), lang: z.enum(['prompt', 'bash']), text: z.string() }),
]);
export const tutorials = defineCollection({
  loader: {
    name: 'triforge-tutorials',
    async load({ config, store, parseData, renderMarkdown }) {
      store.clear();
      for (const { slug, href, title } of writtenTutorials()) {
        const repoPath = `site/src/content/tutorials/${slug}.md`;
        const base = { fileURL: fileURL(repoPath) };
        const html = async (markdown: string) => (await renderMarkdown(markdown, base)).html;
        const segments = (list: TutorialSegment[]) =>
          Promise.all(list.map(async (s) => (s.kind === 'md' ? { kind: s.kind, html: await html(s.md) } : s)));
        const { meta, intro, steps, recap } = parseTutorial(readFileSync(join(REPO, repoPath), 'utf8'), repoPath);
        const rendered = [];
        for (const step of steps) {
          rendered.push({
            title: step.title,
            id: step.id,
            skills: step.skills,
            common: await segments(step.common),
            tabs: step.tabs && (await Promise.all(step.tabs.map(async (t) => ({ lead: t.lead, label: t.label, segments: await segments(t.segments) })))),
            happens: await html(step.happens),
            why: await html(step.why),
            checkpoint: await html(step.checkpoint),
          });
        }
        const data = await parseData({ id: slug, data: { title, href, ...meta, intro: await html(intro), steps: rendered, recap: await html(recap) } });
        store.set({ id: slug, data, filePath: filePathFrom(config.root, repoPath) });
      }
    },
  },
  schema: z.object({
    title: z.string(),
    href: z.string(),
    description: z.string(),
    intro: z.string(),
    steps: z.array(
      z.object({
        title: z.string(),
        id: z.string(),
        skills: z.array(z.string()),
        common: z.array(segment),
        tabs: z.array(z.object({ lead: z.enum(LEADS), label: z.string(), segments: z.array(segment) })).nullable(),
        happens: z.string(),
        why: z.string(),
        checkpoint: z.string(),
      }),
    ),
    recap: z.string(),
  }),
});


// guides  the hand-written guide pages (KTD4): one entry per src/content/guides/*.md, id = the page's
//         slug in the docs map's GUIDE_PAGES (only "leases" today). data: description (the meta
//         description) and intro (the plain-text paragraph under the title). The title and the page's
//         place in the sidebar come from the docs map.
export const guides = defineCollection({
  loader: glob({ base: './src/content/guides', pattern: '*.md' }),
  schema: z.object({
    description: z.string(),
    intro: z.string(),
  }),
});

export const collections = { skills, docs, personas, releases, tutorials, guides };
