// Video figures (VideoFigure.astro, FilmPlayer.astro). Every figure plays on its own while at least
// half of it is on screen (or, when it is taller than twice the viewport, while it fills half the
// viewport) and pauses when it leaves; there is no pause control. Loops loop; the film plays once.
// With reduced motion nothing starts on its own. A Play button shows whenever nothing else will start
// a video: under reduced motion, when the browser refuses to start it (data saver, low power mode),
// when it fails to load, and after the film ends (as Replay). A chapter press plays the film from that
// chapter, reduced motion or not. Without JavaScript the native controls stay. Every video is
// preload="none" and nothing calls play() before a figure is on screen, so no video bytes load early.
// Loaded with a dynamic import, only on pages that have a figure.

const clock = (t: number) => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;
// a ratio step every 10 %, so a figure taller than the viewport still reports as it scrolls
const THRESHOLDS = Array.from({ length: 11 }, (_, i) => i / 10);

interface Figure {
  fig: HTMLElement;
  v: HTMLVideoElement;
  play(rewind?: boolean): void;
  auto(): void;
}

export function initVideos(doc: Document = document, win: Window & typeof globalThis = window) {
  const reduced = win.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const figures: Figure[] = [];

  doc.querySelectorAll<HTMLElement>('[data-vfig]').forEach((fig) => {
    const v = fig.querySelector('video');
    if (!v) return;
    v.removeAttribute('controls');
    fig.classList.add('vjs');
    const big = fig.querySelector<HTMLButtonElement>('.vf-big');
    const label = big?.dataset.label ?? 'the video';
    let inView = false;
    let refused = false;
    let failed = false;

    const sync = () => {
      const playing = !v.paused && !v.ended;
      if (playing) refused = false;
      fig.classList.toggle('is-playing', playing);
      fig.classList.toggle('show-big', !playing && (reduced || refused || failed || v.ended));
      if (big) {
        const word = v.ended ? 'Replay' : 'Play';
        const text = big.querySelector('span');
        if (text) text.textContent = word;
        big.setAttribute('aria-label', `${word} ${label}`);
      }
    };
    const start = () => {
      v.play().then(sync, (error: unknown) => {
        // an AbortError only means a pause() came first, as when the figure leaves the screen
        if ((error as DOMException | null)?.name !== 'AbortError') refused = true;
        sync();
      });
    };
    const ctl: Figure = {
      fig,
      v,
      play(rewind = true) {
        if (rewind && v.ended) v.currentTime = 0;
        failed = false;
        start();
      },
      auto() {
        if (inView && !reduced && !failed && !v.ended && v.paused && !doc.hidden) start();
      },
    };

    (['play', 'pause', 'ended'] as const).forEach((ev) => v.addEventListener(ev, sync));
    // the video is shown over its poster only once frames arrive, so a failed load keeps the poster
    v.addEventListener('playing', () => {
      fig.classList.add('is-started');
      sync();
    });
    const fail = () => {
      failed = true;
      sync();
    };
    v.addEventListener('error', fail);
    v.querySelector('source')?.addEventListener('error', fail);
    big?.addEventListener('click', () => ctl.play());

    new win.IntersectionObserver(
      (entries) => {
        const e = entries[entries.length - 1];
        const fillsHalf = !!e.rootBounds && e.intersectionRect.height >= e.rootBounds.height / 2;
        inView = e.isIntersecting && (e.intersectionRatio >= 0.5 || fillsHalf);
        if (!inView) {
          if (!v.paused) v.pause();
          return;
        }
        ctl.auto();
      },
      { threshold: THRESHOLDS },
    ).observe(v);
    sync();
    figures.push(ctl);
    if (fig.hasAttribute('data-film')) initFilm(ctl, win);
  });

  doc.addEventListener('visibilitychange', () => {
    figures.forEach((c) => (doc.hidden ? !c.v.paused && c.v.pause() : c.auto()));
  });
}

// The film: chapter buttons seek and follow playback; a line of dots shows and sets the position.
function initFilm({ fig, v, play }: Figure, win: Window & typeof globalThis) {
  const dur0 = parseFloat(fig.dataset.duration ?? '') || 1;
  const dur = () => (Number.isFinite(v.duration) && v.duration > 0 ? v.duration : dur0);
  const chaps = [...fig.querySelectorAll<HTMLButtonElement>('.chapters button[data-t]')].map((b) => ({ b, t: parseFloat(b.dataset.t ?? '0') }));
  const dots = fig.querySelector<HTMLElement>('.film-dots');
  const time = fig.querySelector<HTMLElement>('.film-time');
  let circles: SVGCircleElement[] = [];
  let n = 0;
  let active = -1;
  let shown = '';
  let raf = 0;

  const build = () => {
    if (!dots) return;
    const w = dots.clientWidth || 600;
    n = Math.max(20, Math.min(90, Math.round(w / 12)));
    let svg = `<svg viewBox="0 0 ${w} 22" aria-hidden="true">`;
    for (let i = 0; i < n; i++) svg += `<circle cx="${(6 + (i * (w - 12)) / (n - 1)).toFixed(1)}" cy="11" r="3" class="u"/>`;
    dots.innerHTML = `${svg}</svg>`;
    circles = [...dots.querySelectorAll<SVGCircleElement>('circle')];
    show(v.currentTime || 0);
  };
  const show = (t: number) => {
    const k = Math.round((t / dur()) * (n - 1));
    circles.forEach((c, i) => {
      const cls = i < k ? 'f' : i === k ? 'c' : 'u';
      if (c.getAttribute('class') !== cls) {
        c.setAttribute('class', cls);
        c.setAttribute('r', cls === 'c' ? '6' : cls === 'f' ? '4' : '3');
      }
    });
    let i = 0;
    chaps.forEach((c, j) => {
      if (t + 0.05 >= c.t) i = j;
    });
    if (i !== active) {
      active = i;
      chaps.forEach((c, j) => (j === i ? c.b.setAttribute('aria-current', 'step') : c.b.removeAttribute('aria-current')));
    }
    // the readout changes once a second; the loop runs every frame, so write it only when it changes
    const readout = `${clock(t)}|${clock(dur())}|${Math.round(t)}`;
    if (readout === shown) return;
    shown = readout;
    if (time) time.textContent = `${clock(t)} / ${clock(dur())}`;
    if (dots) {
      dots.setAttribute('aria-valuenow', String(Math.round(t)));
      dots.setAttribute('aria-valuetext', `${clock(t)} of ${clock(dur())}`);
    }
  };
  const loop = () => {
    show(v.currentTime);
    raf = win.requestAnimationFrame(loop);
  };
  v.addEventListener('playing', () => {
    win.cancelAnimationFrame(raf);
    raf = win.requestAnimationFrame(loop);
  });
  (['pause', 'ended', 'seeked', 'loadedmetadata'] as const).forEach((ev) =>
    v.addEventListener(ev, () => {
      win.cancelAnimationFrame(raf);
      show(v.currentTime);
      // a seek inside the buffer may not fire `playing` again; keep the readout moving
      if (!v.paused && !v.ended) raf = win.requestAnimationFrame(loop);
    }),
  );
  const jump = (t: number) => {
    if (v.preload === 'none') v.preload = 'metadata';
    v.currentTime = Math.max(0, Math.min(t, dur() - 0.05));
    show(v.currentTime);
  };
  chaps.forEach((c) =>
    c.b.addEventListener('click', () => {
      jump(c.t + 0.01);
      play(false);
    }),
  );
  if (dots) {
    const scrub = (e: PointerEvent) => {
      const r = dots.getBoundingClientRect();
      jump(((e.clientX - r.left) / r.width) * dur());
    };
    dots.addEventListener('pointerdown', (e) => {
      scrub(e);
      dots.setPointerCapture?.(e.pointerId);
    });
    dots.addEventListener('pointermove', (e) => {
      if (dots.hasPointerCapture?.(e.pointerId)) scrub(e);
    });
    dots.addEventListener('keydown', (e) => {
      const step = e.key === 'ArrowRight' || e.key === 'ArrowUp' ? 5 : e.key === 'ArrowLeft' || e.key === 'ArrowDown' ? -5 : 0;
      if (step) {
        e.preventDefault();
        jump(v.currentTime + step);
      } else if (e.key === 'Home' || e.key === 'End') {
        e.preventDefault();
        jump(e.key === 'Home' ? 0 : dur());
      }
    });
    let resize = 0;
    win.addEventListener('resize', () => {
      win.clearTimeout(resize);
      resize = win.setTimeout(build, 150);
    });
  }
  build();
}
