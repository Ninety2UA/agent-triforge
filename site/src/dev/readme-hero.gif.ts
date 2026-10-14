// /media/readme-hero.gif under `astro dev` only (kit-route.mjs): the README loop as a GIF, for the media
// kit. The repo keeps the file once, at docs/images/readme-hero.gif, where READMEs link it; this route
// serves that file, so a new render shows on the kit with no second copy under site/public.
import type { APIRoute } from 'astro';
import { readFileSync } from 'node:fs';

import { README_GIF } from './files.mjs';

export const GET: APIRoute = () =>
  new Response(readFileSync(README_GIF.file), { headers: { 'Content-Type': 'image/gif', 'Cache-Control': 'no-store' } });
