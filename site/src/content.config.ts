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
import { z } from 'astro/zod';
import { join, relative, sep } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import { docPages } from './lib/docs.mjs';
import { getPersonas } from './lib/personas.mjs';
import { getReleases } from './lib/releases.mjs';
import { REPO } from './lib/repo.mjs';
import { getSkills } from './lib/skills.mjs';

const fileURL = (repoPath: string) => pathToFileURL(join(REPO, repoPath));
const filePathFrom = (configRoot: URL, repoPath: string) => relative(fileURLToPath(configRoot), join(REPO, repoPath)).split(sep).join('/');

const group = z.object({ key: z.string(), label: z.string() });

const skills = defineCollection({
  loader: {
    name: 'triforge-skills',
    async load({ config, store, parseData, renderMarkdown }) {
      store.clear();
      for (const { body, ...skill } of getSkills()) {
        const data = await parseData({ id: skill.name, data: skill });
        const rendered = await renderMarkdown(body, { fileURL: fileURL(skill.path) });
        store.set({ id: skill.name, data, body, filePath: filePathFrom(config.root, skill.path), rendered });
      }
    },
  },
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
  loader: {
    name: 'triforge-personas',
    async load({ config, store, parseData, renderMarkdown }) {
      store.clear();
      for (const { body, ...persona } of getPersonas()) {
        const data = await parseData({ id: persona.name, data: persona });
        const rendered = await renderMarkdown(body, { fileURL: fileURL(persona.path) });
        store.set({ id: persona.name, data, body, filePath: filePathFrom(config.root, persona.path), rendered });
      }
    },
  },
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
  loader: {
    name: 'triforge-releases',
    async load({ config, store, parseData, renderMarkdown }) {
      store.clear();
      for (const { body, ...release } of getReleases()) {
        const data = await parseData({ id: release.anchor, data: release });
        const rendered = await renderMarkdown(body, { fileURL: fileURL(release.file) });
        store.set({ id: release.anchor, data, body, filePath: filePathFrom(config.root, release.file), rendered });
      }
    },
  },
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

export const collections = { skills, docs, personas, releases };
