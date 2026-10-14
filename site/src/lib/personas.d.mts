import type { Persona, PersonaGroup } from './types';
export function getPersonas(root?: string): Persona[];
export function personaGroups(root?: string): (PersonaGroup & { count: number })[];
export function personasPage(root?: string): { href: string; title: string; intro: string };
