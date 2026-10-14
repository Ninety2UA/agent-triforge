import { IC, type IconName } from './icons';

/** One of the examples' icons inside a React island. The markup is a fixed string from icons.ts. */
export function Icon({ name }: { name: IconName }) {
  return <span className="contents" dangerouslySetInnerHTML={{ __html: IC[name] }} />;
}
