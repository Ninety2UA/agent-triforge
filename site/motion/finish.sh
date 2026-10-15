#!/usr/bin/env bash
# Final encodes from the HyperFrames masters in .work/<name>/renders/<name>-master.mp4 (git ignores
# .work/): H.264 yuv420p, faststart, no audio, 30 fps, each at its display size; a WebP poster per
# video at the video's frame size (the film's at 1600 and 960 wide); film-chapters.json; and the
# README GIF. Writes site/public/media/ and docs/images/readme-hero.gif. See RENDER.md.
set -euo pipefail
MOTION="$(cd "$(dirname "$0")" && pwd)"
SITE="$(dirname "$MOTION")"
REPO="$(dirname "$SITE")"
WORK="$MOTION/.work"
OUT="$SITE/public/media"
GIF="$REPO/docs/images/readme-hero.gif"
# Lanczos with exact YUV->RGB rounding: swscale's default rounding prints the white ground as #fdfdfd
SCALE="lanczos+accurate_rnd+full_chroma_int"
mkdir -p "$OUT" "$WORK/posters"

master() { echo "$WORK/$1/renders/$1-master.mp4"; }
for n in film loop-roster loop-lease loop-review loop-unattended readme-hero; do
  [ -s "$(master "$n")" ] || { echo "finish.sh: no master for $n at $(master "$n") (render it first, RENDER.md)" >&2; exit 1; }
done

enc() { # name width height crf
  ffmpeg -v error -y -i "$(master "$1")" -an -vf "scale=$2:$3:flags=$SCALE" -c:v libx264 -preset slow -crf "$4" \
    -pix_fmt yuv420p -r 30 -movflags +faststart "$OUT/$1.mp4"
}
poster() { # name seconds width height [output name]
  ffmpeg -v error -y -ss "$2" -i "$(master "$1")" -frames:v 1 -vf "scale=$3:$4:flags=$SCALE" "$WORK/posters/${5:-$1}.png"
  (cd "$SITE" && node -e 'require("sharp")(process.argv[1]).webp({ quality: 82, effort: 6 }).toFile(process.argv[2]).catch((e) => { console.error(e.message); process.exit(1); })' \
    "$WORK/posters/${5:-$1}.png" "$OUT/${5:-$1}.webp")
}

enc film 1280 720 19
for n in loop-roster loop-lease loop-review loop-unattended; do enc "$n" 800 500 17; done
enc readme-hero 960 384 16

poster film 2.0 1600 900
poster film 2.0 960 540 film-960
poster loop-roster 1.9 800 500
poster loop-lease 2.4 800 500
poster loop-review 6.2 800 500
poster loop-unattended 4.2 800 500
poster readme-hero 1.6 960 384

cp "$MOTION/src/film-chapters.json" "$OUT/film-chapters.json"

# README GIF: 960 px wide, 15 fps, loops forever. Near-white (the scaler's ringing around the dots) is
# set to white first, so palettegen spends its 16 colours on the greys and the accent; stats_mode=diff
# weighs what moves, which keeps the accent. No dither.
PRE="fps=15,scale=960:-1:flags=$SCALE,format=rgb24,lutrgb=r='if(gte(val\,244)\,255\,val)':g='if(gte(val\,244)\,255\,val)':b='if(gte(val\,244)\,255\,val)'"
ffmpeg -v error -y -i "$(master readme-hero)" -vf "$PRE,palettegen=max_colors=16:stats_mode=diff" "$WORK/hero-palette.png"
ffmpeg -v error -y -i "$(master readme-hero)" -i "$WORK/hero-palette.png" \
  -lavfi "$PRE [x]; [x][1:v] paletteuse=dither=none:diff_mode=rectangle" -loop 0 "$GIF"

ls -l "$OUT" "$GIF" | awk 'NF > 5 { print $5, $NF }'
echo "site/public/media total: $(find "$OUT" -type f -exec stat -f %z {} + | awk '{ s += $1 } END { print s }') bytes"
