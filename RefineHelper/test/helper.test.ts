import { test } from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdtemp, writeFile, rm, appendFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { analyze } from '../src/analysis/analyze.js';
import { routeMatches } from '../src/analysis/graph.js';
import { skipReason } from '../src/analysis/walk.js';
import { parseRequest } from '../src/protocol/messages.js';

const FIXTURE = fileURLToPath(new URL('../../test/fixtures/sample-app', import.meta.url));

async function copyFixture() {
  const dir = await mkdtemp(join(tmpdir(), 'refine-helper-'));
  await cp(FIXTURE, dir, { recursive: true });
  return dir;
}

test('excludes secrets, dependencies and binaries', () => {
  assert.equal(skipReason('.env'), 'secret');
  assert.equal(skipReason('config/.env.production'), 'secret');
  assert.equal(skipReason('keys/server.pem'), 'secret');
  assert.equal(skipReason('node_modules/x/index.js'), 'ignored-dir');
  assert.equal(skipReason('assets/logo.png'), 'binary');
  assert.equal(skipReason('dist/bundle.min.js'), 'ignored-dir');
  assert.equal(skipReason('src/app.ts'), null);
});

test('builds an evidence-backed graph of the sample app', async () => {
  const root = await copyFixture();
  try {
    const { graph, index } = await analyze(root, 'ws-1');
    assert.ok(!index.files['.env'], '.env must never be read');
    const ids = graph.nodes.map((n) => n.id);
    for (const id of ['mod:src/server', 'mod:src/services', 'mod:src/db', 'mod:src/web', 'mod:api', 'ext:pg']) assert.ok(ids.includes(id), `missing ${id}`);

    const node = (id: string) => graph.nodes.find((n) => n.id === id)!;
    assert.equal(node('mod:src/server').type, 'api');
    assert.deepEqual(node('mod:src/server').routes.map((r) => `${r.method} ${r.path}`), ['GET /api/users/:id']);
    assert.equal(node('mod:src/web').type, 'frontend');
    assert.equal(node('mod:api').type, 'api');
    assert.ok(node('mod:api').evidence.some((e) => /sqlalchemy model User/.test(e.detail ?? '')));

    const edge = (id: string) => graph.edges.find((e) => e.id === id);
    const imports = edge('mod:src/server->mod:src/services:imports');
    assert.equal(imports?.verification, 'confirmed');
    assert.deepEqual(imports?.evidence[0], { path: 'src/server/index.ts', line: 2, detail: 'import ../services/users' });
    assert.equal(edge('mod:src/db->ext:pg:uses-database')?.verification, 'confirmed');
    // Matching a fetch() path to a route is a string match: it must never be reported as confirmed.
    assert.equal(edge('mod:src/web->mod:src/server:calls-api')?.verification, 'inferred');
    for (const e of graph.edges) if (e.verification === 'confirmed') assert.ok(e.evidence.length > 0, `${e.id} has no evidence`);

    assert.ok(graph.metadata.frameworks.some((f) => f.name === 'Express'));
    assert.ok(graph.metadata.frameworks.some((f) => f.name === 'FastAPI'));
    assert.ok(graph.metadata.warnings.some((w) => /secrets/.test(w)));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('reuses unchanged files and reports what changed', async () => {
  const root = await copyFixture();
  try {
    const first = await analyze(root, 'ws-1');
    const second = await analyze(root, 'ws-1', first.index);
    assert.equal(second.graph.metadata.stats.reparsed, 0);
    assert.deepEqual(second.changes, { added: [], modified: [], removed: [] });

    await appendFile(join(root, 'src/services/users.ts'), "\nimport { Pool } from 'pg';\n");
    await writeFile(join(root, 'src/services/billing.ts'), "export class BillingService {}\n");
    await rm(join(root, 'src/web/UserList.tsx'));
    const third = await analyze(root, 'ws-1', second.index);
    assert.deepEqual(third.changes, { added: ['src/services/billing.ts'], modified: ['src/services/users.ts'], removed: ['src/web/UserList.tsx'] });
    assert.equal(third.graph.metadata.stats.reparsed, 2);
    assert.ok(third.graph.edges.some((e) => e.id === 'mod:src/services->ext:pg:uses-database'));
    assert.ok(!third.graph.nodes.some((n) => n.id === 'mod:src/web'));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('analysis extracts bounded context metadata without reading secrets', async () => {
  const root = await copyFixture();
  try {
    const { graph, index } = await analyze(root, 'ws-1');
    assert.ok(graph.metadata.languages.some((language) => language.name === 'TypeScript' && language.analyzed));
    assert.ok(graph.nodes.find((node) => node.id === 'mod:src/services')?.symbols.some((symbol) => symbol.name === 'listUsers'));
    assert.ok(!Object.keys(index.files).some((path) => path.includes('.env')));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

test('route matching handles parameters', () => {
  assert.ok(routeMatches('/api/users/:id', '/api/users/42'));
  assert.ok(routeMatches('/items/{item_id}', '/items/7'));
  assert.ok(routeMatches('/api/users/[id]', '/api/users/'));
  assert.ok(!routeMatches('/api/users', '/api/orders'));
});

test('protocol rejects bad requests', () => {
  assert.throws(() => parseRequest('{"protocol":1,"id":"1","method":"hello"}'), /protocol/);
  assert.throws(() => parseRequest('{"protocol":2,"id":"1","method":"rm"}'), /Unknown method/);
  assert.throws(() => parseRequest('nope'), /JSON/);
  assert.equal(parseRequest('{"protocol":2,"id":"1","method":"hello"}').method, 'hello');
});

test('the helper process answers over stdio and exits when stdin closes', async () => {
  const main = fileURLToPath(new URL('../src/main.js', import.meta.url));
  const child = spawn(process.execPath, [main], { stdio: ['pipe', 'pipe', 'inherit'] });
  let out = '';
  child.stdout.on('data', (d) => (out += d));
  child.stdin.end('{"protocol":2,"id":"a","method":"hello","params":{}}\n{"protocol":2,"id":"b","method":"nope","params":{}}\n');
  const code = await new Promise((resolve) => child.on('exit', resolve));
  assert.equal(code, 0);
  const lines = out.trim().split('\n').map((l) => JSON.parse(l));
  const a = lines.find((l) => l.id === 'a'), b = lines.find((l) => l.id === 'b');
  assert.equal(a.ok, true);
  assert.equal(a.result.protocol, 2);
  assert.equal(typeof a.result.helperVersion, 'string');
  assert.equal(b.ok, false);
  assert.equal(b.error.code, 'unknown_method');
});
