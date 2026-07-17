// Direct port of Appa/src/Syntax/Parser.cs's control flow and diagnostics. This is a
// diagnostics-only parser: it walks the token stream exactly like the real recursive
// descent parser (same grammar, same order of checks, same error codes/messages/hints)
// but does not build a retained AST, since the language server only needs to know
// *whether and where* a file fails to parse, not to re-emit or transform it. Where the
// real parser returns an AST node, this returns void and simply keeps advancing.
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
  [TK.Dot]: "'.'", [TK.Eq]: "'='", [TK.Arrow]: "'->'",
  [TK.EOF]: 'end of file',
};

const MAX_DEPTH = 200;

export class Parser {
  private readonly tokens: Token[];
  private pp = 0;
  private pe = 0;
  private depth = 0;

  constructor(tokens: Token[]) {
    this.tokens = tokens;
  }

  // #region Core stream helpers

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

  // #endregion

  // #region Annotations

  private parseAnnotations(): void {
    while (true) {
      if (this.at(TK.AtIntrinsic)) { this.advance(); }
      else if (this.at(TK.AtPreamble)) { this.advance(); }
      else if (this.at(TK.AtKeep)) { this.advance(); }
      else if (this.at(TK.AtBuiltin)) { this.advance(); }
      else break;
    }
  }

  private rejectAnnsCount(count: number, what: string, span: Span): void {
    if (count > 0) this.failAt(span, `annotations have no effect on ${what}`, Codes.BadAnnotation);
  }

  // #endregion

  // #region Top-level declarations

  parseProgram(): void {
    while (!this.at(TK.EOF)) this.parseTopLevel();
  }

  private parseFreeFuncDecl(): void {
    this.parseMods();
    this.try_(TK.Entry);
    this.try_(TK.Throws);
    const ret = this.parseOptionalReturnType();
    if (ret && this.at(TK.LBrace))
      this.fail(`expected 'func', found '{' -- did you forget 'process' before it?`, Codes.BadDeclHeader);
    this.expect(TK.Func);
    const name = this.expect(TK.Ident).value;
    this.parseGenericParamList();
    this.expect(TK.LParen); this.parseParamList(); this.expect(TK.RParen);
    if (this.at(TK.Arrow)) this.fail(`'${name}': return type goes before 'func', not after the parameter list`, Codes.BadDeclHeader);
    this.parseMethodBody();
  }

  private parseGenericParamList(): void {
    if (!this.at(TK.LBrack)) return;
    this.advance();
    this.expectBareGenericParam();
    while (this.try_(TK.Comma)) this.expectBareGenericParam();
    this.expect(TK.RBrack);
  }

  private parseTopLevel(): void {
    if (this.at(TK.Import)) { this.parseImport(); return; }
    if (this.at(TK.AtEnvironment)) { this.advance(); return; }
    const s = this.cur.span.start;
    let annCount = 0;
    while (this.at(TK.AtIntrinsic) || this.at(TK.AtPreamble) || this.at(TK.AtKeep) || this.at(TK.AtBuiltin)) {
      this.advance();
      annCount++;
    }
    if (this.at(TK.NativeContent)) { this.advance(); return; }
    if (this.at(TK.NativeTypeDecl)) { this.parseNativeType(); return; }

    if (this.at(TK.Enum)) { this.rejectAnnsCount(annCount, 'an enum', this.to(s)); this.parseEnumDecl(); return; }
    if (this.at(TK.Union)) { this.rejectAnnsCount(annCount, 'a union', this.to(s)); this.parseUnionDecl(); return; }
    if (this.at(TK.Class)) { this.parseClassDecl(); return; }
    if (this.at(TK.Module)) { this.parseModuleDecl(); return; }
    if (this.at(TK.Kernel)) { this.rejectAnnsCount(annCount, 'kernel', this.to(s)); this.parseContextDecl(); return; }
    if (this.at(TK.User)) { this.rejectAnnsCount(annCount, 'user', this.to(s)); this.parseContextDecl(); return; }
    if (this.at(TK.Process) || this.at(TK.Foreground) || this.at(TK.Background)) {
      this.rejectAnnsCount(annCount, 'a process', this.to(s));
      this.parseProcessDeclTop();
      return;
    }
    if (this.at(TK.AtExtern)) { this.parseExternDecl(); return; }
    this.parseFreeFuncDecl();
  }

  private parseImport(): void {
    this.expect(TK.Import);
    if (this.at(TK.StrLit)) { this.advance(); this.expect(TK.Semi); return; }
    this.expect(TK.Ident);
    this.expect(TK.Semi);
  }

  private parseNativeType(): void {
    this.advance();
  }

  private parseExternDecl(): void {
    this.advance(); // @extern
    this.parseOptionalReturnType();
    this.expect(TK.Func);
    const name = this.expect(TK.Ident).value;
    this.expect(TK.LParen); this.parseParamList(); this.expect(TK.RParen);
    if (this.at(TK.Arrow)) this.fail(`'${name}': return type goes before 'func', not after the parameter list`, Codes.BadDeclHeader);
    this.expect(TK.Semi);
  }

  private parseContextDecl(): void {
    this.advance();
    this.expect(TK.LBrace);
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) this.parseContextItem();
    this.expect(TK.RBrace);
  }

  private parseContextItem(): void {
    if (this.at(TK.Kernel) || this.at(TK.User)) this.fail('contexts cannot be nested', Codes.InvalidNesting);
    const s = this.cur.span.start;
    let annCount = 0;
    while (this.at(TK.AtIntrinsic) || this.at(TK.AtPreamble) || this.at(TK.AtKeep) || this.at(TK.AtBuiltin)) {
      this.advance();
      annCount++;
    }
    if (this.at(TK.NativeContent)) { this.advance(); return; }
    if (this.at(TK.NativeTypeDecl)) { this.parseNativeType(); return; }
    if (this.at(TK.AtExtern)) { this.parseExternDecl(); return; }
    if (this.at(TK.Enum)) { this.rejectAnnsCount(annCount, 'an enum', this.to(s)); this.parseEnumDecl(); return; }
    if (this.at(TK.Union)) { this.rejectAnnsCount(annCount, 'a union', this.to(s)); this.parseUnionDecl(); return; }
    if (this.at(TK.Class)) { this.parseClassDecl(); return; }
    if (this.at(TK.Module)) { this.parseModuleDecl(); return; }
    if (this.at(TK.Process) || this.at(TK.Foreground) || this.at(TK.Background)) {
      this.rejectAnnsCount(annCount, 'a process', this.to(s));
      this.parseProcessDeclTop();
      return;
    }
    this.parseFreeFuncDecl();
  }

  // #endregion

  // #region Class and module

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

  // #endregion

  // #region Enum and union

  private parseEnumDecl(): void {
    this.expect(TK.Enum);
    this.expect(TK.Ident);
    this.expect(TK.LBrace);
    if (!this.at(TK.RBrace) && !this.at(TK.EOF)) {
      this.expect(TK.Ident);
      if (this.try_(TK.Eq)) this.parseExpr();
      while (this.try_(TK.Comma)) {
        if (this.at(TK.RBrace)) this.fail("trailing comma not allowed after the last enum member; remove it", Codes.TrailingComma);
        this.expect(TK.Ident);
        if (this.try_(TK.Eq)) this.parseExpr();
      }
    }
    this.expect(TK.RBrace);
  }

  private parseUnionDecl(): void {
    this.expect(TK.Union);
    this.expect(TK.Ident);
    this.expect(TK.LBrace);
    if (!this.at(TK.RBrace) && !this.at(TK.EOF)) {
      this.expect(TK.Ident);
      if (this.at(TK.LParen)) this.parseUnionFieldList();
      while (this.try_(TK.Comma)) {
        if (this.at(TK.RBrace)) this.fail("trailing comma not allowed after the last union variant; remove it", Codes.TrailingComma);
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
      if (this.at(TK.RParen)) this.fail("trailing comma not allowed after the last field; remove it", Codes.TrailingComma);
      this.parseParam();
    }
    this.expect(TK.RParen);
  }

  // #endregion

  // #region Type specs

  private parseTypeName(): void {
    this.enterDepth();
    try { this.parseTypeNameInner(); } finally { this.exitDepth(); }
  }

  private parseTypeNameInner(): void {
    const name = this.parseSimpleTypeName();
    if (!this.at(TK.LBrack)) return;
    this.advance();
    this.parseTypeName();
    while (this.try_(TK.Comma)) this.parseTypeName();
    if (!this.at(TK.RBrack)) this.fail(`invalid type argument in '${name}[...]', found ${this.found()}`);
    this.expect(TK.RBrack);
  }

  private parseSimpleTypeName(): string {
    if (this.at(TK.Ident)) return this.advance().value;
    if (this.isPrim(this.cur.kind)) return this.primName(this.advance());
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

  // #endregion

  // #region Class members

  private parseClassMember(): void {
    if (this.at(TK.Class) || this.at(TK.Module)) this.fail('classes and modules cannot be nested', Codes.InvalidNesting);
    if (this.at(TK.Kernel) || this.at(TK.User)) this.fail('context blocks cannot appear inside a class', Codes.InvalidNesting);

    if (this.at(TK.Fields)) { this.advance(); return; }

    let annCount = 0;
    while (this.at(TK.AtIntrinsic) || this.at(TK.AtPreamble) || this.at(TK.AtKeep) || this.at(TK.AtBuiltin)) {
      this.advance();
      annCount++;
    }
    const mods = this.parseMods();
    const isEntry = this.try_(TK.Entry);
    const isThrow = this.try_(TK.Throws);

    if (this.at(TK.Operator)) {
      if (annCount > 0) this.fail('annotations have no effect on an operator', Codes.BadAnnotation);
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
      this.expect(TK.LParen); this.parseParamList(); this.expect(TK.RParen);
      if (this.at(TK.Arrow)) this.fail(`'${name}': return type goes before 'func', not after the parameter list`, Codes.BadDeclHeader);
      this.parseMethodBody();
      return;
    }

    if (isEntry) this.fail("'entry' has no meaning on a field", Codes.BadDeclHeader);
    if (isThrow) this.fail("'throws' has no meaning on a field", Codes.BadDeclHeader);
    if (annCount > 0) this.fail('annotations have no effect on a field', Codes.BadAnnotation);
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
    if (this.atP('+') || this.atP('-') || this.atP('*') || this.atP('/') || this.atP('<') || this.atP('>')) return this.advance().value;
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
    let mods = Modifiers.None;
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

  // #endregion

  // #region Process and thread

  private parseProcessDeclTop(): void {
    let mode = 'foreground';
    let modeExplicit = false;
    if (this.at(TK.Foreground)) { mode = 'foreground'; modeExplicit = true; this.advance(); }
    else if (this.at(TK.Background)) { mode = 'background'; modeExplicit = true; this.advance(); }
    this.expect(TK.Process);
    const name = this.expect(TK.Ident).value;
    if (this.try_(TK.Colon)) {
      if (modeExplicit) this.fail(`'${name}': mode specified twice`, Codes.BadDeclHeader);
      if (this.at(TK.Foreground)) { mode = 'foreground'; modeExplicit = true; this.advance(); }
      else if (this.at(TK.Background)) { mode = 'background'; modeExplicit = true; this.advance(); }
      else this.fail(`expected 'foreground' or 'background' after ':', found ${this.found()}`, Codes.BadDeclHeader);
    }
    if (!modeExplicit)
      this.fail(
        `'${name}': process declaration is missing a foreground/background mode -- write 'foreground process ${name}' or 'background process ${name}'`,
        Codes.MissingProcessMode,
      );
    this.expect(TK.LBrace);
    while (!this.at(TK.RBrace) && !this.at(TK.EOF)) this.parseThreadDecl();
    this.expect(TK.RBrace);
  }

  private parseThreadDecl(): void {
    if (this.at(TK.Foreground)) this.advance();
    else if (this.at(TK.Background)) this.advance();
    if (!this.at(TK.Thread)) this.fail("a process body may only contain 'thread' declarations", Codes.BadDeclHeader);
    this.advance();
    this.expect(TK.Ident);
    this.expect(TK.LBrace);
    this.parseThreadEntry();
    if (!this.at(TK.RBrace)) this.fail("a thread body must contain a single 'entry func' and nothing else", Codes.BadDeclHeader);
    this.expect(TK.RBrace);
  }

  private parseThreadEntry(): void {
    if (this.at(TK.Thread)) this.fail('threads cannot be nested', Codes.InvalidNesting);
    const mods = this.parseMods();
    if (!this.try_(TK.Entry)) this.fail("a thread body must contain a single 'entry func'", Codes.BadDeclHeader);
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

  // #endregion

  // #region Parameters

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

  // #endregion

  // #region Statements

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
    const s = this.cur.span.start;
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
      this.fail("expected a statement -- missing 'let'?", Codes.MissingLet, this.at(TK.Ident) ? [`e.g. 'let ${this.cur.value} ...'`] : undefined);
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
    } else if (this.peek(n).kind === TK.Ident) {
      n++;
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
      this.advance(); // 'in'
      this.parseExpr();
      this.parseBlock();
      return;
    }

    this.expect(TK.LParen);
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

  // #endregion

  // #region Expressions

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
    if (this.atP('!')) { this.advance(); this.parseUnary(); return; }
    if (this.atP('~')) { this.advance(); this.parseUnary(); return; }
    if (this.atP('-')) { this.advance(); this.parseUnary(); return; }
    if (this.atP('&')) { this.advance(); this.parseUnary(); return; }
    if (this.atP('*')) { this.advance(); this.parseUnary(); return; }
    this.parsePostfix();
  }

  private parsePostfix(): void {
    this.parsePrimary();
    while (true) {
      if (this.at(TK.Inc)) { this.advance(); }
      else if (this.at(TK.Dec)) { this.advance(); }
      else if (this.at(TK.Dot)) { this.advance(); this.expect(TK.Ident); }
      else if (this.at(TK.LBrack)) { this.advance(); this.parseExpr(); this.expect(TK.RBrack); }
      else if (this.at(TK.LParen)) { this.advance(); this.parseArgList(); this.expect(TK.RParen); }
      else break;
    }
  }

  private parseArgList(): void {
    if (this.at(TK.RParen)) return;
    this.parseArg();
    while (this.try_(TK.Comma)) this.parseArg();
  }

  private parseArg(): void {
    if (this.try_(TK.Ref)) { this.parseExpr(); return; }
    this.parseExpr();
  }

  private parsePrimary(): void {
    this.enterDepth();
    try { this.parsePrimaryInner(); } finally { this.exitDepth(); }
  }

  private parsePrimaryInner(): void {
    if (this.at(TK.IntLit)) { this.advance(); return; }
    if (this.at(TK.FloatLit)) { this.advance(); return; }
    if (this.at(TK.BoolLit)) { this.advance(); return; }
    if (this.at(TK.CharLit)) { this.advance(); return; }
    if (this.at(TK.StrLit)) { this.advance(); return; }
    if (this.at(TK.Null)) { this.advance(); return; }
    if (this.at(TK.InterpStrStart)) { this.parseInterpStr(); return; }

    if (this.at(TK.Sizeof)) {
      this.advance(); this.expect(TK.LParen);
      this.parseTypeSpec();
      this.expect(TK.RParen);
      return;
    }
    if (this.at(TK.Default)) {
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

  // #endregion

  // #region Switch and match

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

  // #endregion
}
