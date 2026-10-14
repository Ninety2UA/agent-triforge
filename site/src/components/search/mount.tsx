import { createRoot, type Root } from 'react-dom/client';
import CommandPalette, { type Entry } from './CommandPalette';

// The palette's React root, created the first time someone asks for search. The dialog renders
// through a portal, so the host element stays empty.
let root: Root | null = null;
let state = { open: false, returnFocus: null as HTMLElement | null, initialQuery: '' };
let entries: Entry[] = [];

function render() {
  if (!root) {
    const host = document.createElement('div');
    host.dataset.searchPalette = '';
    document.body.append(host);
    root = createRoot(host);
  }
  root.render(<CommandPalette {...state} entries={entries} onOpenChange={(open) => { state = { ...state, open }; render(); }} />);
}

export function openPalette(list: Entry[], returnFocus: HTMLElement | null, initialQuery = '') {
  entries = list;
  if (state.open) return;
  state = { open: true, returnFocus, initialQuery };
  render();
}
