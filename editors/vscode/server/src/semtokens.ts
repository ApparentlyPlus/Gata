// Semantic classification of a Gata file, over the same token stream the parser reads.
//
// A TextMate grammar can only guess at an identifier from its shape. This walks the file
// once to learn what each name was declared as, then walks it again to label every use, so
// a generic parameter is a generic parameter because it was declared as one, a call is a
// call because something with that name is a function, and a member is a member because of
// what sits to the left of the dot. The editor paints these on top of the grammar.
import { Lexer } from './lexer';
import { TK, Token } from './token';

/** The legend, in the order the LSP encodes them. Kept in sync with server.ts. */
export const TOKEN_TYPES = [
  'namespace',
  'class',
  'enum',
  'struct',
  'typeParameter',
  'parameter',
  'variable',
  'property',
  'enumMember',
  'function',
  'method',
  'macro',
  'type',
] as const;

export const TOKEN_MODIFIERS = ['declaration', 'defaultLibrary'] as const;

type TokenType = typeof TOKEN_TYPES[number];

const TYPE_INDEX = new Map<TokenType, number>(TOKEN_TYPES.map((t, i) => [t, i]));
const MOD_DECLARATION = 1 << 0;
const MOD_DEFAULT_LIBRARY = 1 << 1;

export interface SemanticToken {
  start: number;
  length: number;
  type: number;
  modifiers: number;
}

const LIBGATA = new Set([
  'Algorithms', 'Char', 'Console', 'Format', 'Hash', 'Int', 'List', 'Long', 'Map', 'Math',
  'Mem', 'Misc', 'Optional', 'PriorityQueue', 'Process', 'Queue', 'Random', 'Runtime', 'Set',
  'Stack', 'String', 'StringBuilder', 'Sync', 'Sys', 'Thread', 'Time',
]);

interface Declarations {
  classes: Set<string>;
  enums: Set<string>;
  unions: Set<string>;
  variants: Set<string>;
  enumMembers: Set<string>;
  functions: Set<string>;
  typeParams: Set<string>;
  namespaces: Set<string>;
}

function emptyDeclarations(): Declarations {
  return {
    classes: new Set(), enums: new Set(), unions: new Set(), variants: new Set(),
    enumMembers: new Set(), functions: new Set(), typeParams: new Set(), namespaces: new Set(),
  };
}

export function classify(text: string): SemanticToken[] {
  const tokens = new Lexer(text).tokenizeLenient();
  return label(tokens, collect(tokens));
}

function isIdent(t: Token): boolean {
  return t.kind === TK.Ident;
}

function valueIs(t: Token, word: string): boolean {
  return t.kind === TK.Ident && t.value === word;
}

function nativeTypeName(t: Token): string {
  const sep = t.value.indexOf('\x1F');
  return sep < 0 ? t.value : t.value.slice(0, sep);
}

function collect(tokens: Token[]): Declarations {
  const d = emptyDeclarations();

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];

    switch (t.kind) {
      case TK.Class:
      case TK.Module: {
        if (isIdent(tokens[i + 1])) {
          d.classes.add(tokens[i + 1].value);
          collectGenericParams(tokens, i + 2, d);
        }
        break;
      }
      case TK.Enum: {
        if (isIdent(tokens[i + 1])) {
          d.enums.add(tokens[i + 1].value);
          collectEnumMembers(tokens, i + 2, d);
        }
        break;
      }
      case TK.Union: {
        if (isIdent(tokens[i + 1])) {
          d.unions.add(tokens[i + 1].value);
          const afterParams = collectGenericParams(tokens, i + 2, d);
          collectVariants(tokens, afterParams, d);
        }
        break;
      }
      case TK.Func: {
        if (isIdent(tokens[i + 1])) {
          d.functions.add(tokens[i + 1].value);
          collectGenericParams(tokens, i + 2, d);
        }
        break;
      }
      case TK.NativeTypeDecl: {
        const name = nativeTypeName(t);
        if (name.length > 0) d.classes.add(name);
        break;
      }
      default:
        break;
    }

    if ((valueIs(t, 'process') || valueIs(t, 'thread')) && isIdent(tokens[i + 1])) d.namespaces.add(tokens[i + 1].value);
  }

  return d;
}

function collectDeclarationParens(tokens: Token[]): Set<number> {
  const out = new Set<number>();

  const skipBrackets = (n: number): number => {
    if (tokens[n]?.kind !== TK.LBrack) return n;
    let depth = 0;
    while (n < tokens.length && tokens[n].kind !== TK.EOF) {
      if (tokens[n].kind === TK.LBrack) depth++;
      else if (tokens[n].kind === TK.RBrack && --depth === 0) return n + 1;
      n++;
    }
    return n;
  };

  for (let i = 0; i < tokens.length; i++) {
    const k = tokens[i].kind;

    if (k === TK.Func) {
      if (tokens[i + 1]?.kind === TK.LParen) continue;
      let n = i + 1;
      if (tokens[n]?.kind === TK.Ident) n++;
      n = skipBrackets(n);
      if (tokens[n]?.kind === TK.LParen) out.add(n);
      continue;
    }

    if (k === TK.Operator) {
      let n = i + 1;
      const limit = Math.min(tokens.length, i + 12);
      while (n < limit && tokens[n].kind !== TK.Func) n++;
      while (n < limit && tokens[n].kind !== TK.LParen) n++;
      if (tokens[n]?.kind === TK.LParen) out.add(n);
      continue;
    }

    if (k === TK.Union) {
      let n = i + 1;
      if (tokens[n]?.kind === TK.Ident) n++;
      n = skipBrackets(n);
      if (tokens[n]?.kind !== TK.LBrace) continue;
      let expectVariant = true;
      for (n++; n < tokens.length && tokens[n].kind !== TK.RBrace && tokens[n].kind !== TK.EOF; n++) {
        if (tokens[n].kind === TK.Comma) { expectVariant = true; continue; }
        if (expectVariant && tokens[n].kind === TK.Ident && tokens[n + 1]?.kind === TK.LParen) out.add(n + 1);
        expectVariant = false;
      }
    }
  }

  return out;
}

function collectGenericParams(tokens: Token[], i: number, d: Declarations): number {
  if (tokens[i]?.kind !== TK.LBrack) return i;
  let n = i + 1;
  while (n < tokens.length && tokens[n].kind !== TK.RBrack && tokens[n].kind !== TK.EOF) {
    if (isIdent(tokens[n])) d.typeParams.add(tokens[n].value);
    n++;
  }
  return n + 1;
}

function collectEnumMembers(tokens: Token[], i: number, d: Declarations): void {
  if (tokens[i]?.kind !== TK.LBrace) return;
  let expectMember = true;
  for (let n = i + 1; n < tokens.length && tokens[n].kind !== TK.RBrace && tokens[n].kind !== TK.EOF; n++) {
    if (tokens[n].kind === TK.Comma) { expectMember = true; continue; }
    if (expectMember && isIdent(tokens[n])) d.enumMembers.add(tokens[n].value);
    expectMember = false;
  }
}

function collectVariants(tokens: Token[], i: number, d: Declarations): void {
  if (tokens[i]?.kind !== TK.LBrace) return;
  let expectVariant = true;
  let depth = 0;
  for (let n = i + 1; n < tokens.length && tokens[n].kind !== TK.EOF; n++) {
    const k = tokens[n].kind;
    if (k === TK.LParen) { depth++; continue; }
    if (k === TK.RParen) { depth--; continue; }
    if (k === TK.RBrace && depth === 0) break;
    if (depth > 0) continue;
    if (k === TK.Comma) { expectVariant = true; continue; }
    if (expectVariant && isIdent(tokens[n])) d.variants.add(tokens[n].value);
    expectVariant = false;
  }
}

function label(tokens: Token[], d: Declarations): SemanticToken[] {
  const labels = new Array<{ type: TokenType; modifiers: number } | undefined>(tokens.length);
  const declParens = collectDeclarationParens(tokens);

  const set = (i: number, type: TokenType, modifiers = 0) => {
    if (i < 0 || i >= tokens.length) return;
    if (tokens[i].kind !== TK.Ident && tokens[i].kind !== TK.Kernel && tokens[i].kind !== TK.Userspace) return;
    labels[i] = { type, modifiers };
  };

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    switch (t.kind) {
      case TK.Class:
      case TK.Module:
        set(i + 1, 'class', MOD_DECLARATION);
        markGenericParams(tokens, i + 2, labels);
        break;
      case TK.Enum:
        set(i + 1, 'enum', MOD_DECLARATION);
        break;
      case TK.Union: {
        set(i + 1, 'struct', MOD_DECLARATION);
        const afterParams = markGenericParams(tokens, i + 2, labels);
        markVariants(tokens, afterParams, labels);
        break;
      }
      case TK.Func:
        if (isIdent(tokens[i + 1])) {
          set(i + 1, 'function', MOD_DECLARATION);
          markGenericParams(tokens, i + 2, labels);
        }
        break;
      case TK.Let:
        markLetName(tokens, i, labels);
        break;
      case TK.For:
        if (isIdent(tokens[i + 1]) && tokens[i + 2]?.kind === TK.In) set(i + 1, 'variable', MOD_DECLARATION);
        break;
      case TK.Case:
        markMatchCase(tokens, i, labels);
        break;
      default:
        break;
    }

    if (valueIs(t, 'process') || valueIs(t, 'thread')) set(i + 1, 'namespace', MOD_DECLARATION);
    if (t.kind === TK.Realm && (tokens[i + 1]?.kind === TK.Kernel || tokens[i + 1]?.kind === TK.Userspace))
      labels[i + 1] = { type: 'namespace', modifiers: MOD_DECLARATION };
    if (t.kind === TK.LParen && declParens.has(i)) markParameters(tokens, i, labels);
  }

  // Uses.
  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];

    if (t.kind === TK.Kernel || t.kind === TK.Userspace) {
      if (!labels[i] && tokens[i + 1]?.kind === TK.Dot) labels[i] = { type: 'namespace', modifiers: 0 };
      continue;
    }
    if (t.kind !== TK.Ident || labels[i]) continue;
    if (t.value === 'self') continue;                 // the grammar gives this its own color
    if (valueIs(t, 'process') || valueIs(t, 'thread') || valueIs(t, 'native')) continue;

    const prev = tokens[i - 1];
    const next = tokens[i + 1];

    if (prev?.kind === TK.Dot) {
      const owner = tokens[i - 2];
      if (next?.kind === TK.LParen) { labels[i] = { type: 'method', modifiers: 0 }; continue; }
      if (owner?.kind === TK.Ident && d.enums.has(owner.value) && d.enumMembers.has(t.value)) {
        labels[i] = { type: 'enumMember', modifiers: 0 };
        continue;
      }
      if (owner?.kind === TK.Ident && d.unions.has(owner.value) && d.variants.has(t.value)) {
        labels[i] = { type: 'enumMember', modifiers: 0 };
        continue;
      }
      labels[i] = { type: 'property', modifiers: 0 };
      continue;
    }

    if (d.typeParams.has(t.value)) { labels[i] = { type: 'typeParameter', modifiers: 0 }; continue; }

    const library = LIBGATA.has(t.value) ? MOD_DEFAULT_LIBRARY : 0;
    if (d.classes.has(t.value)) { labels[i] = { type: 'class', modifiers: library }; continue; }
    if (d.enums.has(t.value)) { labels[i] = { type: 'enum', modifiers: library }; continue; }
    if (d.unions.has(t.value)) { labels[i] = { type: 'struct', modifiers: library }; continue; }
    if (d.namespaces.has(t.value)) { labels[i] = { type: 'namespace', modifiers: 0 }; continue; }
    if (d.enumMembers.has(t.value) && !d.functions.has(t.value)) { labels[i] = { type: 'enumMember', modifiers: 0 }; continue; }

    if (next?.kind === TK.LParen) { labels[i] = { type: 'function', modifiers: library }; continue; }
    if (d.functions.has(t.value)) { labels[i] = { type: 'function', modifiers: library }; continue; }

    if (library !== 0) { labels[i] = { type: 'class', modifiers: library }; continue; }
    if (/^[A-Z]/.test(t.value) && (next?.kind === TK.LBrack || next?.kind === TK.Ident || prev?.kind === TK.New)) {
      labels[i] = { type: 'type', modifiers: 0 };
      continue;
    }
    labels[i] = { type: 'variable', modifiers: 0 };
  }

  for (let i = 0; i < tokens.length; i++) {
    const k = tokens[i].kind;
    if (k === TK.AtIntrinsic || k === TK.AtPreamble || k === TK.AtExtern || k === TK.AtEnvironment
      || k === TK.AtKeep || k === TK.AtBuiltin || k === TK.AtShadows)
      labels[i] = { type: 'macro', modifiers: 0 };
  }

  const out: SemanticToken[] = [];
  for (let i = 0; i < tokens.length; i++) {
    const l = labels[i];
    if (!l) continue;
    const span = tokens[i].span;
    if (span.length <= 0) continue;
    out.push({ start: span.start, length: span.length, type: TYPE_INDEX.get(l.type) ?? 0, modifiers: l.modifiers });
  }
  return out;
}

function markGenericParams(
  tokens: Token[],
  i: number,
  labels: Array<{ type: TokenType; modifiers: number } | undefined>,
): number {
  if (tokens[i]?.kind !== TK.LBrack) return i;
  let n = i + 1;
  for (; n < tokens.length && tokens[n].kind !== TK.RBrack && tokens[n].kind !== TK.EOF; n++)
    if (tokens[n].kind === TK.Ident) labels[n] = { type: 'typeParameter', modifiers: MOD_DECLARATION };
  return n + 1;
}

function markVariants(
  tokens: Token[],
  i: number,
  labels: Array<{ type: TokenType; modifiers: number } | undefined>,
): void {
  if (tokens[i]?.kind !== TK.LBrace) return;
  let expect = true;
  let depth = 0;
  for (let n = i + 1; n < tokens.length && tokens[n].kind !== TK.EOF; n++) {
    const k = tokens[n].kind;
    if (k === TK.LParen) { depth++; continue; }
    if (k === TK.RParen) { depth--; continue; }
    if (k === TK.RBrace && depth === 0) return;
    if (depth > 0) continue;
    if (k === TK.Comma) { expect = true; continue; }
    if (expect && k === TK.Ident) labels[n] = { type: 'enumMember', modifiers: MOD_DECLARATION };
    expect = false;
  }
}

function markLetName(
  tokens: Token[],
  i: number,
  labels: Array<{ type: TokenType; modifiers: number } | undefined>,
): void {
  let last = -1;
  for (let n = i + 1; n < tokens.length; n++) {
    const k = tokens[n].kind;
    if (k === TK.Eq || k === TK.Semi || k === TK.EOF || k === TK.LBrace || k === TK.RBrace) break;
    if (k === TK.Ident) last = n;
  }
  if (last >= 0) labels[last] = { type: 'variable', modifiers: MOD_DECLARATION };
}

function markMatchCase(
  tokens: Token[],
  i: number,
  labels: Array<{ type: TokenType; modifiers: number } | undefined>,
): void {
  if (tokens[i + 1]?.kind !== TK.Ident) return;
  const opens = tokens[i + 2]?.kind === TK.LParen;
  if (!opens && tokens[i + 2]?.kind !== TK.LBrace) return;
  labels[i + 1] = { type: 'enumMember', modifiers: 0 };
  if (!opens) return;
  for (let n = i + 3; n < tokens.length && tokens[n].kind !== TK.RParen && tokens[n].kind !== TK.EOF; n++)
    if (tokens[n].kind === TK.Ident) labels[n] = { type: 'variable', modifiers: MOD_DECLARATION };
}

function markParameters(
  tokens: Token[],
  open: number,
  labels: Array<{ type: TokenType; modifiers: number } | undefined>,
): void {
  let depth = 1;
  let last = -1;
  for (let n = open + 1; n < tokens.length && tokens[n].kind !== TK.EOF; n++) {
    const k = tokens[n].kind;
    if (k === TK.LParen || k === TK.LBrack) { depth++; continue; }
    if (k === TK.RBrack) { depth--; continue; }
    if (k === TK.RParen) {
      depth--;
      if (depth === 0) { if (last >= 0) labels[last] = { type: 'parameter', modifiers: MOD_DECLARATION }; return; }
      continue;
    }
    if (depth !== 1) continue;
    if (k === TK.Comma) {
      if (last >= 0) labels[last] = { type: 'parameter', modifiers: MOD_DECLARATION };
      last = -1;
      continue;
    }
    if (k === TK.Ident) last = n;
  }
}

