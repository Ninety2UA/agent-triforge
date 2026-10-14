// The home page's own behaviour, loaded on the home page only: the dot field, the section reveals and
// the reviewer bench. Everything here works from a visible default; without JavaScript or under
// reduced motion each section is simply there.
import { initDotField } from './dotfield';

const doc = document;
const reduced = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const $$ = <T extends Element = HTMLElement>(sel: string, root: ParentNode = doc) => [...root.querySelectorAll<T>(sel)];

const watch = (el: Element, cb: (on: boolean) => void, threshold: number) =>
  new IntersectionObserver((es) => es.forEach((e) => cb(e.isIntersecting && e.intersectionRatio >= threshold)), { threshold: [0, threshold] }).observe(el);

// Section reveals: a section's parts rise into place once, as it first enters from below. Sections
// already on screen at load are left alone, so nothing above the fold moves.
function initReveals() {
  if (reduced() || !('IntersectionObserver' in window) || !Element.prototype.animate) return;
  const seen = new WeakSet<Element>();
  const io = new IntersectionObserver(
    (es) => {
      es.forEach((e) => {
        if (!e.isIntersecting || seen.has(e.target)) return;
        seen.add(e.target);
        io.unobserve(e.target);
        if (e.boundingClientRect.top < window.innerHeight * 0.6) return;
        const parts = $$('[data-rv]', e.target).concat(e.target.hasAttribute('data-rv') ? [e.target as HTMLElement] : []);
        parts.forEach((el, i) => {
          el.animate([{ opacity: 0, transform: 'translateY(24px)' }, { opacity: 1, transform: 'none' }], {
            duration: 760,
            delay: Math.min(i, 6) * 80,
            easing: 'cubic-bezier(0.16, 1, 0.3, 1)',
            fill: 'backwards',
          });
        });
      });
    },
    { rootMargin: '0px 0px -6% 0px' },
  );
  $$('[data-rv-group]').forEach((g) => io.observe(g));
}

// One task's life: pick who reviews task 1 (and whether it touches a protected file), then watch it
// go through, wait for you, or get refused. Plain words, no code.
function initBench() {
  const bench = doc.getElementById('bench');
  if (!bench) return;
  const steps = $$('.track li', bench);
  const tok = bench.querySelector<HTMLElement>('.tok');
  const out = doc.getElementById('verdict');
  const track = bench.querySelector<HTMLElement>('.track');
  const NAMES: Record<string, string> = { codex: 'Codex', antigravity: 'Antigravity' };
  let timers: number[] = [];
  let started = false;

  const conf = () => {
    const rev = bench.querySelector<HTMLInputElement>('input[name="rev"]:checked')?.value ?? 'codex';
    const prot = bench.querySelector<HTMLInputElement>('#prot')?.checked ?? false;
    return { rev, self: rev === 'claude', prot: prot && rev !== 'claude' };
  };
  const setStep = (i: number, state: string) => steps[i]?.setAttribute('data-state', state);
  const moveTok = (i: number, active = false, stop = false) => {
    if (!tok || !track || !steps[i]) return;
    const tr = track.getBoundingClientRect();
    const r = steps[i].getBoundingClientRect();
    tok.style.transform = `translateX(${r.left - tr.left + r.width / 2 - 14}px)`;
    tok.dataset.on = 'true';
    tok.dataset.pink = String(active);
    tok.dataset.stop = String(stop);
  };
  const texts = (c: ReturnType<typeof conf>) => {
    $$('[data-when]', bench).forEach((el) => {
      const w = el.dataset.when;
      el.hidden = !(w === 'self' ? c.self : w === 'prot' ? c.prot : w === 'plain' ? !c.self && !c.prot : !c.self && !c.prot && w === `rev-${c.rev}`);
    });
  };
  const run = () => {
    timers.forEach(clearTimeout);
    timers = [];
    const c = conf();
    const fast = reduced();
    texts(c);
    steps.forEach((st) => st.setAttribute('data-state', 'todo'));
    if (tok) tok.style.transition = fast ? 'none' : 'transform 700ms cubic-bezier(0.16, 1, 0.3, 1), background-color 200ms';
    const say = (text: string) => {
      if (out) out.textContent = text;
    };
    const seq: (() => void)[] = [
      () => { setStep(0, 'active'); moveTok(0); },
      () => { setStep(0, 'done'); setStep(1, 'active'); moveTok(1); },
      () => { setStep(1, 'done'); setStep(2, c.self ? 'stop' : 'active'); moveTok(2, false, c.self); },
    ];
    if (c.self) {
      seq.push(() => {
        setStep(3, 'off');
        setStep(4, 'off');
        say("Refused. Claude Code built task 1, so it can't review it. Pick an agent that didn't write it and the task goes on.");
      });
    } else {
      seq.push(() => { setStep(2, 'done'); setStep(3, 'active'); moveTok(3, true); });
      seq.push(() => { setStep(3, 'done'); setStep(4, c.prot ? 'stop' : 'active'); moveTok(4, true, c.prot); });
      seq.push(() => {
        if (c.prot) say('Waits for you. Task 1 changes a protected file, so you review it, and only you can approve moving it to main.');
        else {
          setStep(4, 'done');
          say(`Merged and on main. ${NAMES[c.rev]} reviewed what Claude Code built, and the lead merged it.`);
        }
      });
    }
    seq.forEach((f, i) => (fast ? f() : timers.push(window.setTimeout(f, i * 900))));
  };
  $$('input', bench).forEach((i) => i.addEventListener('change', run));
  doc.getElementById('bench-run')?.addEventListener('click', run);
  watch(bench, (on) => {
    if (on && !started) {
      started = true;
      run();
    }
  }, 0.3);
  let resize = 0;
  window.addEventListener('resize', () => {
    clearTimeout(resize);
    resize = window.setTimeout(() => {
      const live = steps.filter((st) => ['active', 'stop'].includes(st.dataset.state ?? ''));
      if (live.length) moveTok(steps.indexOf(live[live.length - 1]), tok?.dataset.pink === 'true', tok?.dataset.stop === 'true');
    }, 120);
  });
}

initDotField();
initReveals();
initBench();
