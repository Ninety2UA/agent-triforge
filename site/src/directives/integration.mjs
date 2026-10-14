// Registers client:interaction (interaction.ts): islands that hydrate on first use.
import { fileURLToPath } from 'node:url';

/** @returns {import('astro').AstroIntegration} */
export default function interactionDirective() {
  return {
    name: 'agent-blueprint:client-interaction',
    hooks: {
      'astro:config:setup': ({ addClientDirective }) => {
        addClientDirective({
          name: 'interaction',
          entrypoint: fileURLToPath(new URL('./interaction.ts', import.meta.url)),
        });
      },
    },
  };
}
