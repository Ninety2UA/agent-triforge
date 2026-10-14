// escape-skill-html.mjs: SKILL.md bodies and persona prompts show raw HTML as text (ported from
// Agent Blueprint's site).
//
// The skills and personas write placeholders such as <base-branch>, <file or diff> and <agent> in
// prose. Rendered as Markdown, those are raw HTML: the browser treats them as unknown elements and
// their text disappears. This Satteri mdast plugin turns every raw HTML node of a skills/<name>/SKILL.md
// or a personas/<name>.md into text, so the placeholder shows as written. It runs only for those files
// (checked on the file path the content loader passes as fileURL), so docs pages, the FAQ and release
// notes keep their HTML (<details>, <summary>).
//
// The same plugin keeps command flags intact. Satteri's smart punctuation runs while it parses, so
// "node --prof" in prose reaches the plugin as "node –prof"; an en dash with whitespace (or nothing)
// before it and a letter right after it is put back as the two hyphens it was. En dashes between
// spaces or numbers stay, and code was never converted.
//
// Astro 7 renders Markdown with Satteri, which does not run markdown.remarkPlugins; the integration
// adds the plugin to the processor's own mdastPlugins list, as Astro lets integrations do in
// astro:config:setup.
//
// Exports
//   isSkillFile(fileURL, skillsDir)       true for <skillsDir>/<name>/SKILL.md
//   isPersonaFile(fileURL, personasDir)   true for <personasDir>/<name>.md
//   escapeSkillHtml({ skillsDir, personasDir })   the plugin factory (null for any other file)
//   default(options?)                     the Astro integration; skillsDir and personasDir default to the
//                                         repo's skills/ and personas/ folders
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { REPO } from '../repo.mjs';

const FLAG = /(^|\s)–(?=[A-Za-z])/g;

// Parents whose children are blocks: raw HTML there becomes a paragraph, elsewhere plain text.
const FLOW_PARENTS = new Set(['root', 'blockquote', 'listItem', 'footnoteDefinition', 'containerDirective']);

function partsUnder(fileURL, dir) {
  if (!fileURL) return null;
  const parts = relative(dir, fileURLToPath(fileURL)).split(sep);
  return parts[0] === '..' ? null : parts;
}

export function isSkillFile(fileURL, skillsDir) {
  const parts = partsUnder(fileURL, skillsDir);
  return parts !== null && parts.length === 2 && parts[1] === 'SKILL.md';
}

export function isPersonaFile(fileURL, personasDir) {
  const parts = partsUnder(fileURL, personasDir);
  return parts !== null && parts.length === 1 && parts[0].endsWith('.md');
}

export function escapeSkillHtml({ skillsDir, personasDir }) {
  return (ctx) =>
    isSkillFile(ctx.fileURL, skillsDir) || isPersonaFile(ctx.fileURL, personasDir)
      ? {
          name: 'escape-skill-html',
          html(node, visit) {
            const text = { type: 'text', value: node.value };
            return FLOW_PARENTS.has(visit.parent(node)?.type ?? 'root') ? { type: 'paragraph', children: [text] } : text;
          },
          text(node, visit) {
            const value = node.value.replace(FLAG, '$1--');
            if (value !== node.value) visit.replaceNode(node, { type: 'text', value });
          },
        }
      : null;
}

/** @returns {import('astro').AstroIntegration} */
export default function escapeSkillHtmlIntegration({ skillsDir = join(REPO, 'skills'), personasDir = join(REPO, 'personas') } = {}) {
  return {
    name: 'agent-triforge:escape-skill-html',
    hooks: {
      'astro:config:setup': ({ config }) => {
        const processor = config.markdown.processor;
        // another processor would skip the plugin and the placeholders would vanish again
        if (processor.name !== 'satteri') {
          throw new Error(`escape-skill-html: expected the satteri Markdown processor, found "${processor.name}"`);
        }
        processor.options.mdastPlugins.push(escapeSkillHtml({ skillsDir, personasDir }));
      },
    },
  };
}
