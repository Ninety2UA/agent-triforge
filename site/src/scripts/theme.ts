// Light and dark theme. THEME_INIT runs inline in <head> before first paint, so a page never
// flashes the other theme: a stored choice wins, else the system preference. initThemeToggle wires
// every [data-theme-toggle] button to switch and store the choice. Storage can throw (some private
// modes, blocked site data); then the choice lasts for this page only.
export const THEME_KEY = 'triforge-theme';

export const THEME_INIT =
  "(()=>{let t;try{t=localStorage.getItem('" + THEME_KEY + "')}catch(e){}" +
  "if(t!=='dark'&&t!=='light')t=matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';" +
  'document.documentElement.dataset.theme=t})()';

export function initThemeToggle(doc: Document = document) {
  const root = doc.documentElement;
  const buttons = doc.querySelectorAll<HTMLButtonElement>('[data-theme-toggle]');
  const sync = () => buttons.forEach((b) => b.setAttribute('aria-pressed', String(root.dataset.theme === 'dark')));
  sync();
  buttons.forEach((b) =>
    b.addEventListener('click', () => {
      const theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
      root.dataset.theme = theme;
      sync();
      try {
        localStorage.setItem(THEME_KEY, theme);
      } catch {
        /* storage unavailable: the choice lasts for this page only */
      }
      // the dot field and anything else drawn from tokens re-reads its colours
      doc.dispatchEvent(new CustomEvent('themechange'));
    }),
  );
}
