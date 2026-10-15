// The site's Pagefind index, which astro-pagefind writes to /pagefind/ after the build.
// Nothing here runs on page load: the loader starts loadIndex() on the first request for
// search, at the same time as it fetches the palette, and the palette waits for the same
// promise.

export interface PagefindResult {
  data(): Promise<{ url: string; excerpt: string; meta: { title?: string }; filters: Record<string, string[]> }>;
}
export interface PagefindInstance {
  init(): Promise<void>;
  search(term: string): Promise<{ results: PagefindResult[] }>;
}

// a path the bundler must not resolve: the file exists only in the built site
const PAGEFIND = '/pagefind/pagefind.js';

let index: Promise<PagefindInstance> | null = null;

export function loadIndex(): Promise<PagefindInstance> {
  index ??= (async () => {
    const pagefind = await import(/* @vite-ignore */ PAGEFIND);
    const instance: PagefindInstance = pagefind.createInstance({ excerptLength: 20 });
    await instance.init();
    return instance;
  })().catch((error: unknown) => {
    index = null; // the next open tries again
    throw error;
  });
  return index;
}
