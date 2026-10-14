// The hero's live dot field (DotField.astro): each CLI is a cluster of dots, a task is a dot that moves
// into a workspace of its own, a review is a different CLI's cluster reaching the task, and a merge
// brings the dot onto the shared line. One caption per step, in the film's order, in plain words.
// The canvas draws over the static SVG of the final frame, which is what shows without JavaScript and
// under reduced motion (one still frame, nothing moves). It runs only while on screen. There is no
// pause control (the user's decision, as on Agent Blueprint).

interface Cluster { x: number; y: number; opt?: number; dots: number[][] }
interface Task { from: number[]; cell: number[]; line: number[] }
interface Layout { cols: number; rows: number; clusters: Cluster[]; tasks: Task[]; line: { x0: number; x1: number; y: number }; touch: number[][] }
interface Spring { x: number; v: number }
interface Dot { c: number; k: number; hx: number; hy: number; px: Spring; py: Spring; sx: number; sy: number; opt: boolean; rr: number }
interface TaskState { id: number; x: number; y: number; on: boolean; big: boolean; pink: boolean; rev: number; self: boolean }

// critically damped spring: no overshoot
function spring(p: Spring, target: number, w: number, dt: number) {
  const d = p.x - target;
  const c2 = p.v + w * d;
  const e = Math.exp(-w * dt);
  p.x = target + (d + c2 * dt) * e;
  p.v = (c2 - w * (d + c2 * dt)) * e;
}
const rnd = (seed: number) => {
  const x = Math.sin(seed * 9301 + 49297) * 233280;
  return x - Math.floor(x);
};

export function initDotField(doc: Document = document, win: Window & typeof globalThis = window) {
  const field = doc.querySelector<HTMLElement>('.field[data-layouts]');
  const cv = field?.querySelector('canvas');
  const ctx = cv?.getContext('2d');
  if (!field || !cv || !ctx) return;
  const L: Record<'d' | 'm', Layout> = JSON.parse(field.dataset.layouts ?? '{}');
  const CAPS: string[] = JSON.parse(field.dataset.captions ?? '[]');
  const cap = field.parentElement?.querySelector<HTMLElement>('.field-cap p') ?? null;
  const RM = win.matchMedia('(prefers-reduced-motion: reduce)');
  const narrow = win.matchMedia('(max-width: 760px)');
  const reduced = () => RM.matches;

  // canvas needs rgb(); resolve each token (OKLCH included) through a 1 px canvas
  const probe = doc.createElement('canvas').getContext('2d', { willReadFrequently: true })!;
  const rgb = (token: string) => {
    probe.clearRect(0, 0, 1, 1);
    probe.fillStyle = '#000';
    probe.fillStyle = getComputedStyle(doc.documentElement).getPropertyValue(token).trim() || '#000';
    probe.fillRect(0, 0, 1, 1);
    // the alpha is dropped on purpose: the paper screen's dots are drawn in full ink at a tiny radius,
    // as in the approved design, and antialiasing makes them read as a light grey
    const [r, g, b] = probe.getImageData(0, 0, 1, 1).data;
    return `rgb(${r},${g},${b})`;
  };
  const col = { rest: '', active: '', opt: '', fg: '', quiet: '', screen: '', reg: 0 };
  // rest: a cluster at rest; active: the CLI at work, the shared line, merged tasks; opt: optional
  // members; fg: a task in progress; quiet: workspaces and a refused review
  const colors = () => {
    col.rest = rgb('--dot-rest');
    col.active = rgb('--dot-active');
    col.opt = rgb('--dot-opt');
    col.fg = rgb('--foreground');
    col.quiet = rgb('--muted-foreground');
    col.screen = rgb('--dot-screen');
    // a second ink prints a hair off register; with one ink there is nothing to misregister
    col.reg = col.active !== col.fg ? 0.5 : 0;
  };

  let lay: Layout;
  let dots: Dot[] = [];
  let W = 0;
  let H = 0;
  let s = 1;
  let dpr = 1;
  let t0 = performance.now();
  let last = t0;
  let running = false;
  let visible = true;
  const goal = { x: { x: 0, v: 0 }, y: { x: -3, v: 0 } };
  const taskDots: (null | { x: Spring; y: Spring })[] = [null, null];

  const setup = () => {
    lay = narrow.matches ? L.m : L.d;
    field.style.aspectRatio = `${lay.cols} / ${lay.rows}`;
    const r = field.getBoundingClientRect();
    dpr = Math.min(2, win.devicePixelRatio || 1);
    W = r.width;
    H = r.height;
    cv.width = Math.round(W * dpr);
    cv.height = Math.round(H * dpr);
    s = W / lay.cols;
    dots = [];
    lay.clusters.forEach((c, ci) => {
      c.dots.forEach(([dx, dy], k) => {
        const seed = ci * 97 + k * 13 + 1;
        const dist = Math.hypot(dx, dy);
        dots.push({
          c: ci, k, hx: c.x + dx, hy: c.y + dy, px: { x: c.x + dx, v: 0 }, py: { x: c.y + dy, v: 0 },
          sx: Math.floor(rnd(seed) * lay.cols), sy: Math.floor(rnd(seed + 7) * lay.rows), opt: !!c.opt,
          rr: c.opt ? 0.31 - dist * 0.04 : 0.45 - dist * 0.055,
        });
      });
    });
  };

  // the story in seconds, one caption per step: goal, split, build, review, merge, then a self-review
  // that is refused and a review by a different agent
  const T = 21;
  const MARKS = [1.6, 3.4, 5.0, 6.6, 8.4, 10.2, 11.8, 13.6, 15.4];
  const stateAt = (t: number) => {
    const st = { scatter: t < 0.4 || t > 19.6, builder: -1, reviewer: -1, cap: 0, tasks: [] as TaskState[], cells: t >= 3.4, goal: t >= 1.6 && t < 3.4, refusedAt: 12.6 };
    const [a, b] = lay.tasks;
    MARKS.forEach((m, i) => {
      if (t >= m) st.cap = i + 1;
    });
    if (t > 19.6) st.cap = 0;
    if (st.goal || (t >= 5.0 && t < 6.6) || (t >= 10.2 && t < 11.8)) st.builder = 0;
    st.tasks.push({ id: 0, x: t < 5.0 ? a.from[0] : t < 8.4 ? a.cell[0] : a.line[0], y: t < 5.0 ? a.from[1] : t < 8.4 ? a.cell[1] : a.line[1],
      on: t >= 3.4, big: t >= 5.6, pink: t >= 8.6, rev: t >= 6.6 && t < 8.2 ? 2 : -1, self: false });
    st.tasks.push({ id: 1, x: t < 10.2 ? b.from[0] + 1.6 : t < 15.4 ? b.cell[0] : b.line[0], y: t < 10.2 ? b.from[1] : t < 15.4 ? b.cell[1] : b.line[1],
      on: t >= 3.4, big: t >= 10.8, pink: t >= 15.6, rev: t >= 11.8 && t < 13.4 ? 0 : t >= 13.6 && t < 15.2 ? 2 : -1, self: t >= 11.8 && t < 13.4 });
    if ((t >= 6.6 && t < 8.2) || (t >= 13.6 && t < 15.2)) st.reviewer = 2;
    if (t >= 11.8 && t < 13.4) st.reviewer = 0;
    return st;
  };

  const draw = (now: number) => {
    let dt = Math.min(0.05, (now - last) / 1000);
    last = now;
    const still = reduced();
    const t = still ? 17.5 : ((now - t0) / 1000) % T;
    if (still) dt = 10;
    const st = stateAt(t);
    field.dataset.scatter = String(st.scatter);
    if (cap && cap.dataset.i !== String(st.cap)) {
      cap.dataset.i = String(st.cap);
      cap.textContent = CAPS[st.cap] ?? '';
    }
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    // the paper's dot screen
    ctx.fillStyle = col.screen;
    ctx.beginPath();
    for (let gx = 0; gx <= lay.cols; gx++) {
      for (let gy = 0; gy <= lay.rows; gy++) {
        ctx.moveTo((gx + 0.5) * s + s * 0.06, (gy + 0.5) * s);
        ctx.arc((gx + 0.5) * s, (gy + 0.5) * s, s * 0.06, 0, 6.2832);
      }
    }
    ctx.fill();
    const rest: number[][] = [];
    const opt: number[][] = [];
    const fg: number[][] = [];
    const pink: number[][] = [];
    const mute: number[][] = [];
    for (let lx = lay.line.x0; lx <= lay.line.x1; lx++) pink.push([lx, lay.line.y, 0.15]);
    // reviewers send four dots to touch the task's workspace
    dots.forEach((d) => {
      let tx = d.hx;
      let ty = d.hy;
      let w = 9;
      if (st.scatter) {
        tx = d.sx;
        ty = d.sy;
        w = 4.5;
      }
      const tsk = st.tasks.find((k) => k.rev === d.c && d.k < 4 && k.on) ?? null;
      if (tsk && !st.scatter) {
        const cell = lay.tasks[tsk.id].cell;
        const side = d.c === 0 ? -1 : 1;
        const off = lay.touch[d.k];
        tx = cell[0] + side * ((tsk.self ? 4 : 1) + off[0]);
        ty = cell[1] + off[1];
        w = 7;
      }
      spring(d.px, tx, w, dt);
      spring(d.py, ty, w, dt);
      const refused = !!tsk && tsk.self && t > st.refusedAt;
      const isPink = !st.scatter && (d.c === st.builder || d.c === st.reviewer) && !(refused && d.c === 0);
      // each cluster prints as a halftone disc; the CLI at work prints a little heavier
      const rr = isPink ? d.rr * 1.14 : d.rr;
      (isPink ? pink : refused ? mute : d.opt ? opt : rest).push([d.px.x, d.py.x, rr]);
    });
    // workspaces: a square outline of small dots
    if (st.cells && !st.scatter) {
      lay.tasks.forEach((k) => {
        for (let cx = -3; cx <= 3; cx++) for (let cy = -3; cy <= 3; cy++) if (Math.abs(cx) === 3 || Math.abs(cy) === 3) mute.push([k.cell[0] + cx, k.cell[1] + cy, 0.11]);
      });
    }
    // the goal: one dot that drops beside the lead's cluster, then splits into the tasks
    const lc = lay.clusters[0];
    const gx = lc.x + 3.6;
    if (st.goal && !st.scatter) {
      spring(goal.x, gx, 6, dt);
      spring(goal.y, lc.y, 6, dt);
      fg.push([goal.x.x, goal.y.x, 0.8]);
    } else {
      goal.x = { x: gx, v: 0 };
      goal.y = { x: -3, v: 0 };
    }
    st.tasks.forEach((k) => {
      if (!k.on) return;
      if (st.scatter) {
        taskDots[k.id] = null;
        return;
      }
      const o = (taskDots[k.id] ??= { x: { x: k.x, v: 0 }, y: { x: k.y, v: 0 } });
      spring(o.x, k.x, 6, dt);
      spring(o.y, k.y, 6, dt);
      (k.pink ? pink : fg).push([o.x.x, o.y.x, k.big ? 0.6 : 0.4]);
    });
    const batch = (list: number[][], color: string, dx: number, dy: number) => {
      ctx.fillStyle = color;
      ctx.beginPath();
      list.forEach(([px, py, pr]) => {
        const x = (px + 0.5) * s + dx;
        const y = (py + 0.5) * s + dy;
        const r = pr * s;
        ctx.moveTo(x + r, y);
        ctx.arc(x, y, r, 0, 6.2832);
      });
      ctx.fill();
    };
    batch(mute, col.quiet, 0, 0);
    batch(opt, col.opt, 0, 0);
    batch(rest, col.rest, 0, 0);
    batch(fg, col.fg, 0, 0);
    batch(pink, col.active, col.reg, -col.reg * 0.7);
  };

  const loop = (now: number) => {
    if (!running) return;
    draw(now);
    if (reduced()) {
      running = false;
      return;
    }
    win.requestAnimationFrame(loop);
  };
  const start = () => {
    if (running || !visible) return;
    running = true;
    last = performance.now();
    win.requestAnimationFrame(loop);
  };

  colors();
  setup();
  field.dataset.live = 'true';
  if (reduced()) draw(performance.now());
  new win.IntersectionObserver((es) => {
    visible = es[es.length - 1].isIntersecting;
    if (visible) start();
    else running = false;
  }, { threshold: [0, 0.05] }).observe(field);

  let resize = 0;
  win.addEventListener('resize', () => {
    win.clearTimeout(resize);
    resize = win.setTimeout(() => {
      setup();
      if (!running) draw(performance.now());
    }, 120);
  });
  doc.addEventListener('themechange', () => {
    colors();
    if (!running) draw(performance.now());
  });
  RM.addEventListener('change', () => {
    t0 = performance.now();
    if (reduced()) {
      running = false;
      draw(performance.now());
    } else start();
  });
}
