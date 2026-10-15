export declare const LEADS: readonly ['claude-code', 'codex'];
export type Lead = (typeof LEADS)[number];
export declare const LEAD_NAMES: Record<Lead, string>;
export declare const LEAD_TABS: { id: Lead; label: string; lead: Lead }[];
export declare function isLead(value: unknown): value is Lead;
