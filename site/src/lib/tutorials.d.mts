import type { SectionPage } from './types';
import type { Lead } from '../data/leads.mjs';
export type { Lead };
export type TutorialSegment = { kind: 'md'; md: string } | { kind: 'cmd'; lang: 'prompt' | 'bash'; text: string };
export interface TutorialStep {
  title: string;
  id: string;
  skills: string[];
  common: TutorialSegment[];
  tabs: { lead: Lead; label: string; segments: TutorialSegment[] }[] | null;
  happens: string;
  why: string;
  checkpoint: string;
  markdown: string;
}
export const TUTORIALS: { slug: string; title: string }[];
export function tutorialPages(): SectionPage[];
export function writtenTutorials(root?: string): SectionPage[];
export function parseTutorial(text: string, file: string): { meta: { description: string }; intro: string; steps: TutorialStep[]; recap: string };
export function skillTokens(markdown: string, names: string[]): string[];
