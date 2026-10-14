import type { Cli, Role } from './types';
export const ROLE_NAMES: string[];
export function parseRegistry(text: string, where?: string): Record<string, Record<string, unknown>>;
export function getClis(root?: string): Cli[];
export const CORE_TRIO: string[];
export function getRoles(root?: string): Role[];
