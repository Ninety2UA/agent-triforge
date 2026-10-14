// shortcut.mjs: which key presses open the Cmd-K palette. Plain JavaScript with no DOM, so
// site/test/search-palette.test.mjs imports it directly; loader.ts is its only other user.
//
//   shortcutAction(event, { typing })  'toggle' for Cmd-K or Ctrl-K, 'open' for "/" outside a
//                                      text field, otherwise null. A press another handler
//                                      already took (defaultPrevented) is left alone: the skills
//                                      catalog's "/" focuses its own search box.

/**
 * @param {{ key: string, metaKey: boolean, ctrlKey: boolean, altKey: boolean, defaultPrevented: boolean }} event
 * @param {{ typing: boolean }} where  typing: the press landed in an input, textarea, select or editable element
 * @returns {'toggle' | 'open' | null}
 */
export function shortcutAction(event, { typing }) {
  if (event.defaultPrevented || event.altKey) return null;
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') return 'toggle';
  if (event.key === '/' && !event.metaKey && !event.ctrlKey && !typing) return 'open';
  return null;
}
