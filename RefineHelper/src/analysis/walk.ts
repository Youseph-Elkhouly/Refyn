import { readdir, lstat, realpath } from 'node:fs/promises';
import { join, relative, sep, basename, extname } from 'node:path';
import { isRepository, listFiles } from '../git/git.js';

export const MAX_FILE_BYTES = 512 * 1024;
const MAX_FILES = 20_000;

const IGNORED_DIRS = new Set([
  'node_modules', '.git', '.hg', '.svn', 'dist', 'build', 'out', '.build', '.next', '.nuxt', '.svelte-kit',
  '.output', 'coverage', '.turbo', '.cache', 'vendor', 'Pods', 'Carthage', 'DerivedData', '.venv', 'venv',
  'env', '__pycache__', '.mypy_cache', '.pytest_cache', '.tox', 'target', '.gradle', '.idea', '.swiftpm',
  'graphify-out', '.parcel-cache', '.vercel', 'bower_components',
]);

const SECRET_NAMES = [
  /^\.env(\..*)?$/i, /^\.npmrc$/i, /^\.pypirc$/i, /^\.netrc$/i, /^id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$/i,
  /credentials/i, /secrets?\.(json|ya?ml|toml)$/i, /\.(pem|key|p12|pfx|keystore|jks|mobileprovision|cer|crt)$/i,
  /^service-account.*\.json$/i, /\.tfstate(\.backup)?$/i,
];

const BINARY_EXT = new Set([
  '.png', '.jpg', '.jpeg', '.gif', '.webp', '.ico', '.icns', '.pdf', '.zip', '.gz', '.tgz', '.bz2', '.xz', '.7z',
  '.mp3', '.mp4', '.mov', '.wav', '.m4a', '.woff', '.woff2', '.ttf', '.otf', '.eot', '.so', '.dylib', '.dll', '.exe',
  '.o', '.a', '.class', '.jar', '.wasm', '.sqlite', '.db', '.bin', '.mlmodel', '.mlmodelc', '.psd', '.sketch', '.car',
]);

const GENERATED = [/\.min\.(js|css)$/, /\.map$/, /\.lock$/, /^package-lock\.json$/, /^yarn\.lock$/, /^pnpm-lock\.yaml$/, /\.generated\./, /\.pb\.(go|swift)$/, /_pb2\.py$/, /\.d\.ts$/];

export type SkipReason = 'secret' | 'binary' | 'generated' | 'ignored-dir' | 'outside-workspace';

export function skipReason(path: string): SkipReason | null {
  const parts = path.split('/');
  if (parts.some((p) => IGNORED_DIRS.has(p))) return 'ignored-dir';
  const name = basename(path);
  if (SECRET_NAMES.some((re) => re.test(name))) return 'secret';
  if (BINARY_EXT.has(extname(name).toLowerCase())) return 'binary';
  if (GENERATED.some((re) => re.test(name))) return 'generated';
  return null;
}

export interface WalkResult {
  files: { path: string; size: number; mtimeMs: number }[];
  skipped: Record<SkipReason | 'too-large' | 'limit', number>;
}

/** Candidate files under root, relative and with "/" separators. Never follows symlinks out of root. */
export async function walk(root: string): Promise<WalkResult> {
  const realRoot = await realpath(root);
  const skipped: WalkResult['skipped'] = { secret: 0, binary: 0, generated: 0, 'ignored-dir': 0, 'outside-workspace': 0, 'too-large': 0, limit: 0 };
  let candidates: string[];
  if (await isRepository(realRoot)) candidates = await listFiles(realRoot);
  else candidates = await crawl(realRoot);

  const files: WalkResult['files'] = [];
  for (const rel of candidates) {
    const reason = skipReason(rel);
    if (reason) { skipped[reason]++; continue; }
    if (files.length >= MAX_FILES) { skipped.limit++; continue; }
    const abs = join(realRoot, rel);
    const st = await lstat(abs).catch(() => null);
    if (!st || !st.isFile()) { if (st?.isSymbolicLink()) skipped['outside-workspace']++; continue; }
    if (st.size > MAX_FILE_BYTES) { skipped['too-large']++; continue; }
    files.push({ path: rel.split(sep).join('/'), size: st.size, mtimeMs: Math.round(st.mtimeMs) });
  }
  files.sort((a, b) => a.path.localeCompare(b.path));
  return { files, skipped };
}

async function crawl(root: string): Promise<string[]> {
  const out: string[] = [];
  const stack = [root];
  while (stack.length && out.length < MAX_FILES * 2) {
    const dir = stack.pop()!;
    const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);
    for (const e of entries) {
      if (e.isSymbolicLink()) continue;
      const abs = join(dir, e.name);
      if (e.isDirectory()) { if (!IGNORED_DIRS.has(e.name)) stack.push(abs); }
      else if (e.isFile()) out.push(relative(root, abs));
    }
  }
  return out;
}
