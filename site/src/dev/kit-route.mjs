// The media kit (/kit/) and the README GIF it shows (/media/readme-hero.gif) are for the maintainer:
// `astro dev` serves them, and `astro build` never builds them, so they stay out of the public site, its
// sitemap, its search index and llms.txt (KTD15). Ported from Agent Blueprint's site.
import { fileURLToPath } from 'node:url';

const entry = (file) => fileURLToPath(new URL(file, import.meta.url));

/** @returns {import('astro').AstroIntegration} */
export default function kitDevRoute() {
  return {
    name: 'agent-triforge:kit-dev-route',
    hooks: {
      'astro:config:setup': ({ command, injectRoute }) => {
        if (command !== 'dev') return;
        injectRoute({ pattern: '/kit', entrypoint: entry('./kit.astro') });
        injectRoute({ pattern: '/media/readme-hero.gif', entrypoint: entry('./readme-hero.gif.ts') });
      },
    },
  };
}
