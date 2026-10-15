// The built roster and sprint pages against the repo files they are made from. The roles and their
// fallback chains are read here from templates/ops/roster.toml with plain line matching, not with the
// site's TOML reader. Skipped without a build.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import { REPO } from '../src/lib/repo.mjs';
import { getClis } from '../src/lib/roster.mjs';
import { sprintPhases } from '../src/lib/sprint.mjs';
import { DIST, skip } from './built.mjs';

const page = (path) => readFileSync(join(DIST, path, 'index.html'), 'utf8');

// [{ role, chain: [cli, ...fallbacks] }] in the template's order
function templateRoles() {
  const text = readFileSync(join(REPO, 'templates/ops/roster.toml'), 'utf8');
  return [...text.matchAll(/^\[roles\.([a-z]+)\]\n([\s\S]*?)(?=^\[|^# ---)/gm)].map(([, role, body]) => {
    const cli = body.match(/^cli = "([^"]+)"/m)?.[1];
    const fallbacks = [...(body.match(/^fallbacks = \[([^\]]*)\]/m)?.[1] ?? '').matchAll(/"([^"]+)"/g)].map((m) => m[1]);
    return { role, chain: [cli, ...fallbacks] };
  });
}

test('the template read here has every role with a chain', () => {
  const roles = templateRoles();
  assert.ok(roles.length > 0);
  for (const r of roles) assert.ok(r.chain[0] && r.chain.length > 1, `${r.role}: ${r.chain.join(' -> ')}`);
});

test('the roster page lists every role in templates/ops/roster.toml with its full fallback chain', { skip }, () => {
  const html = page('roster');
  const shown = [...html.matchAll(/<ol class="c-chain" data-role="([a-z]+)"[^>]*>([\s\S]*?)<\/ol>/g)].map(([, role, body]) => ({
    role,
    chain: [...body.matchAll(/data-cli="([a-z]+)"/g)].map((m) => m[1]),
  }));
  assert.deepEqual(shown, templateRoles());
  // and each station is named as the registry names the CLI
  const names = new Map(getClis().map((c) => [c.id, c.name]));
  for (const [, cli, name] of html.matchAll(/<li data-cli="([a-z]+)"[^>]*>\s*<span class="d"[^>]*><\/span>\s*<b>([^<]+)<\/b>/g)) assert.equal(name, names.get(cli));
});

test('the roster page lists every CLI in the registry, with its provider', { skip }, () => {
  const html = page('roster');
  const listed = [...html.matchAll(/<li data-cli="([a-z]+)"><div class="c-who">/g)].map((m) => m[1]);
  assert.deepEqual([...listed].sort(), getClis().map((c) => c.id).sort());
  for (const c of getClis()) assert.ok(html.includes(c.egress.replace(/&/g, '&amp;')), `${c.id}: the page does not state "${c.egress}"`);
});

test('the sprint page has a station for every phase of the Sprint Pipeline table, with the review loop and the film link', { skip }, () => {
  const html = page('sprint');
  for (const p of sprintPhases()) assert.ok(html.includes(`<li id="${p.id}" class="c-phase">`), `no station for ${p.label}`);
  assert.ok(html.includes('id="fig-loop-review"'));
  assert.ok(html.includes('href="/#film"'));
});
