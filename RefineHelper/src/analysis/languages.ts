import type { ParseLevel } from './types.js';

const BY_EXT: Record<string, string> = {
  '.ts': 'TypeScript', '.tsx': 'TypeScript', '.mts': 'TypeScript', '.cts': 'TypeScript',
  '.js': 'JavaScript', '.jsx': 'JavaScript', '.mjs': 'JavaScript', '.cjs': 'JavaScript',
  '.py': 'Python', '.swift': 'Swift',
  '.go': 'Go', '.rs': 'Rust', '.java': 'Java', '.kt': 'Kotlin', '.rb': 'Ruby', '.php': 'PHP', '.cs': 'C#',
  '.c': 'C', '.h': 'C', '.cpp': 'C++', '.cc': 'C++', '.hpp': 'C++', '.m': 'Objective-C', '.mm': 'Objective-C',
  '.vue': 'Vue', '.svelte': 'Svelte', '.dart': 'Dart', '.scala': 'Scala', '.ex': 'Elixir', '.exs': 'Elixir',
  '.sql': 'SQL', '.prisma': 'Prisma', '.graphql': 'GraphQL', '.gql': 'GraphQL',
};

/** How deeply each language is analyzed. Anything not listed is counted, not analyzed. */
export const SUPPORT: { name: string; level: ParseLevel }[] = [
  { name: 'TypeScript', level: 'syntax' },
  { name: 'JavaScript', level: 'syntax' },
  { name: 'Python', level: 'pattern' },
  { name: 'Swift', level: 'pattern' },
  { name: 'Prisma', level: 'pattern' },
];

export function languageOf(path: string): string | null {
  const dot = path.lastIndexOf('.');
  if (dot < 0) return null;
  return BY_EXT[path.slice(dot).toLowerCase()] ?? null;
}

export const isAnalyzed = (language: string) => SUPPORT.some((s) => s.name === language);
