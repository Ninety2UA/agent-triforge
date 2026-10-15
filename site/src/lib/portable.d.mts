import type { Lead } from '../data/leads.mjs';
export interface Invocation {
  harness: string;
  /** the command with `name` standing for the skill */
  form: string;
  /** Markdown, possibly empty */
  note: string;
}
export interface PortableForm {
  /** unique per form: the lead key or the registry id */
  id: string;
  /** the CLI's registry name */
  name: string;
  lead: Lead | null;
  form: string;
  note: string;
}
export function parseInvocations(markdown: string, file: string): Invocation[];
export function portableInvocations(root?: string): PortableForm[];
export function invocation(form: string, skill: string): string;
