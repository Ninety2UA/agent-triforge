import 'astro';

declare module 'astro' {
  interface AstroClientDirectives {
    /** Hydrate on first interaction with the island (src/directives/interaction.ts). */
    'client:interaction'?: boolean;
  }
}
