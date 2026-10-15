// A video's poster at the widths its box is shown at. The sources live in src/assets/posters (one WebP
// per video, the video's own frame) and Astro's image pipeline writes each width at build time under a
// content-hashed /_astro/ URL, so a phone fetches a poster sized for its screen and a re-render needs
// no new file names.
import { getImage } from 'astro:assets';
import type { ImageMetadata } from 'astro';

const sources = import.meta.glob<{ default: ImageMetadata }>('/src/assets/posters/*.webp', { eager: true });

export async function poster(name: string, widths: number[], sizes: string) {
  const src = sources[`/src/assets/posters/${name}.webp`]?.default;
  if (!src) throw new Error(`site/src/assets/posters/${name}.webp is missing: every video needs its poster`);
  const img = await getImage({ src, widths: widths.filter((w) => w <= src.width), sizes, format: 'webp', quality: 80 });
  return { src: img.src, srcset: img.srcSet.attribute, sizes, width: src.width, height: src.height };
}
