import { posix } from 'node:path';
import type { CodebaseGraph, ComponentType, FileFacts, GraphEdge, GraphNode, Relation, SourceRef, Verification } from './types.js';
import type { Manifests } from './manifests.js';

const MAX_MODULES = 60;
const EVIDENCE_PER_EDGE = 5;

const DB_PACKAGES = new Set([
  'pg', 'postgres', 'mysql', 'mysql2', 'sqlite3', 'better-sqlite3', 'mongodb', 'mongoose', 'redis', 'ioredis', '@prisma/client',
  'prisma', 'drizzle-orm', 'typeorm', 'sequelize', 'knex', 'kysely', '@supabase/supabase-js', '@neondatabase/serverless',
  '@upstash/redis', 'firebase-admin', 'sqlalchemy', 'psycopg2', 'psycopg', 'pymongo', 'sqlite3', 'django.db', 'sqlmodel',
  'GRDB', 'SQLite', 'SQLite3', 'CoreData', 'SwiftData', 'Fluent',
]);
const SERVICE_PACKAGES = new Set([
  'stripe', 'openai', '@anthropic-ai/sdk', 'anthropic', 'ai', '@aws-sdk/client-s3', 'aws-sdk', 'boto3', 'twilio', 'resend',
  '@sendgrid/mail', 'firebase', 'WhisperKit', 'axios', 'requests', 'httpx',
]);
const FRONTEND_DIRS = /(^|\/)(components|pages|app|views|ui|screens|frontend|client|web|layouts|widgets|Views)(\/|$)/;
const SERVICE_DIRS = /(^|\/)(services?|server|backend|workers?|jobs|handlers|controllers|Services)(\/|$)/i;
const TEST_FILE = /(^|\/)(tests?|__tests__|spec|Tests|e2e)(\/|$)|\.(test|spec)\.[jt]sx?$|_test\.py$|^test_.*\.py$|Tests?\.swift$/;

interface Ctx {
  facts: FileFacts[];
  byPath: Map<string, FileFacts>;
  manifests: Manifests;
  warnings: string[];
}

export function buildGraph(workspaceId: string, facts: FileFacts[], manifests: Manifests, snapshot: CodebaseGraph['metadata']['snapshot'], stats: CodebaseGraph['metadata']['stats'], supported: CodebaseGraph['metadata']['supportedLanguages'], extraWarnings: string[]): CodebaseGraph {
  facts = facts.filter((f) => f.language !== 'Other');
  const ctx: Ctx = { facts, byPath: new Map(facts.map((f) => [f.path, f])), manifests, warnings: [...extraWarnings] };
  const analyzed = facts.filter((f) => f.parse !== 'none');
  const moduleOf = moduleAssigner(analyzed.map((f) => f.path), manifests);

  // Nodes: one per module (directory, collapsed to keep the graph readable).
  const members = new Map<string, FileFacts[]>();
  for (const f of analyzed) {
    const key = moduleOf(f.path);
    if (!members.has(key)) members.set(key, []);
    members.get(key)!.push(f);
  }
  const nodes = new Map<string, GraphNode>();
  for (const [key, files] of members) nodes.set(nodeId(key), moduleNode(key, files));

  const edges = new Map<string, GraphEdge>();
  const addEdge = (source: string, target: string, relation: Relation, verification: Verification, ref: SourceRef) => {
    if (source === target) return;
    const id = `${source}->${target}:${relation}`;
    const existing = edges.get(id);
    if (existing) {
      if (existing.evidence.length < EVIDENCE_PER_EDGE) existing.evidence.push(ref);
      // Confirmed evidence upgrades an inferred edge; never the other way around.
      if (verification === 'confirmed') existing.verification = 'confirmed';
      return;
    }
    edges.set(id, { id, source, target, relation, evidence: [ref], verification });
  };

  const externalNode = (name: string, kind: 'database' | 'service', ref: SourceRef) => {
    const id = `ext:${name}`;
    if (!nodes.has(id)) {
      nodes.set(id, {
        id, name, type: 'external', path: '', group: kind === 'database' ? 'Data' : 'External', files: [], languages: [],
        symbols: [], routes: [], evidence: [ref], verification: 'confirmed',
      });
    } else if (nodes.get(id)!.evidence.length < EVIDENCE_PER_EDGE) nodes.get(id)!.evidence.push(ref);
    return id;
  };

  // Import edges, resolved deterministically.
  let unresolved = 0;
  const unresolvedSamples: string[] = [];
  for (const f of analyzed) {
    const from = nodeId(moduleOf(f.path));
    for (const imp of f.imports) {
      const ref: SourceRef = { path: f.path, line: imp.line, detail: `${imp.kind === 'dynamic' ? 'dynamic import' : 'import'} ${imp.spec}` };
      const resolved = resolveImport(f, imp.spec, ctx);
      if (resolved.kind === 'file') {
        addEdge(from, nodeId(moduleOf(resolved.path)), 'imports', 'confirmed', ref);
      } else if (resolved.kind === 'swift-target') {
        const anchor = anchorFor(resolved.dir, [...members.keys()]);
        if (anchor) addEdge(from, nodeId(anchor), 'imports', 'confirmed', ref);
      } else if (resolved.kind === 'external') {
        if (DB_PACKAGES.has(resolved.name)) addEdge(from, externalNode(resolved.name, 'database', ref), 'uses-database', 'confirmed', ref);
        else if (SERVICE_PACKAGES.has(resolved.name)) addEdge(from, externalNode(resolved.name, 'service', ref), 'depends-on', 'confirmed', ref);
      } else if (resolved.kind === 'unresolved') {
        unresolved++;
        if (unresolvedSamples.length < 5) unresolvedSamples.push(`${f.path}:${imp.line} ${imp.spec}`);
      }
    }
  }
  if (unresolved) ctx.warnings.push(`${unresolved} local import(s) could not be resolved, e.g. ${unresolvedSamples.join('; ')}`);

  // Swift files in one module see each other's types without imports. A top-level type name that
  // appears in another module's code is a likely reference, so it becomes an inferred edge.
  const swiftTypes = new Map<string, string>(); // type name -> module id (only names declared once)
  const dupes = new Set<string>();
  for (const f of analyzed.filter((x) => x.language === 'Swift')) {
    for (const s of f.symbols) {
      if (!['class', 'struct', 'enum', 'protocol', 'actor'].includes(s.kind) || s.name.length < 4) continue;
      const mod = nodeId(moduleOf(f.path));
      if (swiftTypes.has(s.name) && swiftTypes.get(s.name) !== mod) dupes.add(s.name);
      swiftTypes.set(s.name, mod);
    }
  }
  dupes.forEach((d) => swiftTypes.delete(d));
  for (const f of analyzed.filter((x) => x.language === 'Swift')) {
    const from = nodeId(moduleOf(f.path));
    for (const [name, line] of f.referencedNames ?? []) {
      const target = swiftTypes.get(name);
      if (target && target !== from) addEdge(from, target, 'depends-on', 'inferred', { path: f.path, line, detail: `references ${name}` });
    }
  }

  // An inferred reference adds nothing where an import already confirms the dependency.
  for (const [id, e] of edges) {
    if (e.verification !== 'inferred' || e.relation !== 'depends-on') continue;
    if (edges.get(`${e.source}->${e.target}:imports`)?.verification === 'confirmed') edges.delete(id);
  }

  // Calls from client code to routes defined in the repo (matched by path string: inferred).
  const routes: { node: string; method: string; path: string; ref: SourceRef }[] = [];
  for (const n of nodes.values()) for (const r of n.routes) routes.push({ node: n.id, method: r.method, path: r.path, ref: r.source });
  for (const f of analyzed) {
    const from = nodeId(moduleOf(f.path));
    for (const call of f.apiCalls) {
      const match = routes.find((r) => routeMatches(r.path, call.path));
      if (match) addEdge(from, match.node, 'calls-api', 'inferred', { path: f.path, line: call.line, detail: `calls ${call.path} (route ${match.method} ${match.path} at ${match.ref.path}:${match.ref.line})` });
    }
  }

  // Modules that define models reach the database through them.
  const unsupported = [...new Set(facts.filter((f) => f.parse === 'none').map((f) => f.language))];
  if (unsupported.length) ctx.warnings.push(`Not analyzed (counted only): ${unsupported.join(', ')}`);

  const langCounts = new Map<string, { files: number; analyzed: boolean }>();
  for (const f of facts) {
    const c = langCounts.get(f.language) ?? { files: 0, analyzed: f.parse !== 'none' };
    c.files++;
    langCounts.set(f.language, c);
  }

  const entryPoints: SourceRef[] = [...manifests.entryPoints];
  for (const f of analyzed) if (f.entry) entryPoints.push({ path: f.path, detail: f.entry });

  const frameworks = [...manifests.frameworks];
  const seenFw = new Set(frameworks.map((f) => f.name));
  for (const f of analyzed.filter((x) => x.language === 'Swift')) {
    for (const imp of f.imports) {
      const name = SWIFT_FW[imp.spec];
      if (name && !seenFw.has(name)) { seenFw.add(name); frameworks.push({ name, evidence: { path: f.path, line: imp.line, detail: `import ${imp.spec}` } }); }
    }
  }

  return {
    schemaVersion: 1,
    metadata: {
      workspaceId,
      analyzedAt: new Date().toISOString(),
      snapshot,
      supportedLanguages: supported,
      languages: [...langCounts].map(([name, c]) => ({ name, ...c })).sort((a, b) => b.files - a.files),
      frameworks,
      entryPoints,
      warnings: ctx.warnings,
      stats,
    },
    nodes: [...nodes.values()].sort((a, b) => a.id.localeCompare(b.id)),
    edges: [...edges.values()].sort((a, b) => a.id.localeCompare(b.id)),
  };
}

const SWIFT_FW: Record<string, string> = {
  SwiftUI: 'SwiftUI', AppKit: 'AppKit', UIKit: 'UIKit', GRDB: 'GRDB', SwiftData: 'SwiftData', CoreData: 'Core Data',
  Vapor: 'Vapor', Combine: 'Combine', AVFoundation: 'AVFoundation', WebKit: 'WebKit', WhisperKit: 'WhisperKit',
};

export const nodeId = (moduleKey: string) => `mod:${moduleKey}`;

/** Directory → module key, collapsing deep trees so a large repo stays at most MAX_MODULES modules. */
function moduleAssigner(paths: string[], manifests: Manifests): (path: string) => string {
  const dirOf = (p: string) => { const d = posix.dirname(p); return d === '.' ? '.' : d; };
  const dirs = [...new Set(paths.map(dirOf))];
  let depth = Math.max(1, ...dirs.map((d) => (d === '.' ? 0 : d.split('/').length)));
  const cut = (d: string, k: number) => (d === '.' ? '.' : d.split('/').slice(0, k).join('/'));
  while (depth > 1 && new Set(dirs.map((d) => cut(d, depth))).size > MAX_MODULES) depth--;
  // SwiftPM targets are modules in their own right: never merge two targets into one node.
  const targets = Object.values(manifests.swiftTargets);
  return (path: string) => {
    const d = dirOf(path);
    const target = targets.find((t) => d === t || d.startsWith(t + '/'));
    const k = cut(d, depth);
    if (target && k.length < target.length) return target;
    return k;
  };
}

function anchorFor(dir: string, modules: string[]): string | null {
  const inside = modules.filter((m) => m === dir || m.startsWith(dir + '/')).sort((a, b) => a.length - b.length);
  return inside[0] ?? null;
}

function moduleNode(key: string, files: FileFacts[]): GraphNode {
  const name = key === '.' ? '(root)' : key.split('/').slice(-2).join('/');
  const type = classify(key, files);
  const symbols = files
    .flatMap((f) => f.symbols.filter((s) => s.exported || f.language === 'Swift' || f.language === 'Python').map((s) => ({ name: s.name, kind: s.kind, path: f.path, line: s.line })))
    .filter((s) => s.kind !== 'extension')
    .slice(0, 40);
  const routes = files.flatMap((f) => f.routes.map((r) => ({ method: r.method, path: r.path, source: { path: f.path, line: r.line, detail: r.framework } })));
  const evidence: SourceRef[] = files.slice(0, 3).map((f) => ({ path: f.path, detail: `${f.language}, ${f.lines} lines` }));
  for (const f of files) for (const m of f.models) if (evidence.length < 8) evidence.push({ path: f.path, line: m.line, detail: `${m.orm} model ${m.name}` });
  for (const f of files) if (f.entry && evidence.length < 10) evidence.push({ path: f.path, detail: `entry: ${f.entry}` });
  return {
    id: nodeId(key), name, type, path: key, group: GROUP[type], files: files.map((f) => f.path),
    languages: [...new Set(files.map((f) => f.language))], symbols, routes, evidence, verification: 'confirmed',
  };
}

const GROUP: Record<ComponentType, string> = {
  frontend: 'Frontend', api: 'API', service: 'Services', database: 'Data', entry: 'Entry points', library: 'Modules',
  test: 'Tests', config: 'Config', external: 'External',
};

function classify(key: string, files: FileFacts[]): ComponentType {
  if (files.every((f) => TEST_FILE.test(f.path))) return 'test';
  if (files.some((f) => f.routes.length)) return 'api';
  if (files.some((f) => f.models.length)) return 'database';
  const ui = files.filter((f) => f.jsx || (f.language === 'Swift' && f.imports.some((i) => i.spec === 'SwiftUI' || i.spec === 'AppKit' || i.spec === 'UIKit')));
  if (files.some((f) => f.entry)) return 'entry';
  if (ui.length * 2 >= files.length || (FRONTEND_DIRS.test(key) && files.some((f) => /\.(t|j)sx$|\.vue$|\.svelte$/.test(f.path)))) return 'frontend';
  if (SERVICE_DIRS.test(key) || files.some((f) => f.symbols.some((s) => /Service$|Client$|Store$/.test(s.name)))) return 'service';
  return 'library';
}

type Resolution =
  | { kind: 'file'; path: string }
  | { kind: 'swift-target'; dir: string }
  | { kind: 'external'; name: string }
  | { kind: 'builtin' }
  | { kind: 'unresolved' };

const TS_EXT = ['', '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '/index.ts', '/index.tsx', '/index.js', '/index.jsx'];
const NODE_BUILTINS = /^(node:|fs$|path$|os$|crypto$|http$|https$|url$|util$|events$|stream$|child_process$|zlib$|net$|tls$|assert$|buffer$|readline$|worker_threads$|process$)/;
const PY_STDLIB = new Set(['os', 'sys', 're', 'json', 'typing', 'datetime', 'time', 'math', 'logging', 'pathlib', 'collections', 'itertools', 'functools', 'dataclasses', 'enum', 'abc', 'asyncio', 'subprocess', 'unittest', 'uuid', 'random', 'hashlib', 'base64', 'io', 'copy', 'contextlib', 'argparse', 'shutil', 'tempfile', 'threading', 'traceback', 'inspect', 'textwrap', 'string', 'http', 'urllib', 'socket', 'csv', 'sqlite3', 'decimal', 'statistics', 'glob', 'pickle', 'queue', 'warnings', 'weakref', '__future__']);

function resolveImport(f: FileFacts, spec: string, ctx: Ctx): Resolution {
  if (f.language === 'Swift') {
    const dir = ctx.manifests.swiftTargets[spec];
    if (dir) return { kind: 'swift-target', dir };
    return { kind: 'external', name: spec };
  }
  if (f.language === 'Python') return resolvePython(f, spec, ctx);

  const tryPaths = (base: string): Resolution | null => {
    const stem = base.replace(/\.(m|c)?js$/, '');
    for (const candidate of [base, ...TS_EXT.map((e) => stem + e)]) {
      const p = posix.normalize(candidate);
      if (ctx.byPath.has(p)) return { kind: 'file', path: p };
    }
    return null;
  };
  if (spec.startsWith('.')) return tryPaths(posix.join(posix.dirname(f.path), spec)) ?? { kind: 'unresolved' };
  for (const a of ctx.manifests.aliases) {
    if (spec.startsWith(a.prefix)) { const r = tryPaths(posix.join(a.dir || '.', spec.slice(a.prefix.length))); if (r) return r; }
  }
  const pkgName = spec.startsWith('@') ? spec.split('/').slice(0, 2).join('/') : spec.split('/')[0];
  const local = ctx.manifests.localPackages[pkgName];
  if (local) {
    const rest = spec.slice(pkgName.length).replace(/^\//, '');
    return tryPaths(posix.join(local, rest || 'src/index')) ?? tryPaths(posix.join(local, rest || 'index')) ?? { kind: 'unresolved' };
  }
  if (NODE_BUILTINS.test(spec)) return { kind: 'builtin' };
  return { kind: 'external', name: pkgName };
}

function resolvePython(f: FileFacts, spec: string, ctx: Ctx): Resolution {
  const tryModule = (parts: string[], base: string): Resolution | null => {
    for (let k = parts.length; k > 0; k--) {
      const p = posix.join(base, ...parts.slice(0, k));
      for (const candidate of [`${p}.py`, `${p}/__init__.py`]) if (ctx.byPath.has(posix.normalize(candidate))) return { kind: 'file', path: posix.normalize(candidate) };
    }
    return null;
  };
  if (spec.startsWith('.')) {
    const dots = spec.match(/^\.+/)![0].length;
    let base = posix.dirname(f.path);
    for (let i = 1; i < dots; i++) base = posix.dirname(base);
    const rest = spec.slice(dots).split('.').filter(Boolean);
    return (rest.length ? tryModule(rest, base) : null) ?? (ctx.byPath.has(posix.join(base, '__init__.py')) ? { kind: 'file', path: posix.join(base, '__init__.py') } : { kind: 'unresolved' });
  }
  const parts = spec.split('.');
  for (const base of ['.', 'src', posix.dirname(f.path)]) { const r = tryModule(parts, base); if (r) return r; }
  if (PY_STDLIB.has(parts[0])) return { kind: 'builtin' };
  return { kind: 'external', name: spec.startsWith('django.db') ? 'django.db' : parts[0] };
}

const norm = (p: string) => p.replace(/\/+$/, '').replace(/\?.*$/, '').split('/').map((s) => (/^(:\w+|\[.*\]|\{.*\}|<.*>)$/.test(s) ? '*' : s));
export function routeMatches(route: string, call: string): boolean {
  const a = norm(route), b = norm(call);
  if (b.length > 0 && call.endsWith('/') && b.length === a.length - 1) b.push('*'); // `${base}/${id}` → template head ends in "/"
  return a.length === b.length && a.every((s, i) => s === '*' || b[i] === '*' || s === b[i]);
}
