import type { ClientDirective } from 'astro';

// client:interaction hydrates an island the first time someone reaches for it, so a
// page ships no framework JavaScript until then. Pointing at it or focusing it starts
// the download early; a click or key press that arrives before hydration is finished
// is replayed on the same element afterwards, so the first press is never lost. If
// hydration fails, presses are no longer held back: the island keeps its no-JS behavior
// and the next interaction tries again.
const START = ['pointerover', 'pointerdown', 'focusin', 'keydown', 'click'] as const;

const interaction: ClientDirective = (load, _options, el) => {
  let hydrating: Promise<void> | null = null;
  let replay: HTMLElement | null = null;
  let holdPresses = true;

  const stop = () => START.forEach((type) => el.removeEventListener(type, onEvent, true));

  const hydrate = () =>
    (hydrating ??= (async () => {
      const run = await load();
      await run();
      stop();
      // the island's markup is hydrated in place, so the pressed element is still the same node
      const target = replay;
      replay = null;
      if (target?.isConnected) {
        // the element took focus before the island was live, so the island never saw that focus;
        // focus it again now, so state that follows focus (a tab list's highlighted tab) is right
        if (document.activeElement === target) {
          target.blur();
          target.focus({ preventScroll: true });
        }
        target.click();
      }
    })().catch(() => {
      hydrating = null;
      replay = null;
      holdPresses = false;
    }));

  function onEvent(event: Event) {
    if (event.type === 'click' && holdPresses) {
      const target = (event.target as Element | null)?.closest<HTMLElement>('button, a, [role="button"]');
      if (target) {
        // keep the press for the hydrated component instead of letting it fall through now
        event.preventDefault();
        event.stopPropagation();
        replay = target;
      }
    }
    void hydrate();
  }

  START.forEach((type) => el.addEventListener(type, onEvent, true));
};

export default interaction;
