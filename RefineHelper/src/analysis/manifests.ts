import { readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import type { SourceRef } from './types.js';

export interface Manifests {
  frameworks: { name: string; evidence: SourceRef }[];
  entryPoints: SourceRef[];
  /** Local package name → directory, for monorepos importing their own packages by name. */
  localPackages: Record<string, string>;
  /** SwiftPM target name → source directory. */
  swiftTargets: Record<string, string>;
  /** tsconfig "paths" aliases: prefix → directory (both without the trailing "*"). */
  aliases: { prefix: string; dir: string }[];
  dependencies: { name: string; ecosystem: 'npm' | 'pypi' | 'swiftpm'; source: SourceRef }[];
}

const NPM_FRAMEWORKS: Record<string, string> = {
  next: 'Next.js', react: 'React', 'react-native': 'React Native', vue: 'Vue', nuxt: 'Nuxt', svelte: 'Svelte',
  '@sveltejs/kit': 'SvelteKit', astro: 'Astro', '@angular/core': 'Angular', express: 'Express', fastify: 'Fastify',
  hono: 'Hono', koa: 'Koa', '@nestjs/core': 'NestJS', electron: 'Electron', vite: 'Vite', tailwindcss: 'Tailwind CSS',
  prisma: 'Prisma', '@prisma/client': 'Prisma', 'drizzle-orm': 'Drizzle', typeorm: 'TypeORM', sequelize: 'Sequelize',
  mongoose: 'Mongoose', 'socket.io': 'Socket.IO', graphql: 'GraphQL', '@trpc/server': 'tRPC', ai: 'AI SDK',
  jest: 'Jest', vitest: 'Vitest', '@playwright/test': 'Playwright',
};

const PY_FRAMEWORKS: Record<string, string> = {
  django: 'Django', flask: 'Flask', fastapi: 'FastAPI', sqlalchemy: 'SQLAlchemy', sqlmodel: 'SQLModel',
  pydantic: 'Pydantic', celery: 'Celery', pytest: 'pytest', torch: 'PyTorch', numpy: 'NumPy', pandas: 'pandas',
};

export async function readManifests(root: string, files: string[]): Promise<Manifests> {
  const m: Manifests = { frameworks: [], entryPoints: [], localPackages: {}, swiftTargets: {}, aliases: [], dependencies: [] };
  const seen = new Set<string>();
  const framework = (name: string, evidence: SourceRef) => { if (!seen.has(name)) { seen.add(name); m.frameworks.push({ name, evidence }); } };
  const read = (rel: string) => readFile(join(root, rel), 'utf8').catch(() => null);

  for (const rel of files.filter((f) => f.endsWith('package.json')).slice(0, 50)) {
    const text = await read(rel);
    if (!text) continue;
    let pkg: Record<string, unknown>;
    try { pkg = JSON.parse(text); } catch { continue; }
    const dir = dirname(rel) === '.' ? '' : dirname(rel);
    if (typeof pkg.name === 'string' && dir) m.localPackages[pkg.name] = dir;
    for (const field of ['dependencies', 'devDependencies', 'peerDependencies']) {
      const deps = pkg[field];
      if (!deps || typeof deps !== 'object') continue;
      for (const name of Object.keys(deps)) {
        m.dependencies.push({ name, ecosystem: 'npm', source: { path: rel, detail: field } });
        if (NPM_FRAMEWORKS[name]) framework(NPM_FRAMEWORKS[name], { path: rel, detail: `${field}: ${name}` });
      }
    }
    const join2 = (p: string) => (dir ? `${dir}/${p.replace(/^\.\//, '')}` : p.replace(/^\.\//, ''));
    if (typeof pkg.main === 'string') m.entryPoints.push({ path: join2(pkg.main), detail: `${rel} main` });
    const bin = pkg.bin;
    if (typeof bin === 'string') m.entryPoints.push({ path: join2(bin), detail: `${rel} bin` });
    else if (bin && typeof bin === 'object') for (const [k, v] of Object.entries(bin)) if (typeof v === 'string') m.entryPoints.push({ path: join2(v), detail: `${rel} bin ${k}` });
  }

  const tsconfig = files.find((f) => f === 'tsconfig.json' || f === 'jsconfig.json');
  if (tsconfig) {
    const text = await read(tsconfig);
    if (text) {
      try {
        const cfg = JSON.parse(text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:"])\/\/.*$/gm, '$1').replace(/,(\s*[}\]])/g, '$1'));
        const base = String(cfg.compilerOptions?.baseUrl ?? '.').replace(/^\.\/?/, '');
        for (const [alias, targets] of Object.entries<string[]>(cfg.compilerOptions?.paths ?? {})) {
          const target = targets?.[0];
          if (!target) continue;
          const dir = [base, target.replace(/\*$/, '').replace(/^\.\//, '')].filter(Boolean).join('/').replace(/\/$/, '');
          m.aliases.push({ prefix: alias.replace(/\*$/, ''), dir });
        }
      } catch { /* a tsconfig we can't read just means no aliases */ }
    }
  }

  for (const rel of files.filter((f) => /(^|\/)(requirements[^/]*\.txt|pyproject\.toml)$/.test(f)).slice(0, 20)) {
    const text = (await read(rel)) ?? '';
    for (const [key, name] of Object.entries(PY_FRAMEWORKS)) {
      if (new RegExp(`(^|[\\s"'\\[])${key}([\\s"'=<>~!\\[;,]|$)`, 'im').test(text)) {
        framework(name, { path: rel, detail: key });
        m.dependencies.push({ name: key, ecosystem: 'pypi', source: { path: rel } });
      }
    }
  }

  const pkgSwift = files.find((f) => f === 'Package.swift');
  if (pkgSwift) {
    const text = (await read(pkgSwift)) ?? '';
    framework('Swift Package Manager', { path: pkgSwift });
    for (const t of text.matchAll(/\.(target|executableTarget|testTarget|macro)\(\s*name:\s*"([^"]+)"([^)]*?path:\s*"([^"]+)")?/g)) {
      const dir = t[4] ?? `${t[1] === 'testTarget' ? 'Tests' : 'Sources'}/${t[2]}`;
      m.swiftTargets[t[2]] = dir;
      if (t[1] === 'executableTarget') m.entryPoints.push({ path: dir, detail: `executable target ${t[2]}` });
    }
    for (const d of text.matchAll(/\.package\(\s*url:\s*"([^"]+)"/g)) {
      const name = d[1].replace(/\.git$/, '').split('/').pop() ?? d[1];
      m.dependencies.push({ name, ecosystem: 'swiftpm', source: { path: pkgSwift, detail: d[1] } });
    }
  }
  return m;
}

export const SWIFT_FRAMEWORKS: Record<string, string> = {
  SwiftUI: 'SwiftUI', AppKit: 'AppKit', UIKit: 'UIKit', GRDB: 'GRDB', SwiftData: 'SwiftData', CoreData: 'Core Data',
  Vapor: 'Vapor', Combine: 'Combine', AVFoundation: 'AVFoundation', WebKit: 'WebKit', WhisperKit: 'WhisperKit',
};
