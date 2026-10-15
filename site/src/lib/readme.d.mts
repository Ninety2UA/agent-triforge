export function readmeSection(heading: string, root?: string): string;
export function installCommands(root?: string): { claude: string[]; codex: string[]; skillsOnly: { cli: string; lines: string[]; invoke: string }[] };
export function faq(root?: string): { question: string; anchor: string; answer: string }[];
export function releaseTable(root?: string): { version: string | null; date: string; file: string; summary: string }[];
