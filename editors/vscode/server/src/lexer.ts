// Direct port of Appa/src/Syntax/Lexer.cs. Behavior (what tokens/errors come out for a
// given source string) is kept faithful to the original; the micro-optimizations the C#
// version uses (frozen dictionaries, span-based lookups, cached strings) don't matter in
// a TS LSP server processing one small file at a time, so this uses plain Maps/strings.
import { Codes, ParseError, Span } from './codes';
import { TK, Token } from './token';

const KEYWORDS: Record<string, TK> = {
  import: TK.Import,
  kernel: TK.Kernel,
  user: TK.User,
  process: TK.Process,
  thread: TK.Thread,
  foreground: TK.Foreground,
  background: TK.Background,
  class: TK.Class,
  enum: TK.Enum,
  module: TK.Module,
  func: TK.Func,
  static: TK.Static,
  public: TK.Public,
  private: TK.Private,
  entry: TK.Entry,
  throws: TK.Throws,
  operator: TK.Operator,
  as: TK.As,
  fields: TK.Fields,
  ref: TK.Ref,
  return: TK.Return,
  if: TK.If,
  else: TK.Else,
  while: TK.While,
  for: TK.For,
  in: TK.In,
  switch: TK.Switch,
  case: TK.Case,
  break: TK.Break,
  continue: TK.Continue,
  debug: TK.Debug,
  panic: TK.Panic,
  try: TK.Try,
  catch: TK.Catch,
  new: TK.New,
  let: TK.Let,
  null: TK.Null,
  unsafe: TK.Unsafe,
  throw: TK.Throw,
  sizeof: TK.Sizeof,
  default: TK.Default,
  defer: TK.Defer,
  match: TK.Match,
  union: TK.Union,
  bool: TK.TBool,
  int: TK.TInt,
  char: TK.TChar,
  float: TK.TFloat,
  double: TK.TDouble,
  short: TK.TShort,
  void: TK.TVoid,

  // Width explicit family
  int64: TK.TPrim,
  uint: TK.TPrim,
  uint64: TK.TPrim,
  ushort: TK.TPrim,
  byte: TK.TPrim,
  sbyte: TK.TPrim,
  usize: TK.TPrim,
  uintptr: TK.TPrim,

  true: TK.BoolLit,
  false: TK.BoolLit,
};

function isWhiteSpace(c: string): boolean {
  return c === ' ' || (c >= '\t' && c <= '\r');
}
function isIdStart(c: string): boolean {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c === '_';
}
function isIdentPart(c: string): boolean {
  return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c === '_';
}
function isHexDigit(c: string): boolean {
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

export class Lexer {
  private pp = 0;
  private ts = 0;
  private readonly tokens: Token[] = [];

  constructor(private readonly src: string) {}

  tokenize(): Token[] {
    while (this.pp < this.src.length) this.readOne();
    this.tokens.push({ kind: TK.EOF, value: '', span: { start: this.src.length, length: 0 } });
    return this.tokens;
  }

  // A method, not a getter - a getter's return value gets narrowed by TS's control-flow
  // analysis as if it couldn't change, which is wrong here since it depends on this.pp,
  // mutated by advance() between re-checks (e.g. a comment/number scanning loop's
  // condition). A plain method call isn't narrowed the same way.
  private cur(): string {
    return this.pp < this.src.length ? this.src[this.pp] : '\0';
  }
  private peek(n = 1): string {
    return this.pp + n < this.src.length ? this.src[this.pp + n] : '\0';
  }
  private advance(n = 1): void {
    this.pp += n;
  }
  private emit(kind: TK, value: string): void {
    this.tokens.push({ kind, value, span: { start: this.ts, length: this.pp - this.ts } });
  }
  private fail(m: string, code: string = Codes.Syntax, hints?: string[]): never {
    throw new ParseError({ start: this.ts, length: Math.max(1, this.pp - this.ts) }, m, code, hints);
  }

  private readOne(): void {
    if (isWhiteSpace(this.cur())) { this.advance(); return; }

    if (this.cur() === '/' && this.peek() === '/') {
      while (this.pp < this.src.length && this.cur() !== '\n') this.advance();
      return;
    }

    if (this.cur() === '/' && this.peek() === '*') {
      this.ts = this.pp;
      this.advance(2);
      while (this.pp < this.src.length - 1 && !(this.cur() === '*' && this.peek() === '/')) this.advance();
      if (!(this.cur() === '*' && this.peek() === '/'))
        this.fail("unterminated block comment; missing closing '*/'", Codes.UnterminatedLiteral);
      this.advance(2);
      return;
    }

    this.ts = this.pp;

    if (this.cur() === '@') {
      this.advance();
      const start = this.pp;
      while (this.pp < this.src.length && isIdentPart(this.cur())) this.advance();
      const nn = this.src.slice(start, this.pp);
      switch (nn) {
        case 'intrinsic': this.emit(TK.AtIntrinsic, this.readParenArg('@intrinsic')); return;
        case 'preamble': this.emit(TK.AtPreamble, this.readParenArg('@preamble')); return;
        case 'extern': this.emit(TK.AtExtern, '@extern'); return;
        case 'environment': this.emit(TK.AtEnvironment, '@environment'); return;
        case 'keep': this.emit(TK.AtKeep, '@keep'); return;
        case 'builtin': this.emit(TK.AtBuiltin, this.readParenArg('@builtin')); return;
        default:
          this.fail(
            `unknown annotation '@${nn}'; expected '@intrinsic', '@preamble', '@extern', '@environment', '@keep', or '@builtin'`,
            Codes.BadAnnotation,
          );
      }
    }

    // native { }  or  native type Name { }
    if (this.matchKw('native')) {
      const start = this.pp;
      this.advance(6);
      this.skipWS();
      if (this.cur() === '{') { this.emit(TK.NativeContent, this.readBalanced()); return; }
      if (this.matchKw('type')) {
        this.advance(4);
        this.skipWS();
        const ns = this.pp;
        while (this.pp < this.src.length && isIdentPart(this.cur())) this.advance();
        const tname = this.src.slice(ns, this.pp);
        this.skipWS();
        if (this.cur() === '{' && tname.length > 0) {
          const body = this.readBalanced();
          this.emit(TK.NativeTypeDecl, tname + '\x1F' + body);
          return;
        }
      }
      this.pp = start;
      this.readID();
      return;
    }

    // fields { }
    if (this.matchKw('fields')) {
      const start = this.pp;
      this.advance(6);
      this.skipWS();
      if (this.cur() !== '{') { this.pp = start; this.readID(); return; }
      this.emit(TK.Fields, this.readBalanced());
      return;
    }

    if (isIdStart(this.cur())) { this.readID(); return; }

    if (this.cur() === '$' && this.peek() === '"') { this.readInterp(); return; }

    if (this.cur() === '"') { this.emit(TK.StrLit, this.readString()); return; }

    if (this.cur() === "'") { this.readCharLit(); return; }

    if (this.cur() >= '0' && this.cur() <= '9') { this.readNumber(); return; }

    switch (this.cur()) {
      case '+':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.PlusEq, '+='); return; }
        if (this.peek() === '+') { this.advance(2); this.emit(TK.Inc, '++'); return; }
        break;
      case '-':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.MinusEq, '-='); return; }
        if (this.peek() === '>') { this.advance(2); this.emit(TK.Arrow, '->'); return; }
        if (this.peek() === '-') { this.advance(2); this.emit(TK.Dec, '--'); return; }
        break;
      case '*':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.StarEq, '*='); return; }
        break;
      case '/':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.SlashEq, '/='); return; }
        break;
      case '%':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.PercentEq, '%='); return; }
        break;
      case '&':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.AmpEq, '&='); return; }
        if (this.peek() === '&') { this.advance(2); this.emit(TK.And, '&&'); return; }
        break;
      case '|':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.PipeEq, '|='); return; }
        if (this.peek() === '|') { this.advance(2); this.emit(TK.Or, '||'); return; }
        break;
      case '^':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.CaretEq, '^='); return; }
        break;
      case '=':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.EqEq, '=='); return; }
        this.advance(); this.emit(TK.Eq, '='); return;
      case '!':
        if (this.peek() === '=') { this.advance(2); this.emit(TK.NotEq, '!='); return; }
        break;
      case '<':
        if (this.peek() === '<') {
          if (this.peek(2) === '=') { this.advance(3); this.emit(TK.ShlEq, '<<='); return; }
          this.advance(2); this.emit(TK.Shl, '<<'); return;
        }
        if (this.peek() === '=') { this.advance(2); this.emit(TK.LtEq, '<='); return; }
        break;
      case '>':
        if (this.peek() === '>') {
          if (this.peek(2) === '=') { this.advance(3); this.emit(TK.ShrEq, '>>='); return; }
          this.advance(2); this.emit(TK.Shr, '>>'); return;
        }
        if (this.peek() === '=') { this.advance(2); this.emit(TK.GtEq, '>='); return; }
        break;
    }

    const c = this.cur();
    this.advance();
    const kind = ((): TK => {
      switch (c) {
        case '(': return TK.LParen;
        case ')': return TK.RParen;
        case '{': return TK.LBrace;
        case '}': return TK.RBrace;
        case '[': return TK.LBrack;
        case ']': return TK.RBrack;
        case ';': return TK.Semi;
        case ',': return TK.Comma;
        case ':': return TK.Colon;
        case '.': return TK.Dot;
        default: return TK.Punct;
      }
    })();
    this.emit(kind, c);
  }

  private matchKw(kw: string): boolean {
    if (this.pp + kw.length > this.src.length) return false;
    if (this.src.slice(this.pp, this.pp + kw.length) !== kw) return false;
    const after = this.pp + kw.length;
    return after >= this.src.length || !isIdentPart(this.src[after]);
  }

  private skipWS(): void {
    while (this.pp < this.src.length && isWhiteSpace(this.cur())) this.advance();
  }

  private readParenArg(ann: string): string {
    this.skipWS();
    if (this.cur() !== '(') this.fail(`'${ann}' requires a parenthesized argument`, Codes.BadAnnotation, [`e.g. ${ann}(name)`]);
    this.advance();
    this.skipWS();
    const s = this.pp;
    while (this.pp < this.src.length && isIdentPart(this.cur())) this.advance();
    const arg = this.src.slice(s, this.pp);
    if (arg.length === 0) this.fail(`'${ann}' argument must be a name`, Codes.BadAnnotation, [`e.g. ${ann}(name)`]);
    this.skipWS();
    if (this.cur() !== ')') this.fail(`missing ')' after '${ann}(${arg}'`, Codes.BadAnnotation);
    this.advance();
    return arg;
  }

  private readBalanced(): string {
    this.advance(); // opening {
    const start = this.pp;
    let depth = 1;
    while (this.pp < this.src.length && depth > 0) {
      const c = this.cur();
      const p = this.peek();
      if (c === '/' && p === '/') {
        while (this.pp < this.src.length && this.cur() !== '\n') this.advance();
      } else if (c === '/' && p === '*') {
        this.advance(2);
        while (this.pp < this.src.length && !(this.cur() === '*' && this.peek() === '/')) this.advance();
        if (this.pp < this.src.length) this.advance(2);
      } else if (c === '"' || c === "'") {
        const quote = c;
        this.advance();
        while (this.pp < this.src.length && this.cur() !== quote) {
          if (this.cur() === '\\' && this.pp + 1 < this.src.length) this.advance();
          this.advance();
        }
        if (this.pp < this.src.length) this.advance();
      } else if (c === '{') { depth++; this.advance(); }
      else if (c === '}') { depth--; this.advance(); }
      else { this.advance(); }
    }
    if (depth > 0) this.fail("Unterminated native block, missing closing '}'", Codes.UnterminatedLiteral);
    return this.src.slice(start, this.pp - 1);
  }

  private readID(): void {
    const start = this.pp;
    while (this.pp < this.src.length && isIdentPart(this.cur())) this.advance();
    const word = this.src.slice(start, this.pp);
    const kw = KEYWORDS[word];
    if (kw !== undefined) this.emit(kw, word);
    else this.emit(TK.Ident, word);
  }

  private readNumber(): void {
    const start = this.pp;

    if (this.cur() === '0' && (this.peek() === 'x' || this.peek() === 'X')) {
      this.advance(2);
      const digits = this.pp;
      while (this.pp < this.src.length && isHexDigit(this.cur())) this.advance();
      if (this.pp === digits) this.fail("hex literal '0x' has no digits", Codes.BadNumber);
      this.readIntSuffix();
      if (isIdentPart(this.cur())) this.fail(`invalid character '${this.cur()}' in hex literal`, Codes.BadNumber);
      this.emit(TK.IntLit, this.src.slice(start, this.pp));
      return;
    }

    while (this.pp < this.src.length && this.cur() >= '0' && this.cur() <= '9') this.advance();

    let isFloat = false;

    if (this.cur() === '.' && this.peek() >= '0' && this.peek() <= '9') {
      isFloat = true;
      this.advance();
      while (this.pp < this.src.length && this.cur() >= '0' && this.cur() <= '9') this.advance();
    }

    if (
      (this.cur() === 'e' || this.cur() === 'E') &&
      ((this.peek() >= '0' && this.peek() <= '9') ||
        ((this.peek() === '+' || this.peek() === '-') && this.peek(2) >= '0' && this.peek(2) <= '9'))
    ) {
      isFloat = true;
      this.advance();
      if (this.cur() === '+' || this.cur() === '-') this.advance();
      while (this.pp < this.src.length && this.cur() >= '0' && this.cur() <= '9') this.advance();
    }

    if (isFloat) {
      if (this.cur() === 'f' || this.cur() === 'F') this.advance();
      if (isIdentPart(this.cur())) this.fail(`invalid suffix on float literal (found '${this.cur()}' after '${this.src.slice(start, this.pp)}')`, Codes.BadNumber);
      this.emit(TK.FloatLit, this.src.slice(start, this.pp));
    } else {
      this.readIntSuffix();
      if (isIdentPart(this.cur())) this.fail(`invalid suffix on integer literal (found '${this.cur()}' after '${this.src.slice(start, this.pp)}')`, Codes.BadNumber);
      this.emit(TK.IntLit, this.src.slice(start, this.pp));
    }
  }

  private readIntSuffix(): void {
    while (this.pp < this.src.length && 'uUlL'.includes(this.cur())) this.advance();
  }

  private static tryEscape(c: string): boolean {
    return c === 'n' || c === 't' || c === 'r' || c === '0' || c === "'" || c === '\\' || c === '"';
  }

  private readInterp(): void {
    this.advance(2); // consume $"
    this.emit(TK.InterpStrStart, '$"');

    while (this.pp < this.src.length && this.cur() !== '"' && this.cur() !== '\n') {
      if (this.cur() === '{' && this.peek() !== '{') {
        this.ts = this.pp; this.advance();
        this.emit(TK.Punct, '{');

        let brdepth = 1;
        while (this.pp < this.src.length && brdepth > 0) {
          if (isWhiteSpace(this.cur())) { this.advance(); continue; }
          if (this.cur() === '{') brdepth++;
          else if (this.cur() === '}') {
            brdepth--;
            if (brdepth === 0) break;
          }
          this.readOne();
        }
        if (brdepth > 0) this.fail("unterminated '{' in interpolated string", Codes.UnterminatedLiteral);

        this.ts = this.pp; this.advance();
        this.emit(TK.Punct, '}');
      } else {
        this.ts = this.pp;
        let start = this.pp;
        let out = '';
        while (
          this.pp < this.src.length &&
          this.cur() !== '"' &&
          this.cur() !== '\n' &&
          !(this.cur() === '{' && this.peek() !== '{')
        ) {
          if (this.cur() === '{' && this.peek() === '{') {
            out += this.src.slice(start, this.pp); this.advance(2); out += '{'; start = this.pp;
          } else if (this.cur() === '}' && this.peek() === '}') {
            out += this.src.slice(start, this.pp); this.advance(2); out += '}'; start = this.pp;
          } else if (this.cur() === '\\') {
            this.advance();
            if (this.pp >= this.src.length) break;
            if (!Lexer.tryEscape(this.cur())) this.fail(`unrecognized escape '\\${this.cur()}' in interpolated string`, Codes.BadEscape);
            this.advance();
          } else this.advance();
        }
        const content = out.length === 0 ? this.src.slice(start, this.pp) : out + this.src.slice(start, this.pp);
        this.emit(TK.StrLit, '"' + content + '"');
      }
    }

    if (this.cur() !== '"') this.fail('unterminated interpolated string', Codes.UnterminatedLiteral);
    this.ts = this.pp; this.advance();
    this.emit(TK.InterpStrEnd, '"');
  }

  private readString(): string {
    const start = this.pp;
    this.advance(); // opening "
    while (this.pp < this.src.length && this.cur() !== '"' && this.cur() !== '\n') {
      if (this.cur() === '\\') {
        this.advance();
        if (this.pp >= this.src.length) break;
        if (!Lexer.tryEscape(this.cur())) this.fail(`unrecognized escape '\\${this.cur()}' in string literal`, Codes.BadEscape);
        this.advance();
      } else this.advance();
    }
    if (this.cur() !== '"') this.fail('unterminated string literal', Codes.UnterminatedLiteral);
    this.advance(); // closing "
    return this.src.slice(start, this.pp);
  }

  private readCharLit(): void {
    this.advance(); // opening '
    if (this.cur() === '\\') {
      this.advance();
      if (!Lexer.tryEscape(this.cur())) this.fail(`unrecognized escape '\\${this.cur()}' in char literal`, Codes.BadEscape);
      this.advance();
    } else if (this.cur() === "'") {
      this.fail('empty char literal', Codes.UnterminatedLiteral);
    } else if (this.cur() === '\n' || this.pp >= this.src.length) {
      this.fail('unterminated char literal', Codes.UnterminatedLiteral);
    } else {
      this.advance();
    }
    if (this.cur() !== "'") this.fail('char literal must hold exactly one character', Codes.UnterminatedLiteral);
    this.advance(); // closing '
    this.emit(TK.CharLit, '0');
  }
}
