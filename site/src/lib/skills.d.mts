import type { Group, Skill, SkillGroup } from './types';
export function getSkills(root?: string): Skill[];
export function skillGroups(root?: string): SkillGroup[];
export function groupSkills(names: string[], groups?: { key: string; label: string; skills: string[] }[]): Map<string, Group>;
