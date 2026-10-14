// Site-wide constants: the origin, and the plugin facts every page shows. Plain Node, no astro:
// imports, so the config, the pages and node:test share it. astro.config.mjs imports this file, so it
// reads only plugin.json and the release-note headers, not the content modules.
//
// Exports
//   SITE_URL   the production origin
//   GH         the repository URL from .claude-plugin/plugin.json (`repository`), no trailing slash
//   VERSION    the plugin version from .claude-plugin/plugin.json
//   RELEASED   the date of the newest release note (docs/releases/)
import { GH, REPO, VERSION } from './repo.mjs';
import { listReleaseNotes } from './sources.mjs';

export const SITE_URL = 'https://agent-triforge.dbenger.com';
export { GH, VERSION };
export const RELEASED = listReleaseNotes(REPO)[0].date;
