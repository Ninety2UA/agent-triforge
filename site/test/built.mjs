// The built site (site/dist) for the tests that check it. Without a build those tests skip and say so,
// so `node --test` before `npm run build` still runs everything else.
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { SITE } from '../src/lib/repo.mjs';

export const DIST = join(SITE, 'dist');

/** node:test's skip reason, or false once the site is built */
export const skip = !existsSync(join(DIST, 'index.html')) && 'site/dist is not built (run npm run build in site/)';
