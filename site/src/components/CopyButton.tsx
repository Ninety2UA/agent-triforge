import { useEffect, useRef, useState } from 'react';
import { InputGroupButton } from '@/components/ui/input-group';
import { Icon } from './Icon';

interface Props {
  /** the exact text that lands on the clipboard */
  text: string;
  /** accessible name before copying */
  label: string;
}

function legacyCopy(text: string) {
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.setAttribute('readonly', '');
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.append(ta);
  ta.select();
  try { document.execCommand('copy'); } catch { /* nothing more to try */ }
  ta.remove();
}

// The copy control: a shadcn InputGroupButton that writes the command to the clipboard, says "Copied"
// for two seconds and announces it in the page's polite live region. Hydrates on first use.
export default function CopyButton({ text, label }: Props) {
  const [done, setDone] = useState(false);
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(timer.current), []);

  const copy = async () => {
    try {
      if (navigator.clipboard && window.isSecureContext) await navigator.clipboard.writeText(text);
      else legacyCopy(text);
    } catch {
      legacyCopy(text);
    }
    setDone(true);
    const live = document.getElementById('live');
    if (live) { live.textContent = ''; window.setTimeout(() => { live.textContent = 'Copied to clipboard'; }, 30); }
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => setDone(false), 2000);
  };

  return (
    <InputGroupButton variant="ghost" size="xs" className="copy" data-done={done ? 'true' : undefined} aria-label={done ? 'Copied to clipboard' : label} onClick={copy}>
      <Icon name={done ? 'check' : 'copy'} />
      <span>{done ? 'Copied' : 'Copy'}</span>
    </InputGroupButton>
  );
}
