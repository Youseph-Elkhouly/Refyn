import { execFile } from 'node:child_process';

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

