// CodebaseGraph → Giotto diagram document, rendered with Giotto's own renderer.
import { toSvg, layoutWarnings } from 'giotto/render';
import type { CodebaseGraph, ComponentType, GraphNode } from '../analysis/types.js';

export const MAX_SHOWN = 45;

export interface Highlight {
  added?: string[];
  modified?: string[];
  removed?: { id: string; name: string; type: ComponentType }[];
  addedEdges?: string[];
}

export interface Planned {
  id: string;
  name: string;
  type: ComponentType;
  connectsTo?: string[];
}

export interface DiagramOptions {
  title?: string;
  highlight?: Highlight;
  planned?: Planned[];
  showTests?: boolean;
  dark?: boolean;
}

const ORDER = ['Frontend', 'Entry points', 'API', 'Services', 'Modules', 'Data', 'External', 'Tests'];
const TONE: Record<ComponentType, string> = {
  frontend: 'frontend', api: 'api', service: 'service', database: 'data', entry: 'entry', library: 'module',
  test: 'module', config: 'module', external: 'external',
};

// Refine's dark look: near-black surfaces, restrained purple accent; diff tones stand out on top.
export const REFINE_STYLE = {
  name: 'Refine',
  radius: 12,
  fontSize: 14,
  maxLabelWidth: 220,
  arrowRoute: 'auto',
  accent: '#a78bfa',
  tones: {
    frontend: { fill: '#e0e7ff', stroke: '#6366f1', text: '#312e81' },
    api: { fill: '#ffedd5', stroke: '#f97316', text: '#7c2d12' },
    service: { fill: '#ede9fe', stroke: '#8b5cf6', text: '#4c1d95' },
    data: { fill: '#dcfce7', stroke: '#22c55e', text: '#14532d' },
    entry: { fill: '#fef3c7', stroke: '#f59e0b', text: '#78350f' },
    module: { fill: '#f1f5f9', stroke: '#94a3b8', text: '#334155' },
    external: { fill: '#f8fafc', stroke: '#cbd5e1', text: '#475569' },
    added: { fill: '#bbf7d0', stroke: '#16a34a', text: '#052e16' },
    modified: { fill: '#fde68a', stroke: '#d97706', text: '#451a03' },
    removed: { fill: '#fee2e2', stroke: '#dc2626', text: '#7f1d1d' },
    planned: { fill: '#f5f3ff', stroke: '#a78bfa', text: '#5b21b6' },
  },
  dark: {
    background: '#0e0d13',
    grid: null,
    fill: '#17151f',
    text: '#ece9f5',
    stroke: '#5b566b',
    arrowColor: '#6f6984',
    groupFill: '#131119',
    groupStroke: '#2a2636',
    accent: '#a78bfa',
    tagFill: '#221f2d',
    tagText: '#c4bdd9',
    tones: {
      frontend: { fill: '#1b1d3a', stroke: '#818cf8', text: '#e0e7ff' },
      api: { fill: '#2d1c10', stroke: '#fb923c', text: '#ffedd5' },
      service: { fill: '#231a3d', stroke: '#a78bfa', text: '#ede9fe' },
      data: { fill: '#112a1c', stroke: '#4ade80', text: '#dcfce7' },
      entry: { fill: '#2e2410', stroke: '#fbbf24', text: '#fef3c7' },
      module: { fill: '#1c1b24', stroke: '#6b6680', text: '#e2e0ea' },
      external: { fill: '#15141b', stroke: '#4a4658', text: '#bdb8cc' },
      added: { fill: '#0f3a22', stroke: '#4ade80', text: '#dcfce7' },
      modified: { fill: '#3a2c0a', stroke: '#facc15', text: '#fef9c3' },
      removed: { fill: '#3b1212', stroke: '#f87171', text: '#fee2e2' },
      planned: { fill: '#1a1530', stroke: '#c4b5fd', text: '#ede9fe' },
    },
  },
};

const safeId = (id: string) => {
  const s = id.toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'n';
  return /^[a-z0-9]/.test(s) ? s : `n${s}`;
};

/** Picks the most connected components when there are too many to draw legibly. */
export function selectNodes(graph: CodebaseGraph, showTests: boolean, keep: Set<string>): { shown: GraphNode[]; hidden: number } {
  const degree = new Map<string, number>();
  for (const e of graph.edges) {
    degree.set(e.source, (degree.get(e.source) ?? 0) + 1);
    degree.set(e.target, (degree.get(e.target) ?? 0) + 1);
  }
  const candidates = graph.nodes.filter((n) => showTests || n.type !== 'test');
  if (candidates.length <= MAX_SHOWN) return { shown: candidates, hidden: graph.nodes.length - candidates.length };
  const ranked = [...candidates].sort((a, b) => Number(keep.has(b.id)) - Number(keep.has(a.id)) || (degree.get(b.id) ?? 0) - (degree.get(a.id) ?? 0) || b.files.length - a.files.length);
  const shown = ranked.slice(0, MAX_SHOWN);
  return { shown, hidden: graph.nodes.length - shown.length };
}

export function toDiagram(graph: CodebaseGraph, opts: DiagramOptions = {}) {
  const hl = opts.highlight ?? {};
  const added = new Set(hl.added ?? []), modified = new Set(hl.modified ?? []), addedEdges = new Set(hl.addedEdges ?? []);
  const { shown, hidden } = selectNodes(graph, !!opts.showTests, new Set([...added, ...modified]));
  const ids = new Map<string, string>(); // graph id -> diagram id
  const taken = new Set<string>(['root', 'legend']);
  const idFor = (gid: string) => {
    if (ids.has(gid)) return ids.get(gid)!;
    let base = safeId(gid), id = base, i = 2;
    while (taken.has(id)) id = `${base}-${i++}`;
    taken.add(id);
    ids.set(gid, id);
    return id;
  };

  const elements: Record<string, unknown>[] = [];
  const groups = new Map<string, string[]>();
  const box = (gid: string, name: string, type: ComponentType, subtitle: string, tone: string, extra: Record<string, unknown> = {}) => {
    const id = idFor(gid);
    const shape = type === 'database' || (type === 'external' && /sql|db|redis|mongo|postgres|prisma|grdb|data/i.test(name)) ? 'cylinder' : 'rectangle';
    elements.push({ id, type: shape, tone, content: [{ type: 'title', text: name }, { type: 'text', text: subtitle }], ...extra });
    return id;
  };

  for (const n of shown) {
    const tone = added.has(n.id) ? 'added' : modified.has(n.id) ? 'modified' : TONE[n.type];
    const subtitle = n.type === 'external' ? 'dependency' : `${n.type} · ${n.files.length} file${n.files.length === 1 ? '' : 's'}${n.routes.length ? ` · ${n.routes.length} route${n.routes.length === 1 ? '' : 's'}` : ''}`;
    const tags = added.has(n.id) ? ['added'] : modified.has(n.id) ? ['modified'] : undefined;
    const id = box(n.id, n.name, n.type, subtitle, tone, tags ? { tags } : {});
    const g = n.group || 'Modules';
    if (!groups.has(g)) groups.set(g, []);
    groups.get(g)!.push(id);
  }
  for (const r of hl.removed ?? []) {
    const id = box(r.id, r.name, r.type, 'removed', 'removed', { strokeStyle: 'dashed', tags: ['removed'] });
    if (!groups.has('Removed')) groups.set('Removed', []);
    groups.get('Removed')!.push(id);
  }
  for (const p of opts.planned ?? []) {
    const id = box(`planned:${p.id}`, p.name, p.type, 'planned · not implemented', 'planned', { strokeStyle: 'dashed', tags: ['planned'] });
    if (!groups.has('Planned (not implemented)')) groups.set('Planned (not implemented)', []);
    groups.get('Planned (not implemented)')!.push(id);
  }

  const groupIds: string[] = [];
  const order = [...ORDER, 'Removed', 'Planned (not implemented)'];
  for (const name of [...groups.keys()].sort((a, b) => (order.indexOf(a) + 99) % 99 - (order.indexOf(b) + 99) % 99)) {
    const children = groups.get(name)!;
    const gid = idFor(`group:${name}`);
    groupIds.push(gid);
    const columns = Math.ceil(children.length / 7);
    elements.push({
      id: gid, type: 'group', label: { title: name }, children,
      layout: columns > 1 ? { direction: 'grid', columns, gap: 18, align: 'stretch' } : { direction: 'column', gap: 18, align: 'stretch' },
      ...(name.startsWith('Planned') || name === 'Removed' ? { strokeStyle: 'dashed' } : {}),
    });
  }
  elements.unshift({ id: 'root', type: 'group', x: 0, y: 0, children: groupIds, layout: { direction: 'row', gap: 70, align: 'start' } });

  const shownIds = new Set(shown.map((n) => n.id));
  for (const e of graph.edges) {
    if (!shownIds.has(e.source) || !shownIds.has(e.target)) continue;
    const label = e.relation === 'calls-api' ? 'calls API' : e.relation === 'uses-database' ? 'data' : undefined;
    elements.push({
      id: idFor(`edge:${e.id}`), type: 'arrow', start: { id: ids.get(e.source) }, end: { id: ids.get(e.target) },
      ...(e.verification === 'inferred' ? { strokeStyle: 'dashed' } : e.verification === 'unknown' ? { strokeStyle: 'dotted' } : {}),
      ...(addedEdges.has(e.id) ? { strokeColor: '#4ade80' } : {}),
      ...(label ? { label: { text: label } } : {}),
    });
  }
  for (const p of opts.planned ?? []) {
    for (const target of p.connectsTo ?? []) {
      if (!ids.has(target)) continue;
      elements.push({ id: idFor(`edge:planned:${p.id}->${target}`), type: 'arrow', start: { id: ids.get(`planned:${p.id}`) }, end: { id: ids.get(target) }, strokeStyle: 'dotted' });
    }
  }

  const legend: { tone: string; text: string }[] = [];
  const usedTones = new Set(elements.map((e) => e.tone).filter(Boolean) as string[]);
  const legendText: Record<string, string> = {
    frontend: 'frontend', api: 'API / routes', service: 'service', data: 'data / models', entry: 'entry point', module: 'module',
    external: 'external dependency', added: 'added since last verified', modified: 'modified since last verified', removed: 'removed', planned: 'planned, not implemented',
  };
  for (const t of Object.keys(legendText)) if (usedTones.has(t)) legend.push({ tone: t, text: legendText[t] });

  const doc = {
    title: opts.title ?? 'Architecture',
    subtitle: `${graph.nodes.length} components · ${graph.edges.length} relationships${hidden ? ` · ${hidden} not shown` : ''} · dashed arrows are inferred`,
    elements,
    legend: { title: 'Legend', items: legend },
  };
  const elementIds = Object.fromEntries([...ids].filter(([g]) => !g.startsWith('group:') && !g.startsWith('edge:')).map(([g, d]) => [d, g]));
  return { doc, elementIds, hidden };
}

export function renderDiagram(graph: CodebaseGraph, opts: DiagramOptions = {}) {
  const { doc, elementIds, hidden } = toDiagram(graph, opts);
  const svg = toSvg(doc, REFINE_STYLE, { dark: opts.dark ?? true });
  const warnings = layoutWarnings(doc, REFINE_STYLE).filter((w: string) => !/runs through/.test(w)).slice(0, 10);
  return { doc, svg, elementIds, hidden, warnings };
}
