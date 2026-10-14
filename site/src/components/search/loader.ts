// The only search code on the page until someone asks for search. ⌘K or Ctrl-K, "/" outside a
// text field, or a press on a [data-open-search] button fetches the palette (React, cmdk, Base UI)
// and opens it with the entries listed in #search-data.
type Mount = typeof import('./mount');
let mod: Mount | null = null;
let loading = false;

const inField = (t: EventTarget | null) => t instanceof HTMLElement && (t.isContentEditable || t.closest('input, textarea, select') !== null);
const entries = () => JSON.parse(document.getElementById('search-data')?.textContent ?? '[]');

async function show(returnFocus: HTMLElement | null) {
  if (!mod) {
    if (loading) return;
    loading = true;
    try {
      mod = await import('./mount');
    } catch {
      const live = document.getElementById('live');
      if (live) live.textContent = 'Search could not load. Reload the page to try again.';
    } finally {
      loading = false;
    }
  }
  mod?.openPalette(entries(), returnFocus);
}

addEventListener('keydown', (e) => {
  const cmdK = e.key.toLowerCase() === 'k' && (e.metaKey || e.ctrlKey);
  const slash = e.key === '/' && !inField(e.target) && !e.metaKey && !e.ctrlKey && !e.altKey;
  if (!cmdK && !slash) return;
  e.preventDefault();
  const focused = document.activeElement;
  void show(focused instanceof HTMLElement && focused !== document.body ? focused : null);
});

// search buttons anywhere (the header, the docs sidebar, the phone menu after it closes)
document.addEventListener('click', (e) => {
  const b = (e.target as Element | null)?.closest<HTMLElement>('[data-open-search]');
  if (b) void show(b);
});
document.addEventListener('triforge:open-search', (e) => void show((e as CustomEvent<HTMLElement | null>).detail ?? null));
