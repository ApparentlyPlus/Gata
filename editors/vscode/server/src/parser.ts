import { Codes, ParseError, Span } from './codes';
import { TK, Token } from './token';

const Modifiers = {
  None: 0,
  Static: 1,
  Public: 2,
  Private: 4,
} as const;

const ASSIGN_KINDS = new Set<TK>([
  TK.Eq, TK.PlusEq, TK.MinusEq, TK.StarEq, TK.SlashEq, TK.PercentEq,
  TK.AmpEq, TK.PipeEq, TK.CaretEq, TK.ShlEq, TK.ShrEq,
]);

const PRIM_KINDS = new Set<TK>([
  TK.TBool, TK.TInt, TK.TChar, TK.TFloat, TK.TDouble, TK.TShort, TK.TVoid, TK.TPrim,
]);

const ANNOTATION_KINDS = new Set<TK>([
  TK.AtIntrinsic, TK.AtPreamble, TK.AtKeep, TK.AtBuiltin, TK.AtShadows,
]);

const KIND_NAMES: Partial<Record<TK, string>> = {
  [TK.Ident]: 'an identifier',
  [TK.IntLit]: 'an integer literal',
  [TK.FloatLit]: 'a float literal',
  [TK.StrLit]: 'a string literal',
  [TK.InterpStrEnd]: "the closing '\"' of the interpolated string",
  [TK.LParen]: "'('", [TK.RParen]: "')'",
  [TK.LBrace]: "'{'", [TK.RBrace]: "'}'",
  [TK.LBrack]: "'['", [TK.RBrack]: "']'",
  [TK.Semi]: "';'", [TK.Comma]: "','", [TK.Colon]: "':'",
  [TK.ColonColon]: "'::'",
  [TK.Dot]: "'.'", [TK.Eq]: "'='", [TK.Arrow]: "'->'",
  [TK.EOF]: 'end of file',
};

const MAX_DEPTH = 200;

function distance(a: string, b: string): number {
  const prev = new Array<number>(b.length + 1);
  const cur = new Array<number>(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost);
    }
    for (let j = 0; j <= b.length; j++) prev[j] = cur[j];
  }
  return prev[b.length];
}

function suggest(typed: string, candidates: readonly string[]): string[] {
  let best: string | undefined;
  let bestDist = Number.MAX_SAFE_INTEGER;
  const maxAllowed = Math.max(1, Math.floor(typed.length / 2));
  for (const c of candidates) {
    if (Math.abs(c.length - typed.length) > maxAllowed) continue;
    const d = distance(typed, c);
    if (d < bestDist) { bestDist = d; best = c; }
  }
  return bestDist <= maxAllowed && best ? [`did you mean '${best}'?`] : [];
}

interface Snapshot { pos: number; end: number; depth: number; }

export class Parser {
  private readonly tokens: Token[];
  private pp = 0;
  private pe = 0;
  private depth = 0;

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  private get cur(): Token {
    return this.tokens[this.pp];
  }
  private peek(n = 1): Token {
    return this.pp + n < this.tokens.length ? this.tokens[this.pp + n] : this.tokens[this.tokens.length - 1];
  }
  private advance(): Token {
    const t = this.cur;
    this.pe = t.span.start + t.span.length;
    if (this.pp < this.tokens.length - 1) this.pp++;
    return t;
  }
  private to(start: number): Span {
    return { start, length: Math.max(0, this.pe - start) };
  }
  private expect(k: TK): Token {
    if (this.cur.kind !== k) this.fail(`expected ${this.kindName(k)}, found ${this.found()}`);
    return this.advance();
  }
  private found(): string {
    return this.cur.kind === TK.EOF ? 'end of file' : `'${this.cur.value}'`;
  }
  private kindName(k: TK): string {
    return KIND_NAMES[k] ?? `'${TK[k].toLowerCase()}'`;
  }
  private at(k: TK): boolean {
    return this.cur.kind === k;
  }
  private atValue(word: string): boolean {
    return this.cur.kind === TK.Ident && this.cur.value === word;
  }
  private try_(k: TK): boolean {
    if (this.at(k)) { this.advance(); return true; }
    return false;
  }
  private atP(v: string): boolean {
    return this.cur.kind === TK.Punct && this.cur.value === v;
  }
  private fail(m: string, code: string = Codes.Syntax, hints?: string[]): never {
    throw new ParseError(this.cur.span, m, code, hints);
  }
  private failAt(span: Span, m: string, code: string = Codes.Syntax, hints?: string[]): never {
    throw new ParseError(span, m, code, hints);
  }
  private isAssignTk(k: TK): boolean {
    return ASSIGN_KINDS.has(k);
  }
  private noAssignHere(where: string, hint: string): void {
    if (this.isAssignTk(this.cur.kind))
      this.fail(
        `assignment is a statement in Gata, not an expression, and cannot appear in ${where}`,
        Codes.AssignInExpr,
        [hint],
      );
  }
  private enterDepth(): void {
    if (++this.depth > MAX_DEPTH) this.fail('nested too deeply');
  }
  private exitDepth(): void {
    this.depth--;
  }
  private mark(): Snapshot {
    return { pos: this.pp, end: this.pe, depth: this.depth };
  }
  private rewind(m: Snapshot): void {
    this.pp = m.pos;
    this.pe = m.end;
    this.depth = m.depth;
  }
  private parseAnnotations(): { count: number; span: Span } {
    const start = this.cur.span.start;
    let count = 0;
    while (ANNOTATION_KINDS.has(this.cur.kind)) { this.advance(); count++; }
    return { count, span: this.to(start) };
  }

  private rejectAnns(anns: { count: number; span: Span }, what: string): void {
    if (anns.count > 0) this.failAt(anns.span, `annotations have no effect on ${what}`, Codes.BadAnnotation);
  }

  parseProgram(): void {
    while (!this.at(TK.EOF)) this.parseTopLevel();
  }

  private parseTopLevel(): void {
    if (this.at(TK.Import)) { this.parseImport(); return; }
    if (this.at(TK.AtEnvironment)) { this.advance(); return; }
    const anns = this.parseAnnotations();
    if (this.at(TK.Import)) this.rejectAnns(anns, 'an import');
    if (this.at(TK.NativeContent)) { this.advance(); return; }
    if (this.at(TK.NativeTypeDecl)) { this.advance(); return; }
    if (this.at(TK.Enum)) { this.rejectAnns(anns, 'an enum'); this.parseEnumDecl(); return; }
    if (this.at(TK.Union)) { this.parseUnionDecl(); return; }
    if (this.at(TK.Class)) { this.parseClassDecl(); return; }
    if (this.at(TK.Module)) { this.parseModuleDecl(); return; }
    if (this.at(TK.Realm)) { this.rejectAnns(anns, 'a realm'); this.parseRealmDecl(); return; }
    if (this.at(TK.Kernel)) this.requireRealmKeyword();
    if (this.atProcessStart())
      this.fail("a 'process' must be declared inside a 'realm' block", Codes.TopologyOutsideRealm,
        ["wrap it in 'realm kernel { ... }' or 'realm userspace { ... }'"]);
    this.rejectStrayThread();
    this.rejectModifierOnType();
    if (this.at(TK.AtExtern)) { this.parseExternDecl(); return; }
    this.parseFreeFuncDecl();
  }

  private rejectModifierOnType(): void {
    if (this.cur.kind !== TK.Public && this.cur.kind !== TK.Private && this.cur.kind !== TK.Static) return;
    const what =
      this.peek().kind === TK.Class ? 'a class' :
      this.peek().kind === TK.Module ? 'a module' :
      this.peek().kind === TK.Enum ? 'an enum' :
      this.peek().kind === TK.Union ? 'a union' :
      this.peek().kind === TK.NativeTypeDecl ? 'a native type' : '';
    if (what.length === 0) return;
    const mod = this.cur.value;
    this.failAt(this.cur.span, `'${mod}' has no meaning on ${what}`, Codes.BadDeclHeader, [
      mod === 'private'
        ? 'a top-level type is visible to every file that imports this one; there is no file-local type'
        : `remove '${mod}'; only a free function takes 'private' here`,
    ]);
  }

  private parseFreeFuncDecl(): void {
    const modSpan = this.cur.span;
    const mods = this.parseMods();
    this.rejectPublicOnFreeFunc(mods, modSpan);
    let isEntry = this.try_(TK.Entry);
    this.try_(TK.Throws);
    if (!isEntry) isEntry = this.try_(TK.Entry);
    const ret = this.parseOptionalReturnType();
    if (ret && this.at(TK.LBrace))
      this.fail("expected 'func', found '{'", Codes.BadDeclHeader, [
        "did you forget 'process' before it?",
        "e.g. 'foreground process Name { ... }'",
      ]);
    this.expect(TK.Func);
    const name = this.expect(TK.Ident).value;
    this.parseGenericParamList();
    this.expect(TK.LParen); this.parseParamList(); this.expect(TK.RParen);
    if (this.at(TK.Arrow)) this.fail(`'${name}': return type goes before 'func', not after the parameter list`, Codes.BadDeclHeader);
    this.parseMethodBody();
  }

  private rejectPublicOnFreeFunc(mods: number, span: Span): void {
    if ((mods & Modifiers.Public) === 0) return;
    this.failAt(span, "'public' has no meaning on a free function", Codes.BadDeclHeader, [
      'a free function is already visible to every file that imports this one',
      "remove it, or write 'private' to scope the function to this file",
    ]);
  }

  private parseGenericParamList(): void {
    if (!this.at(TK.LBrack)) return;
    this.advance();
    this.expectBareGenericParam();
    while (this.try_(TK.Comma)) this.expectBareGenericParam();
    this.expect(TK.RBrack);
  }

  private parseImport(): void {
    this.expect(TK.Import);
    if (this.at(TK.StrLit)) { this.advance(); this.expect(TK.Semi); return; }
    this.expect(TK.Ident);
    this.expect(TK.Semi);
  }

  private parseExternDecl(): void {
    this.advance();
    this.parseOptionalReturnType();
    this.expect(TK.Func);
    const name = this.expect(TK.Ident).value;
    this.expect(TK.LParen); this.parseParamList(); this.expect(TK.RParen);
    if (this.at(TK.Arrow)) this.fail(`'${name}': return type goes before 'func', not after the parameter list`, Codes.BadDeclHeader);
    this.expect(TK.Semi);
  }

  private parseRealmDecl(): void {
    this.advance();
    if (this.at(TK.Kernel) || this.at(TK.Userspace)) this.advance();
    else
      this.fail(`unknown realm ${this.found()}; the only realms are 'kernel' and 'userspace'`,
        Codes.UnknownRealm,
        this.at(TK.Ident) ? suggest(this.cur.value, ['kernel', 'userspace']) : []);
    this.expect(TK.LBrace);
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) this.parseRealmItem();
    this.expect(TK.RBrace);
  }

  private requireRealmKeyword(): never {
    this.fail("expected 'realm' before 'kernel'", Codes.MissingRealmKeyword, ["write 'realm kernel { ... }'"]);
  }

  private parseRealmItem(): void {
    if (this.at(TK.Realm)) this.fail("a 'realm' block cannot be nested inside another", Codes.InvalidNesting);
    if (this.at(TK.Kernel)) this.requireRealmKeyword();
    this.rejectStrayImport();
    this.rejectStrayThread();
    if (this.at(TK.AtEnvironment)) { this.advance(); return; }
    const anns = this.parseAnnotations();
    this.rejectStrayImport();
    this.rejectStrayThread();
    if (this.at(TK.NativeContent)) { this.advance(); return; }
    if (this.at(TK.NativeTypeDecl)) { this.advance(); return; }
    if (this.at(TK.AtExtern)) { this.parseExternDecl(); return; }
    if (this.at(TK.Enum)) { this.rejectAnns(anns, 'an enum'); this.parseEnumDecl(); return; }
    if (this.at(TK.Union)) { this.parseUnionDecl(); return; }
    if (this.at(TK.Class)) { this.parseClassDecl(); return; }
    if (this.at(TK.Module)) { this.parseModuleDecl(); return; }
    if (this.atProcessStart()) { this.rejectAnns(anns, 'a process'); this.parseProcessDeclTop(); return; }
    this.parseFreeFuncDecl();
  }

  private parseClassDecl(): void {
    this.expect(TK.Class);
    this.parseSimpleTypeName();
    if (this.at(TK.LBrack)) {
      this.advance();
      this.expectBareGenericParam();
      while (this.try_(TK.Comma)) this.expectBareGenericParam();
      this.expect(TK.RBrack);
    }
    this.expect(TK.LBrace);
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) this.parseClassMember();
    this.expect(TK.RBrace);
  }

  private expectBareGenericParam(): string {
    if (!this.at(TK.Ident)) this.fail(`generic parameter must be a plain name, found ${this.found()}`, Codes.BadDeclHeader);
    const tok = this.advance().value;
    if (this.at(TK.LBrack)) this.fail(`generic parameter '${tok}' cannot itself be generic`, Codes.BadDeclHeader);
    return tok;
  }

  private parseModuleDecl(): void {
    this.expect(TK.Module);
    this.parseSimpleTypeName();
    this.expect(TK.LBrace);
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) this.parseClassMember();
    this.expect(TK.RBrace);
  }

  private parseEnumDecl(): void {
    this.expect(TK.Enum);
    this.expect(TK.Ident);
    this.expect(TK.LBrace);
    if (!this.at(TK.RBrace) && !this.at(TK.EOF)) {
      this.expect(TK.Ident);
      if (this.try_(TK.Eq)) this.parseExpr();
      while (this.try_(TK.Comma)) {
        if (this.at(TK.RBrace)) this.fail('trailing comma not allowed after the last enum member; remove it', Codes.TrailingComma);
        this.expect(TK.Ident);
        if (this.try_(TK.Eq)) this.parseExpr();
      }
    }
    this.expect(TK.RBrace);
  }

  private parseUnionDecl(): void {
    this.expect(TK.Union);
    this.expect(TK.Ident);
    if (this.at(TK.LBrack)) {
      this.advance();
      this.expectBareGenericParam();
      while (this.try_(TK.Comma)) this.expectBareGenericParam();
      this.expect(TK.RBrack);
    }
    this.expect(TK.LBrace);
    if (!this.at(TK.RBrace) && !this.at(TK.EOF)) {
      this.expect(TK.Ident);
      if (this.at(TK.LParen)) this.parseUnionFieldList();
      while (this.try_(TK.Comma)) {
        if (this.at(TK.RBrace)) this.fail('trailing comma not allowed after the last union variant; remove it', Codes.TrailingComma);
        this.expect(TK.Ident);
        if (this.at(TK.LParen)) this.parseUnionFieldList();
      }
    }
    this.expect(TK.RBrace);
  }

  private parseUnionFieldList(): void {
    this.advance(); // opening (
    if (this.at(TK.RParen)) { this.advance(); return; }
    this.parseParam();
    while (this.try_(TK.Comma)) {
      if (this.at(TK.RParen)) this.fail('trailing comma not allowed after the last field; remove it', Codes.TrailingComma);
      this.parseParam();
    }
    this.expect(TK.RParen);
  }

  private parseTypeName(): void {
    this.enterDepth();
    try { this.parseTypeNameInner(); } finally { this.exitDepth(); }
  }

  private parseTypeNameInner(): void {
    if (this.parseScopeQualifier()) {
      this.expectIdent('a scope or type name');
      while (this.try_(TK.Dot)) this.expectIdent('a scope or type name');
      this.finishTypeName('the qualified name');
      return;
    }
    this.finishTypeName(this.parseSimpleTypeName());
  }

  private finishTypeName(name: string): void {
    if (!this.at(TK.LBrack)) return;
    this.advance();
    this.parseTypeName();
    while (this.try_(TK.Comma)) this.parseTypeName();
    if (!this.at(TK.RBrack)) this.fail(`invalid type argument in '${name}[...]', found ${this.found()}`);
    this.expect(TK.RBrack);
  }

  private parseScopeQualifier(): boolean {
    if (this.try_(TK.ColonColon)) return true;
    if (!this.at(TK.Kernel) && !this.at(TK.Userspace)) return false;
    if (this.peek().kind !== TK.Dot) return false;
    this.advance();
    this.advance();
    return true;
  }

  private expectIdent(what: string): string {
    if (this.at(TK.Ident)) return this.advance().value;
    this.fail(`expected ${what}, found ${this.found()}`);
  }

  private parseSimpleTypeName(): string {
    if (this.at(TK.Ident)) return this.advance().value;
    if (this.isPrim(this.cur.kind)) return this.primName(this.advance());
    if (this.at(TK.Let))
      this.fail('a variable cannot be declared here', Codes.Syntax, [
        'a variable belongs inside a function, or directly inside a process, where it becomes state its threads share',
        'types, modules and functions are what a realm or a file can hold',
      ]);
    this.fail(`expected a type name, found ${this.found()}`);
  }

  private parseTypeSpec(): void {
    this.enterDepth();
    try { this.parseTypeSpecInner(); } finally { this.exitDepth(); }
  }

  private parseTypeSpecInner(): void {
    if (this.at(TK.LBrack) && this.peek().kind === TK.IntLit && this.peek(2).kind === TK.RBrack) {
      this.advance();
      this.advance();
      this.expect(TK.RBrack);
      this.parseTypeSpec();
      return;
    }
    if (this.at(TK.Func)) { this.parseFuncTypeSpec(); return; }
    this.parseTypeName();
    while (this.atP('*')) this.advance();
  }

  private parseFuncTypeSpec(): void {
    this.expect(TK.Func);
    this.expect(TK.LParen);
    if (!this.at(TK.RParen)) {
      this.parseTypeSpec();
      while (this.try_(TK.Comma)) this.parseTypeSpec();
    }
    this.expect(TK.RParen);
    this.expect(TK.Arrow);
    this.parseTypeSpec();
    if (this.atP('*')) this.fail('pointer to a function type is not supported; use the function type directly', Codes.BadDeclHeader);
  }

  private isPrim(k: TK): boolean {
    return PRIM_KINDS.has(k);
  }

  private primName(t: Token): string {
    switch (t.kind) {
      case TK.TBool: return 'bool';
      case TK.TInt: return 'int';
      case TK.TChar: return 'char';
      case TK.TFloat: return 'float';
      case TK.TDouble: return 'double';
      case TK.TShort: return 'short';
      case TK.TVoid: return 'void';
      default: return t.value;
    }
  }

  private parseClassMember(): void {
    if (this.at(TK.Class) || this.at(TK.Module)) this.fail('classes and modules cannot be nested', Codes.InvalidNesting);
    if (this.at(TK.Realm)) this.fail("a 'realm' block cannot appear inside a class", Codes.InvalidNesting);

    if (this.at(TK.Fields)) { this.advance(); return; }

    const anns = this.parseAnnotations();
    const mods = this.parseMods();
    let isEntry = this.try_(TK.Entry);
    const isThrow = this.try_(TK.Throws);
    if (!isEntry) isEntry = this.try_(TK.Entry);

    if (this.at(TK.Operator)) {
      if (anns.count > 0) this.fail('annotations have no effect on an operator', Codes.BadAnnotation);
      if (isEntry) this.fail("'entry' has no meaning on an operator", Codes.BadDeclHeader);
      if (isThrow) this.fail("'throws' has no meaning on an operator", Codes.BadDeclHeader);
      if ((mods & Modifiers.Static) !== 0) this.fail("'static' has no meaning on an operator", Codes.BadDeclHeader);
      this.advance();
      if (!(this.at(TK.Func) && this.peek().kind !== TK.LParen)) this.parseTypeSpec();
      this.expect(TK.Func);
      const op = this.parseOperatorSymbol();
      this.expect(TK.LParen); this.parseParamList(); this.expect(TK.RParen);
      if (this.at(TK.Arrow)) this.fail(`'${op}': return type goes after 'operator', not after the parameter list`, Codes.BadDeclHeader);
      this.parseMethodBody();
      return;
    }

    if (this.looksLikeMethod()) {
      if (isEntry) this.fail("'entry' has no meaning on a class method", Codes.BadDeclHeader);
      this.parseOptionalReturnType();
      this.expect(TK.Func);
      const name = this.expect(TK.Ident).value;
      this.parseGenericParamList();
      this.expect(TK.LParen); this.parseParamList(); this.expect(TK.RParen);
      if (this.at(TK.Arrow)) this.fail(`'${name}': return type goes before 'func', not after the parameter list`, Codes.BadDeclHeader);
      this.parseMethodBody();
      return;
    }

    if (isEntry) this.fail("'entry' has no meaning on a field", Codes.BadDeclHeader);
    if (isThrow) this.fail("'throws' has no meaning on a field", Codes.BadDeclHeader);
    if (anns.count > 0) this.fail('annotations have no effect on a field', Codes.BadAnnotation);
    if ((mods & Modifiers.Static) !== 0) this.fail("'static' has no meaning on a field", Codes.BadDeclHeader);

    if (this.at(TK.Ident) && this.peek().kind === TK.Eq) {
      this.advance();
    } else {
      this.parseTypeSpec();
      this.expect(TK.Ident);
    }
    if (this.try_(TK.Eq)) this.parseExpr();
    this.expect(TK.Semi);
  }

  private parseOperatorSymbol(): string {
    if (this.atP('+') || this.atP('-') || this.atP('*') || this.atP('/') || this.atP('%') || this.atP('<') || this.atP('>')) return this.advance().value;
    if (this.at(TK.EqEq) || this.at(TK.NotEq) || this.at(TK.LtEq) || this.at(TK.GtEq)) return this.advance().value;
    if (this.atP('&') || this.atP('|') || this.atP('^') || this.at(TK.Shl) || this.at(TK.Shr)) return this.advance().value;
    if (this.atP('!') || this.atP('~')) return this.advance().value;
    if (this.at(TK.Inc) || this.at(TK.Dec)) return this.advance().value;
    if (this.at(TK.LBrack)) { this.advance(); this.expect(TK.RBrack); return this.try_(TK.Eq) ? '[]=' : '[]'; }
    if (this.at(TK.As)) { this.advance(); return 'as'; }
    this.fail(`expected an operator symbol, found ${this.found()}`);
  }

  private looksLikeMethod(): boolean {
    if (this.at(TK.Func) && this.peek().kind === TK.Ident) return true;
    const n = this.skipTypeSpec(0);
    return n >= 0 && this.peek(n).kind === TK.Func;
  }

  private parseOptionalReturnType(): boolean {
    if (this.at(TK.Func) && this.peek().kind === TK.Ident) return false;
    this.parseTypeSpec();
    return true;
  }

  private parseMethodBody(): void {
    if (this.at(TK.NativeContent)) { this.advance(); return; }
    this.parseBlock();
  }

  private parseMods(): number {
    let mods: number = Modifiers.None;
    while (true) {
      let m: number = Modifiers.None;
      switch (this.cur.kind) {
        case TK.Static: m = Modifiers.Static; break;
        case TK.Public: m = Modifiers.Public; break;
        case TK.Private: m = Modifiers.Private; break;
      }
      if (m === Modifiers.None) break;
      if ((mods & m) !== 0) this.fail(`duplicate modifier '${this.cur.value}'`, Codes.ConflictingModifiers);
      mods |= m;
      this.advance();
    }
    if ((mods & Modifiers.Public) !== 0 && (mods & Modifiers.Private) !== 0)
      this.fail("'public' and 'private' cannot be combined on one declaration", Codes.ConflictingModifiers);
    return mods;
  }

  private atProcessStart(): boolean {
    if (this.at(TK.Foreground) || this.at(TK.Background)) return true;
    return this.atValue('process') && this.peek().kind === TK.Ident
      && (this.peek(2).kind === TK.LBrace || this.peek(2).kind === TK.Colon);
  }

  private atThreadStart(): boolean {
    return this.atValue('thread') || this.at(TK.Foreground) || this.at(TK.Background);
  }

  private atNestedProcess(): boolean {
    if (this.at(TK.Foreground) || this.at(TK.Background))
      return this.peek().kind === TK.Ident && this.peek().value === 'process';
    return this.atProcessStart();
  }

  private rejectStrayImport(): void {
    if (this.at(TK.Import))
      this.fail("an 'import' must be at the top level of the file", Codes.TopologyOutsideRealm,
        ['move it above the block; imports apply to the whole file']);
  }

  private rejectStrayThread(): void {
    if (this.atValue('thread') && this.peek().kind === TK.Ident && this.peek(2).kind === TK.LBrace)
      this.fail("a 'thread' must be declared inside a 'process' block", Codes.TopologyOutsideRealm,
        ["threads are a process's entry points; wrap it in 'foreground process P { ... }'"]);
  }

  private parseProcessDeclTop(): void {
    let modeExplicit = false;
    if (this.at(TK.Foreground) || this.at(TK.Background)) { modeExplicit = true; this.advance(); }
    if (!this.atValue('process')) this.fail(`expected 'process', found ${this.found()}`, Codes.BadDeclHeader);
    this.advance();
    const name = this.expect(TK.Ident).value;

    if (this.at(TK.Colon))
      this.fail(`'${name}': the deployment mode is written before 'process'`, Codes.MissingProcessMode,
        [`write 'foreground process ${name} { ... }' or 'background process ${name} { ... }'`]);

    if (!modeExplicit)
      this.fail(`'${name}': process declaration is missing a foreground/background mode`, Codes.MissingProcessMode,
        [`write 'foreground process ${name}' or 'background process ${name}'`]);

    this.expect(TK.LBrace);
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) {
      if (this.atNestedProcess()) this.fail('a process cannot be nested inside another process', Codes.InvalidNesting);
      if (this.atThreadStart()) this.parseThreadDecl();
      else this.parseProcessItem();
    }
    this.expect(TK.RBrace);
  }

  private parseProcessItem(): void {
    if (this.at(TK.Realm)) this.fail("a 'realm' block cannot appear inside a process", Codes.InvalidNesting);
    if (this.at(TK.Kernel)) this.requireRealmKeyword();
    if (this.atProcessStart()) this.fail('a process cannot be nested inside another process', Codes.InvalidNesting);
    this.rejectStrayImport();

    if (this.at(TK.AtEnvironment)) { this.advance(); return; }
    const anns = this.parseAnnotations();
    this.rejectStrayImport();
    if (this.atValue('thread')) this.rejectAnns(anns, 'a thread');
    if (this.at(TK.NativeContent)) { this.advance(); return; }
    if (this.at(TK.NativeTypeDecl)) { this.advance(); return; }
    if (this.at(TK.AtExtern)) { this.parseExternDecl(); return; }
    if (this.at(TK.Enum)) { this.rejectAnns(anns, 'an enum'); this.parseEnumDecl(); return; }
    if (this.at(TK.Union)) { this.parseUnionDecl(); return; }
    if (this.at(TK.Class)) { this.parseClassDecl(); return; }
    if (this.at(TK.Module)) { this.parseModuleDecl(); return; }
    if (this.at(TK.Let)) { this.rejectAnns(anns, 'a process variable'); this.parseProcessVarDecl(); return; }
    this.parseFreeFuncDecl();
  }

  private parseProcessVarDecl(): void {
    this.expect(TK.Let);
    this.parseTypeSpec();
    const name = this.expect(TK.Ident).value;
    if (this.try_(TK.Eq)) this.parseExpr();
    else
      this.fail(`process variable '${name}' has no initial value`, Codes.UninitialisedProcessVar, [
        `write 'let <type> ${name} = <value>;'`,
        'every thread of the process shares this one variable, so there is no point later in the '
        + 'program where a first assignment could be known to have run before a read',
      ]);
    this.expect(TK.Semi);
  }

  private parseThreadDecl(): void {
    let mode: string | null = null;
    if (this.at(TK.Foreground) || this.at(TK.Background)) { mode = this.advance().value; }
    if (!this.atValue('thread'))
      this.fail(`expected 'thread' after '${mode}', found ${this.found()}`, Codes.BadDeclHeader,
        ['a process body may contain classes, modules, enums, unions, functions, and threads']);
    this.advance();
    this.expect(TK.Ident);
    this.expect(TK.LBrace);
    this.parseThreadEntry();
    if (!this.at(TK.RBrace)) this.fail("a thread body must contain a single 'entry func' and nothing else", Codes.BadDeclHeader);
    this.expect(TK.RBrace);
  }

  private parseThreadEntry(): void {
    if (this.atValue('thread')) this.fail('threads cannot be nested', Codes.InvalidNesting);
    const mods = this.parseMods();
    const throwsFirst = this.try_(TK.Throws);
    if (!this.try_(TK.Entry)) this.fail("a thread body must contain a single 'entry func'", Codes.BadDeclHeader);
    if (throwsFirst || this.at(TK.Throws))
      this.fail(
        "a thread entry cannot be 'throws' - the runtime starts it, so there is no caller to receive the error",
        Codes.BadEntrySignature,
        ["handle failure inside the thread: 'let T x = f() catch { assign <fallback>; };'"]);
    const hasRet = !(this.at(TK.Func) && this.peek().kind === TK.Ident);
    if (hasRet) this.parseTypeSpec();
    this.expect(TK.Func);
    if (this.at(TK.Ident)) this.advance();
    this.expect(TK.LParen); const parms = this.parseParamList(); this.expect(TK.RParen);
    if (hasRet) this.fail('a thread entry has no return value; remove the return type', Codes.BadDeclHeader);
    if (mods !== Modifiers.None) this.fail('access/storage modifiers have no meaning on a thread entry', Codes.BadDeclHeader);
    if (parms > 0)
      this.fail('a thread entry takes no parameters; pass state through fields or module data instead', Codes.BadEntrySignature);
    this.parseBlock();
  }

  private parseParamList(): number {
    if (this.at(TK.RParen)) return 0;
    let n = 1;
    this.parseParam();
    while (this.try_(TK.Comma)) { this.parseParam(); n++; }
    return n;
  }

  private parseParam(): void {
    this.try_(TK.Ref);
    this.parseTypeSpec();
    this.expect(TK.Ident);
  }

  parseBlock(): void {
    this.expect(TK.LBrace);
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) this.parseStmt();
    this.expect(TK.RBrace);
  }

  private parseStmt(): void {
    this.enterDepth();
    try { this.parseStmtInner(); } finally { this.exitDepth(); }
  }

  private parseStmtInner(): void {
    if (this.at(TK.NativeContent)) { this.advance(); return; }
    if (this.at(TK.LBrace)) { this.parseBlock(); return; }
    if (this.at(TK.Let)) { this.parseLetStmt(); return; }
    if (this.at(TK.If)) { this.parseIfStmt(); return; }
    if (this.at(TK.While)) { this.parseWhileStmt(); return; }
    if (this.at(TK.For)) { this.parseForStmt(); return; }
    if (this.at(TK.Switch)) { this.parseSwitchStmt(); return; }
    if (this.at(TK.Match)) { this.parseMatchStmt(); return; }
    if (this.at(TK.Try)) { this.parseTryCatchStmt(); return; }
    if (this.at(TK.Unsafe)) { this.parseUnsafeBlock(); return; }
    if (this.at(TK.Defer)) { this.advance(); this.parseStmt(); return; }
    if (this.at(TK.Return)) { this.advance(); if (!this.at(TK.Semi)) this.parseExpr(); this.expect(TK.Semi); return; }
    if (this.at(TK.Break)) { this.advance(); this.expect(TK.Semi); return; }
    if (this.at(TK.Continue)) { this.advance(); this.expect(TK.Semi); return; }
    if (this.at(TK.Throw)) { this.advance(); this.expect(TK.Semi); return; }
    if (this.at(TK.Assign)) { this.advance(); this.parseExpr(); this.expect(TK.Semi); return; }
    if (this.at(TK.Debug)) {
      this.advance();
      if (!this.at(TK.StrLit)) this.fail("'debug' takes a string literal", Codes.Syntax, ['e.g. debug "message";']);
      this.advance();
      this.expect(TK.Semi);
      return;
    }
    if (this.at(TK.Panic)) {
      this.advance();
      if (!this.at(TK.StrLit)) this.fail("'panic' takes a string literal", Codes.Syntax, ['e.g. panic "message";']);
      this.advance();
      this.expect(TK.Semi);
      return;
    }
    if (this.looksLikeMissingLet())
      this.fail('expected a statement', Codes.MissingLet,
        this.at(TK.Ident) ? ["missing 'let'?", `e.g. 'let ${this.cur.value} ...'`] : ["missing 'let'?"]);
    this.parseExprOrAssign();
  }

  private parseLetStmt(): void {
    this.expect(TK.Let);
    if (this.looksLikeTypeAndIdent()) this.parseTypeSpec();
    this.expect(TK.Ident);
    if (this.try_(TK.Eq)) this.parseExpr();
    this.expect(TK.Semi);
  }

  private skipBrackets(n: number): number {
    let depth = 0;
    do {
      const t = this.peek(n);
      if (t.kind === TK.EOF) return -1;
      if (t.kind === TK.LBrack) depth++;
      else if (t.kind === TK.RBrack) depth--;
      n++;
    } while (depth > 0);
    return n;
  }

  private skipFuncTypeSpec(n: number): number {
    if (this.peek(n).kind !== TK.Func) return -1;
    n++;
    if (this.peek(n).kind !== TK.LParen) return -1;
    n++;
    if (this.peek(n).kind !== TK.RParen) {
      n = this.skipTypeSpec(n);
      if (n < 0) return -1;
      while (this.peek(n).kind === TK.Comma) {
        n++;
        n = this.skipTypeSpec(n);
        if (n < 0) return -1;
      }
    }
    if (this.peek(n).kind !== TK.RParen) return -1;
    n++;
    if (this.peek(n).kind !== TK.Arrow) return -1;
    n++;
    return this.skipTypeSpec(n);
  }

  private skipTypeSpec(n: number): number {
    while (this.peek(n).kind === TK.LBrack && this.peek(n + 1).kind === TK.IntLit && this.peek(n + 2).kind === TK.RBrack) n += 3;
    if (this.peek(n).kind === TK.Func) {
      n = this.skipFuncTypeSpec(n);
      if (n < 0) return -1;
    } else if (this.isPrim(this.peek(n).kind)) {
      n++;
    } else if (this.peek(n).kind === TK.Ident || this.peek(n).kind === TK.ColonColon
      || this.peek(n).kind === TK.Kernel || this.peek(n).kind === TK.Userspace) {
      if (this.peek(n).kind === TK.ColonColon) n++;
      else if (this.peek(n).kind === TK.Kernel || this.peek(n).kind === TK.Userspace) {
        if (this.peek(n + 1).kind !== TK.Dot) return -1;
        n += 2;
      }
      if (this.peek(n).kind !== TK.Ident) return -1;
      n++;
      while (this.peek(n).kind === TK.Dot && this.peek(n + 1).kind === TK.Ident) n += 2;
      if (this.peek(n).kind === TK.LBrack) { n = this.skipBrackets(n); if (n < 0) return -1; }
    } else return -1;
    while (this.peek(n).kind === TK.Punct && this.peek(n).value === '*') n++;
    return n;
  }

  private looksLikeMissingLet(): boolean {
    if (!this.at(TK.Ident) && !this.at(TK.LBrack)) return false;
    const n = this.skipTypeSpec(0);
    return n >= 0 && this.peek(n).kind === TK.Ident;
  }

  private looksLikeTypeAndIdent(): boolean {
    if (this.isPrim(this.cur.kind)) return true;
    if (this.at(TK.Func)) return true;
    if (this.at(TK.LBrack) && this.peek().kind === TK.IntLit && this.peek(2).kind === TK.RBrack) return true;
    if (this.at(TK.ColonColon)) return true;
    if (this.at(TK.Kernel) || this.at(TK.Userspace)) return this.peek().kind === TK.Dot;
    if (!this.at(TK.Ident)) return false;
    return (
      this.peek().kind === TK.Ident ||
      this.peek().kind === TK.LBrack ||
      (this.peek().kind === TK.Punct && this.peek().value === '*')
    );
  }

  private parseLetNoSemi(): void {
    this.expect(TK.Let);
    if (this.looksLikeTypeAndIdent()) this.parseTypeSpec();
    this.expect(TK.Ident);
    if (this.try_(TK.Eq)) this.parseExpr();
  }

  private parseIfStmt(): void {
    this.expect(TK.If); this.expect(TK.LParen); this.parseExpr();
    this.noAssignHere("an 'if' condition", this.at(TK.Eq) ? "did you mean '=='?" : "assign before the 'if' instead");
    this.expect(TK.RParen);
    this.parseStmt();
    if (this.try_(TK.Else)) this.parseStmt();
  }

  private parseWhileStmt(): void {
    this.expect(TK.While); this.expect(TK.LParen); this.parseExpr();
    this.noAssignHere("a 'while' condition", this.at(TK.Eq) ? "did you mean '=='?" : 'move the update into the loop body');
    this.expect(TK.RParen);
    this.parseStmt();
  }

  private parseForStmt(): void {
    this.expect(TK.For);
    if (this.at(TK.Ident) && this.peek().kind === TK.In) {
      this.advance();
      this.advance();
      this.parseExpr();
      this.parseBlock();
      return;
    }

    this.expect(TK.LParen);
    if ((this.at(TK.Ident) && this.peek().kind === TK.In)
      || (this.at(TK.Let) && this.peek().kind === TK.Ident && this.peek(2).kind === TK.In))
      this.fail("a 'for ... in' loop is written without parentheses", Codes.Syntax, [
        "write 'for x in xs { ... }'",
        "the parenthesised form is the C-style loop, which takes 'for (init; condition; step)'",
      ]);

    if (!this.at(TK.Semi)) {
      if (this.at(TK.Let)) this.parseLetNoSemi();
      else this.parseForClause();
    }
    this.expect(TK.Semi);
    let hasCond = false;
    if (!this.at(TK.Semi)) { this.parseExpr(); hasCond = true; }
    if (hasCond) this.noAssignHere('the loop condition', this.at(TK.Eq) ? "did you mean '=='?" : 'move the update into the loop body');
    this.expect(TK.Semi);
    if (!this.at(TK.RParen)) {
      if (this.at(TK.Let)) this.fail('cannot declare a variable in the for-loop step');
      this.parseForClause();
    }
    this.expect(TK.RParen);
    this.parseBlock();
  }

  private parseForClause(): void {
    this.parseExpr();
    if (this.isAssignTk(this.cur.kind)) {
      this.advance();
      this.parseExpr();
    }
  }

  private parseTryCatchStmt(): void {
    this.expect(TK.Try);
    this.parseBlock();
    this.expect(TK.Catch);
    this.parseBlock();
  }

  private parseUnsafeBlock(): void {
    this.expect(TK.Unsafe);
    this.parseBlock();
  }

  private parseExprOrAssign(): void {
    this.parseExpr();
    if (this.isAssignTk(this.cur.kind)) {
      this.advance();
      this.parseExpr();
      this.expect(TK.Semi);
      return;
    }
    this.expect(TK.Semi);
  }

  parseExpr(): void {
    this.parseTernary();
  }

  private parseTernary(): void {
    this.enterDepth();
    try { this.parseTernaryInner(); } finally { this.exitDepth(); }
  }

  private parseTernaryInner(): void {
    this.parseOr();
    if (!this.atP('?')) return;
    this.advance();
    this.parseExpr();
    if (this.at(TK.ColonColon))
      this.fail("'::' names the root scope and cannot be the ':' of a conditional", Codes.Syntax,
        ["put a space after the ':', as in 'c ? a : ::Name'"]);
    this.expect(TK.Colon);
    this.parseTernary();
  }

  private parseOr(): void {
    this.parseAnd();
    while (this.at(TK.Or)) { this.advance(); this.parseAnd(); }
  }
  private parseAnd(): void {
    this.parseBitOr();
    while (this.at(TK.And)) { this.advance(); this.parseBitOr(); }
  }
  private parseBitOr(): void {
    this.parseBitXor();
    while (this.atP('|')) { this.advance(); this.parseBitXor(); }
  }
  private parseBitXor(): void {
    this.parseBitAnd();
    while (this.atP('^')) { this.advance(); this.parseBitAnd(); }
  }
  private parseBitAnd(): void {
    this.parseEquality();
    while (this.atP('&')) { this.advance(); this.parseEquality(); }
  }
  private parseEquality(): void {
    this.parseRelational();
    while (this.at(TK.EqEq) || this.at(TK.NotEq)) { this.advance(); this.parseRelational(); }
  }
  private parseRelational(): void {
    this.parseShift();
    while (this.atP('<') || this.atP('>') || this.at(TK.LtEq) || this.at(TK.GtEq)) { this.advance(); this.parseShift(); }
  }
  private parseShift(): void {
    this.parseAdditive();
    while (this.at(TK.Shl) || this.at(TK.Shr)) { this.advance(); this.parseAdditive(); }
  }
  private parseAdditive(): void {
    this.parseMultiplicative();
    while (this.atP('+') || this.atP('-')) { this.advance(); this.parseMultiplicative(); }
  }
  private parseMultiplicative(): void {
    this.parseAs();
    while (this.atP('*') || this.atP('/') || this.atP('%')) { this.advance(); this.parseAs(); }
  }
  private parseAs(): void {
    this.parseUnary();
    while (this.at(TK.As)) { this.advance(); this.parseTypeSpec(); }
  }

  private parseUnary(): void {
    this.enterDepth();
    try { this.parseUnaryInner(); } finally { this.exitDepth(); }
  }

  private parseUnaryInner(): void {
    if (this.atP('!') || this.atP('~') || this.atP('-') || this.atP('&') || this.atP('*')) {
      this.advance();
      this.parseUnary();
      return;
    }
    this.parsePostfix();
  }

  private parsePostfix(): void {
    this.parsePrimary();
    let called = false;
    while (true) {
      if (this.at(TK.Inc) || this.at(TK.Dec)) { this.advance(); }
      else if (this.at(TK.Dot)) { this.advance(); this.expect(TK.Ident); called = false; }
      else if (this.at(TK.LBrack)) { this.parseBracketed(); called = false; }
      else if (this.at(TK.LParen)) { this.advance(); this.parseArgList(); this.expect(TK.RParen); called = true; }
      else if (this.at(TK.Catch)) {
        if (!called)
          this.fail("'catch' here must follow a call to a 'throws' function", Codes.Syntax,
            ['e.g. let int x = Parse(s) catch { assign 0; };']);
        this.advance();
        this.parseBlock();
        called = false;
      }
      else break;
    }
  }

  private parseBracketed(): void {
    this.rejectExplicitTypeArgs();
    const start = this.mark();

    let sawTypeArgs = false;
    try {
      this.advance();
      this.parseTypeName();
      while (this.try_(TK.Comma)) this.parseTypeName();
      if (this.at(TK.RBrack)) {
        this.advance();
        if (this.at(TK.Dot)) sawTypeArgs = true;
      }
    } catch (e) {
      if (!(e instanceof ParseError)) throw e;
    }

    if (sawTypeArgs) return;

    this.rewind(start);
    this.advance();
    this.parseExpr();
    this.expect(TK.RBrack);
  }

  private rejectExplicitTypeArgs(): void {
    let i = 1;
    let sawPrim = false;
    let depth = 1;
    for (; this.pp + i < this.tokens.length; i++) {
      const k = this.peek(i).kind;
      if (k === TK.LBrack) depth++;
      else if (k === TK.RBrack && --depth === 0) break;
      else if (this.isPrim(k)) sawPrim = true;
      else if (k === TK.LParen || k === TK.Semi || k === TK.LBrace) return;
    }
    if (!sawPrim || this.peek(i).kind !== TK.RBrack) return;
    if (this.peek(i + 1).kind !== TK.LParen) return;

    this.fail('a function call cannot take explicit type arguments', Codes.ExplicitTypeArgs, [
      "type parameters are inferred from the argument types, so write 'f(x)' rather than 'f[T](x)'",
      'if the element at an index is what you meant to call, the index has to be an expression - '
      + 'a type name is not one',
    ]);
  }

  private parseArgList(): void {
    if (this.at(TK.RParen)) return;
    this.parseArg();
    while (this.try_(TK.Comma)) this.parseArg();
  }

  private parseArg(): void {
    this.try_(TK.Ref);
    this.parseExpr();
  }

  private parsePrimary(): void {
    this.enterDepth();
    try { this.parsePrimaryInner(); } finally { this.exitDepth(); }
  }

  private parsePrimaryInner(): void {
    if (this.parseScopeQualifier()) {
      this.expectIdent('a scope or declaration name');
      while (this.at(TK.Dot) && this.peek().kind === TK.Ident) { this.advance(); this.advance(); }
      if (this.at(TK.LBrack)) {
        this.advance();
        this.parseTypeName();
        while (this.try_(TK.Comma)) this.parseTypeName();
        this.expect(TK.RBrack);
        while (this.at(TK.Dot) && this.peek().kind === TK.Ident) { this.advance(); this.advance(); }
      }
      return;
    }

    if (this.at(TK.IntLit) || this.at(TK.FloatLit) || this.at(TK.BoolLit) || this.at(TK.CharLit)
      || this.at(TK.StrLit) || this.at(TK.Null)) { this.advance(); return; }
    if (this.at(TK.InterpStrStart)) { this.parseInterpStr(); return; }

    if (this.at(TK.Sizeof) || this.at(TK.Default)) {
      this.advance(); this.expect(TK.LParen);
      this.parseTypeSpec();
      this.expect(TK.RParen);
      return;
    }

    if (this.at(TK.New)) { this.parseNewExpr(); return; }

    if (this.at(TK.LBrack)) {
      this.advance();
      if (this.at(TK.RBrack)) { this.advance(); return; }
      this.parseExpr();
      while (this.try_(TK.Comma)) this.parseExpr();
      this.expect(TK.RBrack);
      return;
    }

    if (this.at(TK.LParen)) {
      this.advance();
      if (this.isPrim(this.cur.kind)) {
        this.parseTypeSpec();
        this.expect(TK.RParen);
        this.parseUnary();
        return;
      }
      this.parseExpr();
      this.expect(TK.RParen);
      return;
    }

    if (this.at(TK.Ident)) { this.advance(); return; }

    this.fail(`expected an expression, found ${this.found()}`);
  }

  private parseInterpStr(): void {
    this.advance(); // InterpStrStart
    while (!this.at(TK.InterpStrEnd) && !this.at(TK.EOF)) {
      if (this.at(TK.StrLit)) { this.advance(); }
      else if (this.atP('{')) {
        this.advance();
        this.parseExpr();
        if (!this.atP('}')) this.fail(`expected '}' to close the interpolated expression, found ${this.found()}`);
        this.advance();
      } else break;
    }
    this.expect(TK.InterpStrEnd);
  }

  private parseNewExpr(): void {
    this.expect(TK.New);
    this.parseTypeSpec();
    if (this.at(TK.LParen)) {
      this.advance();
      this.parseArgList();
      this.expect(TK.RParen);
    }
    if (this.at(TK.LBrace)) { this.parseCollectionInit(TK.LBrace, TK.RBrace); return; }
    if (this.at(TK.LBrack)) { this.parseCollectionInit(TK.LBrack, TK.RBrack); return; }
  }

  private parseCollectionInit(open: TK, close: TK): void {
    this.advance();
    if (this.at(close)) { this.advance(); return; }
    this.parseExpr();
    while (this.try_(TK.Comma)) this.parseExpr();
    this.expect(close);
  }

  private parseSwitchStmt(): void {
    this.expect(TK.Switch); this.expect(TK.LParen); this.parseExpr(); this.expect(TK.RParen);
    this.expect(TK.LBrace);
    let sawDefault = false;
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) {
      if (this.at(TK.Default)) {
        this.advance();
        if (sawDefault) this.fail("'switch' already has a 'default' arm; remove one", Codes.DuplicateName);
        sawDefault = true;
        this.parseBlock();
        continue;
      }
      this.expect(TK.Case);
      this.parseExpr();
      while (this.try_(TK.Comma)) this.parseExpr();
      this.parseBlock();
    }
    this.expect(TK.RBrace);
  }

  private parseMatchStmt(): void {
    this.expect(TK.Match); this.expect(TK.LParen); this.parseExpr(); this.expect(TK.RParen);
    this.expect(TK.LBrace);
    let sawDefault = false;
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) {
      if (this.at(TK.Default)) {
        this.advance();
        if (sawDefault) this.fail("'match' already has a 'default' arm; remove one", Codes.DuplicateName);
        sawDefault = true;
        this.parseBlock();
        continue;
      }
      this.expect(TK.Case);
      this.expect(TK.Ident);
      if (this.at(TK.LParen)) {
        this.advance();
        if (!this.at(TK.RParen)) {
          this.expect(TK.Ident);
          while (this.try_(TK.Comma)) this.expect(TK.Ident);
        }
        this.expect(TK.RParen);
      }
      this.parseBlock();
    }
    this.expect(TK.RBrace);
  }
}
