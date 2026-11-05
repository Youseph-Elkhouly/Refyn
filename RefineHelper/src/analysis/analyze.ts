import { createHash } from 'node:crypto';
import { readFile, stat, realpath } from 'node:fs/promises';
import { join } from 'node:path';
import { walk } from './walk.js';
import { languageOf, isAnalyzed, SUPPORT } from './languages.js';
import { extractTs } from './extract-ts.js';
import { extractPython, extractSwift, extractPrisma } from './extract-patterns.js';
import { readManifests } from './manifests.js';
import { buildGraph } from './graph.js';
import { info } from '../git/git.js';
import { HelperError } from '../protocol/messages.js';
import type { CodebaseGraph, FileFacts, FileIndex } from './types.js';

export const OTHER = 'Other';
const MANIFEST = /(^|\/)(package\.json|tsconfig\.json|jsconfig\.json|Package\.swift|requirements[^/]*\.txt|pyproject\.toml)$/;

export interface AnalyzeResult {
  graph: CodebaseGraph;
  index: FileIndex;
  changes: { added: string[]; modified: string[]; removed: string[] };
}

export function extract(path: string, language: string, text: string): Omit<FileFacts, 'path' | 'language' | 'size' | 'mtimeMs' | 'hash' | 'lines' | 'parse'> & { parse: FileFacts['parse'] } {
  try {
    switch (language) {
      case 'TypeScript':
      case 'JavaScript':
        return { ...extractTs(path, text), parse: 'syntax' };
      case 'Python':
        return { ...extractPython(text), parse: 'pattern' };
      case 'Swift':
        return { ...extractSwift(path, text), parse: 'pattern' };
      case 'Prisma':
        return { ...extractPrisma(text), parse: 'pattern' };
    }
  } catch (e) {
    return { imports: [], symbols: [], routes: [], models: [], apiCalls: [], entry: null, jsx: false, parse: 'none', error: (e as Error).message };
  }
  return { imports: [], symbols: [], routes: [], models: [], apiCalls: [], entry: null, jsx: false, parse: 'none' };
}

/**
 * Scans the workspace and builds its graph. With a previous index, files whose size and mtime are
 * unchanged are not read at all, and files whose content hash is unchanged are not re-parsed.
 */
export async function analyze(rootParam: string, workspaceId: string, previous?: FileIndex | null): Promise<AnalyzeResult> {
  const st = await stat(rootParam).catch(() => null);
  if (!st?.isDirectory()) throw new HelperError('not_found', `Workspace folder not found: ${rootParam}`);
  const root = await realpath(rootParam);
  const prev = previous?.version === 1 ? previous.files : {};
  const { files, skipped } = await walk(root);

  const facts: FileFacts[] = [];
  const manifestFiles: string[] = [];
  let reparsed = 0, reused = 0;
  for (const file of files) {
    if (MANIFEST.test(file.path)) manifestFiles.push(file.path);
    // Every scanned file is hashed for workspace change detection; only known languages are parsed.
    const language = languageOf(file.path) ?? OTHER;
    const old = prev[file.path];
    if (old && old.size === file.size && old.mtimeMs === file.mtimeMs) { facts.push(old); reused++; continue; }
    const buf = await readFile(join(root, file.path)).catch(() => null);
    if (!buf || buf.includes(0)) continue; // unreadable or binary
    const hash = createHash('sha256').update(buf).digest('hex');
    if (old && old.hash === hash) { facts.push({ ...old, mtimeMs: file.mtimeMs }); reused++; continue; }
    const text = buf.toString('utf8');
    const lines = text.split('\n').length;
    const base = { path: file.path, language, size: file.size, mtimeMs: file.mtimeMs, hash, lines };
    facts.push(isAnalyzed(language) ? { ...base, ...extract(file.path, language, text) } : { ...base, imports: [], symbols: [], routes: [], models: [], apiCalls: [], entry: null, jsx: false, parse: 'none' });
    reparsed++;
  }

  const index: FileIndex = { version: 1, files: Object.fromEntries(facts.map((f) => [f.path, f])) };
  const changes = { added: [] as string[], modified: [] as string[], removed: [] as string[] };
  if (previous) {
    for (const f of facts) {
      const old = prev[f.path];
      if (!old) changes.added.push(f.path);
      else if (old.hash !== f.hash) changes.modified.push(f.path);
    }
    for (const p of Object.keys(prev)) if (!index.files[p]) changes.removed.push(p);
  }

  const manifests = await readManifests(root, manifestFiles);
  const git = await info(root);
  const fingerprint = createHash('sha256').update(facts.map((f) => `${f.path}:${f.hash}`).join('\n')).digest('hex');
  const warnings: string[] = [];
  if (!git.isRepository) warnings.push('Not a git repository: workspace change detection uses file hashes only.');
  const skippedTotal = Object.values(skipped).reduce((a, b) => a + b, 0);
  if (skipped.secret) warnings.push(`${skipped.secret} file(s) that look like secrets or credentials were excluded.`);
  if (skipped.limit) warnings.push(`File limit reached: ${skipped.limit} file(s) were not scanned.`);
  const failed = facts.filter((f) => f.error);
  if (failed.length) warnings.push(`${failed.length} file(s) failed to parse, e.g. ${failed[0].path}: ${failed[0].error}`);

  const graph = buildGraph(
    workspaceId,
    facts,
    manifests,
    { head: git.head, branch: git.branch, dirty: git.changes.length > 0, fingerprint },
    { files: facts.length, reparsed, reused, skipped: skippedTotal },
    SUPPORT,
    warnings,
  );
  return { graph, index, changes };
}
