// /llms.txt: the site's name and summary, its main pages, every docs and guide page and every skill
// page with its one-line summary, built from the repo at build time (lib/llms.mjs).
import type { APIRoute } from 'astro';

import { NAV } from '@/data/nav';
import { llmsTxt } from '@/lib/llms.mjs';

export const GET: APIRoute = () => new Response(llmsTxt(NAV), { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
