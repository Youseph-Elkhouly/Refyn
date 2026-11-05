import ts from 'typescript';
import type { FileFacts } from './types.js';

type Facts = Pick<FileFacts, 'imports' | 'symbols' | 'routes' | 'models' | 'apiCalls' | 'entry' | 'jsx'>;

const HTTP_METHODS = new Set(['get', 'post', 'put', 'patch', 'delete', 'options', 'head', 'all']);
const ROUTERS = new Set(['app', 'router', 'server', 'api', 'routes', 'fastify', 'hono']);
const NEXT_HANDLERS = new Set(['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', 'HEAD']);

/** Parses (never runs) a TypeScript or JavaScript file with the TypeScript compiler's parser. */
export function extractTs(path: string, text: string): Facts {
  const kind = path.endsWith('x') ? ts.ScriptKind.TSX : path.match(/\.(m|c)?js$/) ? ts.ScriptKind.JS : ts.ScriptKind.TS;
  const sf = ts.createSourceFile(path, text, ts.ScriptTarget.Latest, true, kind);
  const facts: Facts = { imports: [], symbols: [], routes: [], models: [], apiCalls: [], entry: null, jsx: false };
  const line = (node: ts.Node) => sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1;
  const exported = (node: ts.Node) => !!(ts.canHaveModifiers(node) && ts.getModifiers(node)?.some((m) => m.kind === ts.SyntaxKind.ExportKeyword));
  const literal = (node: ts.Node | undefined) => (node && (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) ? node.text : null);

  const visit = (node: ts.Node, depth: number) => {
    if (ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) {
      const spec = node.moduleSpecifier && literal(node.moduleSpecifier);
      if (spec) facts.imports.push({ spec, line: line(node), kind: 'static' });
    } else if (ts.isImportEqualsDeclaration(node) && ts.isExternalModuleReference(node.moduleReference)) {
      const spec = literal(node.moduleReference.expression);
      if (spec) facts.imports.push({ spec, line: line(node), kind: 'require' });
    } else if (ts.isCallExpression(node)) {
      const callee = node.expression;
      if (callee.kind === ts.SyntaxKind.ImportKeyword) {
        const spec = literal(node.arguments[0]);
        if (spec) facts.imports.push({ spec, line: line(node), kind: 'dynamic' });
      } else if (ts.isIdentifier(callee) && callee.text === 'require') {
        const spec = literal(node.arguments[0]);
        if (spec) facts.imports.push({ spec, line: line(node), kind: 'require' });
      } else if (ts.isPropertyAccessExpression(callee)) {
        const method = callee.name.text.toLowerCase();
        const target = callee.expression;
        const targetName = ts.isIdentifier(target) ? target.text.toLowerCase() : '';
        const first = literal(node.arguments[0]);
        if (HTTP_METHODS.has(method) && first?.startsWith('/') && (ROUTERS.has(targetName) || targetName.endsWith('router'))) {
          facts.routes.push({ method: method.toUpperCase(), path: first, line: line(node), framework: 'express-style' });
        } else if (HTTP_METHODS.has(method) && first?.startsWith('/') && ['axios', 'http', 'client', 'api'].includes(targetName)) {
          facts.apiCalls.push({ path: first, line: line(node) });
        } else if (targetName === 'mongoose' && method === 'model') {
          if (first) facts.models.push({ name: first, line: line(node), orm: 'mongoose' });
        } else if (method === 'define' && targetName === 'sequelize' && first) {
          facts.models.push({ name: first, line: line(node), orm: 'sequelize' });
        }
      } else if (ts.isIdentifier(callee) && callee.text === 'fetch') {
        const first = literal(node.arguments[0]) ?? templateHead(node.arguments[0]);
        if (first?.startsWith('/')) facts.apiCalls.push({ path: first, line: line(node) });
      } else if (ts.isIdentifier(callee) && ['pgTable', 'sqliteTable', 'mysqlTable'].includes(callee.text)) {
        const first = literal(node.arguments[0]);
        if (first) facts.models.push({ name: first, line: line(node), orm: 'drizzle' });
      }
    } else if (ts.isJsxElement(node) || ts.isJsxSelfClosingElement(node) || ts.isJsxFragment(node)) {
      facts.jsx = true;
    }

    // Declarations, top level only (nested helpers are noise in an architecture view).
    if (depth === 0) {
      if (ts.isClassDeclaration(node) && node.name) {
        facts.symbols.push({ name: node.name.text, kind: 'class', line: line(node), exported: exported(node) });
        const decorators = ts.canHaveDecorators(node) ? ts.getDecorators(node) ?? [] : [];
        if (decorators.some((d) => /^@Entity\b/.test(d.getText(sf)))) facts.models.push({ name: node.name.text, line: line(node), orm: 'typeorm' });
      } else if (ts.isFunctionDeclaration(node) && node.name) {
        facts.symbols.push({ name: node.name.text, kind: 'function', line: line(node), exported: exported(node) });
        if (exported(node) && NEXT_HANDLERS.has(node.name.text) && /(^|\/)route\.(t|j)sx?$/.test(path)) {
          facts.routes.push({ method: node.name.text, path: nextRoutePath(path), line: line(node), framework: 'next' });
        }
      } else if (ts.isInterfaceDeclaration(node)) {
        facts.symbols.push({ name: node.name.text, kind: 'interface', line: line(node), exported: exported(node) });
      } else if (ts.isTypeAliasDeclaration(node)) {
        facts.symbols.push({ name: node.name.text, kind: 'type', line: line(node), exported: exported(node) });
      } else if (ts.isEnumDeclaration(node)) {
        facts.symbols.push({ name: node.name.text, kind: 'enum', line: line(node), exported: exported(node) });
      } else if (ts.isVariableStatement(node)) {
        for (const d of node.declarationList.declarations) {
          if (!ts.isIdentifier(d.name) || !d.initializer) continue;
          if (ts.isArrowFunction(d.initializer) || ts.isFunctionExpression(d.initializer)) {
            facts.symbols.push({ name: d.name.text, kind: 'function', line: line(d), exported: exported(node) });
            if (exported(node) && NEXT_HANDLERS.has(d.name.text) && /(^|\/)route\.(t|j)sx?$/.test(path)) {
              facts.routes.push({ method: d.name.text, path: nextRoutePath(path), line: line(d), framework: 'next' });
            }
          }
        }
      } else if (ts.isExportAssignment(node) && /(^|\/)pages\/api\//.test(path)) {
        facts.routes.push({ method: 'ANY', path: nextPagesApiPath(path), line: line(node), framework: 'next-pages' });
      }
    }
    const nested = depth + (ts.isFunctionLike(node) || ts.isClassLike(node) || ts.isBlock(node) ? 1 : 0);
    ts.forEachChild(node, (child) => visit(child, nested));
  };
  ts.forEachChild(sf, (child) => visit(child, 0));
  return facts;
}

function templateHead(node: ts.Node | undefined): string | null {
  return node && ts.isTemplateExpression(node) ? node.head.text : null;
}

function nextRoutePath(path: string): string {
  const parts = path.split('/');
  const app = parts.lastIndexOf('app');
  const segs = parts.slice(app + 1, -1).filter((s) => !/^\(.*\)$/.test(s) && !s.startsWith('@'));
  return '/' + segs.join('/');
}

function nextPagesApiPath(path: string): string {
  const after = path.slice(path.indexOf('pages/api/') + 'pages/'.length).replace(/\.(t|j)sx?$/, '').replace(/\/index$/, '');
  return '/' + after;
}
