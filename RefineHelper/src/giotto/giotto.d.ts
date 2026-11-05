// Giotto ships plain JavaScript; these are the parts Refine uses.
declare module 'giotto/render' {
  export function toSvg(doc: unknown, style: unknown, options?: { dark?: boolean }): string;
  export function layoutWarnings(doc: unknown, style: unknown, ids?: string[]): string[];
}
