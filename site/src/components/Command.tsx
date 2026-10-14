import { Fragment } from 'react';
import { InputGroup, InputGroupAddon } from '@/components/ui/input-group';
import CopyButton from './CopyButton';
import { tokens } from '@/lib/cmd';

interface Props { lines: string[]; label: string; prompt?: boolean }

/** One command line, wrapping only at spaces or after a slash, with a hanging indent. */
export function CommandLine({ line, prompt }: { line: string; prompt: boolean }) {
  return (
    <span className="ln">
      {prompt && <span className="p">$ </span>}
      {tokens(line).map((pieces, i) => (
        <Fragment key={i}>
          {i > 0 && ' '}
          {pieces.map((p, j) => <Fragment key={j}>{j > 0 && <wbr />}<span className="nw">{p}</span></Fragment>)}
        </Fragment>
      ))}
    </span>
  );
}

/** The copy control inside an island: shadcn InputGroup holding the command and its copy Button. */
export default function Command({ lines, label, prompt = true }: Props) {
  return (
    <InputGroup data-cmd="">
      <pre data-slot="input-group-control"><code>{lines.map((l, i) => <CommandLine key={i} line={l} prompt={prompt} />)}</code></pre>
      <InputGroupAddon align="inline-end"><CopyButton text={lines.join('\n')} label={label} /></InputGroupAddon>
    </InputGroup>
  );
}
