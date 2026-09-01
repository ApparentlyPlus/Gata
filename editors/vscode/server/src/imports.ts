import * as fs from 'fs';
import * as path from 'path';

import { Lexer } from './lexer';
import { TK } from './token';
import {
  Declarations, External, collectDeclarations, emptyExternal,
} from './semtokens';
import { GataSymbol, symbolsOf } from './symbols';
import { GataSettings, findGconf, detectLibgata } from './semantic';

export interface ImportRef {
  name: string;
  isPath: boolean;
}

export interface ImportIndex {
  external: External;
  symbols: GataSymbol[];
  files: string[];
}

export const emptyIndex = (): ImportIndex => ({ external: emptyExternal(), symbols: [], files: [] });

const FILE_BUDGET = 512;

export function importsOf(text: string): ImportRef[] {
  const tokens = new Lexer(text).tokenizeLenient();
  const out: ImportRef[] = [];
  for (let i = 0; i < tokens.length; i++) {
    if (tokens[i].kind !== TK.Import) continue;
    const next = tokens[i + 1];
    if (!next) continue;
    if (next.kind === TK.Ident && next.value.length > 0) out.push({ name: next.value, isPath: false });
    else if (next.kind === TK.StrLit) {
      const literal = unquote(next.value);
      if (literal.length > 0) out.push({ name: literal, isPath: true });
    }
  }
  return out;
}

function unquote(literal: string): string {
  const body = literal.startsWith('"') ? literal.slice(1, literal.endsWith('"') ? -1 : undefined) : literal;
  return body.replace(/\\(.)/g, '$1');
}

export interface ResolveContext {
  projectRoot?: string;
  stdlibDir?: string;
}

export function resolveContext(filePath: string, settings: GataSettings): ResolveContext {
  const gconf = findGconf(path.dirname(filePath));
  const projectRoot = gconf ? path.dirname(gconf) : undefined;

  const candidates: string[] = [];
  if (settings.libgataPath) candidates.push(settings.libgataPath);
  if (projectRoot) candidates.push(path.join(projectRoot, 'selfhostlib'), path.join(projectRoot, 'libgata'));
  const detected = detectLibgata(projectRoot ?? path.dirname(filePath));
  if (detected) candidates.push(detected);

  const stdlibDir = candidates.find(isDirectory);
  return { projectRoot, stdlibDir };
}

function isDirectory(p: string): boolean {
  try { return fs.statSync(p).isDirectory(); } catch { return false; }
}

function resolveImport(ref: ImportRef, ctx: ResolveContext, fromFile: string): string | undefined {
  if (ref.isPath) {
    const roots = [ctx.projectRoot, path.dirname(fromFile)].filter((r): r is string => !!r);
    for (const root of roots) {
      const candidate = path.resolve(root, ref.name);
      if (isFile(candidate)) return candidate;
    }
    return undefined;
  }
  if (!ctx.stdlibDir) return undefined;
  const candidate = path.join(ctx.stdlibDir, ref.name + '.g');
  return isFile(candidate) ? candidate : undefined;
}

function isFile(p: string): boolean {
  try { return fs.statSync(p).isFile(); } catch { return false; }
}

interface CachedFile {
  mtimeMs: number;
  size: number;
  decls: Declarations;
  symbols: GataSymbol[];
  imports: ImportRef[];
}

const cache = new Map<string, CachedFile>();

function readFile(file: string): CachedFile | undefined {
  let stat: fs.Stats;
  try { stat = fs.statSync(file); } catch { return undefined; }
  const hit = cache.get(file);
  if (hit && hit.mtimeMs === stat.mtimeMs && hit.size === stat.size) return hit;

  let text: string;
  try { text = fs.readFileSync(file, 'utf8'); } catch { return undefined; }

  const entry: CachedFile = {
    mtimeMs: stat.mtimeMs,
    size: stat.size,
    decls: collectDeclarations(new Lexer(text).tokenizeLenient()),
    symbols: symbolsOf(text),
    imports: importsOf(text),
  };
  cache.set(file, entry);
  return entry;
}

export function forgetFile(file: string): void {
  cache.delete(file);
}

export function indexFor(filePath: string, text: string, settings: GataSettings): ImportIndex {
  const ctx = resolveContext(filePath, settings);
  const index = emptyIndex();

  const visited = new Set<string>([path.resolve(filePath)]);
  const queue: Array<{ file: string; refs: ImportRef[] }> = [{ file: filePath, refs: importsOf(text) }];

  while (queue.length > 0 && index.files.length < FILE_BUDGET) {
    const { file, refs } = queue.shift()!;
    for (const ref of refs) {
      const resolved = resolveImport(ref, ctx, file);
      if (!resolved || visited.has(resolved)) continue;
      visited.add(resolved);

      const entry = readFile(resolved);
      if (!entry) continue;

      index.files.push(resolved);
      merge(index, entry.decls, entry.symbols, isUnder(resolved, ctx.stdlibDir));
      queue.push({ file: resolved, refs: entry.imports });
      if (index.files.length >= FILE_BUDGET) break;
    }
  }

  return index;
}

function isUnder(file: string, dir: string | undefined): boolean {
  if (!dir) return false;
  const rel = path.relative(path.resolve(dir), path.resolve(file));
  return rel.length > 0 && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function merge(index: ImportIndex, d: Declarations, symbols: GataSymbol[], library: boolean): void {
  const ext = index.external;
  for (const name of d.classes) ext.classes.add(name);
  for (const name of d.enums) ext.enums.add(name);
  for (const name of d.unions) ext.unions.add(name);
  for (const name of d.functions) ext.functions.add(name);
  for (const name of d.namespaces) ext.namespaces.add(name);
  for (const name of d.enumMembers) ext.members.add(name);
  for (const name of d.variants) ext.members.add(name);

  if (library) {
    for (const name of d.classes) ext.library.add(name);
    for (const name of d.enums) ext.library.add(name);
    for (const name of d.unions) ext.library.add(name);
    for (const name of d.functions) ext.library.add(name);
  }

  for (const sym of symbols) index.symbols.push(sym);
}
