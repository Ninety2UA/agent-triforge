// A page for the client-script tests: linkedom parses the markup the components render, and a small
// window object supplies what linkedom lacks (location, storage, selection, the platform) so a test
// can set each one, including storage that throws.
import { parseHTML } from 'linkedom';

/**
 * @param {string} body  markup for <body>
 * @param {{ hash?: string, stored?: Record<string, string>, storageThrows?: boolean, platform?: string }} [opts]
 */
export function page(body, { hash = '', stored = {}, storageThrows = false, platform = 'MacIntel' } = {}) {
  const { document, window: lw } = parseHTML(`<!doctype html><html><head></head><body>${body}<div id="live" aria-live="polite"></div></body></html>`);
  // linkedom's <textarea> has no select(); a browser's selects its text
  const textarea = Object.getPrototypeOf(document.createElement('textarea'));
  if (!textarea.select) textarea.select = function select() {};
  const data = { ...stored };
  const fail = () => {
    throw new Error('SecurityError: storage is disabled');
  };
  const listeners = {};
  const selection = { ranges: [], removeAllRanges() { this.ranges = []; }, addRange(r) { this.ranges.push(r); } };
  const win = {
    document,
    location: { hash },
    localStorage: {
      getItem: (k) => (storageThrows ? fail() : (data[k] ?? null)),
      setItem: (k, v) => (storageThrows ? fail() : (data[k] = String(v))),
    },
    navigator: { platform, userAgent: platform },
    getSelection: () => selection,
    addEventListener: (type, fn) => (listeners[type] ??= []).push(fn),
    setTimeout: (fn) => 0,
    clearTimeout: () => {},
    Event: lw.Event,
  };
  return {
    document,
    window: win,
    stored: data,
    selection,
    /** sets location.hash and fires hashchange, as a click on an in-page link would */
    navigate(h) {
      win.location.hash = h;
      (listeners.hashchange ?? []).forEach((fn) => fn(new lw.Event('hashchange')));
    },
    click(el) {
      el.dispatchEvent(new lw.Event('click', { bubbles: true }));
    },
    key(el, key) {
      const e = new lw.Event('keydown', { bubbles: true, cancelable: true });
      e.key = key;
      el.dispatchEvent(e);
      return e;
    },
  };
}
