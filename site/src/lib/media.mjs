// Build-time facts about the media in site/public/media: an MP4's length and frame size read from its
// own boxes (mvhd and the first video tkhd), the film's chapters, and versioned URLs. A re-render
// changes the pages with no edit under site/src. Plain Node, shared with node:test.
import { createHash } from 'node:crypto';
import { closeSync, existsSync, fstatSync, openSync, readFileSync, readSync } from 'node:fs';
import { join } from 'node:path';
import { PUBLIC } from './repo.mjs';

const facts = new Map();

/**
 * Length (seconds) and frame size of an MP4 under site/public, e.g. "/media/film.mp4".
 * @param {string} sitePath
 * @returns {{ duration: number, width: number, height: number }}
 */
export function mp4Facts(sitePath) {
  let f = facts.get(sitePath);
  if (!f) facts.set(sitePath, (f = readMp4Facts(sitePath)));
  return f;
}

function readMp4Facts(sitePath) {
  const fd = openSync(join(PUBLIC, sitePath), 'r');
  try {
    const read = (pos, len) => {
      const buf = Buffer.alloc(len);
      readSync(fd, buf, 0, len, pos);
      return buf;
    };
    // the boxes between start and end, each with its payload range
    const boxes = (start, end) => {
      const out = [];
      for (let pos = start; pos + 8 <= end; ) {
        const head = read(pos, 16);
        let size = head.readUInt32BE(0);
        let header = 8;
        if (size === 1) {
          size = Number(head.readBigUInt64BE(8));
          header = 16;
        } else if (size === 0) {
          size = end - pos;
        }
        out.push({ type: head.toString('latin1', 4, 8), at: pos + header, end: pos + size });
        pos += size;
      }
      return out;
    };
    const find = (list, type) => {
      const box = list.find((b) => b.type === type);
      if (!box) throw new Error(`${sitePath}: no ${type} box`);
      return box;
    };

    const moov = find(boxes(0, fstatSync(fd).size), 'moov');
    const inMoov = boxes(moov.at, moov.end);
    const m = read(find(inMoov, 'mvhd').at, 32);
    const duration = m[0] === 1 ? Number(m.readBigUInt64BE(24)) / m.readUInt32BE(20) : m.readUInt32BE(16) / m.readUInt32BE(12);
    // tkhd ends with the track's width and height as 16.16 fixed point
    for (const trak of inMoov.filter((b) => b.type === 'trak')) {
      const tkhd = find(boxes(trak.at, trak.end), 'tkhd');
      const wh = read(tkhd.end - 8, 8);
      const width = wh.readUInt32BE(0) >>> 16;
      const height = wh.readUInt32BE(4) >>> 16;
      if (width && height) return { duration, width, height };
    }
    throw new Error(`${sitePath}: no video track`);
  } finally {
    closeSync(fd);
  }
}

/**
 * The film's chapters from site/public/media/film-chapters.json and its length from film.mp4.
 * There is no fallback: a film without its chapter list fails the build instead of showing made-up chapters.
 * @returns {{ chapters: { label: string, start: number }[], duration: number }}
 */
export function filmChapters() {
  const file = join(PUBLIC, 'media', 'film-chapters.json');
  if (!existsSync(file)) throw new Error('site/public/media/film-chapters.json is missing: the film needs its chapter list');
  const chapters = JSON.parse(readFileSync(file, 'utf8'));
  return { chapters, duration: mp4Facts('/media/film.mp4').duration };
}

const versions = new Map();

/**
 * The URL a page requests for a file under site/public: the path plus ?v= and the first 8 hex digits
 * of the file's SHA-1. /media/ is cached for a day, so a re-rendered file needs a new URL.
 * @param {string} sitePath
 */
export function versioned(sitePath) {
  let v = versions.get(sitePath);
  if (!v) versions.set(sitePath, (v = createHash('sha1').update(readFileSync(join(PUBLIC, sitePath))).digest('hex').slice(0, 8)));
  return `${sitePath}?v=${v}`;
}

/** 59.5 -> "0:59" */
export function clock(seconds) {
  const t = Math.max(0, seconds);
  return `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
}
