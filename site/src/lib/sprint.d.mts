export interface SprintPhase {
  id: string;
  label: string;
  number: string;
  name: string;
  happensHtml: string;
  agentsHtml: string;
  workflowsHtml: string;
  workflows: string[];
}
export function parsePipeline(text: string, where?: string): { phase: string; happens: string; agents: string; workflows: string }[];
export function sprintPhases(root?: string): SprintPhase[];
export function qualityGates(root?: string): { number: string; name: string; enforcedByHtml: string; rule: string }[];
export function convergenceModes(root?: string): { mode: string; exit: string; use: string; isDefault: boolean }[];
export function completionChecklist(root?: string): string[];
export function cellHtml(markdown: string): string;
