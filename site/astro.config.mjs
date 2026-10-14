// @ts-check
// The Agent Triforge site: static Astro with React islands that hydrate on first use, Tailwind 4
// and shadcn on Base UI, the approved Ultramarine design. Pages are built from the repo's own
// files (src/lib), so the site cannot drift from the plugin.
import { defineConfig, fontProviders } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import pagefind from 'astro-pagefind';
import tailwindcss from '@tailwindcss/vite';
import interactionDirective from './src/directives/integration.mjs';
import escapeSkillHtml from './src/lib/markdown/escape-skill-html.mjs';
import kitDevRoute from './src/dev/kit-route.mjs';
import { SITE_URL } from './src/lib/site.mjs';

export default defineConfig({
  site: SITE_URL,
  trailingSlash: 'always',
  build: {
    format: 'directory',
    // one request fewer before first paint; render-blocking stylesheets cost about a second on a
    // throttled phone
    inlineStylesheets: 'always',
  },
  // Fenced code renders as plain <pre><code>, set in the page's own surface and ink (docs.css): a
  // highlighter's dark block and its per-token inline styles would weigh every docs and skill page down.
  markdown: { syntaxHighlight: false },
  // escapeSkillHtml: raw HTML in SKILL.md bodies and persona prompts renders as text, so
  // placeholders such as <base-branch> stay visible
  integrations: [
    react(),
    sitemap({ filter: (page) => !/\/404\/?$/.test(page) }),
    pagefind(),
    interactionDirective(),
    escapeSkillHtml(),
    kitDevRoute(),
  ],
  fonts: [
    {
      provider: fontProviders.local(),
      name: 'Familjen Grotesk',
      cssVariable: '--font-familjen',
      // "Familjen Grotesk Fallback" is the set of metric-matched Arial faces in global.css, one per
      // weight band plus one for digits and one for the space, so the layout made before the font
      // arrives already has Familjen's line breaks. Astro's generated fallback is one Arial face for
      // every weight, which moves lines when the real font lands.
      fallbacks: ['Familjen Grotesk Fallback', 'ui-sans-serif', 'system-ui', 'sans-serif'],
      optimizedFallbacks: false,
      options: {
        variants: [
          {
            weight: '400 700',
            style: 'normal',
            // block, not swap: until this preloaded file arrives the text is laid out invisibly in
            // the fallback faces, so a slow connection never shows Arial and then reflows
            display: 'block',
            src: ['./src/assets/fonts/FamiljenGrotesk-var.woff2'],
          },
        ],
      },
    },
    {
      provider: fontProviders.local(),
      name: 'Sometype Mono',
      cssVariable: '--font-sometype',
      // "Sometype Mono Fallback" is Menlo or Courier scaled to Sometype's 0.58 em advance (global.css),
      // so a command block keeps its line breaks when the font swaps in
      fallbacks: ['Sometype Mono Fallback', 'ui-monospace', 'monospace'],
      optimizedFallbacks: false,
      options: {
        variants: [
          {
            weight: '400 700',
            style: 'normal',
            display: 'swap',
            src: ['./src/assets/fonts/SometypeMono-var.woff2'],
          },
        ],
      },
    },
    {
      provider: fontProviders.local(),
      name: 'Doto',
      cssVariable: '--font-doto',
      // only the sprint numerals use it; fixed-size boxes, so a swap moves nothing
      fallbacks: ['Familjen Grotesk Fallback', 'sans-serif'],
      optimizedFallbacks: false,
      options: {
        variants: [
          {
            weight: '100 900',
            style: 'normal',
            display: 'swap',
            src: ['./src/assets/fonts/Doto-var.woff2'],
          },
        ],
      },
    },
  ],
  vite: {
    plugins: [tailwindcss()],
  },
});
