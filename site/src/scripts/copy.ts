// Copy buttons (CodeBlock.astro): plain script, so the clipboard write happens inside the real tap
// (Safari allows it only in a trusted gesture, which a click replayed after hydration is not).
// It tries the async clipboard, then the legacy copy command, and checks both results. When neither
// copies, the button says so, the command is selected, and the live region tells the reader to press
// ⌘C (Ctrl+C off a Mac). "Copied" or "Copy failed" shows for two seconds.

async function write(text: string, doc: Document, win: Window): Promise<boolean> {
  try {
    if (win.navigator.clipboard?.writeText) {
      await win.navigator.clipboard.writeText(text);
      return true;
    }
  } catch {
    /* refused or not a secure context: try the legacy command */
  }
  const ta = doc.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  doc.body.append(ta);
  ta.select();
  let ok = false;
  try {
    ok = doc.execCommand('copy');
  } catch {
    ok = false;
  }
  ta.remove();
  return ok;
}

export function initCopy(doc: Document = document, win: Window = window) {
  const timers = new WeakMap<HTMLElement, number>();
  const mac = /Mac|iPhone|iPad|iPod/.test(win.navigator.platform || win.navigator.userAgent || '');

  doc.addEventListener('click', async (event) => {
    const btn = (event.target as Element | null)?.closest<HTMLButtonElement>('.copy[data-copy]');
    if (!btn) return;
    const ok = await write(btn.dataset.copy ?? '', doc, win);
    const label = btn.querySelector('.copy-label');
    const live = doc.getElementById('live');
    btn.dataset.done = ok ? 'true' : 'false';
    if (label) label.textContent = ok ? 'Copied' : 'Copy failed';
    if (!ok) {
      // select the command so the reader can copy it by hand
      const code = btn.closest('[data-cmd]')?.querySelector('code');
      const sel = win.getSelection?.();
      if (code && sel) {
        const range = doc.createRange();
        range.selectNodeContents(code);
        sel.removeAllRanges();
        sel.addRange(range);
      }
    }
    if (live) live.textContent = ok ? 'Copied to the clipboard' : `Copy failed. The command is selected. Press ${mac ? '⌘C' : 'Ctrl+C'} to copy it.`;
    win.clearTimeout(timers.get(btn));
    timers.set(
      btn,
      win.setTimeout(() => {
        delete btn.dataset.done;
        if (label) label.textContent = 'Copy';
      }, 2000),
    );
  });
}
