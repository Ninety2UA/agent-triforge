// Checks on the media in site/public/media, their posters in site/src/assets/posters (Astro's image
// pipeline makes each poster's display widths at build time) and the README GIF: every MP4 streams from
// its first bytes (moov before mdat) and has a poster of the same frame proportions, the media stay inside the size
// budget (every install of the plugin copies the whole repo), the film refuses to build without its
// chapter list, and the built pages request every media file under a content-hash URL.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { closeSync, existsSync, fstatSync, mkdirSync, mkdtempSync, openSync, readFileSync, readSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { pathToFileURL } from 'node:url';

import { PUBLIC, REPO, SITE } from '../src/lib/repo.mjs';
import { mp4Facts } from '../src/lib/media.mjs';
import { DIST as dist, skip } from './built.mjs';
import { readPages } from '../scripts/check-site.mjs';

const MEDIA = join(PUBLIC, 'media');
const POSTERS = join(SITE, 'src', 'assets', 'posters');
const GIF = join(REPO, 'docs', 'images', 'readme-hero.gif');
const MEDIA_BUDGET = 8_000_000; // bytes, site/public/media and the poster sources in all
const GIF_BUDGET = 500_000; // bytes
// the videos the pages request by name
const VIDEOS = ['film', 'loop-roster', 'loop-lease', 'loop-review', 'loop-unattended', 'readme-hero'];

const filesIn = (dir) => (existsSync(dir) ? readdirSync(dir).filter((n) => statSync(join(dir, n)).isFile()) : []);
const mediaFiles = () => filesIn(MEDIA);

/** The file's top-level box types in order. */
function topBoxes(path) {
  const fd = openSync(path, 'r');
  try {
    const size = fstatSync(fd).size;
    const head = Buffer.alloc(16);
    const types = [];
    for (let pos = 0; pos + 8 <= size; ) {
      readSync(fd, head, 0, 16, pos);
      let len = head.readUInt32BE(0);
      if (len === 1) len = Number(head.readBigUInt64BE(8));
      else if (len === 0) len = size - pos;
      if (len < 8) throw new Error(`${path}: a box of ${len} bytes at ${pos}`);
      types.push(head.toString('latin1', 4, 8));
      pos += len;
    }
    return types;
  } finally {
    closeSync(fd);
  }
}

/** Width and height of a WebP from its RIFF header (lossy VP8, lossless VP8L or extended VP8X). */
function webpSize(path) {
  const b = readFileSync(path);
  assert.equal(b.toString('latin1', 0, 4), 'RIFF', `${path}: not a RIFF file`);
  assert.equal(b.toString('latin1', 8, 12), 'WEBP', `${path}: not a WebP`);
  const chunk = b.toString('latin1', 12, 16);
  if (chunk === 'VP8X') return { width: 1 + b.readUIntLE(24, 3), height: 1 + b.readUIntLE(27, 3) };
  if (chunk === 'VP8L') {
    const bits = b.readUInt32LE(21);
    return { width: 1 + (bits & 0x3fff), height: 1 + ((bits >> 14) & 0x3fff) };
  }
  if (chunk === 'VP8 ') return { width: b.readUInt16LE(26) & 0x3fff, height: b.readUInt16LE(28) & 0x3fff };
  throw new Error(`${path}: unknown WebP chunk ${chunk}`);
}

test('every MP4 has its moov box before mdat and a poster of the same proportions', () => {
  const mp4s = mediaFiles().filter((n) => n.endsWith('.mp4'));
  assert.deepEqual(mp4s.map((n) => n.slice(0, -4)).sort(), [...VIDEOS].sort(), 'site/public/media should hold exactly the six videos the pages request');
  for (const name of mp4s) {
    const types = topBoxes(join(MEDIA, name));
    assert.ok(types.includes('moov') && types.includes('mdat'), `${name}: boxes ${types.join(' ')}`);
    assert.ok(types.indexOf('moov') < types.indexOf('mdat'), `${name}: moov after mdat (encode with -movflags +faststart): ${types.join(' ')}`);
    const poster = join(POSTERS, name.replace(/\.mp4$/, '.webp'));
    assert.ok(existsSync(poster), `${name}: no poster ${relative(SITE, poster)}`);
    const { width, height } = mp4Facts(`/media/${name}`);
    const p = webpSize(poster);
    assert.ok(Math.abs(p.width / p.height - width / height) < 0.01, `${name}: poster ${p.width}x${p.height} does not have the video's ${width}x${height} proportions`);
  }
});

test(`the media and their posters total at most ${MEDIA_BUDGET} bytes and the README GIF at most ${GIF_BUDGET}`, () => {
  const total = [MEDIA, POSTERS].reduce((sum, dir) => sum + filesIn(dir).reduce((s, n) => s + statSync(join(dir, n)).size, 0), 0);
  assert.ok(total > 0, 'site/public/media is empty');
  assert.ok(total <= MEDIA_BUDGET, `the media and posters are ${total} bytes, over the ${MEDIA_BUDGET}-byte budget`);
  assert.ok(existsSync(GIF), `no README GIF at ${relative(REPO, GIF)}`);
  const gif = statSync(GIF).size;
  assert.ok(gif <= GIF_BUDGET, `${relative(REPO, GIF)} is ${gif} bytes, over the ${GIF_BUDGET}-byte budget`);
});

test('the film fails the build without film-chapters.json instead of inventing chapters', () => {
  // a throwaway repo with a film but no chapter list; media.mjs finds the repo from the working directory
  const root = mkdtempSync(join(tmpdir(), 'triforge-media-'));
  try {
    mkdirSync(join(root, '.claude-plugin'));
    writeFileSync(join(root, '.claude-plugin', 'plugin.json'), '{}');
    writeFileSync(join(root, 'README.md'), '');
    mkdirSync(join(root, 'site', 'public', 'media'), { recursive: true });
    const script = `import { filmChapters } from ${JSON.stringify(pathToFileURL(join(SITE, 'src', 'lib', 'media.mjs')).href)};
try { filmChapters(); console.log('no error'); } catch (e) { console.log(e.message); }`;
    const out = execFileSync(process.execPath, ['--input-type=module', '-e', script], { cwd: root, encoding: 'utf8' }).trim();
    assert.equal(out, 'site/public/media/film-chapters.json is missing: the film needs its chapter list');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('every media URL in the built pages carries the content hash of its file', { skip }, () => {
  const html = readPages(dist).map((p) => ({ page: p.file, text: p.html }));
  const sha = new Map();
  const hashOf = (file) => {
    if (!sha.has(file)) sha.set(file, createHash('sha1').update(readFileSync(join(MEDIA, file))).digest('hex').slice(0, 8));
    return sha.get(file);
  };
  const problems = [];
  let seen = 0;
  for (const { page, text } of html) {
    // every /media/ reference in an attribute value, srcset entries included
    for (const [, url] of text.matchAll(/(\/media\/[^\s"'<>,)]+)/g)) {
      seen += 1;
      const m = url.match(/^\/media\/([^?#]+)\?v=([0-9a-f]{8})$/);
      if (!m) problems.push(`${page}: ${url} has no ?v=<content hash>`);
      else if (!existsSync(join(MEDIA, m[1]))) problems.push(`${page}: ${url} names no file in site/public/media`);
      else if (m[2] !== hashOf(m[1])) problems.push(`${page}: ${url} carries ${m[2]}, the file's hash is ${hashOf(m[1])}`);
    }
  }
  assert.ok(seen > 0, 'no /media/ URL in the built pages: the pattern no longer matches');
  assert.deepEqual(problems, []);
});
