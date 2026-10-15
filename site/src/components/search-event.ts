// The hook between the static search buttons and the Cmd-K palette (KTD14).
//
// Every element with `data-open-search` (the header button, the mobile menu entry, the
// docs sidebar button) dispatches this event on `document` when pressed, with the
// pressed element as `detail.trigger` so the palette can return focus to it on close.
// The palette listens for it, and owns its own keyboard shortcuts (Cmd-K, Ctrl-K, `/`).
//
//   document.addEventListener(OPEN_SEARCH_EVENT, (e) => open(e.detail.trigger));
export const OPEN_SEARCH_EVENT = 'triforge:open-search';

export interface OpenSearchDetail {
  trigger: HTMLElement | null;
}

export function requestSearch(trigger: HTMLElement | null): void {
  document.dispatchEvent(new CustomEvent<OpenSearchDetail>(OPEN_SEARCH_EVENT, { detail: { trigger } }));
}
