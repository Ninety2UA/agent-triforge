import type { Release } from './types';
export function getReleases(root?: string): Release[];
export const UNTAGGED: string[];
export function compareVersions(a: string, b: string): number;
export function orderReleases<T>(notes: T[]): T[];
export function parseReleaseHeader(line: string, where?: string): { date: string; version: string | null; title: string };
export function releaseAnchor(note: { version: string | null; date: string }): string;
export function releaseRef(version: string | null): string;
