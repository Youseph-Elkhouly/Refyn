import { execFile } from 'node:child_process';
import { HelperError } from '../protocol/messages.js';

// Repository config can name programs git would run (fsmonitor, external diff, textconv). Refine only
// reads, so those are switched off for every call.
const SAFE = ['-c', 'core.fsmonitor=false', '-c', 'diff.external=', '-c', 'core.pager=cat', '--no-pager'];

export function git(root: string, args: string[], { maxBuffer = 32 * 1024 * 1024 } = {}): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile('git', [...SAFE, '-C', root, ...args], { maxBuffer, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0', GIT_TERMINAL_PROMPT: '0' } }, (err, stdout, stderr) => {
      if (err) reject(new Error(stderr.trim() || err.message));
      else resolve(stdout);
    });
  });
}

export async function isRepository(root: string): Promise<boolean> {
  try {
    return (await git(root, ['rev-parse', '--is-inside-work-tree'])).trim() === 'true';
  } catch {
    return false;
  }
}

export interface GitInfo {
  isRepository: boolean;
  head: string | null;
  branch: string | null;
  changes: { path: string; status: string }[];
}

export async function info(root: string): Promise<GitInfo> {
  if (!(await isRepository(root))) return { isRepository: false, head: null, branch: null, changes: [] };
  const head = await git(root, ['rev-parse', 'HEAD']).then((s) => s.trim(), () => null); // null before the first commit
  const branch = await git(root, ['rev-parse', '--abbrev-ref', 'HEAD']).then((s) => s.trim(), () => null);
  const porcelain = await git(root, ['status', '--porcelain=v1', '-z', '--untracked-files=all']);
  return { isRepository: true, head, branch, changes: parsePorcelain(porcelain) };
}

export function parsePorcelain(out: string): { path: string; status: string }[] {
  const parts = out.split('\0').filter(Boolean);
  const result: { path: string; status: string }[] = [];
  for (let i = 0; i < parts.length; i++) {
    const entry = parts[i];
    const status = entry.slice(0, 2).trim() || '?';
    result.push({ path: entry.slice(3), status });
    if (entry[0] === 'R' || entry[0] === 'C') i++; // the source path of a rename follows
  }
  return result;
}

/** Files git knows plus untracked files that are not ignored. */
export async function listFiles(root: string): Promise<string[]> {
  const out = await git(root, ['ls-files', '-z', '--cached', '--others', '--exclude-standard']);
  return [...new Set(out.split('\0').filter(Boolean))];
}

export interface FileDiff {
  path: string;
  additions: number | null;
  deletions: number | null;
  patch: string;
  truncated: boolean;
}

const PATCH_LIMIT = 12_000;

/** Line counts and a bounded patch for each path, against `base` (a commit) or HEAD. */
export async function diff(root: string, base: string | null, paths: string[]): Promise<FileDiff[]> {
  if (!(await isRepository(root))) throw new HelperError('not_a_repository', `${root} is not a git repository`);
  const against = base ?? (await git(root, ['rev-parse', 'HEAD']).then((s) => s.trim(), () => null));
  const result: FileDiff[] = [];
  for (const path of paths) {
    let numstat = '', patch = '';
    if (against) {
      numstat = await git(root, ['diff', '--no-ext-diff', '--no-textconv', '--numstat', against, '--', path]).catch(() => '');
      patch = await git(root, ['diff', '--no-ext-diff', '--no-textconv', '--unified=3', against, '--', path]).catch(() => '');
    }
    if (!patch) {
      // Untracked (or no commits yet): show it as a new file.
      const tracked = await git(root, ['ls-files', '--error-unmatch', '--', path]).then(() => true, () => false);
      if (!tracked) {
        patch = await git(root, ['diff', '--no-ext-diff', '--no-textconv', '--no-index', '--', '/dev/null', path]).catch((e: Error) => e.message);
        numstat = await git(root, ['diff', '--no-ext-diff', '--numstat', '--no-index', '--', '/dev/null', path]).catch((e: Error) => e.message);
      }
    }
    const [add, del] = numstat.split('\t');
    result.push({
      path,
      additions: /^\d+$/.test(add ?? '') ? Number(add) : null,
      deletions: /^\d+$/.test(del ?? '') ? Number(del) : null,
      patch: patch.slice(0, PATCH_LIMIT),
      truncated: patch.length > PATCH_LIMIT,
    });
  }
  return result;
}
