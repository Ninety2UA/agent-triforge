// Tabs (Tabs.astro): WAI-ARIA tabs as plain script, so they work on page load and from a link,
// before any island hydrates. Every panel is in the static HTML; a link to a panel's id, or to
// anything inside a panel, opens that tab (browsers do not scroll to a target inside a hidden panel).
// Lead tabs (data-lead="claude-code" or "codex") share one choice across the page and across pages:
// picking a lead stores it, selects it in every lead tab group and points every [data-lead-href]
// link (the Install buttons) at that lead's install tab. Storage may throw; then the choice holds
// for this page only.
import { isLead, type Lead } from '@/data/leads.mjs';

export const LEAD_KEY = 'triforge-lead';

/** the lead a reader chose on an earlier page, or null (none stored, or storage refused) */
export const storedLead = (win: Window = window): Lead | null => {
  try {
    const lead = win.localStorage.getItem(LEAD_KEY);
    return isLead(lead) ? lead : null;
  } catch {
    return null;
  }
};

export function initTabs(doc: Document = document, win: Window = window) {
  const groups = [...doc.querySelectorAll<HTMLElement>('[data-tabs]')].map((root) => {
    const tabs = [...root.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
    const panelOf = (t: HTMLElement) => doc.getElementById(t.getAttribute('aria-controls') ?? '');
    const select = (tab: HTMLButtonElement, focus = false) => {
      tabs.forEach((t) => {
        const on = t === tab;
        t.setAttribute('aria-selected', String(on));
        t.setAttribute('tabindex', on ? '0' : '-1');
        if (on) t.setAttribute('data-active', '');
        else t.removeAttribute('data-active');
        const p = panelOf(t);
        if (p) p.hidden = !on;
      });
      if (focus) tab.focus();
    };
    return { root, tabs, panelOf, select };
  });

  const pointInstallLinks = (lead: Lead) =>
    doc.querySelectorAll<HTMLAnchorElement>('[data-lead-href]').forEach((a) => a.setAttribute('href', `${a.dataset.leadHref}#${lead}`));
  const applyLead = (lead: string | undefined, except?: HTMLElement) => {
    if (!isLead(lead)) return;
    groups.forEach((g) => {
      if (g.root === except) return;
      const tab = g.tabs.find((t) => t.dataset.lead === lead);
      if (tab) g.select(tab);
    });
    pointInstallLinks(lead);
  };

  // The panel holding the hash target: the panel itself, or a panel that contains it.
  const fromHash = () => {
    let id = '';
    try {
      id = decodeURIComponent(win.location.hash.slice(1));
    } catch {
      return false; // a malformed escape names no panel
    }
    const target = id ? doc.getElementById(id) : null;
    if (!target) return false;
    let opened = false;
    groups.forEach((g) => {
      const tab = g.tabs.find((t) => {
        const p = g.panelOf(t);
        return p !== null && (p === target || p.contains(target));
      });
      if (tab) {
        g.select(tab);
        opened = true;
      }
    });
    if (opened) target.scrollIntoView?.({ block: 'start' });
    return opened;
  };

  groups.forEach((g) => {
    g.tabs.forEach((t, i) => {
      t.addEventListener('click', () => {
        g.select(t);
        const lead = t.dataset.lead;
        if (!lead) return;
        try {
          win.localStorage.setItem(LEAD_KEY, lead);
        } catch {
          /* storage unavailable: the choice holds for this page only */
        }
        applyLead(lead, g.root);
      });
      t.addEventListener('keydown', (e) => {
        const last = g.tabs.length - 1;
        const next =
          e.key === 'ArrowRight' || e.key === 'ArrowDown' ? (i + 1) % g.tabs.length
          : e.key === 'ArrowLeft' || e.key === 'ArrowUp' ? (i - 1 + g.tabs.length) % g.tabs.length
          : e.key === 'Home' ? 0
          : e.key === 'End' ? last
          : null;
        if (next === null) return;
        e.preventDefault();
        // moving selects, as a click would, so a lead chosen by keyboard is stored too
        g.tabs[next].click();
        g.tabs[next].focus();
      });
    });
  });

  // a link into a tab wins over the stored lead; the stored lead still sets the Install links
  const lead = storedLead(win);
  const hashed = fromHash();
  if (lead) {
    if (hashed) pointInstallLinks(lead);
    else applyLead(lead);
  }
  win.addEventListener('hashchange', () => void fromHash());
}
