// The facts the media kit lists for each file, read from the file at dev time (ported from Agent
// Blueprint's kit/files.mjs): its size, its format, its frame size from its own header (PNG, GIF, WebP;
// an MP4's comes from media.mjs) and a GIF's length from its frame delays. Dev only: kit.astro and
// readme-hero.gif.ts import it, the build never does.
import { readFileSync, statSync } from 'node:fs';
import { extname, join } from 'node:path';

import { PUBLIC, REPO } from '../lib/repo.mjs';

/** The README loop as a GIF: kept once, in docs/images, and served under `astro dev` at `href`. */
export const README_GIF = { file: join(REPO, 'docs', 'images', 'readme-hero.gif'), href: '/media/readme-hero.gif' };

/**
 * The mark's colors for a light and a dark ground, as the favicon (public/brand/favicon.svg) sets them:
 * its ground rect, its ink circles (.i) and its accent circles (.a), then the same three under
 * prefers-color-scheme: dark. The kit's mark files use these, so they match the favicon.
 * @returns {{ light: { ground: string, ink: string, accent: string }, dark: { ground: string, ink: string, accent: string } }}
 */
export function markColors(file = join(PUBLIC, 'brand', 'favicon.svg')) {
  const css = readFileSync(file, 'utf8').match(/<style>([\s\S]*?)<\/style>/)?.[1] ?? '';
  const [light, dark = ''] = css.split(/@media\s*\(prefers-color-scheme:\s*dark\)/);
  /** @param {string} block @param {string} selector */
  const fill = (block, selector) => {
    const value = block.match(new RegExp(`(?:^|[{}\\s])${selector}\\s*\\{\\s*fill:\\s*(#[0-9a-f]{3,8})\\b`, 'i'))?.[1];
    if (!value) throw new Error(`${file}: no fill for "${selector}" in its ${block === light ? 'light' : 'dark'} styles`);
    return value;
  };
  /** @param {string} block */
  const colors = (block) => ({ ground: fill(block, 'rect'), ink: fill(block, '\\.i'), accent: fill(block, '\\.a') });
  return { light: colors(light), dark: colors(dark) };
}

const FORMATS = { '.mp4': 'MP4', '.gif': 'GIF', '.png': 'PNG', '.webp': 'WebP', '.svg': 'SVG', '.json': 'JSON' };

/** 297 -> "297 B", 32174 -> "31 KB", 4698183 -> "4.48 MB" */
export function humanSize(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  if (bytes < 1024) return `${bytes} B`;
  return `${Math.round(bytes / 1024)} KB`;
}

// The logical screen size, then every block up to the trailer; each graphic control extension holds
// the delay before the next frame, in hundredths of a second.
function gif(buf) {
  const table = (flags) => (flags & 0x80 ? 3 * (1 << ((flags & 7) + 1)) : 0);
  const skipSubBlocks = (pos) => {
    while (buf[pos] !== 0) pos += buf[pos] + 1;
    return pos + 1;
  };
  let hundredths = 0;
  let pos = 13 + table(buf[10]);
  while (pos < buf.length && buf[pos] !== 0x3b) {
    if (buf[pos] === 0x21) {
      if (buf[pos + 1] === 0xf9) hundredths += buf.readUInt16LE(pos + 4);
      pos = skipSubBlocks(pos + 2);
    } else if (buf[pos] === 0x2c) {
      pos = skipSubBlocks(pos + 10 + table(buf[pos + 9]) + 1);
    } else {
      throw new Error(`GIF: unknown block 0x${buf[pos].toString(16)} at byte ${pos}`);
    }
  }
  return { width: buf.readUInt16LE(6), height: buf.readUInt16LE(8), duration: hundredths / 100 };
}

// The first chunk after "WEBP": lossy VP8, lossless VP8L or extended VP8X.
function webp(buf) {
  const chunk = buf.toString('latin1', 12, 16);
  if (chunk === 'VP8 ') return { width: buf.readUInt16LE(26) & 0x3fff, height: buf.readUInt16LE(28) & 0x3fff };
  if (chunk === 'VP8L') {
    const bits = buf.readUInt32LE(21);
    return { width: (bits & 0x3fff) + 1, height: ((bits >> 14) & 0x3fff) + 1 };
  }
  if (chunk === 'VP8X') return { width: buf.readUIntLE(24, 3) + 1, height: buf.readUIntLE(27, 3) + 1 };
  throw new Error(`WebP: unknown chunk "${chunk}"`);
}

/**
 * { size, format, frame, length } for the file at `path`: frame is "1200 × 630" for a PNG, GIF or WebP
 * and length "6.0 s" for a GIF; both are "" where they do not apply.
 * @param {string} path
 */
export function fileFacts(path) {
  const ext = extname(path).toLowerCase();
  const size = humanSize(statSync(path).size);
  const format = FORMATS[ext] ?? ext.slice(1).toUpperCase();
  let dims = null;
  let length = '';
  if (ext === '.gif') {
    const g = gif(readFileSync(path));
    dims = g;
    length = `${g.duration.toFixed(1)} s`;
  } else if (ext === '.png') {
    const buf = readFileSync(path);
    dims = { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
  } else if (ext === '.webp') {
    dims = webp(readFileSync(path));
  }
  return { size, format, frame: dims ? `${dims.width} × ${dims.height}` : '', length };
}
