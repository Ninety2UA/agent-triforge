// Halftone dot engine shared by every composition. Every frame is a pure
// function of time: formations are fixed dot lists on a strict grid, tracks
// move dots between formations with a critically damped spring
// 1-(1+wt)e^(-wt) (no overshoot), and the renderer prints two inks: the dot
// ink first, then the accent (index ACC) on top. The colours are the site's
// Ultramarine palette (sRGB of its OKLCH tokens; the accent is
// oklch(0.47 0.19 264)); on paper the accent is overprinted (multiply) a hair
// out of register. Text is HTML on top.
const HT = (() => {
  const C = { ground: "#ffffff", text: "#0e1012", muted: "#52565a", dot: "#0e1012", dotMuted: "#83878b", accent: "#204ec3", accentBoost: 1, blend: "multiply", misreg: [0.5, -0.4] };
  const INK = 0, PINK = 1, MUTED = 2, RING = 3, RINGM = 4, RINGP = 5;
  const TAU = Math.PI * 2;
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, p) => a + (b - a) * p;
  function hash(i, s) {
    let x = Math.imul((i | 0) ^ Math.imul((s | 0) + 1, 0x9e3779b1), 0x85ebca6b);
    x ^= x >>> 13; x = Math.imul(x, 0xc2b2ae35); x ^= x >>> 16;
    return (x >>> 0) / 4294967296;
  }
  // critically damped spring, starts at rest, ~0.995 at u = 1, snaps to 1 after
  function spring(u) {
    if (u <= 0) return 0;
    if (u >= 1) return 1;
    const x = 7.5 * u;
    return 1 - (1 + x) * Math.exp(-x);
  }
  const win = (t, t0, d) => clamp((t - t0) / d, 0, 1);
  const sp = (t, t0, d) => spring((t - t0) / d);

  // ---------- formations ----------
  // A formation is a packed dot list; `dyn(t, r)` may rewrite radii per frame
  // (halftone images), positions never change inside one formation.
  function pack(a, dyn) {
    const n = a.length / 4;
    const f = { n, x: new Float32Array(n), y: new Float32Array(n), r: new Float32Array(n), c: new Uint8Array(n), dyn: dyn || null };
    for (let i = 0; i < n; i++) { f.x[i] = a[4 * i]; f.y[i] = a[4 * i + 1]; f.r[i] = a[4 * i + 2]; f.c[i] = a[4 * i + 3]; }
    return f;
  }
  const EMPTY = pack([]);
  function radii(f, t) {
    if (!f.dyn) return f.r;
    if (!f._rb) f._rb = new Float32Array(f.n);
    f.dyn(t, f._rb, f);
    return f._rb;
  }
  function join(...fs) {
    const a = [];
    const dyns = [];
    let off = 0;
    fs.forEach((f) => {
      if (!f) return;
      for (let i = 0; i < f.n; i++) a.push(f.x[i], f.y[i], f.r[i], f.c[i]);
      if (f.dyn) dyns.push([f, off]);
      off += f.n;
    });
    const out = pack(a);
    if (dyns.length) {
      out.dyn = (t, r) => {
        for (let i = 0; i < out.n; i++) r[i] = out.r[i];
        dyns.forEach(([f, o]) => { const rr = radii(f, t); for (let i = 0; i < f.n; i++) r[o + i] = rr[i]; });
      };
    }
    return out;
  }
  // translate / recolor / rescale a static formation
  function map(f, fn) {
    const a = [];
    for (let i = 0; i < f.n; i++) {
      const d = fn({ x: f.x[i], y: f.y[i], r: f.r[i], c: f.c[i], i });
      if (d) a.push(d.x, d.y, d.r, d.c);
    }
    return pack(a);
  }
  const shift = (f, dx, dy) => map(f, (d) => ({ ...d, x: d.x + dx, y: d.y + dy }));
  const tint = (f, c) => map(f, (d) => ({ ...d, c }));
  const scaleR = (f, k) => map(f, (d) => ({ ...d, r: d.r * k }));

  // a disc of dots on the grid, shaded like a printed sphere
  function disc(cx, cy, R, o) {
    o = o || {};
    const p = o.pitch || 12, rmax = o.rmax || p * 0.42, c = o.c || 0, a = [];
    const n = Math.ceil(R / p) + 1;
    for (let j = -n; j <= n; j++) for (let i = -n; i <= n; i++) {
      const x = i * p, y = j * p, d = Math.hypot(x, y) / R;
      if (d > 1.0001) continue;
      const prof = o.flat ? 1 : Math.max(o.min || 0.34, Math.sqrt(1 - d * d * 0.86));
      a.push(cx + x, cy + y, rmax * prof, c);
    }
    return pack(a);
  }
  // a rectangular block of dots, cols x rows, top-left node at (x, y)
  function block(x, y, cols, rows, o) {
    o = o || {};
    const p = o.pitch || 12, r = o.r || p * 0.36, c = o.c || 0, a = [];
    for (let j = 0; j < rows; j++) for (let i = 0; i < cols; i++) {
      const rr = o.rf ? o.rf(i, j) : r;
      if (rr > 0) a.push(x + i * p, y + j * p, rr, c);
    }
    return pack(a);
  }
  // dots along a segment at a fixed spacing
  function seg(x1, y1, x2, y2, o) {
    o = o || {};
    const p = o.pitch || 12, r = o.r || 3.6, c = o.c || 0, a = [];
    const L = Math.hypot(x2 - x1, y2 - y1), n = Math.max(1, Math.round(L / p));
    for (let k = 0; k <= n; k++) a.push(lerp(x1, x2, k / n), lerp(y1, y2, k / n), o.rf ? o.rf(k, n) : r, c);
    return pack(a);
  }
  // dots along a polyline [[x,y],...] at a fixed spacing
  function poly(pts, o) {
    o = o || {};
    const p = o.pitch || 12, r = o.r || 3.6, c = o.c || 0, a = [];
    let carry = 0;
    for (let s = 0; s < pts.length - 1; s++) {
      const [x1, y1] = pts[s], [x2, y2] = pts[s + 1];
      const L = Math.hypot(x2 - x1, y2 - y1);
      let d = carry;
      while (d <= L) { a.push(lerp(x1, x2, d / L), lerp(y1, y2, d / L), r, c); d += p; }
      carry = d - L;
    }
    const last = pts[pts.length - 1];
    a.push(last[0], last[1], r, c);
    return pack(a);
  }
  // dots on a circle
  function ringOf(cx, cy, R, o) {
    o = o || {};
    const p = o.pitch || 12, r = o.r || 3, c = o.c || 0, a = [];
    const n = Math.max(6, Math.round((TAU * R) / p));
    for (let k = 0; k < n; k++) a.push(cx + R * Math.cos((k / n) * TAU), cy + R * Math.sin((k / n) * TAU), r, c);
    return pack(a);
  }
  // dots on the outline of a rectangle
  function frame(x, y, w, h, o) {
    return join(seg(x, y, x + w, y, o), seg(x + w, y, x + w, y + h, o), seg(x + w, y + h, x, y + h, o), seg(x, y + h, x, y, o));
  }
  // dots along a cubic curve, evenly spaced by arc length
  function curve(p0, p1, p2, p3, o) {
    o = o || {};
    const pts = [];
    for (let k = 0; k <= 64; k++) {
      const u = k / 64, v = 1 - u;
      pts.push([v * v * v * p0[0] + 3 * v * v * u * p1[0] + 3 * v * u * u * p2[0] + u * u * u * p3[0],
        v * v * v * p0[1] + 3 * v * v * u * p1[1] + 3 * v * u * u * p2[1] + u * u * u * p3[1]]);
    }
    return poly(pts, o);
  }
  // the mark: three dot clusters flowing into one pink line, on a strict grid
  // (logo-1 concept regularised). (cx, cy) = the junction dot, p = pitch.
  const LOGO = (() => {
    const up = [[0, -3, 0.45], [1, -3, 0.42], [2, -3, 0.38], [1, -2, 0.4], [2, -2, 0.35], [3, -2, 0.3], [4, -1, 0.24]];
    const mid = [[0, 0, 0.45], [1, 0, 0.43], [2, 0, 0.39], [3, 0, 0.34], [4, 0, 0.27], [5, 0, 0.2]];
    const lo = up.map(([x, y, r]) => [x, -y, r]);
    const pk = [6, 7, 8, 9, 10, 11].map((x) => [x, 0, 0.42]);
    return { up, mid, lo, pk };
  })();
  function logo(x0, y0, p, o) {
    o = o || {};
    const a = [];
    const put = (list, c) => list.forEach(([x, y, r]) => a.push(x0 + x * p, y0 + y * p, r * p, c));
    put(LOGO.up, o.ink == null ? 0 : o.ink); put(LOGO.mid, o.ink == null ? 0 : o.ink); put(LOGO.lo, o.ink == null ? 0 : o.ink);
    if (!o.noPink) put(LOGO.pk, o.pink == null ? 1 : o.pink);
    return pack(a);
  }

  // ---------- halftone images ----------
  // lum: base64 Uint8 darkness map (0 white .. 255 ink), lw x lh.
  function image(b64, lw, lh) {
    const bin = atob(b64), d = new Float32Array(bin.length);
    for (let i = 0; i < bin.length; i++) d[i] = bin.charCodeAt(i) / 255;
    function at(u, v) { // bilinear, u v in 0..1
      const fx = clamp(u, 0, 1) * (lw - 1), fy = clamp(v, 0, 1) * (lh - 1);
      const x0 = Math.floor(fx), y0 = Math.floor(fy), x1 = Math.min(lw - 1, x0 + 1), y1 = Math.min(lh - 1, y0 + 1);
      const ax = fx - x0, ay = fy - y0;
      return lerp(lerp(d[y0 * lw + x0], d[y0 * lw + x1], ax), lerp(d[y1 * lw + x0], d[y1 * lw + x1], ax), ay);
    }
    return { at, lw, lh };
  }
  // A fixed screen over a region; the picture moves under it (push/pan), so
  // the dots change size while their positions stay on the grid.
  // o: {x,y,w,h (region), pitch, angle (deg), rmax, view(t) -> {cx, cy, s} in
  //     image uv (centre, and image-width fraction shown across region w),
  //     mask(x,y) -> 0..1, gain(t) -> 0..1, gamma, c, pinkPath, pinkW}
  function halftone(img, o) {
    const p = o.pitch || 12, ang = ((o.angle == null ? 45 : o.angle) * Math.PI) / 180;
    const ca = Math.cos(ang), sa = Math.sin(ang);
    const cxr = o.x + o.w / 2, cyr = o.y + o.h / 2;
    const R = Math.hypot(o.w, o.h) / 2 + p;
    const a = [];
    const n = Math.ceil(R / p);
    for (let j = -n; j <= n; j++) for (let i = -n; i <= n; i++) {
      const x = cxr + (i * ca - j * sa) * p, y = cyr + (i * sa + j * ca) * p;
      if (x < o.x - 1 || x > o.x + o.w + 1 || y < o.y - 1 || y > o.y + o.h + 1) continue;
      const m = o.mask ? o.mask(x, y) : 1;
      if (m <= 0.001) continue;
      a.push(x, y, 0, o.c || 0);
    }
    const f = pack(a);
    const mk = new Float32Array(f.n);
    for (let i = 0; i < f.n; i++) mk[i] = o.mask ? o.mask(f.x[i], f.y[i]) : 1;
    const rmax = o.rmax || p * 0.6, gam = o.gamma || 1, aspect = img.lh / img.lw;
    f.dyn = (t, r) => {
      const v = o.view ? o.view(t) : { cx: 0.5, cy: 0.5, s: 1 };
      const g = o.gain ? o.gain(t) : 1;
      const sx = v.s / o.w; // uv per px
      for (let i = 0; i < f.n; i++) {
        const u = v.cx + (f.x[i] - cxr) * sx, vv = v.cy + ((f.y[i] - cyr) * sx) / aspect;
        let dk = img.at(u, vv);
        if (gam !== 1) dk = Math.pow(dk, gam);
        const gi = o.sweep ? o.sweep(t, f.x[i], f.y[i]) : g;
        const ho = o.hole ? o.hole(t, f.x[i], f.y[i]) : 1;
        r[i] = rmax * Math.sqrt(dk) * mk[i] * gi * ho;
      }
    };
    return f;
  }

  // ---------- tracks: formations in time, joined by spring morphs ----------
  // pair every dot of A with its nearest in B and every unpaired B dot with
  // its nearest in A: dots assemble into, and disperse out of, clusters.
  function nearest(fx, fy, n, x, y) {
    let best = -1, bd = Infinity;
    for (let k = 0; k < n; k++) { const dx = fx[k] - x, dy = fy[k] - y, d = dx * dx + dy * dy; if (d < bd) { bd = d; best = k; } }
    return best;
  }
  function visible(f, rr, thr) { const ix = []; for (let i = 0; i < f.n; i++) if (rr[i] > thr) ix.push(i); return ix; }
  function pairUp(A, B, rA, rB, mode) {
    const ia = visible(A, rA, 0.35), ib = visible(B, rB, 0.35);
    const pa = [], pb = [];
    if (!ia.length || !ib.length) {
      ia.forEach((i) => { pa.push(i); pb.push(-1); });
      ib.forEach((i) => { pa.push(-1); pb.push(i); });
      return { pa, pb };
    }
    if (mode === "grow") { // dots present in both stay; the rest print in or out in place
      const keyOf = (f, i) => Math.round(f.x[i] * 2) + ":" + Math.round(f.y[i] * 2);
      const am = new Map();
      ia.forEach((i) => am.set(keyOf(A, i), i));
      const used = new Set();
      ib.forEach((i) => {
        const a = am.get(keyOf(B, i));
        if (a != null && !used.has(a)) { used.add(a); pa.push(a); pb.push(i); } else { pa.push(-1); pb.push(i); }
      });
      ia.forEach((i) => { if (!used.has(i)) { pa.push(i); pb.push(-1); } });
      return { pa, pb };
    }
    if (mode === "index") {
      const M = Math.max(ia.length, ib.length);
      for (let k = 0; k < M; k++) { pa.push(ia[Math.floor((k * ia.length) / M)]); pb.push(ib[Math.floor((k * ib.length) / M)]); }
      return { pa, pb };
    }
    if (mode === "sortx") {
      const key = (f) => (i) => f.x[i] * 4 + f.y[i] * 0.01;
      ia.sort((u, v) => key(A)(u) - key(A)(v));
      ib.sort((u, v) => key(B)(u) - key(B)(v));
      const M = Math.max(ia.length, ib.length);
      for (let k = 0; k < M; k++) { pa.push(ia[Math.floor((k * ia.length) / M)]); pb.push(ib[Math.floor((k * ib.length) / M)]); }
      return { pa, pb };
    }
    const bx = Float32Array.from(ib, (i) => B.x[i]), by = Float32Array.from(ib, (i) => B.y[i]);
    const ax = Float32Array.from(ia, (i) => A.x[i]), ay = Float32Array.from(ia, (i) => A.y[i]);
    const hit = new Uint8Array(ib.length);
    ia.forEach((i) => { const k = nearest(bx, by, ib.length, A.x[i], A.y[i]); hit[k] = 1; pa.push(i); pb.push(ib[k]); });
    ib.forEach((i, k) => { if (hit[k]) return; const q = nearest(ax, ay, ia.length, B.x[i], B.y[i]); pa.push(ia[q]); pb.push(i); });
    return { pa, pb };
  }

  // keys: [{t, f (formation or fn(t)->formation), dur, sweep, dir:[dx,dy], jitter, mode, bend, shrink}]
  // The key at t replaces the previous one with a morph that starts at t.
  function track(keys, opts) {
    opts = opts || {};
    keys = keys.slice().sort((a, b) => a.t - b.t);
    const cache = new Map();
    const fAt = (k, t) => (typeof k.f === "function" ? k.f(t) : k.f) || EMPTY;
    function plan(idx) {
      if (cache.has(idx)) return cache.get(idx);
      const K = keys[idx], P = keys[idx - 1];
      const A = fAt(P, K.t), B = fAt(K, K.t);
      const rA = radii(A, K.t), rB = radii(B, K.t + (K.dur || 1));
      const pr = pairUp(A, B, rA, rB, K.mode || "near");
      // stagger: a sweep along dir across the source extent, plus jitter
      const dir = K.dir || [1, 0];
      let lo = Infinity, hi = -Infinity;
      const proj = pr.pa.map((ia, k) => {
        const ib = pr.pb[k];
        const x = ia >= 0 ? A.x[ia] : B.x[ib], y = ia >= 0 ? A.y[ia] : B.y[ib];
        const v = x * dir[0] + y * dir[1];
        if (v < lo) lo = v; if (v > hi) hi = v;
        return v;
      });
      const span = hi - lo || 1;
      const sweep = K.sweep == null ? 0.3 : K.sweep, jit = K.jitter == null ? 0.1 : K.jitter;
      const delay = new Float32Array(proj.length);
      proj.forEach((v, k) => { delay[k] = sweep * ((v - lo) / span) + jit * hash(k, idx * 31 + 7); });
      const pl = { A, B, pa: pr.pa, pb: pr.pb, delay };
      cache.set(idx, pl);
      return pl;
    }
    function emit(t, out) {
      if (opts.clock) t = opts.clock(t);
      let idx = -1;
      for (let i = 0; i < keys.length; i++) if (keys[i].t <= t) idx = i;
      if (idx < 0) return;
      const K = keys[idx];
      const dur = K.dur || 1;
      const settled = idx === 0 || t >= K.t + dur + (K.sweep == null ? 0.3 : K.sweep) + (K.jitter == null ? 0.1 : K.jitter);
      if (settled) {
        const B = fAt(K, t), rB = radii(B, t);
        for (let i = 0; i < B.n; i++) if (rB[i] > 0.15) out.push(B.x[i], B.y[i], rB[i], B.c[i]);
        return;
      }
      const pl = plan(idx);
      const A = pl.A, B = pl.B;
      const rA = radii(A, t), rB = radii(B, t);
      const shrink = K.shrink == null ? 0.35 : K.shrink, bend = K.bend == null ? 0.12 : K.bend;
      for (let k = 0; k < pl.pa.length; k++) {
        const ia = pl.pa[k], ib = pl.pb[k];
        const p = spring((t - K.t - pl.delay[k]) / dur);
        if (ia < 0) { // print in, in place
          const r = rB[ib] * p;
          if (r > 0.15) out.push(B.x[ib], B.y[ib], r, B.c[ib]);
          continue;
        }
        if (ib < 0) { // print out, in place
          const r = rA[ia] * (1 - p);
          if (r > 0.15) out.push(A.x[ia], A.y[ia], r, A.c[ia]);
          continue;
        }
        const x0 = A.x[ia], y0 = A.y[ia], x1 = B.x[ib], y1 = B.y[ib];
        const s = Math.sin(Math.PI * p);
        const bo = bend * s * (hash(k, 911) - 0.5);
        const x = lerp(x0, x1, p) - (y1 - y0) * bo, y = lerp(y0, y1, p) + (x1 - x0) * bo;
        const r = lerp(rA[ia], rB[ib], p) * (1 - shrink * s);
        const c = p < 0.5 ? A.c[ia] : B.c[ib];
        if (r > 0.15) out.push(x, y, r, c);
      }
    }
    return { emit, keys };
  }
  // ---------- travellers: single dots that move along a path ----------
  // path from points, parametrised by arc length
  function path(pts) {
    const acc = [0];
    for (let i = 1; i < pts.length; i++) acc.push(acc[i - 1] + Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]));
    const L = acc[acc.length - 1] || 1;
    function at(u) {
      const d = clamp(u, 0, 1) * L;
      let i = 1;
      while (i < acc.length - 1 && acc[i] < d) i++;
      const seg = acc[i] - acc[i - 1] || 1, k = (d - acc[i - 1]) / seg;
      return [lerp(pts[i - 1][0], pts[i][0], k), lerp(pts[i - 1][1], pts[i][1], k)];
    }
    return { at, L, pts };
  }
  function bez(p0, p1, p2, p3, n) {
    const out = [];
    n = n || 40;
    for (let k = 0; k <= n; k++) {
      const u = k / n, v = 1 - u;
      out.push([v * v * v * p0[0] + 3 * v * v * u * p1[0] + 3 * v * u * u * p2[0] + u * u * u * p3[0],
        v * v * v * p0[1] + 3 * v * v * u * p1[1] + 3 * v * u * u * p2[1] + u * u * u * p3[1]]);
    }
    return out;
  }
  // movers: [{p: path, t0, d, r, c, grow, ease}] each prints in at the start,
  // travels (ease-in-out spring feel), and is gone once it arrives
  function movers(list) {
    return {
      emit(t, out) {
        list.forEach((m) => {
          const u = (t - m.t0) / m.d;
          if (u < 0 || u > 1) return;
          const e = m.ease ? m.ease(u) : u < 0.5 ? 4 * u * u * u : 1 - Math.pow(-2 * u + 2, 3) / 2;
          const [x, y] = m.p.at(e);
          const g = Math.min(1, u / 0.12, (1 - u) / 0.1);
          out.push(x, y, m.r * Math.max(0.2, g), m.c || 0);
        });
      },
    };
  }

  // a formation that is only shown inside [t0, t1), printed in and out
  function show(f, t0, t1, o) {
    o = o || {};
    const kin = { t: t0, f, dur: o.din || 0.5, sweep: o.sin == null ? 0.2 : o.sin, jitter: o.jin == null ? 0.08 : o.jin, dir: o.dir };
    const keys = [{ t: -1, f: EMPTY }, kin];
    if (t1 != null) keys.push({ t: t1, f: EMPTY, dur: o.dout || 0.4, sweep: o.sout == null ? 0.15 : o.sout, jitter: 0.05, dir: o.dir });
    return track(keys);
  }

  // ---------- renderer ----------
  function renderer(canvas, w, h, o) {
    o = o || {};
    canvas.width = w; canvas.height = h;
    canvas.style.width = w + "px"; canvas.style.height = h + "px";
    const ctx = canvas.getContext("2d");
    const buf = [];
    function draw(t, emitters) {
      buf.length = 0;
      emitters.forEach((e) => e.emit(t, buf));
      ctx.globalCompositeOperation = "source-over";
      ctx.fillStyle = C.ground;
      ctx.fillRect(0, 0, w, h);
      const paths = [new Path2D(), new Path2D(), new Path2D(), new Path2D(), new Path2D(), new Path2D()];
      const boost = C.accentBoost || 1;
      for (let i = 0; i < buf.length; i += 4) {
        const x = buf[i], y = buf[i + 1], c = buf[i + 3];
        const r = c === PINK || c === RINGP ? buf[i + 2] * boost : buf[i + 2];
        const pth = paths[c];
        pth.moveTo(x + r, y);
        pth.arc(x, y, r, 0, TAU);
      }
      ctx.fillStyle = C.dotMuted; ctx.fill(paths[MUTED]);
      ctx.fillStyle = C.dot; ctx.fill(paths[INK]);
      ctx.lineWidth = 1.6;
      ctx.strokeStyle = C.dotMuted; ctx.stroke(paths[RINGM]);
      ctx.strokeStyle = C.dot; ctx.stroke(paths[RING]);
      // the accent: the second ink, printed last
      ctx.save();
      ctx.globalCompositeOperation = C.blend || "source-over";
      const mis = C.misreg || [0, 0];
      ctx.translate(mis[0], mis[1]);
      ctx.fillStyle = C.accent; ctx.fill(paths[PINK]);
      ctx.lineWidth = 2; ctx.strokeStyle = C.accent; ctx.stroke(paths[RINGP]);
      ctx.restore();
    }
    return { draw, ctx };
  }

  // ---------- type helpers (HTML) ----------
  function tx(parent, x, y, html, cls, size, extra) {
    const e = document.createElement("div");
    e.className = "tx " + (cls || "");
    e.style.left = x + "px";
    e.style.top = y + "px";
    if (size) e.style.fontSize = size + "px";
    if (extra) Object.assign(e.style, extra);
    e.innerHTML = html;
    parent.appendChild(e);
    // a transform from the first frame, so text antialiasing never changes
    // when a tween later adds one (loops must end on their first frame)
    gsap.set(e, { x: 0, y: 0, force3D: false });
    return e;
  }
  // wrap each word of an element in an inline-block span (for waterfall moves)
  function words(e) {
    const out = [];
    const walk = (node) => {
      [...node.childNodes].forEach((ch) => {
        if (ch.nodeType === 3) {
          const parts = ch.textContent.split(/(\s+)/);
          const frag = document.createDocumentFragment();
          parts.forEach((pt) => {
            if (!pt) return;
            if (/^\s+$/.test(pt)) { frag.appendChild(document.createTextNode(pt)); return; }
            const s = document.createElement("span"); s.className = "w"; s.textContent = pt; frag.appendChild(s); out.push(s);
            gsap.set(s, { x: 0, y: 0, force3D: false });
          });
          node.replaceChild(frag, ch);
        } else if (ch.nodeType === 1 && !ch.classList.contains("w")) {
          if (ch.dataset.whole != null) { ch.classList.add("w"); out.push(ch); } else walk(ch);
        }
      });
    };
    walk(e);
    return out;
  }
  // Seek-safe moves: only `to` tweens and `tl.set` live on the timeline; an
  // element that first appears later is hidden at build with `hide: true`.
  // in: rise from below, waterfall by word (binary opacity at ignition)
  function inWords(tl, ws, t, o) {
    o = o || {};
    const dy = o.dy == null ? 28 : o.dy, d = o.d || 0.42, st = o.st == null ? 0.035 : o.st;
    if (o.hide !== false) gsap.set(ws, { opacity: 0, y: dy });
    ws.forEach((w, k) => {
      const tt = t + Math.min(k * st, 0.45);
      tl.set(w, { opacity: 1, y: dy }, tt);
      tl.to(w, { y: 0, duration: d, ease: "expo.out" }, tt);
    });
  }
  // out: leftward, accelerating, faded early (cut-the-curve exit)
  function outLeft(tl, els, t, o) {
    o = o || {};
    const dx = o.dx || 90, d = o.d || 0.32;
    [].concat(els).forEach((e, k) => {
      const tt = t + k * (o.st == null ? 0.02 : o.st);
      tl.to(e, { x: -dx, duration: d, ease: "power4.in" }, tt);
      tl.to(e, { opacity: 0, duration: d * 0.6, ease: "none" }, tt);
    });
  }
  // in from the right, mid-flight (cut-the-curve entry)
  function inLeft(tl, els, t, o) {
    o = o || {};
    const dx = o.dx || 90, d = o.d || 0.5;
    els = [].concat(els);
    if (o.hide) gsap.set(els, { opacity: 0 });
    els.forEach((e, k) => {
      const tt = t + k * (o.st == null ? 0.03 : o.st);
      tl.set(e, { opacity: 0.35, x: dx }, tt);
      tl.to(e, { x: 0, duration: d, ease: "power4.out" }, tt);
      tl.to(e, { opacity: 1, duration: d * 0.5, ease: "power2.out" }, tt);
    });
  }
  function rise(tl, els, t, o) {
    o = o || {};
    els = [].concat(els);
    const dy = o.dy == null ? 18 : o.dy;
    if (o.hide !== false) gsap.set(els, { opacity: 0, y: dy });
    else tl.set(els, { opacity: 0, y: dy }, t);
    tl.to(els, { opacity: 1, y: 0, duration: o.d || 0.5, ease: "expo.out", stagger: o.st == null ? 0.06 : o.st }, t);
  }
  function fadeOut(tl, els, t, o) {
    o = o || {};
    tl.to([].concat(els), { opacity: 0, duration: o.d || 0.3, ease: "power2.in", stagger: o.st || 0 }, t);
  }
  function fadeIn(tl, els, t, o) {
    o = o || {};
    els = [].concat(els);
    if (o.hide) gsap.set(els, { opacity: 0 });
    tl.to(els, { opacity: 1, duration: o.d || 0.4, ease: "power2.out", stagger: o.st || 0 }, t);
  }
  function fontsReady() {
    const fams = ['450 40px "Triforge Sans"', '520 40px "Triforge Sans"', '600 40px "Triforge Sans"', '650 40px "Triforge Sans"'];
    return Promise.all(fams.map((f) => document.fonts.load(f))).then(() => document.fonts.ready);
  }
  // drive the canvas from the paused timeline: one linear proxy tween, so a
  // seek to any time redraws that time
  function drive(tl, dur, fn) {
    const proxy = { t: 0 };
    fn(0);
    tl.to(proxy, { t: dur, duration: dur, ease: "none", onUpdate: () => fn(proxy.t) }, 0);
  }

  return {
    C, INK, PINK, ACC: PINK, MUTED, RING, RINGM, RINGP, RINGA: RINGP, TAU, clamp, lerp, hash, spring, win, sp,
    pack, EMPTY, join, map, shift, tint, scaleR, disc, block, seg, poly, ringOf, frame, curve, logo, LOGO,
    image, halftone, track, show, renderer, radii, path, bez, movers,
    tx, words, inWords, outLeft, inLeft, rise, fadeOut, fadeIn, fontsReady, drive,
  };
})();
