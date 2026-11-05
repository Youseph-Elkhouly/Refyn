// Wire protocol between the Refine app and this helper: one JSON object per line on stdin/stdout.
// Schema: SharedSchemas/helper-protocol.schema.json. Bump PROTOCOL_VERSION on any breaking change.
export const PROTOCOL_VERSION = 2;
export const HELPER_VERSION = '0.1.0';

export type Method = 'hello' | 'analyze';
export const METHODS: readonly Method[] = ['hello', 'analyze'];

export interface Request {
  protocol: number;
  id: string;
  method: Method;
  params: Record<string, unknown>;
}

export interface ErrorBody {
  code: 'bad_request' | 'unsupported_protocol' | 'unknown_method' | 'not_found' | 'not_a_repository' | 'internal';
  message: string;
}

export type Response =
  | { protocol: number; id: string; ok: true; result: unknown }
  | { protocol: number; id: string | null; ok: false; error: ErrorBody };

export class HelperError extends Error {
  constructor(public code: ErrorBody['code'], message: string) {
    super(message);
  }
}

export function parseRequest(line: string): Request {
  let raw: unknown;
  try {
    raw = JSON.parse(line);
  } catch {
    throw new HelperError('bad_request', 'Request is not valid JSON');
  }
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new HelperError('bad_request', 'Request must be an object');
  const r = raw as Record<string, unknown>;
  if (r.protocol !== PROTOCOL_VERSION) throw new HelperError('unsupported_protocol', `Expected protocol ${PROTOCOL_VERSION}, got ${String(r.protocol)}`);
  if (typeof r.id !== 'string' || !r.id) throw new HelperError('bad_request', 'Request id must be a non-empty string');
  if (typeof r.method !== 'string' || !METHODS.includes(r.method as Method)) throw new HelperError('unknown_method', `Unknown method ${String(r.method)}`);
  const params = r.params ?? {};
  if (typeof params !== 'object' || Array.isArray(params)) throw new HelperError('bad_request', 'params must be an object');
  return { protocol: PROTOCOL_VERSION, id: r.id, method: r.method as Method, params: params as Record<string, unknown> };
}

export function requireString(params: Record<string, unknown>, key: string): string {
  const v = params[key];
  if (typeof v !== 'string' || !v) throw new HelperError('bad_request', `params.${key} must be a non-empty string`);
  return v;
}

export function optionalString(params: Record<string, unknown>, key: string): string | undefined {
  const v = params[key];
  if (v === undefined || v === null) return undefined;
  if (typeof v !== 'string') throw new HelperError('bad_request', `params.${key} must be a string`);
  return v;
}

