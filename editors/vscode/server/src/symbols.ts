import { Lexer } from './lexer';
import { TK, Token } from './token';

export type SymbolKind =
  | 'class' | 'module' | 'enum' | 'union' | 'variant' | 'enumMember'
  | 'function' | 'method' | 'operator' | 'realm' | 'process' | 'thread' | 'nativeType';

export interface GataSymbol {
  name: string;
  kind: SymbolKind;
  detail: string;
  start: number;
  length: number;
  container?: string;
}

const HEADER_KINDS = new Set<TK>([
  TK.Public, TK.Private, TK.Static, TK.Entry, TK.Throws, TK.Ident, TK.Dot, TK.LBrack, TK.RBrack,
  TK.IntLit, TK.Comma, TK.ColonColon, TK.Kernel, TK.Userspace, TK.Punct, TK.Arrow, TK.LParen, TK.RParen,
  TK.TBool, TK.TInt, TK.TChar, TK.TFloat, TK.TDouble, TK.TShort, TK.TVoid, TK.TPrim,
  TK.AtIntrinsic, TK.AtPreamble, TK.AtKeep, TK.AtBuiltin, TK.AtShadows, TK.AtExtern, TK.Func, TK.Operator,
]);

function squash(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

export function symbolsOf(text: string): GataSymbol[] {
  const tokens = new Lexer(text).tokenizeLenient();
  const out: GataSymbol[] = [];
  const containers: Array<{ name: string; holdsMembers: boolean } | undefined> = [];
  let depth = 0;
  let pendingContainer: { name: string; holdsMembers: boolean } | undefined;

  const enclosing = () => {
    for (let i = containers.length - 1; i >= 0; i--) if (containers[i]) return containers[i];
    return undefined;
  };
  const container = (): string | undefined => enclosing()?.name;

  const sliceTo = (from: number, stop: number): string => squash(text.slice(from, stop));

  const headEnd = (i: number): number => {
    for (let n = i; n < tokens.length; n++) {
      const k = tokens[n].kind;
      if (k === TK.LBrace || k === TK.Semi || k === TK.EOF || k === TK.NativeContent)
        return tokens[n].span.start;
    }
    return tokens[tokens.length - 1].span.start;
  };

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];

    if (t.kind === TK.LBrace) {
      depth++;
      containers[depth] = pendingContainer;
      pendingContainer = undefined;
      continue;
    }
    if (t.kind === TK.RBrace) {
      containers[depth] = undefined;
      depth = Math.max(0, depth - 1);
      continue;
    }

    const name = tokens[i + 1];

    switch (t.kind) {
      case TK.Class:
      case TK.Module: {
        if (name?.kind !== TK.Ident) break;
        const kind: SymbolKind = t.kind === TK.Class ? 'class' : 'module';
        out.push({
          name: name.value, kind, detail: sliceTo(t.span.start, headEnd(i)),
          start: name.span.start, length: name.span.length, container: container(),
        });
        pendingContainer = { name: name.value, holdsMembers: true };
        break;
      }
      case TK.Enum: {
        if (name?.kind !== TK.Ident) break;
        out.push({
          name: name.value, kind: 'enum', detail: sliceTo(t.span.start, headEnd(i)),
          start: name.span.start, length: name.span.length, container: container(),
        });
        pendingContainer = { name: name.value, holdsMembers: true };
        collectEnumMembers(tokens, i + 2, name.value, out);
        break;
      }
      case TK.Union: {
        if (name?.kind !== TK.Ident) break;
        out.push({
          name: name.value, kind: 'union', detail: sliceTo(t.span.start, headEnd(i)),
          start: name.span.start, length: name.span.length, container: container(),
        });
        pendingContainer = { name: name.value, holdsMembers: true };
        collectVariants(tokens, i + 2, name.value, text, out);
        break;
      }
      case TK.NativeTypeDecl: {
        const sep = t.value.indexOf('\x1F');
        const typeName = sep < 0 ? t.value : t.value.slice(0, sep);
        if (typeName.length === 0) break;
        out.push({
          name: typeName, kind: 'nativeType', detail: `native type ${typeName}`,
          start: t.span.start, length: t.span.length, container: container(),
        });
        break;
      }
      case TK.Func: {
        let head = i;
        while (head > 0 && HEADER_KINDS.has(tokens[head - 1].kind) && tokens[head - 1].kind !== TK.Func) head--;
        const owner = enclosing();
        const isOperator = tokens.slice(head, i).some((h) => h.kind === TK.Operator);

        if (name?.kind === TK.Ident) {
          out.push({
            name: name.value,
            kind: owner?.holdsMembers ? 'method' : 'function',
            detail: sliceTo(tokens[head].span.start, headEnd(i)),
            start: name.span.start, length: name.span.length, container: owner?.name,
          });
          break;
        }

        if (!isOperator || !name) break;
        const close = operatorSymbolEnd(tokens, i + 1);
        const symbol = squash(text.slice(name.span.start, close));
        out.push({
          name: `operator ${symbol}`, kind: 'operator',
          detail: sliceTo(tokens[head].span.start, headEnd(i)),
          start: name.span.start, length: Math.max(1, close - name.span.start), container: owner?.name,
        });
        break;
      }
      case TK.Realm: {
        if (name?.kind !== TK.Kernel && name?.kind !== TK.Userspace) break;
        out.push({
          name: name.value, kind: 'realm', detail: `realm ${name.value}`,
          start: name.span.start, length: name.span.length,
        });
        pendingContainer = { name: name.value, holdsMembers: false };
        break;
      }
      default:
        break;
    }

    if (t.kind === TK.Ident && (t.value === 'process' || t.value === 'thread') && name?.kind === TK.Ident) {
      const kind: SymbolKind = t.value === 'process' ? 'process' : 'thread';
      const mode = tokens[i - 1];
      const from = mode && (mode.kind === TK.Foreground || mode.kind === TK.Background) ? mode.span.start : t.span.start;
      out.push({
        name: name.value, kind, detail: sliceTo(from, headEnd(i)),
        start: name.span.start, length: name.span.length, container: container(),
      });
      pendingContainer = { name: name.value, holdsMembers: false };
    }
  }

  return out;
}

function collectEnumMembers(tokens: Token[], i: number, owner: string, out: GataSymbol[]): void {
  if (tokens[i]?.kind !== TK.LBrace) return;
  let expect = true;
  for (let n = i + 1; n < tokens.length && tokens[n].kind !== TK.RBrace && tokens[n].kind !== TK.EOF; n++) {
    if (tokens[n].kind === TK.Comma) { expect = true; continue; }
    if (expect && tokens[n].kind === TK.Ident)
      out.push({
        name: tokens[n].value, kind: 'enumMember', detail: `${owner}.${tokens[n].value}`,
        start: tokens[n].span.start, length: tokens[n].span.length, container: owner,
      });
    expect = false;
  }
}

function collectVariants(tokens: Token[], i: number, owner: string, text: string, out: GataSymbol[]): void {
  if (tokens[i]?.kind !== TK.LBrace) return;
  let expect = true;
  let depth = 0;
  for (let n = i + 1; n < tokens.length && tokens[n].kind !== TK.EOF; n++) {
    const k = tokens[n].kind;
    if (k === TK.LParen) { depth++; continue; }
    if (k === TK.RParen) { depth--; continue; }
    if (k === TK.RBrace && depth === 0) break;
    if (depth > 0) continue;
    if (k === TK.Comma) { expect = true; continue; }
    if (expect && k === TK.Ident) {
      const close = closingParen(tokens, n + 1);
      const end = close >= 0 ? tokens[close].span.start + tokens[close].span.length : tokens[n].span.start + tokens[n].span.length;
      out.push({
        name: tokens[n].value, kind: 'variant', detail: `${owner}.${squash(text.slice(tokens[n].span.start, end))}`,
        start: tokens[n].span.start, length: tokens[n].span.length, container: owner,
      });
    }
    expect = false;
  }
}

/** The offset just past an operator's symbol, which may be one token, two, or '[ ] ='. */
function operatorSymbolEnd(tokens: Token[], i: number): number {
  let n = i;
  while (n < tokens.length && tokens[n].kind !== TK.LParen && tokens[n].kind !== TK.EOF) n++;
  const last = tokens[Math.max(i, n - 1)];
  return last.span.start + last.span.length;
}

function closingParen(tokens: Token[], open: number): number {
  if (tokens[open]?.kind !== TK.LParen) return -1;
  let depth = 0;
  for (let n = open; n < tokens.length && tokens[n].kind !== TK.EOF; n++) {
    if (tokens[n].kind === TK.LParen) depth++;
    else if (tokens[n].kind === TK.RParen && --depth === 0) return n;
  }
  return -1;
}
