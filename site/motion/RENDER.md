# Motion sources

The film, the four section loops and the README hero are HyperFrames compositions in the site's Ultramarine palette: a white ground, ink `#0e1012`, muted text `#52565a`, grey dots `#83878b`, and one accent `#204ec3` (`oklch(0.47 0.19 264)`) that marks the active thing in each beat. Everything is drawn as halftone dots on a canvas, with Familjen Grotesk set as HTML on top. The videos stay light on the white card in both site themes.

The motion shows plain sentences and product names only, never code: no file names, config, commands, helper output, return codes, or skill or persona ids. Check every frame for this before committing a render.

| Source | Output | Composition | Encoded | Length |
|---|---|---|---|---|
| `src/film.html` | `public/media/film.mp4`, `film.webp` (1600x900), `film-960.webp`, `film-chapters.json` | 1920x1080 | 1280x720, CRF 19 | 54.8 s |
| `src/loop-roster.html`, `loop-lease.html`, `loop-review.html`, `loop-unattended.html` | `public/media/loop-*.mp4` and `loop-*.webp` | 1200x750 | 800x500, CRF 17 | 8 s loop each |
| `src/readme-hero.html` | `public/media/readme-hero.mp4` and `.webp`, and `docs/images/readme-hero.gif` at the repo root | 1280x512 | 960x384, CRF 16; GIF 960x384 at 15 fps | 10 s loop |

- `src/ds.js` is the dot engine every composition shares: formations on a strict grid, spring morphs between them, and two inks printed in order, the accent last. `src/ds.css` holds the type. `build.py` inlines both into each composition.
- The film's scenes run on their own clock, and a piecewise-linear map (`OLD` and `NEW` in `src/film.html`) lands each chapter on its start in `src/film-chapters.json`. Change a chapter start in `NEW` and in `film-chapters.json` together. The site reads the chapter list, and the build fails without it.
- The README hero's line matches the site's sub-line: "One agent leads. The others build, review and test, and nothing merges until a different agent has checked it." Change both together.
- The words state facts about the framework. Keep them true to the repo (`scripts/lib/registry.sh`, `templates/ops/roster.toml`): eight CLIs, the core trio Claude Code, Codex and Antigravity, the five optional CLIs OpenCode, Kimi Code, Cursor, Grok Build and Devin, five reviewers in the test phase, up to three fix cycles, and up to five unattended sessions.

## Third-party files

- `vendor/gsap.min.js` is GSAP 3.14.2, used under GreenSock's standard no-charge license (https://gsap.com/standard-license). It only drives the composition timelines at render time and never ships to the site.
- The font is the site's own `src/assets/fonts/FamiljenGrotesk-var.woff2` (SIL Open Font License); `build.py` copies it into each project.

## How to render

Needs Node 22.12 or later, Python 3, ffmpeg, and the site's dependencies (`npm ci` in `site/`; `finish.sh` writes the WebP posters with its `sharp`). HyperFrames 0.8.140 renders locally through `npx`. Nothing goes to a cloud service.

```bash
export DO_NOT_TRACK=1 HYPERFRAMES_NO_TELEMETRY=1 HYPERFRAMES_NO_UPDATE_CHECK=1 HYPERFRAMES_SKIP_SKILLS=1
cd site/motion
python3 build.py                 # or: python3 build.py film readme-hero
for n in film loop-roster loop-lease loop-review loop-unattended readme-hero; do
  (cd ".work/$n" && npx --yes hyperframes@0.8.140 check && \
   npx --yes hyperframes@0.8.140 render --crf 2 --fps 30 --output "renders/$n-master.mp4")
done
bash finish.sh
cd .. && node --test 'test/media.test.mjs'
```

Render one project at a time; each render uses every core. Each takes under a minute on an Apple M-series machine. Never edit the generated projects under `.work/`; git ignores that folder, and the masters, posters' PNG sources and the GIF palette stay there.

`finish.sh` re-encodes each master with `ffmpeg -an -c:v libx264 -preset slow -pix_fmt yuv420p -r 30 -movflags +faststart`, CRF 19 for the film, 17 for the loops and 16 for the README hero, scaled with `lanczos+accurate_rnd+full_chroma_int`. It skips `-tune animation`, which leaves faint ghosts beside hairlines. The exact rounding keeps the white ground at `#ffffff` in the posters and the GIF; swscale's default rounding prints it as `#fdfdfd`. The film is encoded at 1280x720, its display size (the film box is at most 1180 CSS px wide), and the loops at 800 px wide for figures of about 600 CSS px.

Posters are WebP (quality 82) at the video's frame size, taken from the masters at these times: film 2.0 s (also at 960x540 for `film-960.webp`), roster 1.9 s, lease 2.4 s, review 6.2 s, unattended 4.2 s, README hero 1.6 s. The page sizes the poster and the video from the MP4's frame size, so a poster must keep its video's proportions.

The README GIF is 960 px wide at 15 fps and loops forever. Near-white pixels (the scaler's ringing around the dots) are set to white first, then `palettegen=max_colors=16:stats_mode=diff` picks the palette and `paletteuse=dither=none:diff_mode=rectangle` applies it. Counting pixels over the whole frame (`stats_mode=full`) spends the 16 colours on off-whites and drops the accent; `diff` weighs what moves, which keeps it.

## Size budget

Every install of the plugin copies the whole repository, and a Codex lead's marketplace install clones every branch with its history, so any media file ever pushed stays in every Codex install. `site/test/media.test.mjs` holds the budget: `site/public/media` at most 8,000,000 bytes in all and `docs/images/readme-hero.gif` at most 500,000 bytes. It also checks that every MP4 has its `moov` box before `mdat` and a poster of the same proportions, that the film refuses to build without its chapter list, and that the built pages request each media file under its content hash.

| File | Bytes |
|---|---|
| `film.mp4` | 4,698,183 |
| `loop-roster.mp4` | 721,654 |
| `loop-unattended.mp4` | 658,315 |
| `readme-hero.mp4` | 526,739 |
| `loop-lease.mp4` | 457,603 |
| `loop-review.mp4` | 260,847 |
| seven WebP posters | 326,508 |
| `film-chapters.json` | 297 |
| `site/public/media` in all | 7,650,146 |
| `docs/images/readme-hero.gif` | 393,556 |

Commit media only in their final encoding: never a stand-in, a master or an intermediate encode. Re-render and commit a video only when its content changes.

## Checks before committing a render

- `npx hyperframes check` passes for each project. The two lint warnings (a large file, and the canvas inside the timed stage) are expected for a single-canvas composition, and so is the README hero's layout note: its dot grid runs to the right edge on purpose.
- Pull frames from the final files and look at them: one still a second for the film and every half second for the loops and the hero. No code, paths or config on screen, every label reads at display size, and each loop's last frame leads into its first.
- `node --test 'site/test/**/*.test.mjs'` passes, and `npm run build` in `site/` succeeds with the new media.
