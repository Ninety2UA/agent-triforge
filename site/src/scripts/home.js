// The page runtime: theme, section reveals, videos, the film player, the hero dot field, the
// reviewer bench and the sprint stations. Plain script; the shadcn islands are separate.
(function () {
  'use strict';
  var doc = document, root = doc.documentElement;
  var RM = window.matchMedia('(prefers-reduced-motion: reduce)');
  var reduced = function () { return RM.matches; };
  var $ = function (s, c) { return (c || doc).querySelector(s); };
  var $$ = function (s, c) { return Array.prototype.slice.call((c || doc).querySelectorAll(s)); };

  function css(name, el) { return getComputedStyle(el || root).getPropertyValue(name).trim(); }

  /* resolve any CSS colour to rgb() so canvas can use it (oklch included) */
  var probe = doc.createElement('canvas').getContext('2d');
  function rgb(c) {
    var el = doc.createElement('i'); el.style.color = c; el.style.display = 'none'; doc.body.appendChild(el);
    var v = getComputedStyle(el).color; el.remove();
    if (/^oklch|^color\(/.test(v)) { probe.fillStyle = '#000'; probe.fillStyle = v; probe.fillRect(0, 0, 1, 1); var d = probe.getImageData(0, 0, 1, 1).data; return 'rgb(' + d[0] + ',' + d[1] + ',' + d[2] + ')'; }
    return v;
  }
  function rgbLum(c) { var m = c.match(/\d+(\.\d+)?/g) || [0, 0, 0]; return (0.2126 * m[0] + 0.7152 * m[1] + 0.0722 * m[2]) / 255; }

  /* ---------- sprint stations: tabs with roving focus and arrow keys (the shadcn Tabs islands manage their own) ---------- */
  $$('.press [role="tablist"]').forEach(function (list) {
    var tabs = $$('[role="tab"]', list);
    function select(tab, focus) {
      tabs.forEach(function (t) {
        var on = t === tab; t.setAttribute('aria-selected', String(on)); t.setAttribute('data-state', on ? 'active' : 'inactive'); t.tabIndex = on ? 0 : -1;
        var p = doc.getElementById(t.getAttribute('aria-controls')); if (p) { p.hidden = !on; p.setAttribute('data-state', on ? 'active' : 'inactive'); }
      });
      if (focus) tab.focus();
      list.dispatchEvent(new CustomEvent('tabchange', { detail: tab }));
    }
    tabs.forEach(function (t, i) {
      t.addEventListener('click', function () { select(t, false); });
      t.addEventListener('keydown', function (e) {
        var k = e.key, n = null;
        if (k === 'ArrowRight' || k === 'ArrowDown') n = tabs[(i + 1) % tabs.length];
        else if (k === 'ArrowLeft' || k === 'ArrowUp') n = tabs[(i - 1 + tabs.length) % tabs.length];
        else if (k === 'Home') n = tabs[0]; else if (k === 'End') n = tabs[tabs.length - 1];
        if (n) { e.preventDefault(); select(n, true); }
      });
    });
  });

  /* ---------- posters: lazy for the first paint, fetched once the page is idle ---------- */
  (window.requestIdleCallback || function (f) { setTimeout(f, 1200); })(function () { $$('.vid > img[loading="lazy"]').forEach(function (i) { i.loading = 'eager'; }); }, { timeout: 2000 });

  /* ---------- visibility helper ---------- */
  function watch(el, cb, thr) {
    if (!('IntersectionObserver' in window)) { cb(true, 1); return; }
    new IntersectionObserver(function (es) { es.forEach(function (e) { cb(e.isIntersecting && e.intersectionRatio >= (thr || 0), e.intersectionRatio); }); },
      { threshold: [0, thr || 0.01, 0.5, 1] }).observe(el);
  }

  /* ---------- section reveals: animate from a visible default ---------- */
  if (!reduced() && 'IntersectionObserver' in window && Element.prototype.animate) {
    var revealed = new WeakSet();
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) {
        if (!e.isIntersecting || revealed.has(e.target)) return;
        revealed.add(e.target); io.unobserve(e.target);
        if (e.boundingClientRect.top < innerHeight * 0.6) return;
        $$('[data-rv]', e.target).concat(e.target.hasAttribute('data-rv') ? [e.target] : []).forEach(function (el, i) {
          el.animate([{ opacity: 0, transform: 'translateY(' + (el.getAttribute('data-rv') || 24) + 'px)' }, { opacity: 1, transform: 'none' }],
            { duration: 760, delay: Math.min(i, 6) * 80, easing: 'cubic-bezier(0.16, 1, 0.3, 1)', fill: 'backwards' });
        });
      });
    }, { rootMargin: '0px 0px -6% 0px' });
    $$('[data-rv-group]').forEach(function (g) { io.observe(g); });
  }

  /* ---------- videos: play at half visible, pause off screen, never under reduced motion ---------- */
  $$('.vid[data-video]').forEach(function (box) {
    var fig = box.closest('figure'), v = $('video', box), btn = fig ? $('.vplay', fig) : null, want = !reduced(), userPaused = false, inView = false;
    if (btn) btn.hidden = false;
    if (!v) return;
    var sync = function () { box.setAttribute('data-playing', String(!v.paused)); if (fig) fig.setAttribute('data-playing', String(!v.paused)); if (btn) btn.setAttribute('aria-label', (v.paused ? 'Play ' : 'Pause ') + box.getAttribute('data-name')); };
    v.addEventListener('play', sync); v.addEventListener('pause', sync); v.addEventListener('playing', function () { box.setAttribute('data-started', 'true'); });
    var tryPlay = function () { var p = v.play(); if (p && p.catch) p.catch(function () {}); };
    if (btn) btn.addEventListener('click', function () { if (v.paused) { userPaused = false; tryPlay(); } else { userPaused = true; v.pause(); } });
    if (box.hasAttribute('data-film')) return;
    watch(box, function (on) { inView = on; if (on && want && !userPaused) tryPlay(); else if (!on && !v.paused) v.pause(); }, 0.5);
    sync();
  });

  /* ---------- film player: chapters, dot progress, play/pause ---------- */
  $$('.film').forEach(function (film) {
    var box = $('.vid', film), v = $('video', box), chs = JSON.parse(film.getAttribute('data-chapters') || '[]');
    var btns = $$('.chapters button', film), toggle = $('.film-toggle', film), time = $('.film-time', film), dots = $('.film-dots', film);
    var dur = parseFloat(film.getAttribute('data-duration')) || 50, N = 0, circles = [], userPaused = false, ended = false;
    function fmt(s) { s = Math.max(0, Math.floor(s)); return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }
    function build() {
      if (!dots) return;
      var w = dots.clientWidth || 600; N = Math.max(20, Math.min(90, Math.round(w / 12)));
      var svg = '<svg viewBox="0 0 ' + w + ' 22" aria-hidden="true">';
      for (var i = 0; i < N; i++) { var x = 6 + i * (w - 12) / (N - 1); svg += '<circle cx="' + x.toFixed(1) + '" cy="11" r="3" class="u"/>'; }
      dots.innerHTML = svg + '</svg>'; circles = $$('circle', dots); paint();
    }
    function paint() {
      var t = v.currentTime || 0, d = v.duration || dur, k = Math.round(t / d * (N - 1));
      for (var i = 0; i < circles.length; i++) {
        var c = circles[i], cls = i < k ? 'f' : (i === k ? 'c' : 'u');
        if (c.getAttribute('class') !== cls) { c.setAttribute('class', cls); c.setAttribute('r', cls === 'c' ? 6 : (cls === 'f' ? 4 : 3)); }
      }
      var cur = 0; for (var j = 0; j < chs.length; j++) if (t >= chs[j].start - 0.05) cur = j;
      btns.forEach(function (b, i) { if (i === cur) b.setAttribute('aria-current', 'true'); else b.removeAttribute('aria-current'); });
      if (time) time.textContent = fmt(t) + ' / ' + fmt(d);
      if (dots) dots.setAttribute('aria-valuenow', Math.round(t)), dots.setAttribute('aria-valuetext', fmt(t) + ' of ' + fmt(d) + ', ' + (chs[cur] ? chs[cur].label : ''));
    }
    function play() { ended = false; var p = v.play(); if (p && p.catch) p.catch(function () {}); }
    function seek(s) { v.currentTime = Math.max(0, Math.min((v.duration || dur) - 0.1, s)); paint(); }
    var sync = function () { film.setAttribute('data-playing', String(!v.paused)); box.setAttribute('data-playing', String(!v.paused)); if (toggle) toggle.setAttribute('aria-label', v.paused ? 'Play the film' : 'Pause the film'); };
    v.addEventListener('play', sync); v.addEventListener('pause', sync); v.addEventListener('timeupdate', paint);
    v.addEventListener('playing', function () { box.setAttribute('data-started', 'true'); });
    v.addEventListener('loadedmetadata', function () { paint(); });
    v.addEventListener('ended', function () { ended = true; sync(); });
    if (toggle) toggle.addEventListener('click', function () { if (v.paused) { userPaused = false; if (ended) seek(0); play(); } else { userPaused = true; v.pause(); } });
    btns.forEach(function (b, i) { b.addEventListener('click', function () { if (v.preload === 'none') v.preload = 'metadata'; seek(chs[i].start + 0.01); userPaused = false; play(); }); });
    if (dots) {
      var scrub = function (e) { var r = dots.getBoundingClientRect(); seek((e.clientX - r.left) / r.width * (v.duration || dur)); };
      dots.addEventListener('pointerdown', function (e) { scrub(e); dots.setPointerCapture(e.pointerId); });
      dots.addEventListener('pointermove', function (e) { if (dots.hasPointerCapture && dots.hasPointerCapture(e.pointerId)) scrub(e); });
      dots.addEventListener('keydown', function (e) {
        if (e.key === 'ArrowRight') { e.preventDefault(); seek(v.currentTime + 5); } else if (e.key === 'ArrowLeft') { e.preventDefault(); seek(v.currentTime - 5); }
        else if (e.key === ' ' || e.key === 'Enter') { e.preventDefault(); toggle.click(); }
      });
    }
    $$('[data-seek-film]').forEach(function (b) {
      b.addEventListener('click', function () { seek(parseFloat(b.getAttribute('data-seek-film')) + 0.01); userPaused = false; play(); film.scrollIntoView({ behavior: reduced() ? 'auto' : 'smooth', block: 'center' }); });
    });
    build(); window.addEventListener('resize', function () { clearTimeout(film._r); film._r = setTimeout(build, 150); });
    // a hero film waits for the page to settle (poster first, then the press starts) before it streams
    var ready = false, inView = false;
    var auto = function () { if (ready && inView && !reduced() && !userPaused && !ended && v.currentTime < (v.duration || dur) - 0.2) play(); };
    var arm = function () { setTimeout(function () { ready = true; auto(); }, film.hasAttribute('data-hero') ? 3000 : 0); };
    if (doc.readyState === 'complete') arm(); else window.addEventListener('load', arm);
    watch(box, function (on) { inView = on; if (on) auto(); else if (!v.paused) v.pause(); }, 0.5);
    sync();
  });

  /* ---------- critically damped spring: no overshoot ---------- */
  function spring(p, target, w, dt) {
    var d = p.x - target, c2 = p.v + w * d, e = Math.exp(-w * dt);
    p.x = target + (d + c2 * dt) * e; p.v = (c2 - w * (d + c2 * dt)) * e;
  }

  /* ---------- hero dot field: CLIs as clusters, one lease at a time ---------- */
  var field = $('.field[data-layouts]');
  if (field) (function () {
    var cv = $('canvas', field), ctx = cv.getContext('2d'), L = JSON.parse(field.getAttribute('data-layouts'));
    var cap = $('.field-cap p'), pauseBtn = $('.field-pause'), mq = window.matchMedia('(max-width: 760px)');
    var lay, dots, W, H, s, dpr, col = {}, t0 = performance.now(), last = t0, running = false, visible = true, paused = false, frame = 0;
    var CAPS = JSON.parse(field.getAttribute('data-captions'));
    // rest: a cluster at rest; active: the CLI at work, the integration line, merged tasks;
    // opt: optional members; fg: a task in progress; quiet: cells and a refused review
    function colors() {
      col.rest = rgb(css('--dot-rest')); col.active = rgb(css('--dot-active')); col.opt = rgb(css('--dot-opt'));
      col.fg = rgb(css('--foreground')); col.quiet = rgb(css('--muted-foreground')); col.screen = rgb(css('--dot-screen'));
      // a second ink prints a hair off register; with one ink there is nothing to misregister
      col.reg = col.active !== col.fg ? 0.5 : 0;
    }
    function rnd(seed) { var x = Math.sin(seed * 9301 + 49297) * 233280; return x - Math.floor(x); }
    function setup() {
      lay = mq.matches ? L.m : (field.hasAttribute('data-wide') && L.w ? L.w : L.d); field.style.aspectRatio = lay.cols + ' / ' + lay.rows;
      var r = field.getBoundingClientRect(); dpr = Math.min(2, window.devicePixelRatio || 1);
      W = r.width; H = r.height; cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr); s = W / lay.cols;
      dots = [];
      lay.clusters.forEach(function (c, ci) {
        c.dots.forEach(function (o, k) {
          var hx = c.x + o[0], hy = c.y + o[1], seed = ci * 97 + k * 13 + 1;
          var dist = Math.sqrt(o[0] * o[0] + o[1] * o[1]), rr = c.opt ? 0.31 - dist * 0.04 : 0.45 - dist * 0.055;
          dots.push({ c: ci, k: k, hx: hx, hy: hy, px: { x: hx, v: 0 }, py: { x: hy, v: 0 }, sx: Math.floor(rnd(seed) * lay.cols), sy: Math.floor(rnd(seed + 7) * lay.rows), opt: !!c.opt, rr: rr });
        });
      });
    }
    // the story (seconds), one caption per step, in the film's order: goal, split, build, review,
    // merge, then a self-review that is refused and a review by a different agent
    var T = 21, MARKS = [1.6, 3.4, 5.0, 6.6, 8.4, 10.2, 11.8, 13.6, 15.4];
    function stateAt(t) {
      var st = { scatter: t < 0.4 || t > 19.6, builder: -1, reviewer: -1, cap: 0, tasks: [], cells: t >= 3.4, goal: t >= 1.6 && t < 3.4, refusedAt: 12.6 };
      var a = lay.tasks[0], b = lay.tasks[1];
      for (var i = 0; i < MARKS.length; i++) if (t >= MARKS[i]) st.cap = i + 1;
      if (t > 19.6) st.cap = 0;
      if (st.goal) st.builder = 0;
      if ((t >= 5.0 && t < 6.6) || (t >= 10.2 && t < 11.8)) st.builder = 0;
      st.tasks.push({ id: 0, x: t < 5.0 ? a.from[0] : (t < 8.4 ? a.cell[0] : a.line[0]), y: t < 5.0 ? a.from[1] : (t < 8.4 ? a.cell[1] : a.line[1]),
        on: t >= 3.4, big: t >= 5.6, pink: t >= 8.6, rev: t >= 6.6 && t < 8.2 ? 2 : -1, self: false });
      st.tasks.push({ id: 1, x: t < 10.2 ? b.from[0] + 1.6 : (t < 15.4 ? b.cell[0] : b.line[0]), y: t < 10.2 ? b.from[1] : (t < 15.4 ? b.cell[1] : b.line[1]),
        on: t >= 3.4, big: t >= 10.8, pink: t >= 15.6, rev: t >= 11.8 && t < 13.4 ? 0 : (t >= 13.6 && t < 15.2 ? 2 : -1), self: t >= 11.8 && t < 13.4 });
      if ((t >= 6.6 && t < 8.2) || (t >= 13.6 && t < 15.2)) st.reviewer = 2;
      if (t >= 11.8 && t < 13.4) st.reviewer = 0;
      return st;
    }
    function draw(now) {
      var dt = Math.min(0.05, (now - last) / 1000); last = now;
      var t = reduced() ? 17.5 : ((now - t0) / 1000) % T, st = stateAt(t);
      if (reduced()) { dt = 10; }
      field.setAttribute('data-scatter', String(st.scatter));
      if (cap && cap._i !== st.cap) { cap._i = st.cap; cap.textContent = CAPS[st.cap]; }
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0); ctx.clearRect(0, 0, W, H);
      // the paper's dot screen
      ctx.fillStyle = col.screen; ctx.beginPath();
      for (var gx = 0; gx <= lay.cols; gx++) for (var gy = 0; gy <= lay.rows; gy++) { ctx.moveTo((gx + 0.5) * s + s * 0.06, (gy + 0.5) * s); ctx.arc((gx + 0.5) * s, (gy + 0.5) * s, s * 0.06, 0, 6.2832); }
      ctx.fill();
      // integration line: small pink dots along it, merged tasks become full pink dots
      var ln = lay.line, rest = [], opt = [], fg = [], pink = [], mute = [];
      for (var lx = ln.x0; lx <= ln.x1; lx++) pink.push([lx, ln.y, 0.15]);
      // reviewers send four dots to touch the task's cell
      dots.forEach(function (d) {
        var tx = d.hx, ty = d.hy, w = 9;
        if (st.scatter) { tx = d.sx; ty = d.sy; w = 4.5; }
        var tsk = null; st.tasks.forEach(function (k) { if (k.rev === d.c && d.k < 4 && k.on) tsk = k; });
        if (tsk && !st.scatter) {
          var cell = lay.tasks[tsk.id].cell, side = d.c === 0 ? -1 : 1, off = lay.touch[d.k];
          if (tsk.self) { tx = cell[0] + side * (4 + off[0]); ty = cell[1] + off[1]; }
          else { tx = cell[0] + side * (1 + off[0]); ty = cell[1] + off[1]; }
          w = 7;
        }
        var delay = st.scatter ? 0 : 0;
        spring(d.px, tx, w, dt); spring(d.py, ty, w, dt);
        var isPink = !st.scatter && (d.c === st.builder || d.c === st.reviewer) && !(tsk && tsk.self && d.c === 0 && t > st.refusedAt);
        // each cluster prints as a halftone disc: full dots at the centre, smaller to the edge;
        // the CLI at work prints a little heavier, so it reads even with one ink
        var rr = isPink ? d.rr * 1.14 : d.rr;
        (isPink ? pink : (tsk && tsk.self && t > st.refusedAt ? mute : (d.opt ? opt : rest))).push([d.px.x, d.py.x, rr]);
      });
      // cells: a square outline of small dots
      lay.tasks.forEach(function (k, i) {
        var on = st.cells && !st.scatter;
        if (!on) return;
        for (var cx = -3; cx <= 3; cx++) for (var cy = -3; cy <= 3; cy++) if (Math.abs(cx) === 3 || Math.abs(cy) === 3) mute.push([k.cell[0] + cx, k.cell[1] + cy, 0.11]);
      });
      // the goal: one dot that drops onto the lead's cluster, then splits into the tasks
      // (it lands beside the cluster in ink, so it reads against the highlighted lead)
      var lc = lay.clusters[0], gx = lc.x + 3.6, g = field.goal || (field.goal = { x: { x: gx, v: 0 }, y: { x: -3, v: 0 } });
      if (st.goal && !st.scatter) { spring(g.x, gx, 6, dt); spring(g.y, lc.y, 6, dt); fg.push([g.x.x, g.y.x, 0.8]); }
      else { g.x.x = gx; g.x.v = 0; g.y.x = -3; g.y.v = 0; }
      // task dots
      st.tasks.forEach(function (k) {
        if (!k.on) return;
        var p = k._p || (k._p = {}); var key = 'tk' + k.id; var o = field[key] || (field[key] = { x: { x: k.x, v: 0 }, y: { x: k.y, v: 0 } });
        if (st.scatter) { o.x.x = lay.tasks[k.id].from[0]; o.y.x = lay.tasks[k.id].from[1]; return; }
        spring(o.x, k.x, 6, dt); spring(o.y, k.y, 6, dt);
        (k.pink ? pink : fg).push([o.x.x, o.y.x, k.big ? 0.6 : 0.4]);
      });
      if (st.scatter) { field.tk0 = null; field.tk1 = null; }
      function batch(list, color, dx, dy) {
        ctx.fillStyle = color; ctx.beginPath();
        list.forEach(function (p) { var x = (p[0] + 0.5) * s + dx, y = (p[1] + 0.5) * s + dy, r = p[2] * s; ctx.moveTo(x + r, y); ctx.arc(x, y, r, 0, 6.2832); });
        ctx.fill();
      }
      batch(mute, col.quiet, 0, 0); batch(opt, col.opt, 0, 0); batch(rest, col.rest, 0, 0); batch(fg, col.fg, 0, 0);
      batch(pink, col.active, col.reg, -col.reg * 0.7);
      frame++;
    }
    function loop(now) {
      if (!running) return;
      draw(now);
      if (reduced()) { running = false; return; }
      requestAnimationFrame(loop);
    }
    function start() { if (running || paused || !visible) return; running = true; last = performance.now(); requestAnimationFrame(loop); }
    function stop() { running = false; }
    colors(); setup(); field.setAttribute('data-live', 'true');
    if (reduced()) { draw(performance.now()); }
    watch(field, function (on) { visible = on; if (on) start(); else stop(); }, 0.05);
    if (pauseBtn) {
      pauseBtn.hidden = reduced();
      pauseBtn.addEventListener('click', function () {
        paused = !paused; field.setAttribute('data-paused', String(paused));
        pauseBtn.setAttribute('aria-label', paused ? 'Play the dot field' : 'Pause the dot field');
        if (paused) stop(); else { t0 = performance.now() - ((last - t0) % (T * 1000)); start(); }
      });
    }
    var rs = function () { setup(); if (!running) draw(performance.now()); };
    window.addEventListener('resize', function () { clearTimeout(field._r); field._r = setTimeout(rs, 120); });
    doc.addEventListener('themechange', function () { colors(); if (!running) draw(performance.now()); });
    RM.addEventListener && RM.addEventListener('change', function () { t0 = performance.now(); if (reduced()) { stop(); draw(performance.now()); } else start(); });
  })();

  /* ---------- one task's life: pick a reviewer, run the task (plain words, no code) ---------- */
  var bench = $('#bench');
  if (bench) (function () {
    var steps = $$('.track li', bench), tok = $('.tok', bench), out = $('#verdict'), runBtn = $('#bench-run');
    var timer = [], started = false;
    var NAMES = { codex: 'Codex', antigravity: 'Antigravity' };
    function conf() {
      var r = $('input[name="rev"]:checked', bench).value, prot = $('#prot', bench).checked;
      return { rev: r, self: r === 'claude', prot: prot && r !== 'claude' };
    }
    function setStep(i, state) { if (steps[i]) steps[i].setAttribute('data-state', state); }
    function moveTok(i, active, stop) {
      if (!tok || !steps[i]) return;
      var tr = bench.querySelector('.track').getBoundingClientRect(), r = steps[i].getBoundingClientRect();
      tok.style.transform = 'translateX(' + (r.left - tr.left + r.width / 2 - 14) + 'px)'; tok.setAttribute('data-on', 'true');
      tok.setAttribute('data-pink', String(!!active)); tok.setAttribute('data-stop', String(!!stop));
    }
    function texts(c) {
      $$('[data-when]', bench).forEach(function (el) {
        var w = el.getAttribute('data-when'), on;
        if (w === 'self') on = c.self;
        else if (w === 'prot') on = c.prot;
        else if (w === 'plain') on = !c.self && !c.prot;
        else on = !c.self && !c.prot && w === 'rev-' + c.rev;
        el.hidden = !on;
      });
    }
    function run() {
      timer.forEach(clearTimeout); timer = [];
      var c = conf(), fast = reduced(), gap = fast ? 0 : 900;
      texts(c);
      steps.forEach(function (st) { st.setAttribute('data-state', 'todo'); });
      if (tok) tok.style.transition = fast ? 'none' : 'transform 700ms cubic-bezier(0.16, 1, 0.3, 1), background-color 200ms';
      var seq = [
        function () { setStep(0, 'active'); moveTok(0); },
        function () { setStep(0, 'done'); setStep(1, 'active'); moveTok(1); },
        function () { setStep(1, 'done'); setStep(2, c.self ? 'stop' : 'active'); moveTok(2, false, c.self); }
      ];
      if (c.self) {
        seq.push(function () { setStep(3, 'off'); setStep(4, 'off'); out.textContent = 'Refused. Claude Code built task 1, so it can\'t review it. Pick an agent that didn\'t write it and the task goes on.'; });
      } else {
        seq.push(function () { setStep(2, 'done'); setStep(3, 'active'); moveTok(3, true); });
        seq.push(function () { setStep(3, 'done'); setStep(4, c.prot ? 'stop' : 'active'); moveTok(4, true, c.prot); });
        seq.push(function () {
          if (c.prot) out.textContent = 'Waits for you. Task 1 changes a protected file, so you review it, and only you can approve moving it to main.';
          else { setStep(4, 'done'); out.textContent = 'Merged and on main. ' + NAMES[c.rev] + ' reviewed what Claude Code built, and the lead merged it.'; }
        });
      }
      seq.forEach(function (f, i) { if (fast) f(); else timer.push(setTimeout(f, i * gap)); });
    }
    $$('input', bench).forEach(function (i) { i.addEventListener('change', run); });
    if (runBtn) runBtn.addEventListener('click', run);
    watch(bench, function (on) { if (on && !started) { started = true; run(); } }, 0.3);
    window.addEventListener('resize', function () { var a = steps.filter(function (st) { var v = st.getAttribute('data-state'); return v === 'active' || v === 'stop'; }); if (a.length) moveTok(steps.indexOf(a[a.length - 1]), tok && tok.getAttribute('data-pink') === 'true', tok && tok.getAttribute('data-stop') === 'true'); });
  })();
})();
