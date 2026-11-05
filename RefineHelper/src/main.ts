#!/usr/bin/env node
// Refine helper: reads one JSON request per line on stdin, writes one JSON response per line on stdout.
// It exits when stdin closes, so it never outlives the app that started it.
import { createInterface } from 'node:readline';
import { readFile, writeFile, mkdir, rename } from 'node:fs/promises';
import { dirname } from 'node:path';
import { createRequire } from 'node:module';
import { HELPER_VERSION, PROTOCOL_VERSION, HelperError, parseRequest, requireString, optionalString, stringArray, type Request, type Response } from './protocol/messages.js';
import { analyze } from './analysis/analyze.js';
import { SUPPORT } from './analysis/languages.js';
import { info, diff } from './git/git.js';
import { renderDiagram, type DiagramOptions } from './giotto/diagram.js';
import type { CodebaseGraph, FileIndex } from './analysis/types.js';

async function giottoVersion(): Promise<string> {
  try {
    const path = createRequire(import.meta.url).resolve('giotto/package.json');
    return JSON.parse(await readFile(path, 'utf8')).version ?? 'unknown';
  } catch {
    return 'unknown';
  }
}

export async function handle(req: Request): Promise<unknown> {
  const p = req.params;
  switch (req.method) {
    case 'hello':
      return { protocol: PROTOCOL_VERSION, helperVersion: HELPER_VERSION, giottoVersion: await giottoVersion(), node: process.version, languages: SUPPORT };
    case 'analyze': {
      // The file index lives in a file the app owns, so large indexes never cross stdio.
      const indexPath = optionalString(p, 'indexPath');
      let cache: FileIndex | null = null;
      if (indexPath) {
        try {
          const parsed = JSON.parse(await readFile(indexPath, 'utf8'));
          if (parsed?.version === 1 && parsed.files && typeof parsed.files === 'object') cache = parsed;
        } catch { /* first run, or unreadable cache: full scan */ }
      }
      const { index, ...result } = await analyze(requireString(p, 'root'), optionalString(p, 'workspaceId') ?? '', cache);
      if (indexPath) {
        await mkdir(dirname(indexPath), { recursive: true });
        await writeFile(`${indexPath}.tmp`, JSON.stringify(index));
        await rename(`${indexPath}.tmp`, indexPath);
      }
      return result;
    }
    case 'git.info':
      return info(requireString(p, 'root'));
    case 'git.diff':
      return { files: await diff(requireString(p, 'root'), optionalString(p, 'base') ?? null, stringArray(p, 'paths').slice(0, 200)) };
    case 'diagram.render': {
      const graph = p.graph as CodebaseGraph;
      if (!graph || graph.schemaVersion !== 1 || !Array.isArray(graph.nodes) || !Array.isArray(graph.edges)) throw new HelperError('bad_request', 'params.graph must be a version 1 CodebaseGraph');
      return renderDiagram(graph, (p.options ?? {}) as DiagramOptions);
    }
  }
}

function write(res: Response) {
  process.stdout.write(JSON.stringify(res) + '\n');
}

function main() {
  const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
  let pending = 0, closed = false;
  const settle = () => { if (closed && pending === 0) process.exit(0); };
  rl.on('line', async (line) => {
    if (!line.trim()) return;
    pending++;
    try { await respond(line); } finally { pending--; settle(); }
  });
  rl.on('close', () => { closed = true; settle(); });
}

async function respond(line: string) {
  {
    let req: Request;
    try {
      req = parseRequest(line);
    } catch (e) {
      const err = e instanceof HelperError ? e : new HelperError('bad_request', String(e));
      let id: string | null = null;
      try { id = JSON.parse(line).id ?? null; } catch { /* not JSON */ }
      write({ protocol: PROTOCOL_VERSION, id, ok: false, error: { code: err.code, message: err.message } });
      return;
    }
    try {
      write({ protocol: PROTOCOL_VERSION, id: req.id, ok: true, result: await handle(req) });
    } catch (e) {
      const err = e instanceof HelperError ? { code: e.code, message: e.message } : { code: 'internal' as const, message: (e as Error)?.message ?? String(e) };
      write({ protocol: PROTOCOL_VERSION, id: req.id, ok: false, error: err });
    }
  }
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) main();
