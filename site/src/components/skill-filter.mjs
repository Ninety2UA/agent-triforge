// skill-filter.mjs: the skill catalog's filter as plain script (R11, KTD6, KTD14). Every card is in the
// static HTML and shows without JavaScript. This module owns what the filter changes on the page: which
// cards show, the "N of total" count, the empty state, the search box's text and the chips' pressed
// state. The SkillFilter island (React, hydrated on first use) draws the search box and the chips and
// calls the controller; the page script starts the controller on load, so it can:
//   - show /skills/?q=<text>&group=<key> filtered before any island loads (the search palette's
//     fallback links to ?q=, a skill page's breadcrumb to ?group=), when the catalog has data-read-url;
//   - take "/" for the catalog's own search box: outside a text field and with no modifier it calls
//     preventDefault(), so the palette loader on window skips the key, and focuses the box, whose focus
//     hydrates the island;
//   - make the empty state's button show every card again and give focus back to the search box;
//   - put the first chip in the Tab order, which Base UI does only once the island has mounted.
//
// The page's markup:
//   [data-catalog]            the root; data-read-url to read ?q= and ?group= on load
//   [data-filter-q]           the search box (optional; drawn by the island)
//   [data-group-chip=<key>]   the chips (drawn by the island), "all" for every group
//   [data-skill-card]         a card: data-group (key), data-group-label, data-text (lower-case match text)
//   [data-count]              the number shown
//   [data-empty]              the empty state, hidden; [data-empty-text] its sentence, [data-filter-clear] its button
//
// Exports
//   ALL                       the chip value meaning every group
//   matchText(...parts)       a card's data-text: its parts in lower case, backticks dropped
//   matches(card, state)      true when the card is in state.group (or ALL) and every word of state.q starts
//                             a word of its text (leading punctuation dropped, so /at-review finds at-review)
//   matcher(state)            the same test as a function of the card, with the query read once
//   readState(search, groups) { q, group } from a query string; a group not in `groups` reads as ALL
//   initCatalog(doc?, win?)   the page's controller, created once per page, or null without [data-catalog]:
//                             { getState(), subscribe(fn) -> unsubscribe, setQuery(q), setGroup(key), clear(),
//                             key(name) -> true when it took the key (Escape with a search typed) }

import { isTyping } from './search/shortcut.mjs';
import { escapeRegExp } from '../lib/text.mjs';

export const ALL = 'all';

/** @typedef {{ q: string, group: string }} FilterState */

/** @param {...string} parts */
export function matchText(...parts) {
  return parts.join(' ').replace(/`/g, '').replace(/\s+/g, ' ').trim().toLowerCase();
}

/**
 * @param {{ group: string, text: string }} card
 * @param {FilterState} state
 */
export function matches(card, state) {
  return matcher(state)(card);
}

/**
 * matches() for one state: the query's word patterns are built once, then tested on each card.
 * @param {FilterState} state
 * @returns {(card: { group: string, text: string }) => boolean}
 */
export function matcher({ q, group }) {
  const words = q
    .toLowerCase()
    .split(/\s+/)
    // "/at-review" as typed in a session is the word "at-review"
    .map((word) => word.replace(/^[^a-z0-9]+/, ''))
    .filter(Boolean)
    // from the start of a word: "cut" finds "cutting", not "execution"
    .map((word) => new RegExp(`(?:^|[^a-z0-9])${escapeRegExp(word)}`));
  return (card) => (group === ALL || card.group === group) && words.every((re) => re.test(card.text));
}

/**
 * @param {string} search
 * @param {string[]} groups
 * @returns {FilterState}
 */
export function readState(search, groups) {
  const params = new URLSearchParams(search);
  const group = params.get('group') ?? ALL;
  return { q: params.get('q') ?? '', group: groups.includes(group) ? group : ALL };
}

/**
 * @param {Document} [doc]
 * @param {Window & { triforgeCatalog?: any }} [win]
 */
export function initCatalog(doc = document, win = window) {
  if (win.triforgeCatalog?.doc === doc) return win.triforgeCatalog;
  const root = doc.querySelector('[data-catalog]');
  if (!root) return null;

  const cards = [...root.querySelectorAll('[data-skill-card]')].map((el) => ({
    el,
    group: el.getAttribute('data-group') ?? '',
    label: el.getAttribute('data-group-label') ?? '',
    text: el.getAttribute('data-text') ?? '',
  }));
  const groups = [...new Set(cards.map((c) => c.group))];
  // the island may draw (or redraw) these after load, so they are looked up each time
  const input = () => /** @type {HTMLInputElement | null} */ (root.querySelector('[data-filter-q]'));
  const listeners = new Set();
  /** @type {FilterState} */
  let state = { q: '', group: ALL };

  const apply = () => {
    let shown = 0;
    const test = matcher(state);
    for (const card of cards) {
      const on = test(card);
      card.el.toggleAttribute('hidden', !on);
      if (on) shown += 1;
    }
    const count = root.querySelector('[data-count]');
    if (count) count.textContent = String(shown);
    const empty = root.querySelector('[data-empty]');
    if (empty) {
      empty.toggleAttribute('hidden', shown > 0);
      const text = empty.querySelector('[data-empty-text]');
      const label = cards.find((c) => c.group === state.group)?.label;
      const q = state.q.trim();
      if (text && !shown) text.textContent = `No skill${label ? ` in ${label}` : ''}${q ? ` matches “${q}”` : ''}.`;
    }
    for (const chip of root.querySelectorAll('[data-group-chip]')) {
      const on = chip.getAttribute('data-group-chip') === state.group;
      chip.setAttribute('aria-pressed', String(on));
      chip.toggleAttribute('data-pressed', on);
    }
    const box = input();
    if (box && box.value !== state.q) box.value = state.q;
    listeners.forEach((fn) => fn());
  };
  /** @param {Partial<FilterState>} next */
  const set = (next) => {
    state = { ...state, ...next };
    apply();
  };

  const controller = {
    doc,
    getState: () => state,
    /** @param {() => void} fn */
    subscribe(fn) {
      listeners.add(fn);
      return () => void listeners.delete(fn);
    },
    /** @param {string} q */
    setQuery: (q) => set({ q }),
    /** @param {string} group */
    setGroup: (group) => set({ group: groups.includes(group) ? group : ALL }),
    clear() {
      set({ q: '', group: ALL });
      input()?.focus();
    },
    /** @param {string} name */
    key(name) {
      if (name !== 'Escape' || !state.q) return false;
      set({ q: '' });
      return true;
    },
  };
  win.triforgeCatalog = controller;

  // Base UI's roving focus renders every chip at tabindex -1 and puts the first at 0 only once it
  // mounts, so before the island hydrates no chip could be reached with Tab; give the first one the
  // stop Base UI will give it
  const chips = root.querySelectorAll('[data-group-chip]');
  if (chips.length && !root.querySelector('[data-group-chip][tabindex="0"]')) chips[0].setAttribute('tabindex', '0');

  if (root.hasAttribute('data-read-url')) {
    const fromUrl = readState(win.location?.search ?? '', groups);
    if (fromUrl.q || fromUrl.group !== ALL) set(fromUrl);
  }

  root.addEventListener('click', (event) => {
    if (/** @type {Element | null} */ (event.target)?.closest?.('[data-filter-clear]')) controller.clear();
  });

  // "/" focuses the catalog's own search box; the palette loader (on window) then skips the press
  doc.addEventListener('keydown', (event) => {
    const e = /** @type {KeyboardEvent} */ (event);
    if (e.key !== '/' || e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey || isTyping(e.target)) return;
    const box = input();
    if (!box) return;
    e.preventDefault();
    box.focus();
  });

  return controller;
}
