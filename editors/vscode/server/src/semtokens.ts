import { Lexer } from './lexer';
import { TK, Token } from './token';
import { Span } from './codes';

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

const ANNOTATION_WORD: ReadonlyMap<TK, string> = new Map([
  [TK.AtIntrinsic, '@intrinsic'],
  [TK.AtPreamble, '@preamble'],
  [TK.AtExtern, '@extern'],
  [TK.AtEnvironment, '@environment'],
  [TK.AtKeep, '@keep'],
  [TK.AtBuiltin, '@builtin'],
  [TK.AtShadows, '@shadows'],
]);

export interface Declarations {
  classes: Set<string>;
  enums: Set<string>;
  unions: Set<string>;
  variants: Set<string>;
  enumMembers: Set<string>;
  functions: Set<string>;
  typeParams: Set<string>;
  namespaces: Set<string>;
  imports: Set<string>;
}

export interface External {
  classes: Set<string>;
  enums: Set<string>;
  unions: Set<string>;
  functions: Set<string>;
  namespaces: Set<string>;
  members: Set<string>;
  library: Set<string>;
}

export function emptyDeclarations(): Declarations {
  return {
    classes: new Set(), enums: new Set(), unions: new Set(), variants: new Set(),
    enumMembers: new Set(), functions: new Set(), typeParams: new Set(), namespaces: new Set(),
    imports: new Set(),
  };
}

export function emptyExternal(): External {
  return {
    classes: new Set(), enums: new Set(), unions: new Set(), functions: new Set(),
    namespaces: new Set(), members: new Set(), library: new Set(),
  };
}

export function classify(text: string, external: External = emptyExternal()): SemanticToken[] {
  const tokens = new Lexer(text).tokenizeLenient();
  return label(tokens, collectDeclarations(tokens), external);
}

function isIdent(t: Token | undefined): boolean {
  return t?.kind === TK.Ident;
}

function valueIs(t: Token, word: string): boolean {
  return t.kind === TK.Ident && t.value === word;
}

export function nativeTypeName(t: Token): string {
  const sep = t.value.indexOf('\x1F');
  return sep < 0 ? t.value : t.value.slice(0, sep);
}

type Scope = 'type' | 'members' | 'topology' | 'block';

function scopeStack(tokens: Token[]): Array<Scope | undefined> {
  const at = new Array<Scope | undefined>(tokens.length);
  const stack: Scope[] = [];
  let pending: Scope | undefined;

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];

    if (t.kind === TK.LBrace) {
      at[i] = stack[stack.length - 1];
      stack.push(pending ?? 'block');
      pending = undefined;
      continue;
    }
    if (t.kind === TK.RBrace) {
      stack.pop();
      at[i] = stack[stack.length - 1];
      pending = undefined;
      continue;
    }

    at[i] = stack[stack.length - 1];

    switch (t.kind) {
      case TK.Class:
      case TK.Module:
        pending = 'type';
        break;
      case TK.Enum:
      case TK.Union:
        pending = 'members';
        break;
      case TK.Realm:
        pending = 'topology';
        break;
      case TK.Func:
      case TK.Operator:
        pending = 'block';
        break;
      default:
        if (valueIs(t, 'process') || valueIs(t, 'thread')) pending = 'topology';
        break;
    }
  }
  return at;
}

export function collectDeclarations(tokens: Token[]): Declarations {
  const d = emptyDeclarations();

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];

    switch (t.kind) {
      case TK.Import: {
        if (isIdent(tokens[i + 1])) d.imports.add(tokens[i + 1].value);
        break;
      }
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

function ownerBeforeDot(tokens: Token[], dot: number): Token | undefined {
  let n = dot - 1;
  if (tokens[n]?.kind === TK.RBrack) {
    let depth = 0;
    for (; n >= 0; n--) {
      if (tokens[n].kind === TK.RBrack) depth++;
      else if (tokens[n].kind === TK.LBrack && --depth === 0) { n--; break; }
    }
  }
  return n >= 0 ? tokens[n] : undefined;
}

type Label = { type: TokenType; modifiers: number } | undefined;

function label(tokens: Token[], d: Declarations, ext: External): SemanticToken[] {
  const labels = new Array<Label>(tokens.length);
  const declParens = collectDeclarationParens(tokens);
  const scopes = scopeStack(tokens);

  const set = (i: number, type: TokenType, modifiers = 0) => {
    if (i < 0 || i >= tokens.length) return;
    if (tokens[i].kind !== TK.Ident && tokens[i].kind !== TK.Kernel && tokens[i].kind !== TK.Userspace) return;
    labels[i] = { type, modifiers };
  };

  const isLibrary = (name: string): boolean => d.imports.has(name) || ext.library.has(name);

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
        markEnumMembers(tokens, i + 2, labels);
        break;
      case TK.Union: {
        set(i + 1, 'struct', MOD_DECLARATION);
        const afterParams = markGenericParams(tokens, i + 2, labels);
        markVariants(tokens, afterParams, labels);
        break;
      }
      case TK.Func:
        if (isIdent(tokens[i + 1])) {
          set(i + 1, scopes[i] === 'type' ? 'method' : 'function', MOD_DECLARATION);
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

  markFields(tokens, scopes, labels);

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
    const library = isLibrary(t.value) ? MOD_DEFAULT_LIBRARY : 0;

    if (prev?.kind === TK.Dot) {
      const owner = ownerBeforeDot(tokens, i - 1);
      const ownerName = owner?.kind === TK.Ident ? owner.value : undefined;
      if (ownerName !== undefined) {
        const isEnumOwner = d.enums.has(ownerName) || ext.enums.has(ownerName);
        const isUnionOwner = d.unions.has(ownerName) || ext.unions.has(ownerName);
        const known = d.enumMembers.has(t.value) || d.variants.has(t.value) || ext.members.has(t.value);
        if ((isEnumOwner || isUnionOwner) && known) { labels[i] = { type: 'enumMember', modifiers: 0 }; continue; }
      }
      labels[i] = { type: next?.kind === TK.LParen ? 'method' : 'property', modifiers: 0 };
      continue;
    }

    if (d.typeParams.has(t.value)) { labels[i] = { type: 'typeParameter', modifiers: 0 }; continue; }

    if (d.classes.has(t.value) || ext.classes.has(t.value)) { labels[i] = { type: 'class', modifiers: library }; continue; }
    if (d.enums.has(t.value) || ext.enums.has(t.value)) { labels[i] = { type: 'enum', modifiers: library }; continue; }
    if (d.unions.has(t.value) || ext.unions.has(t.value)) { labels[i] = { type: 'struct', modifiers: library }; continue; }
    if (d.namespaces.has(t.value) || ext.namespaces.has(t.value)) { labels[i] = { type: 'namespace', modifiers: 0 }; continue; }
    if (d.enumMembers.has(t.value) && !d.functions.has(t.value)) { labels[i] = { type: 'enumMember', modifiers: 0 }; continue; }

    if (next?.kind === TK.LParen) { labels[i] = { type: 'function', modifiers: library }; continue; }
    if (d.functions.has(t.value) || ext.functions.has(t.value)) { labels[i] = { type: 'function', modifiers: library }; continue; }

    // An imported module whose file could not be read still names a type, not a variable.
    if (d.imports.has(t.value)) { labels[i] = { type: 'class', modifiers: MOD_DEFAULT_LIBRARY }; continue; }

    if (/^[A-Z]/.test(t.value) && (next?.kind === TK.LBrack || next?.kind === TK.Ident || prev?.kind === TK.New)) {
      labels[i] = { type: 'type', modifiers: library };
      continue;
    }
    labels[i] = { type: 'variable', modifiers: 0 };
  }

  const out: SemanticToken[] = [];
  const push = (span: Span, l: Exclude<Label, undefined>) => {
    if (span.length <= 0) return;
    out.push({ start: span.start, length: span.length, type: TYPE_INDEX.get(l.type) ?? 0, modifiers: l.modifiers });
  };

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];

    const word = ANNOTATION_WORD.get(t.kind);
    if (word !== undefined) {
      push({ start: t.span.start, length: Math.min(word.length, t.span.length) }, { type: 'macro', modifiers: 0 });
      continue;
    }

    if (t.kind === TK.NativeTypeDecl) {
      if (t.nameSpan) push(t.nameSpan, { type: 'class', modifiers: MOD_DECLARATION });
      continue;
    }

    const l = labels[i];
    if (l) push(t.span, l);
  }
  return out;
}

const FIELD_HEAD: ReadonlySet<TK> = new Set([
  TK.LBrack, TK.RBrack, TK.Punct, TK.Public, TK.Private, TK.Static,
  TK.Kernel, TK.Userspace, TK.ColonColon, TK.Dot,
  TK.TBool, TK.TInt, TK.TChar, TK.TFloat, TK.TDouble, TK.TShort, TK.TVoid, TK.TPrim,
]);

function markFields(tokens: Token[], scopes: Array<Scope | undefined>, labels: Label[]): void {
  for (let i = 0; i < tokens.length; i++) {
    if (scopes[i] !== 'type') continue;
    const opener = tokens[i - 1]?.kind;
    if (i > 0 && opener !== TK.LBrace && opener !== TK.RBrace && opener !== TK.Semi) continue;

    let last = -1;
    for (let n = i; n < tokens.length; n++) {
      const k = tokens[n].kind;
      if (k === TK.Semi) {
        if (last >= 0 && !labels[last]) labels[last] = { type: 'property', modifiers: MOD_DECLARATION };
        break;
      }
      if (k === TK.Ident) { last = n; continue; }
      if (FIELD_HEAD.has(k)) continue;
      break;
    }
  }
}

function markGenericParams(tokens: Token[], i: number, labels: Label[]): number {
  if (tokens[i]?.kind !== TK.LBrack) return i;
  let n = i + 1;
  for (; n < tokens.length && tokens[n].kind !== TK.RBrack && tokens[n].kind !== TK.EOF; n++)
    if (tokens[n].kind === TK.Ident) labels[n] = { type: 'typeParameter', modifiers: MOD_DECLARATION };
  return n + 1;
}

function markEnumMembers(tokens: Token[], i: number, labels: Label[]): void {
  if (tokens[i]?.kind !== TK.LBrace) return;
  let expect = true;
  for (let n = i + 1; n < tokens.length && tokens[n].kind !== TK.RBrace && tokens[n].kind !== TK.EOF; n++) {
    if (tokens[n].kind === TK.Comma) { expect = true; continue; }
    if (expect && tokens[n].kind === TK.Ident) labels[n] = { type: 'enumMember', modifiers: MOD_DECLARATION };
    expect = false;
  }
}

function markVariants(tokens: Token[], i: number, labels: Label[]): void {
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

function markLetName(tokens: Token[], i: number, labels: Label[]): void {
  let last = -1;
  for (let n = i + 1; n < tokens.length; n++) {
    const k = tokens[n].kind;
    if (k === TK.Eq || k === TK.Semi || k === TK.EOF || k === TK.LBrace || k === TK.RBrace) break;
    if (k === TK.Ident) last = n;
  }
  if (last >= 0) labels[last] = { type: 'variable', modifiers: MOD_DECLARATION };
}

function markMatchCase(tokens: Token[], i: number, labels: Label[]): void {
  if (tokens[i + 1]?.kind !== TK.Ident) return;
  const opens = tokens[i + 2]?.kind === TK.LParen;
  if (!opens && tokens[i + 2]?.kind !== TK.LBrace) return;
  labels[i + 1] = { type: 'enumMember', modifiers: 0 };
  if (!opens) return;
  for (let n = i + 3; n < tokens.length && tokens[n].kind !== TK.RParen && tokens[n].kind !== TK.EOF; n++)
    if (tokens[n].kind === TK.Ident) labels[n] = { type: 'variable', modifiers: MOD_DECLARATION };
}

function markParameters(tokens: Token[], open: number, labels: Label[]): void {
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
