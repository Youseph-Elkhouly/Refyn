// Line-pattern extractors for languages without a bundled parser. Results are reported with
// parse level "pattern" so the app never presents them as a full syntactic analysis.
import type { FileFacts } from './types.js';

type Facts = Pick<FileFacts, 'imports' | 'symbols' | 'routes' | 'models' | 'apiCalls' | 'entry' | 'jsx' | 'referencedNames'>;
const empty = (): Facts => ({ imports: [], symbols: [], routes: [], models: [], apiCalls: [], entry: null, jsx: false });

/** Removes block comments and string-literal contents that span lines, keeping line numbers intact. */
function stripBlockComments(text: string, open: string, close: string): string {
  let out = '', i = 0;
  while (i < text.length) {
    const start = text.indexOf(open, i);
    if (start < 0) { out += text.slice(i); break; }
    out += text.slice(i, start);
    const end = text.indexOf(close, start + open.length);
    const chunk = end < 0 ? text.slice(start) : text.slice(start, end + close.length);
    out += chunk.replace(/[^\n]/g, ' ');
    i = end < 0 ? text.length : end + close.length;
  }
  return out;
}

export function extractPython(text: string): Facts {
  const f = empty();
  const src = stripBlockComments(stripBlockComments(text, '"""', '"""'), "'''", "'''");
  const lines = src.split('\n');
  let pendingRoute: { method: string; path: string; line: number; framework: string }[] = [];
  lines.forEach((raw, i) => {
    const n = i + 1;
    const line = raw.replace(/#.*$/, '');
    let m: RegExpMatchArray | null;
    if ((m = line.match(/^\s*from\s+([.\w]+)\s+import\s+(.+)/))) {
      const names = m[2].replace(/[()]/g, '').split(',').map((s) => s.trim().split(/\s+as\s+/)[0]).filter(Boolean);
      // "from . import x" names submodules; record both forms so the resolver can match either.
      if (/^\.+$/.test(m[1])) names.forEach((name) => f.imports.push({ spec: m![1] + name, line: n, kind: 'static' }));
      else f.imports.push({ spec: m[1], line: n, kind: 'static' });
    } else if ((m = line.match(/^\s*import\s+(.+)/))) {
      m[1].split(',').map((s) => s.trim().split(/\s+as\s+/)[0]).filter(Boolean).forEach((spec) => f.imports.push({ spec, line: n, kind: 'static' }));
    }
    if ((m = line.match(/^@(\w+)\.(get|post|put|patch|delete|route|api_route)\(\s*['"]([^'"]+)['"](.*)/))) {
      const methods = m[2] === 'route' || m[2] === 'api_route' ? (m[4].match(/methods\s*=\s*\[([^\]]*)\]/)?.[1].match(/\w+/g) ?? ['GET']) : [m[2]];
      methods.forEach((method) => pendingRoute.push({ method: method.toUpperCase(), path: m![3], line: n, framework: m![2] === 'route' ? 'flask' : 'fastapi' }));
    }
    if ((m = line.match(/^(\s*)class\s+(\w+)\s*(\(([^)]*)\))?\s*:/))) {
      const top = m[1].length === 0;
      if (top) f.symbols.push({ name: m[2], kind: 'class', line: n, exported: !m[2].startsWith('_') });
      const bases = m[4] ?? '';
      if (/\b(models\.Model|db\.Model|Base|DeclarativeBase|SQLModel|Document)\b/.test(bases) && !/table\s*=\s*False/.test(bases)) {
        f.models.push({ name: m[2], line: n, orm: /models\.Model/.test(bases) ? 'django' : /SQLModel/.test(bases) ? 'sqlmodel' : /Document/.test(bases) ? 'odm' : 'sqlalchemy' });
      }
      pendingRoute = [];
    } else if ((m = line.match(/^(\s*)(async\s+)?def\s+(\w+)\s*\(/))) {
      if (m[1].length === 0) f.symbols.push({ name: m[3], kind: 'function', line: n, exported: !m[3].startsWith('_') });
      pendingRoute.forEach((r) => f.routes.push(r));
      pendingRoute = [];
    } else if (line.trim() && !line.trim().startsWith('@')) {
      pendingRoute = [];
    }
    if (/^if\s+__name__\s*==\s*['"]__main__['"]/.test(line)) f.entry = 'python __main__';
    if ((m = line.match(/requests\.(get|post|put|patch|delete)\(\s*['"](\/[^'"]*)['"]/))) f.apiCalls.push({ path: m[2], line: n });
  });
  return f;
}

export function extractSwift(path: string, text: string): Facts {
  const f = empty();
  const src = stripBlockComments(text, '/*', '*/');
  const lines = src.split('\n');
  let depth = 0;
  let pendingMain = false;
  const referenced = new Map<string, number>();
  lines.forEach((raw, i) => {
    const n = i + 1;
    const line = raw.replace(/\/\/.*$/, '').replace(/"(?:\\.|[^"\\])*"/g, '""');
    let m: RegExpMatchArray | null;
    for (const id of line.matchAll(/\b[A-Z][A-Za-z0-9_]{3,}\b/g)) if (!referenced.has(id[0]) && referenced.size < 400) referenced.set(id[0], n);
    if (depth === 0 && (m = line.match(/^\s*(@\w+\s+)*import\s+(?:(?:struct|class|enum|protocol|func|typealias)\s+)?([\w.]+)/))) {
      f.imports.push({ spec: m[2].split('.')[0], line: n, kind: 'static' });
    }
    if (/^\s*@main\b/.test(line)) pendingMain = true;
    if (depth === 0 && (m = line.match(/^\s*(?:@\w+(?:\([^)]*\))?\s+)*((?:public|open|internal|fileprivate|private|final|nonisolated|indirect)\s+)*(class|struct|enum|protocol|actor|extension|func)\s+([\w.]+)/))) {
      const access = m[1] ?? '';
      const kind = m[2] as 'class' | 'struct' | 'enum' | 'protocol' | 'actor' | 'extension' | 'func';
      const name = m[3];
      f.symbols.push({ name, kind: kind === 'func' ? 'function' : kind, line: n, exported: /public|open/.test(access) });
      if (pendingMain) { f.entry = `@main ${name}`; pendingMain = false; }
      const rest = line.slice(line.indexOf(name) + name.length);
      if (kind !== 'func' && /:\s*[^{]*\b(Model|FetchableRecord|PersistableRecord|TableRecord|NSManagedObject)\b/.test(rest)) {
        f.models.push({ name, line: n, orm: /NSManagedObject/.test(rest) ? 'coredata' : /Model\b/.test(rest) ? 'swiftdata/fluent' : 'grdb' });
      }
    }
    if ((m = line.match(/\bapp\.(get|post|put|patch|delete)\(\s*""/))) {
      // Vapor routes use string path components; the literal was blanked above, so read the raw line.
      const p = raw.match(/\bapp\.\w+\(\s*"([^"]*)"/)?.[1] ?? '';
      f.routes.push({ method: m[1].toUpperCase(), path: '/' + p, line: n, framework: 'vapor' });
    }
    if (/^\s*(?:try\s+)?db\.create\(table:/.test(line)) {
      const table = raw.match(/create\(table:\s*"([^"]+)"/)?.[1];
      if (table) f.models.push({ name: table, line: n, orm: 'grdb-migration' });
    }
    for (const ch of line) { if (ch === '{') depth++; else if (ch === '}') depth = Math.max(0, depth - 1); }
  });
  if (/(^|\/)main\.swift$/.test(path)) f.entry = f.entry ?? 'main.swift';
  f.referencedNames = [...referenced];
  return f;
}

export function extractPrisma(text: string): Facts {
  const f = empty();
  text.split('\n').forEach((line, i) => {
    const m = line.match(/^\s*model\s+(\w+)\s*\{/);
    if (m) f.models.push({ name: m[1], line: i + 1, orm: 'prisma' });
  });
  return f;
}
