// The palette's loader: the only search code on a page until someone asks for search. Cmd-K or
// Ctrl-K, "/" outside a text field, a press on any [data-open-search] button, or a
// `triforge:open-search` event (the phone menu's Search) fetches the palette (React, cmdk, Base UI)
// and the Pagefind index at the same time, then opens the palette. Keys typed while it loads go into
// the search box once it opens; Escape before then cancels the open and gives the keyboard back at
// once. If the palette's chunk fails to load (offline, or a redeploy replaced its hashed file), a
// notice on the page says so and links to the skills catalog's own search with what was typed, and
// the next request imports it again.
//
// The key listener sits on window, so it runs after every document-level handler: a "/" that the
// skills catalog took for its own search box arrives here defaultPrevented.
import { OPEN_SEARCH_EVENT, type OpenSearchDetail } from '../search-event';
import { loadIndex } from './pagefind';
import { isTyping, shortcutAction } from './shortcut.mjs';

type Palette = typeof import('./mount');

let palette: Palette | null = null;
let loading = false;
// the open waiting for the palette: where focus returns and what was typed meanwhile;
// null when nothing waits, including after Escape cancelled it
let request: { returnFocus: HTMLElement | null; typed: string } | null = null;


function keepTyping(event: KeyboardEvent) {
  if (event.isComposing || !request) return;
  if (event.key === 'Escape') {
    // cancel now, not when the download finishes, so typing reaches the focused field again
    request = null;
    removeEventListener('keydown', keepTyping, true);
  } else if (event.key === 'Backspace') request.typed = request.typed.slice(0, -1);
  else if (event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey) request.typed += event.key;
  else return;
  event.preventDefault();
  event.stopPropagation();
}

// A visible notice when the palette cannot load, with the catalog's search as the way on.
function notify(typed: string) {
  const live = document.getElementById('live');
  if (live) live.textContent = 'Search could not load. Reload the page, or search the skills catalog.';
  let note = document.getElementById('search-failed');
  if (!note) {
    note = document.createElement('p');
    note.id = 'search-failed';
    note.className = 'search-failed';
    note.setAttribute('role', 'alert');
    document.body.append(note);
  }
  const link = document.createElement('a');
  link.href = `/skills/${typed ? `?q=${encodeURIComponent(typed)}` : ''}`;
  link.textContent = 'Search the skills catalog';
  note.replaceChildren('Search could not load. Reload the page to try again, or ', link, '.');
}

async function show(returnFocus: HTMLElement | null, toggle: boolean) {
  if (palette) {
    if (toggle) palette.togglePalette(returnFocus);
    else palette.openPalette(returnFocus);
    return;
  }
  // a request while the palette downloads renews an open that Escape cancelled
  if (!request) {
    request = { returnFocus, typed: '' };
    addEventListener('keydown', keepTyping, true);
  }
  if (loading) return;
  loading = true;
  // the palette waits for the same promise and shows a failure itself
  loadIndex().catch(() => {});
  try {
    palette = await import('./mount');
  } catch {
    notify(request?.typed ?? '');
  } finally {
    removeEventListener('keydown', keepTyping, true);
    loading = false;
  }
  const open = request;
  request = null;
  if (palette && open) palette.openPalette(open.returnFocus, open.typed);
}

addEventListener('keydown', (event) => {
  const action = shortcutAction(event, { typing: isTyping(event.target) });
  if (!action) return;
  event.preventDefault();
  const focused = document.activeElement;
  void show(focused instanceof HTMLElement && focused !== document.body ? focused : null, action === 'toggle');
});

// search buttons anywhere (the header, the docs sidebar, the 404 page)
document.addEventListener('click', (event) => {
  const button = (event.target as Element | null)?.closest?.('[data-open-search]');
  if (button instanceof HTMLElement) void show(button, false);
});

document.addEventListener(OPEN_SEARCH_EVENT, (event) => {
  void show((event as CustomEvent<OpenSearchDetail>).detail?.trigger ?? null, false);
});
