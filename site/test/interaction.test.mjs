// client:interaction (site/src/directives/interaction.ts), the directive every React island hydrates
// through: run in plain Node against a fake island element, with the island's load() settled by hand.
import { test } from 'node:test';
import assert from 'node:assert/strict';

import { deferred, fakeTarget, runClientScript, settle } from './client-script.mjs';

const directive = (doc = { activeElement: null }) => runClientScript('directives/interaction.ts', { globals: { document: doc } });

// something pressable inside the island: closest() finds it for a button or link selector
const pressable = () => ({
  isConnected: true,
  clicks: 0,
  focused: 0,
  click() {
    this.clicks += 1;
  },
  closest(selector) {
    return selector.includes('button') ? this : null;
  },
  blur() {},
  focus() {
    this.focused += 1;
  },
});

test('a click before hydration is held, then replayed once on the same element after the island runs', async () => {
  const interaction = directive();
  const island = fakeTarget();
  const loaded = deferred();
  let ran = 0;
  interaction(() => loaded.promise, {}, island);
  const button = pressable();
  const press = island.fire('click', { target: button });
  assert.equal(press.defaultPrevented, true, 'the press does not fall through to the static markup');
  assert.equal(press.stopped, true);
  assert.equal(button.clicks, 0);
  loaded.resolve(async () => {
    ran += 1;
  });
  await settle();
  assert.equal(ran, 1);
  assert.equal(button.clicks, 1, 'replayed once on the hydrated element');
  assert.equal(island.listeners.length, 0, 'the directive lets go of the island once it is live');
});

test('pointing at the island starts the download once; later events wait for the same load', async () => {
  const interaction = directive();
  const island = fakeTarget();
  let loads = 0;
  interaction(() => ((loads += 1), deferred().promise), {}, island);
  island.fire('pointerover', {});
  island.fire('focusin', {});
  island.fire('pointerover', {});
  await settle();
  assert.equal(loads, 1);
});

test('the element that had focus before hydration gets it again, so the live island sees it', async () => {
  const button = pressable();
  const interaction = directive({ activeElement: button });
  const island = fakeTarget();
  interaction(async () => async () => {}, {}, island);
  island.fire('click', { target: button });
  await settle();
  assert.equal(button.focused, 1);
  assert.equal(button.clicks, 1);
});

test('when loading fails, presses are no longer held and the next interaction tries again', async () => {
  const interaction = directive();
  const island = fakeTarget();
  const first = deferred();
  let loads = 0;
  interaction(() => ((loads += 1), loads === 1 ? first.promise : Promise.resolve(async () => {})), {}, island);
  const button = pressable();
  assert.equal(island.fire('click', { target: button }).defaultPrevented, true);
  first.reject(new Error('the chunk is gone'));
  await settle();
  const next = island.fire('click', { target: button });
  assert.equal(next.defaultPrevented, false, 'after a failure a press goes through to the static markup');
  assert.equal(loads, 2, 'and it tries to load the island again');
  await settle();
  assert.equal(button.clicks, 0, 'a press that was not held is not replayed');
  assert.equal(island.listeners.length, 0);
});

test('a click on something that is not a button or link is not held', () => {
  const interaction = directive();
  const island = fakeTarget();
  interaction(() => deferred().promise, {}, island);
  const press = island.fire('click', { target: { closest: () => null } });
  assert.equal(press.defaultPrevented, false);
  assert.equal(press.stopped, false);
});
