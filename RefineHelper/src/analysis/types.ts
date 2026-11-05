// Mirrors SharedSchemas/codebase-graph.schema.json and the Swift CodebaseGraph types.

export type Verification = 'confirmed' | 'inferred' | 'unknown';
export type ParseLevel = 'syntax' | 'pattern' | 'none';

export type ComponentType =
  | 'frontend'
  | 'api'
  | 'service'
  | 'database'
  | 'entry'
  | 'library'
  | 'test'
  | 'config'
  | 'external';

export type Relation = 'imports' | 'calls-api' | 'uses-database' | 'depends-on';

export interface SourceRef {
  path: string;
  line?: number;
  detail?: string;
}

export interface SymbolFact {
  name: string;
  kind: 'class' | 'function' | 'struct' | 'protocol' | 'enum' | 'interface' | 'type' | 'actor' | 'extension';
  line: number;
  exported: boolean;
}

export interface ImportFact {
  spec: string;
  line: number;
  kind: 'static' | 'dynamic' | 'require';
}

export interface RouteFact {
  method: string;
  path: string;
  line: number;
  framework: string;
}

export interface ModelFact {
  name: string;
  line: number;
  orm: string;
}

export interface FileFacts {
  path: string;
  language: string;
  size: number;
  mtimeMs: number;
  hash: string;
  lines: number;
  parse: ParseLevel;
  imports: ImportFact[];
  symbols: SymbolFact[];
  routes: RouteFact[];
  models: ModelFact[];
  apiCalls: { path: string; line: number }[];
  entry: string | null;
  jsx: boolean;
  /** Swift only: capitalized identifiers used in the file, with the first line each appears on. */
  referencedNames?: [string, number][];
  error?: string;
}

export interface GraphNode {
  id: string;
  name: string;
  type: ComponentType;
  path: string;
  group: string;
  files: string[];
  languages: string[];
  symbols: { name: string; kind: string; path: string; line: number }[];
  routes: { method: string; path: string; source: SourceRef }[];
  evidence: SourceRef[];
  verification: Verification;
}

export interface GraphEdge {
  id: string;
  source: string;
  target: string;
  relation: Relation;
  evidence: SourceRef[];
  verification: Verification;
}

export interface CodebaseGraph {
  schemaVersion: 1;
  metadata: {
    workspaceId: string;
    analyzedAt: string;
    snapshot: { head: string | null; branch: string | null; dirty: boolean; fingerprint: string };
    supportedLanguages: { name: string; level: ParseLevel }[];
    languages: { name: string; files: number; analyzed: boolean }[];
    frameworks: { name: string; evidence: SourceRef }[];
    entryPoints: SourceRef[];
    warnings: string[];
    stats: { files: number; reparsed: number; reused: number; skipped: number };
  };
  nodes: GraphNode[];
  edges: GraphEdge[];
}

export interface FileIndex {
  version: 1;
  files: Record<string, FileFacts>;
}
