import type { DocPage, SectionPage } from './types';
export function docPages(root?: string): DocPage[];
export function sectionPages(section: 'docs' | 'guides', root?: string): SectionPage[];
