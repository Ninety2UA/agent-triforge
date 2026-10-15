import { createRoot, type Root } from 'react-dom/client';

import CommandPalette from './CommandPalette';

// The palette's React root. loader.ts imports this module (and with it React) only when
// someone first asks for search; it lives for the rest of the page. The dialog renders
// through a portal, so the host element stays empty.

let root: Root | null = null;
let state = { open: false, returnFocus: null as HTMLElement | null, initialQuery: '' };

function render() {
  if (!root) {
    const host = document.createElement('div');
    host.dataset.searchPalette = '';
    document.body.append(host);
    root = createRoot(host);
  }
  root.render(
    <CommandPalette
      {...state}
      onOpenChange={(open) => {
        state = { ...state, open };
        render();
      }}
    />,
  );
}

export function openPalette(returnFocus: HTMLElement | null, initialQuery = '') {
  if (state.open) return;
  state = { open: true, returnFocus, initialQuery };
  render();
}

export function togglePalette(returnFocus: HTMLElement | null) {
  if (state.open) {
    state = { ...state, open: false };
    render();
  } else openPalette(returnFocus);
}
