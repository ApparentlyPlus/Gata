/*
 * Parser.g - recursive-descent parser: token stream to an untyped AST
 *
 * Ports Appa/src/Syntax/Parser.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Int.g";
import "src/Diagnostics/TextSpan.g";
import "src/Diagnostics/Diagnostic.g";
import "src/Syntax/Token.g";
import "src/Syntax/Ast.g";

/*
 * Everything a speculative parse may advance, so it can be put back exactly.
 */
class Snapshot {
    public int pos;
    public int end;
    public int depth;
    public int uses;
    func _init(int pos, int end, int depth, int uses) {
        self.pos = pos;
        self.end = end;
        self.depth = depth;
        self.uses = uses;
    }
}

/*
 * Recursive-descent parser that converts a flat token stream into an untyped AST. One instance
 * per file. Call ParseProgram() once and discard.
 */
class Parser {
    List[Token] tokens;

    // current position in the token list
    int pp;

    // end offset of the last consumed token, used by To()
    int pe;

    // Recursion depth guard. Without it, (((((...))))) stack-overflows instead of failing cleanly.
    int depth;

    // Generic instantiation sites collected during parsing, consumed by the Monomorphizer.
    List[GenericUse] gu;

    // Set the moment any scope qualifier is written, so the ScopeBinder knows whether a file that
    // declares nothing scoped still needs its rewrite sweep.
    bool scopedRef;

    // Where a failed parse leaves its detail; `throw;` carries no payload. Shared shape with the
    // Lexer (see ParseError in Diagnostic.g).
    public ParseError lastErr;

    func _init(List[Token] tokens) {
        self.tokens = tokens;
        self.pp = 0;
        self.pe = 0;
        self.depth = 0;
        self.gu = new List[GenericUse]();
        self.scopedRef = false;
        self.lastErr = PErr.Nothing();
    }

    /*
     * MaxDepth - The recursion ceiling; C#'s MaxDepth const
     */
    int func MaxDepth() { return 200; }

    /*
     * EnterDepth - Increments the recursion depth counter and fails past MaxDepth
     */
    throws void func EnterDepth() {
        self.depth = self.depth + 1;
        if (self.depth > self.MaxDepth()) { self.Fail("nested too deeply"); }
    }

    /*
     * ExitDepth - Decrements the recursion depth counter
     */
    void func ExitDepth() { self.depth = self.depth - 1; }

    /*
     * Cur - The token at the current position. Safe without a bounds check because Advance()
     * clamps pp to [0, Length-1].
     */
    Token func Cur() { return self.tokens.Get(self.pp); }

    /*
     * Peek - The next token, or the last token at the end of the stream
     */
    Token func Peek() { return self.Peek(1); }

    /*
     * Peek - The token n positions ahead, or the last token if the offset exceeds the stream
     */
    Token func Peek(int n) {
        if ((self.pp + n) < self.tokens.Length()) { return self.tokens.Get(self.pp + n); }
        return self.tokens.Get(self.tokens.Length() - 1);
    }

    /*
     * PeekKind - The kind of the token n positions ahead
     */
    TK func PeekKind(int n) { return Toks.Kind(self.Peek(n)); }

    /*
     * CurKind - The kind of the current token
     */
    TK func CurKind() { return Toks.Kind(self.Cur()); }

    /*
     * CurStart - The start offset of the current token
     */
    int func CurStart() { return TS.Start(Toks.Span(self.Cur())); }

    /*
     * Advance - Consumes the current token, updates pe for span construction, and advances pp
     */
    Token func Advance() {
        let Token t = self.Cur();
        self.pe = TS.End(Toks.Span(t));
        if (self.pp < self.tokens.Length() - 1) { self.pp = self.pp + 1; }
        return t;
    }

    /*
     * To - A TextSpan from a saved start offset to the end of the last consumed token
     */
    TextSpan func To(int start) {
        let int len = self.pe - start;
        return TextSpan.Span(start, len > 0 ? len : 0);
    }

    /*
     * Expect - Consumes a token of the expected kind, or fails
     */
    throws Token func Expect(TK k) {
        if (self.CurKind() != k) {
            self.Fail("expected " + KindName(k) + ", found " + self.Found());
        }
        return self.Advance();
    }

    /*
     * ExpectValue - Consumes a token of the expected kind and hands back its text
     */
    throws String func ExpectValue(TK k) {
        let Token t = self.Expect(k);
        return Toks.Value(t);
    }

    /*
     * Found - Describes the current token for an error message: its quoted source text, or
     * 'end of file'
     */
    String func Found() {
        if (self.CurKind() == TK.EOF) { return "end of file"; }
        return "'" + Toks.Value(self.Cur()) + "'";
    }

    /*
     * At - True if the current token has the given kind
     */
    bool func At(TK k) { return self.CurKind() == k; }

    /*
     * AtValue - True if the current token is an identifier spelled exactly as given. The test for
     * a contextual keyword - a word that only means something in one grammatical position, and is
     * an ordinary identifier everywhere else.
     */
    bool func AtValue(String word) {
        return self.CurKind() == TK.Ident && Toks.Value(self.Cur()) == word;
    }

    /*
     * AtProcessStart - True if a process declaration starts here
     */
    bool func AtProcessStart() {
        if (self.At(TK.Foreground) || self.At(TK.Background)) { return true; }
        return self.AtValue("process") && self.PeekKind(1) == TK.Ident
            && (self.PeekKind(2) == TK.LBrace || self.PeekKind(2) == TK.Colon);
    }

    /*
     * Try - Consumes the current token and returns true if it matches; otherwise leaves it
     */
    bool func Try(TK k) {
        if (self.At(k)) { self.Advance(); return true; }
        return false;
    }

    /*
     * AtP - True if the current token is TK.Punct with the given value. Only for operator tokens
     * kept as TK.Punct: + - * / % and | ^ less-than greater-than ! ~
     */
    bool func AtP(String v) {
        return self.CurKind() == TK.Punct && Toks.Value(self.Cur()) == v;
    }

    /*
     * Fail - Fails at the current token's span with the generic syntax code
     */
    throws void func Fail(String m) { self.FailAt(Toks.Span(self.Cur()), m, Codes.Syntax(), new List[String]()); }

    /*
     * Fail - Fails at the current token's span with an explicit code
     */
    throws void func Fail(String m, String code) { self.FailAt(Toks.Span(self.Cur()), m, code, new List[String]()); }

    /*
     * Fail - Fails at the current token's span with an explicit code and hints
     */
    throws void func Fail(String m, String code, List[String] hints) {
        self.FailAt(Toks.Span(self.Cur()), m, code, hints);
    }

    /*
     * FailAt - Fails at an explicit span
     */
    throws void func FailAt(TextSpan span, String m, String code, List[String] hints) {
        self.lastErr = ParseError.At(span, code, m, hints);
        throw;
    }

    /*
     * NoAssignHere - After an expression has been parsed in a position where only an expression is
     * legal, rejects a trailing assignment operator with a targeted message instead of letting the
     * generic "expected ')'" error fire.
     */
    throws void func NoAssignHere(String where, String hint) {
        if (IsAssignTk(self.CurKind())) {
            self.Fail("assignment is a statement in Gata, not an expression, and cannot appear in " + where,
                      Codes.AssignInExpr(), HintList.Of1(hint));
        }
    }

    /*
     * GuTake - The generic uses recorded from index `from` onward, as a fresh list (C#'s
     * _gu.GetRange)
     */
    List[GenericUse] func GuTake(int from) {
        let List[GenericUse] r = new List[GenericUse]();
        let int i = from;
        while (i < self.gu.Length()) { r.Add(self.gu.Get(i)); i = i + 1; }
        return r;
    }

    /*
     * GuTruncate - Drops every generic use recorded at or after index `from` (C#'s
     * _gu.RemoveRange)
     */
    void func GuTruncate(int from) {
        while (self.gu.Length() > from) { self.gu.RemoveLast(); }
    }

    /*
     * ParseAnnotations - Parses zero or more leading annotations
     */
    List[Annotation] func ParseAnnotations() {
        let List[Annotation] anns = new List[Annotation]();
        while (true) {
            if (self.At(TK.AtIntrinsic)) {
                let Token t = self.Advance();
                anns.Add(Annotation.IntrinsicAnnotation(new IntrinsicAnnotation(Toks.Value(t), Toks.Span(t))));
            } else if (self.At(TK.AtPreamble)) {
                let Token t = self.Advance();
                anns.Add(Annotation.PreambleAnnotation(new PreambleAnnotation(Toks.Value(t), Toks.Span(t))));
            } else if (self.At(TK.AtKeep)) {
                let Token t = self.Advance();
                anns.Add(Annotation.KeepAnnotation(new KeepAnnotation(Toks.Span(t))));
            } else if (self.At(TK.AtBuiltin)) {
                let Token t = self.Advance();
                anns.Add(Annotation.BuiltinAnnotation(new BuiltinAnnotation(Toks.Value(t), Toks.Span(t))));
            } else if (self.At(TK.AtShadows)) {
                let Token t = self.Advance();
                anns.Add(Annotation.ShadowsAnnotation(new ShadowsAnnotation(Toks.Span(t))));
            } else { break; }
        }
        return anns;
    }

    /*
     * RejectAnns - Rejects annotations on a declaration that cannot use them, allowing @shadows
     */
    throws void func RejectAnns(List[Annotation] anns, String what) {
        self.RejectAnns(anns, what, false, false, true);
    }

    /*
     * RejectAnns - Verifies that no invalid annotations were attached to a declaration that cannot
     * use them. @intrinsic and @preamble bind only to native blocks, native types and functions;
     * @keep and @builtin are what a class or module may carry, and everything else rejects all of
     * them.
     */
    throws void func RejectAnns(List[Annotation] anns, String what, bool allowKeep, bool allowBuiltin, bool allowShadows) {
        let int i = 0;
        while (i < anns.Length()) {
            let Annotation a = anns.Get(i);
            let bool ok = false;
            match (a) {
                case ShadowsAnnotation(x) { ok = allowShadows; }
                case KeepAnnotation(x)    { ok = allowKeep; }
                case BuiltinAnnotation(x) { ok = allowBuiltin; }
                default { ok = false; }
            }
            if (!ok) {
                self.FailAt(Anns.Span(a), "annotations have no effect on " + what,
                            Codes.BadAnnotation(), new List[String]());
            }
            i = i + 1;
        }
    }

    /*
     * ParseProgram - Entry point. Parses a complete source file and returns its AST root.
     */
    public throws Program func ParseProgram() {
        let List[TopLevel] items = new List[TopLevel]();
        while (!self.At(TK.EOF)) {
            let TopLevel t = self.ParseTopLevel();
            items.Add(t);
        }
        let Program p = new Program(items);
        p.genericUses = self.gu.Clone();
        p.hasScopedRefs = self.scopedRef;
        return p;
    }

    /*
     * ParseFreeFuncDecl - Parses a free function declaration. Handles optional modifiers, an
     * optional return type using ParseOptionalReturnType, and an optional generic parameter list
     * between the name and the opening paren.
     */
    throws TopLevel func ParseFreeFuncDecl(List[Annotation] anns, int s) {
        let TextSpan modSpan = Toks.Span(self.Cur());
        let Modifiers mods = self.ParseMods();
        self.RejectPublicOnFreeFunc(mods, modSpan);
        let bool isEntry = self.Try(TK.Entry);
        let bool isThrow = self.Try(TK.Throws);
        if (!isEntry) { isEntry = self.Try(TK.Entry); }
        let Optional[TypeSpec] ret = self.ParseOptionalReturnType();
        match (ret) {
            case Some(r) {
                if (self.At(TK.LBrace)) {
                    let String shown = Specs.ToSpecString(r);
                    self.Fail("expected 'func', found '{'", Codes.BadDeclHeader(),
                              HintList.Of2("did you forget 'process' before '" + shown + "'?",
                                           "e.g. 'foreground process " + shown + " { ... }'"));
                }
            }
            case None { }
        }
        self.Expect(TK.Func);
        let String name = self.ExpectValue(TK.Ident);
        let List[String] generics = self.ParseGenericParamList();
        self.Expect(TK.LParen);
        let List[Param] parms = self.ParseParamList();
        self.Expect(TK.RParen);
        if (self.At(TK.Arrow)) {
            self.Fail("'" + name + "': return type goes before 'func', not after the parameter list",
                      Codes.BadDeclHeader());
        }
        let MethodBody body = self.ParseMethodBody();
        return TopLevel.FuncDecl(new FuncDecl(mods, anns, ret, name, generics, parms, isEntry, isThrow, body, self.To(s)));
    }

    /*
     * RejectPublicOnFreeFunc - Reports 'public' written on a free function, which changes nothing
     */
    throws void func RejectPublicOnFreeFunc(Modifiers mods, TextSpan span) {
        if (!Mods.Has(mods, Modifiers.Public)) { return; }
        self.FailAt(span, "'public' has no meaning on a free function", Codes.BadDeclHeader(),
                    HintList.Of2("a free function is already visible to every file that imports this one",
                                 "remove it, or write 'private' to scope the function to this file"));
    }

    /*
     * ParseGenericParamList - Parses an optional generic parameter list like [T, U]. Returns an
     * empty list if there is no leading bracket. Used by class declarations, free function
     * declarations, and class/module method declarations.
     */
    throws List[String] func ParseGenericParamList() {
        let List[String] gp = new List[String]();
        if (!self.At(TK.LBrack)) { return gp; }
        self.Advance();
        let String first = self.ExpectBareGenericParam();
        gp.Add(first);
        while (self.Try(TK.Comma)) {
            let String more = self.ExpectBareGenericParam();
            gp.Add(more);
        }
        self.Expect(TK.RBrack);
        return gp;
    }

    /*
     * ParseTopLevel - Dispatches to the correct top-level parser based on the current token
     */
    throws TopLevel func ParseTopLevel() {
        if (self.At(TK.Import)) { let TopLevel r1 = self.ParseImport(); return r1; }
        if (self.At(TK.AtEnvironment)) {
            let int es = self.CurStart();
            self.Advance();
            return TopLevel.EnvironmentDecl(new EnvironmentDecl(self.To(es)));
        }
        let int s = self.CurStart();
        let List[Annotation] anns = self.ParseAnnotations();
        if (self.At(TK.Import)) { self.RejectAnns(anns, "an import", false, false, false); }
        if (self.At(TK.NativeContent)) {
            let Token t = self.Advance();
            return TopLevel.NativeBlock(new NativeBlock(ParseNativeBody(t), self.To(s), anns));
        }
        if (self.At(TK.NativeTypeDecl)) { let TopLevel r2 = self.ParseNativeType(anns, s); return r2; }
        if (self.At(TK.Enum)) { self.RejectAnns(anns, "an enum"); let TopLevel r3 = self.ParseEnumDecl(anns, s); return r3; }
        if (self.At(TK.Union)) { self.RejectAnns(anns, "a union"); let TopLevel r4 = self.ParseUnionDecl(anns, s); return r4; }
        if (self.At(TK.Class)) { self.RejectAnns(anns, "a class", true, true, true); let TopLevel r5 = self.ParseClassDecl(anns, s); return r5; }
        if (self.At(TK.Module)) { self.RejectAnns(anns, "a module", true, false, true); let TopLevel r6 = self.ParseModuleDecl(anns, s); return r6; }
        if (self.At(TK.Realm)) { self.RejectAnns(anns, "a realm", false, false, false); let TopLevel r7 = self.ParseRealmDecl(); return r7; }
        if (self.At(TK.Kernel)) { self.RequireRealmKeyword(); }
        if (self.AtProcessStart()) {
            self.Fail("a 'process' must be declared inside a 'realm' block", Codes.TopologyOutsideRealm(),
                      HintList.Of1("wrap it in 'realm kernel { ... }' or 'realm userspace { ... }'"));
        }
        self.RejectStrayThread();
        self.RejectModifierOnType();
        if (self.At(TK.AtExtern)) { let TopLevel r8 = self.ParseExternDecl(anns, s); return r8; }
        let TopLevel r9 = self.ParseFreeFuncDecl(anns, s); return r9;
    }

    /*
     * RejectModifierOnType - Reports a visibility or 'static' modifier written on a top-level type
     * declaration. Only a free function takes one there; without this the modifier is read as the
     * start of a function and the error lands on the 'class' keyword, naming the wrong thing
     * entirely.
     */
    throws void func RejectModifierOnType() {
        let TK k = self.CurKind();
        if (k != TK.Public && k != TK.Private && k != TK.Static) { return; }
        let TK nx = self.PeekKind(1);
        let String what = "";
        if (nx == TK.Class) { what = "a class"; }
        else if (nx == TK.Module) { what = "a module"; }
        else if (nx == TK.Enum) { what = "an enum"; }
        else if (nx == TK.Union) { what = "a union"; }
        else if (nx == TK.NativeTypeDecl) { what = "a native type"; }
        if (what.Length() == 0) { return; }

        let String mod = Toks.Value(self.Cur());
        let String hint = mod == "private"
            ? "a top-level type is visible to every file that imports this one; there is no file-local type"
            : "remove '" + mod + "'; only a free function takes 'private' here";
        self.FailAt(Toks.Span(self.Cur()), "'" + mod + "' has no meaning on " + what,
                    Codes.BadDeclHeader(), HintList.Of1(hint));
    }

    /*
     * ParseImport - Parses an import declaration. A string literal import is a filesystem path; a
     * bare identifier is a module name.
     */
    throws TopLevel func ParseImport() {
        let int s = self.CurStart();
        self.Expect(TK.Import);
        if (self.At(TK.StrLit)) {
            let Token t = self.Advance();
            let String raw = StripQuotes(Toks.Value(t));
            self.Expect(TK.Semi);
            return TopLevel.ImportDecl(new ImportDecl(raw, true, self.To(s)));
        }
        let String name = self.ExpectValue(TK.Ident);
        self.Expect(TK.Semi);
        return TopLevel.ImportDecl(new ImportDecl(name, false, self.To(s)));
    }

    /*
     * ParseNativeType - Parses a native type declaration. The lexer encodes the type name and body
     * separated by the ASCII unit separator in a single NativeTypeDecl token value.
     */
    throws TopLevel func ParseNativeType(List[Annotation] anns, int s) {
        let Token t = self.Advance();
        let String raw = Toks.Value(t);
        let int sep = raw.IndexOfChar(31 as char);
        let String name = raw.Substring(0, sep);
        let String cbody = raw.Substring(sep + 1, raw.Length() - (sep + 1));
        return TopLevel.NativeTypeDecl(new NativeTypeDecl(name, cbody, self.To(s), anns));
    }

    /*
     * ParseExternDecl - Parses an @extern function pre-declaration. Tells the compiler a C
     * function exists so it can be called from Gata without a Gata body.
     */
    throws TopLevel func ParseExternDecl(List[Annotation] anns, int s) {
        self.Advance(); // @extern
        let Optional[TypeSpec] ret = self.ParseOptionalReturnType();
        self.Expect(TK.Func);
        let String name = self.ExpectValue(TK.Ident);
        self.Expect(TK.LParen);
        let List[Param] parms = self.ParseParamList();
        self.Expect(TK.RParen);
        if (self.At(TK.Arrow)) {
            self.Fail("'" + name + "': return type goes before 'func', not after the parameter list",
                      Codes.BadDeclHeader());
        }
        self.Expect(TK.Semi);
        return TopLevel.ExternFuncDecl(new ExternFuncDecl(ret, name, parms, self.To(s), anns));
    }

    /*
     * ParseRealmDecl - Parses a 'realm kernel { ... }' or 'realm userspace { ... }' block. There
     * are exactly two realms; 'kernel' is a keyword, 'userspace' is matched by value since nothing
     * else may follow 'realm'.
     */
    throws TopLevel func ParseRealmDecl() {
        let int s = self.CurStart();
        self.Advance(); // 'realm'
        let Realm kind = Realm.None;
        if (self.At(TK.Kernel)) { kind = Realm.Kernel; self.Advance(); }
        else if (self.At(TK.Userspace)) { kind = Realm.User; self.Advance(); }
        else {
            let List[String] hints = new List[String]();
            if (self.CurKind() == TK.Ident) {
                let List[String] realms = HintList.Of2("kernel", "userspace");
                hints = Suggest.Hints(Toks.Value(self.Cur()), realms);
            }
            self.Fail("unknown realm " + self.Found() + "; the only realms are 'kernel' and 'userspace'",
                      Codes.UnknownRealm(), hints);
        }
        self.Expect(TK.LBrace);
        let List[TopLevel] items = new List[TopLevel]();
        while (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            let TopLevel it = self.ParseContextItem();
            items.Add(it);
        }
        self.Expect(TK.RBrace);
        return TopLevel.ContextDecl(new ContextDecl(kind, items, self.To(s)));
    }

    /*
     * RequireRealmKeyword - Reports a bare 'kernel' that is missing its 'realm' prefix. Kept as a
     * dedicated diagnostic so the pre-'realm' spelling produces advice rather than a generic
     * syntax error.
     */
    throws void func RequireRealmKeyword() {
        self.Fail("expected 'realm' before 'kernel'", Codes.MissingRealmKeyword(),
                  HintList.Of1("write 'realm kernel { ... }'"));
    }

    /*
     * ParseContextItem - Dispatches to the correct parser for a single item inside a realm block.
     * Realm blocks cannot be nested, so a nested 'realm' is a hard error here.
     */
    throws TopLevel func ParseContextItem() {
        if (self.At(TK.Realm)) { self.Fail("a 'realm' block cannot be nested inside another", Codes.InvalidNesting()); }
        if (self.At(TK.Kernel)) { self.RequireRealmKeyword(); }
        self.RejectStrayImport();
        self.RejectStrayThread();
        let int s = self.CurStart();
        if (self.At(TK.AtEnvironment)) {
            self.Advance();
            return TopLevel.EnvironmentDecl(new EnvironmentDecl(self.To(s)));
        }
        let List[Annotation] anns = self.ParseAnnotations();
        self.RejectStrayImport();
        self.RejectStrayThread();
        if (self.At(TK.NativeContent)) {
            let Token t = self.Advance();
            return TopLevel.NativeBlock(new NativeBlock(ParseNativeBody(t), self.To(s), anns));
        }
        if (self.At(TK.NativeTypeDecl)) { let TopLevel r10 = self.ParseNativeType(anns, s); return r10; }
        if (self.At(TK.AtExtern)) { let TopLevel r11 = self.ParseExternDecl(anns, s); return r11; }
        if (self.At(TK.Enum)) { self.RejectAnns(anns, "an enum"); let TopLevel r12 = self.ParseEnumDecl(anns, s); return r12; }
        if (self.At(TK.Union)) { self.RejectAnns(anns, "a union"); let TopLevel r13 = self.ParseUnionDecl(anns, s); return r13; }
        if (self.At(TK.Class)) { self.RejectAnns(anns, "a class", true, true, true); let TopLevel r14 = self.ParseClassDecl(anns, s); return r14; }
        if (self.At(TK.Module)) { self.RejectAnns(anns, "a module", true, false, true); let TopLevel r15 = self.ParseModuleDecl(anns, s); return r15; }
        if (self.AtProcessStart()) {
            self.RejectAnns(anns, "a process", false, false, false);
            let TopLevel r16 = self.ParseProcessDeclTop(); return r16;
        }
        let TopLevel r17 = self.ParseFreeFuncDecl(anns, s); return r17;
    }

    /*
     * ParseClassDecl - Parses a class declaration. The name is mangled with the generic parameter
     * list so the Monomorphizer can match self-references: "class List[T]" becomes "List_T" in the
     * AST, with baseName holding the "List" the user wrote.
     */
    throws TopLevel func ParseClassDecl(List[Annotation] anns, int s) {
        self.Expect(TK.Class);
        let int ns = self.CurStart();
        let String name = self.ParseSimpleTypeName();
        let String baseName = name;
        let List[String] generics = new List[String]();
        if (self.At(TK.LBrack)) {
            self.Advance();
            let String g0 = self.ExpectBareGenericParam();
            generics.Add(g0);
            while (self.Try(TK.Comma)) {
                let String gn = self.ExpectBareGenericParam();
                generics.Add(gn);
            }
            self.Expect(TK.RBrack);
            self.gu.Add(new GenericUse(name, generics.Clone(), self.To(ns), Optional[List[NamedSpec]].None()));
            name = GenericInstance(name, generics);
        }
        self.Expect(TK.LBrace);
        let List[ClassMember] members = new List[ClassMember]();
        while (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            let ClassMember m = self.ParseClassMember();
            members.Add(m);
        }
        self.Expect(TK.RBrace);
        let ClassDecl cd = new ClassDecl(name, generics, anns, members, self.To(s), false);
        cd.baseName = baseName;
        return TopLevel.ClassDecl(cd);
    }

    /*
     * ExpectBareGenericParam - Reads a single bare identifier as a generic parameter name. Type
     * arguments at use sites may nest (List[Map[K,V]]); class parameter declarations may not
     * (class Foo[Bar[Baz]] is rejected).
     */
    throws String func ExpectBareGenericParam() {
        if (!self.At(TK.Ident)) {
            self.Fail("generic parameter must be a plain name, found " + self.Found(), Codes.BadDeclHeader());
        }
        let Token t = self.Advance();
        let String tok = Toks.Value(t);
        if (self.At(TK.LBrack)) {
            self.Fail("generic parameter '" + tok + "' cannot itself be generic", Codes.BadDeclHeader());
        }
        return tok;
    }

    /*
     * ParseModuleDecl - Parses a module declaration. Modules are classes where all members are
     * implicitly static.
     */
    throws TopLevel func ParseModuleDecl(List[Annotation] anns, int s) {
        self.Expect(TK.Module);
        let String name = self.ParseSimpleTypeName();
        self.Expect(TK.LBrace);
        let List[ClassMember] members = new List[ClassMember]();
        while (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            let ClassMember m = self.ParseClassMember();
            members.Add(m);
        }
        self.Expect(TK.RBrace);
        return TopLevel.ClassDecl(new ClassDecl(name, new List[String](), anns, members, self.To(s), true));
    }

    /*
     * ParseEnumDecl - Parses an enum declaration. Members may carry explicit integer values; if
     * absent the C compiler applies the usual increment rule. A trailing comma after the last
     * member is a hard error.
     */
    throws TopLevel func ParseEnumDecl(List[Annotation] anns, int s) {
        self.Expect(TK.Enum);
        let String name = self.ExpectValue(TK.Ident);
        self.Expect(TK.LBrace);
        let List[EnumMember] members = new List[EnumMember]();
        if (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            let int ms = self.CurStart();
            let EnumMember m0 = self.ParseEnumMember(ms);
            members.Add(m0);
            while (self.Try(TK.Comma)) {
                if (self.At(TK.RBrace)) {
                    self.Fail("trailing comma not allowed after the last enum member; remove it",
                              Codes.TrailingComma());
                }
                ms = self.CurStart();
                let EnumMember mn = self.ParseEnumMember(ms);
                members.Add(mn);
            }
        }
        self.Expect(TK.RBrace);
        return TopLevel.EnumDecl(new EnumDecl(name, members, self.To(s), anns));
    }

    /*
     * ParseEnumMember - One enum member: a name and an optional '= constant expression'
     */
    throws EnumMember func ParseEnumMember(int ms) {
        let String mname = self.ExpectValue(TK.Ident);
        let Optional[Expr] value = Optional[Expr].None();
        if (self.Try(TK.Eq)) {
            let Expr v = self.ParseExpr();
            value = Optional.Some(v);
        }
        return new EnumMember(mname, value, self.To(ms));
    }

    /*
     * ParseUnionDecl - Parses a union declaration. Each variant is a name followed by an optional
     * parenthesised field list. A variant with no parens carries no payload. A trailing comma
     * after the last variant is a hard error.
     */
    throws TopLevel func ParseUnionDecl(List[Annotation] anns, int s) {
        self.Expect(TK.Union);
        let int ns = self.CurStart();
        let String name = self.ExpectValue(TK.Ident);
        let String baseName = name;

        // Type parameters, registered and mangled exactly as ParseClassDecl does, so the
        // Monomorphizer discovers the template through the same GenericUse channel.
        let List[String] generics = new List[String]();
        if (self.At(TK.LBrack)) {
            self.Advance();
            let String g0 = self.ExpectBareGenericParam();
            generics.Add(g0);
            while (self.Try(TK.Comma)) {
                let String gn = self.ExpectBareGenericParam();
                generics.Add(gn);
            }
            self.Expect(TK.RBrack);
            self.gu.Add(new GenericUse(name, generics.Clone(), self.To(ns), Optional[List[NamedSpec]].None()));
            name = GenericInstance(name, generics);
        }

        self.Expect(TK.LBrace);
        let List[UnionVariant] variants = new List[UnionVariant]();
        if (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            let UnionVariant v0 = self.ParseUnionVariant();
            variants.Add(v0);
            while (self.Try(TK.Comma)) {
                if (self.At(TK.RBrace)) {
                    self.Fail("trailing comma not allowed after the last union variant; remove it",
                              Codes.TrailingComma());
                }
                let UnionVariant vn = self.ParseUnionVariant();
                variants.Add(vn);
            }
        }
        self.Expect(TK.RBrace);
        let UnionDecl ud = new UnionDecl(name, generics, variants, self.To(s), anns);
        ud.baseName = baseName;
        return TopLevel.UnionDecl(ud);
    }

    /*
     * ParseUnionVariant - One union variant: a name and an optional parenthesised field list
     */
    throws UnionVariant func ParseUnionVariant() {
        let int vs = self.CurStart();
        let String vname = self.ExpectValue(TK.Ident);
        let List[Param] vfields = new List[Param]();
        if (self.At(TK.LParen)) { vfields = self.ParseUnionFieldList(); }
        return new UnionVariant(vname, vfields, self.To(vs));
    }

    /*
     * ParseUnionFieldList - Parses a union variant's parenthesised field list. A trailing comma
     * right before the closing paren is a hard error with a specific message, since the shared
     * ParseParamList used for function parameters does not check for one.
     */
    throws List[Param] func ParseUnionFieldList() {
        self.Advance(); // opening (
        let List[Param] vfields = new List[Param]();
        if (self.At(TK.RParen)) { self.Advance(); return vfields; }
        let Param p0 = self.ParseParam();
        vfields.Add(p0);
        while (self.Try(TK.Comma)) {
            if (self.At(TK.RParen)) {
                self.Fail("trailing comma not allowed after the last field; remove it", Codes.TrailingComma());
            }
            let Param pn = self.ParseParam();
            vfields.Add(pn);
        }
        self.Expect(TK.RParen);
        return vfields;
    }

    /*
     * ParseTypeName - Parses a named type, keeping any generic arguments structurally on the
     * NamedSpec. Generic uses are registered in gu for the Monomorphizer to consume.
     */
    throws NamedSpec func ParseTypeName() {
        self.EnterDepth();
        let NamedSpec name = self.ParseTypeNameInner();
        self.ExitDepth();
        return name;
    }

    throws NamedSpec func ParseTypeNameInner() {
        let int s = self.CurStart();
        let Optional[List[String]] scope = self.ParseScopeQualifier();
        match (scope) {
            case Some(sc) {
                let List[String] path = new List[String]();
                let bool more = true;
                while (more) {
                    let String seg = self.ExpectIdent("a scope or type name");
                    path.Add(seg);
                    more = self.Try(TK.Dot);
                }
                // The scope is everything but the final segment; that last one is the name.
                let List[String] outer = sc.Clone();
                let int i = 0;
                while (i < path.Length() - 1) { outer.Add(path.Get(i)); i = i + 1; }
                let NamedSpec r18 = self.FinishTypeName(path.Last(), Optional.Some(outer), s); return r18;
            }
            case None {
                let String bare = self.ParseSimpleTypeName();
                let NamedSpec r19 = self.FinishTypeName(bare, Optional[List[String]].None(), s); return r19;
            }
        }
    }

    /*
     * FinishTypeName - Completes a type name once its base and any explicit scope are known: the
     * optional argument list, and the instantiation request that goes with it.
     */
    throws NamedSpec func FinishTypeName(String name, Optional[List[String]] scope, int s) {
        if (!self.At(TK.LBrack)) {
            let NamedSpec plain = new NamedSpec(name, new List[NamedSpec](), self.To(s));
            plain.scope = scope;
            return plain;
        }
        self.Advance();
        let List[NamedSpec] args = new List[NamedSpec]();
        let NamedSpec a0 = self.ParseTypeName();
        args.Add(a0);
        while (self.Try(TK.Comma)) {
            let NamedSpec an = self.ParseTypeName();
            args.Add(an);
        }
        if (!self.At(TK.RBrack)) {
            self.Fail("invalid type argument in '" + name + "[...]', found " + self.Found());
        }
        self.Expect(TK.RBrack);
        let NamedSpec spec = new NamedSpec(name, args, self.To(s));
        spec.scope = scope;

        let List[String] mangledArgs = new List[String]();
        let int i = 0;
        while (i < args.Length()) { mangledArgs.Add(args.Get(i).Mangled()); i = i + 1; }
        let GenericUse use = new GenericUse(name, mangledArgs, self.To(s), Optional.Some(args.Clone()));
        use.scope = scope;
        self.gu.Add(use);
        return spec;
    }

    /*
     * ParseScopeQualifier - Consumes a leading scope qualifier and returns its segments, or None
     * when there is none. '::' is the root scope and so has no segments at all.
     */
    Optional[List[String]] func ParseScopeQualifier() {
        if (self.Try(TK.ColonColon)) {
            self.scopedRef = true;
            return Optional.Some(new List[String]());
        }
        if (!self.At(TK.Kernel) && !self.At(TK.Userspace)) { return Optional[List[String]].None(); }
        if (self.PeekKind(1) != TK.Dot) { return Optional[List[String]].None(); }
        let Token t = self.Advance();
        self.Advance();
        self.scopedRef = true;
        let List[String] one = new List[String]();
        one.Add(Toks.Value(t));
        return Optional.Some(one);
    }

    /*
     * ExpectIdent - Consumes an identifier, reporting what was wanted rather than the generic
     * token mismatch
     */
    throws String func ExpectIdent(String what) {
        if (self.At(TK.Ident)) {
            let Token t = self.Advance();
            return Toks.Value(t);
        }
        self.Fail("expected " + what + ", found " + self.Found());
        return "";
    }

    /*
     * ParseSimpleTypeName - Parses the base name of a type, like an identifier (Process/Thread are
     * ordinary identifiers, resolved as builtin types later) or a primitive keyword
     */
    throws String func ParseSimpleTypeName() {
        if (self.At(TK.Ident)) {
            let Token t = self.Advance();
            return Toks.Value(t);
        }
        if (IsPrim(self.CurKind())) {
            let Token t = self.Advance();
            return PrimName(t);
        }
        if (self.At(TK.Let)) {
            self.Fail("a variable cannot be declared here", Codes.Syntax(),
                      HintList.Of2("a variable belongs inside a function, or directly inside a process, "
                                   + "where it becomes state its threads share",
                                   "types, modules and functions are what a realm or a file can hold"));
        }
        self.Fail("expected a type name, found " + self.Found());
        return "";
    }

    /*
     * ParseTypeSpec - Parses a full type specifier. Fixed-array prefix [N], function pointer type,
     * plain type name, and optional pointer suffixes.
     */
    throws TypeSpec func ParseTypeSpec() {
        self.EnterDepth();
        let TypeSpec spec = self.ParseTypeSpecInner();
        self.ExitDepth();
        return spec;
    }

    throws TypeSpec func ParseTypeSpecInner() {
        let int s = self.CurStart();

        // [N]elem, brackets come before the element type.
        if (self.At(TK.LBrack) && self.PeekKind(1) == TK.IntLit && self.PeekKind(2) == TK.RBrack) {
            self.Advance();
            let Token nt = self.Advance();
            self.Expect(TK.RBrack);
            let TypeSpec elem = self.ParseTypeSpec();
            return TypeSpec.ArraySpec(new ArraySpec(Toks.Value(nt), elem, self.To(s)));
        }
        if (self.At(TK.Func)) { let TypeSpec r20 = self.ParseFuncTypeSpec(); return r20; }
        let NamedSpec named = self.ParseTypeName();
        let TypeSpec spec = TypeSpec.NamedSpec(named);
        while (self.AtP("*")) {
            self.Advance();
            spec = TypeSpec.PtrSpec(new PtrSpec(spec, self.To(s)));
        }
        return spec;
    }

    /*
     * ParseFuncTypeSpec - Parses a function pointer type specifier into a FuncSpec node
     */
    throws TypeSpec func ParseFuncTypeSpec() {
        let int s = self.CurStart();
        self.Expect(TK.Func);
        self.Expect(TK.LParen);
        let List[TypeSpec] ps = new List[TypeSpec]();
        if (!self.At(TK.RParen)) {
            let TypeSpec p0 = self.ParseTypeSpec();
            ps.Add(p0);
            while (self.Try(TK.Comma)) {
                let TypeSpec pn = self.ParseTypeSpec();
                ps.Add(pn);
            }
        }
        self.Expect(TK.RParen);
        self.Expect(TK.Arrow);
        let TypeSpec ret = self.ParseTypeSpec();
        let TypeSpec spec = TypeSpec.FuncSpec(new FuncSpec(ps, ret, self.To(s)));
        if (self.AtP("*")) {
            self.Fail("pointer to a function type is not supported; use the function type directly",
                      Codes.BadDeclHeader());
        }
        return spec;
    }

    /*
     * ParseClassMember - Parses a single class member: a fields block, operator overload, method,
     * or field declaration
     */
    throws ClassMember func ParseClassMember() {
        let int s = self.CurStart();
        if (self.At(TK.Class) || self.At(TK.Module)) {
            self.Fail("classes and modules cannot be nested", Codes.InvalidNesting());
        }
        if (self.At(TK.Realm)) {
            self.Fail("a 'realm' block cannot appear inside a class", Codes.InvalidNesting());
        }

        // fields { } block is raw C struct fields injected verbatim into the emitted typedef.
        if (self.At(TK.Fields)) {
            let Token t = self.Advance();
            return ClassMember.FieldsBlock(new FieldsBlock(ParseNativeBody(t), self.To(s)));
        }

        let List[Annotation] anns = self.ParseAnnotations();
        let Modifiers mods = self.ParseMods();
        let bool isEntry = self.Try(TK.Entry);
        let bool isThrow = self.Try(TK.Throws);
        if (!isEntry) { isEntry = self.Try(TK.Entry); }

        if (self.At(TK.Operator)) { let ClassMember r21 = self.ParseOperatorDecl(anns, mods, isEntry, isThrow, s); return r21; }

        // If we reach here, it must be either a method or a field. Fields don't support
        // entry, throws, or annotations.
        if (self.LooksLikeMethod()) {
            if (isEntry) { self.Fail("'entry' has no meaning on a class method", Codes.BadDeclHeader()); }
            let Optional[TypeSpec] ret = self.ParseOptionalReturnType();
            self.Expect(TK.Func);
            let String name = self.ExpectValue(TK.Ident);
            let List[String] generics = self.ParseGenericParamList();
            self.Expect(TK.LParen);
            let List[Param] parms = self.ParseParamList();
            self.Expect(TK.RParen);
            if (self.At(TK.Arrow)) {
                self.Fail("'" + name + "': return type goes before 'func', not after the parameter list",
                          Codes.BadDeclHeader());
            }
            let MethodBody body = self.ParseMethodBody();
            return ClassMember.MethodDecl(new MethodDecl(mods, anns, ret, name, generics, parms, isEntry, isThrow, body, self.To(s)));
        }

        // Field. Entry, throws, annotations, and static are all meaningless here.
        if (isEntry) { self.Fail("'entry' has no meaning on a field", Codes.BadDeclHeader()); }
        if (isThrow) { self.Fail("'throws' has no meaning on a field", Codes.BadDeclHeader()); }
        if (anns.Length() > 0) { self.Fail("annotations have no effect on a field", Codes.BadAnnotation()); }
        if (Mods.Has(mods, Modifiers.Static)) { self.Fail("'static' has no meaning on a field", Codes.BadDeclHeader()); }

        // 'name = expr;' declares a field whose type is inferred from its initializer, same as
        // 'let name = expr;'. Anything else starts with a type spec.
        let Optional[TypeSpec] ftype = Optional[TypeSpec].None();
        let String fname = "";
        if (self.At(TK.Ident) && self.PeekKind(1) == TK.Eq) {
            let Token t = self.Advance();
            fname = Toks.Value(t);
        } else {
            let TypeSpec ft = self.ParseTypeSpec();
            ftype = Optional.Some(ft);
            fname = self.ExpectValue(TK.Ident);
        }
        let Optional[Expr] init = Optional[Expr].None();
        if (self.Try(TK.Eq)) {
            let Expr iv = self.ParseExpr();
            init = Optional.Some(iv);
        }
        self.Expect(TK.Semi);
        return ClassMember.FieldDecl(new FieldDecl(mods, ftype, fname, self.To(s), init));
    }

    /*
     * ParseOperatorDecl - Parses an operator overload, with 'operator' as the current token
     */
    throws ClassMember func ParseOperatorDecl(List[Annotation] anns, Modifiers mods, bool isEntry, bool isThrow, int s) {
        if (anns.Length() > 0) { self.Fail("annotations have no effect on an operator", Codes.BadAnnotation()); }
        if (isEntry) { self.Fail("'entry' has no meaning on an operator", Codes.BadDeclHeader()); }
        if (isThrow) { self.Fail("'throws' has no meaning on an operator", Codes.BadDeclHeader()); }
        if (Mods.Has(mods, Modifiers.Static)) { self.Fail("'static' has no meaning on an operator", Codes.BadDeclHeader()); }
        self.Advance();
        let Optional[TypeSpec] ret = Optional[TypeSpec].None();
        if (!(self.At(TK.Func) && self.PeekKind(1) != TK.LParen)) {
            let TypeSpec r = self.ParseTypeSpec();
            ret = Optional.Some(r);
        }
        self.Expect(TK.Func);
        let String op = self.ParseOperatorSymbol();
        self.Expect(TK.LParen);
        let List[Param] parms = self.ParseParamList();
        self.Expect(TK.RParen);
        if (self.At(TK.Arrow)) {
            self.Fail("'" + op + "': return type goes after 'operator', not after the parameter list",
                      Codes.BadDeclHeader());
        }
        let MethodBody body = self.ParseMethodBody();
        return ClassMember.OperatorDecl(new OperatorDecl(mods, op, parms, ret, body, self.To(s)));
    }

    /*
     * ParseOperatorSymbol - Parses an operator symbol for an operator overload declaration.
     * Handles arithmetic, comparison, bitwise, and indexer operators.
     */
    throws String func ParseOperatorSymbol() {
        if (self.AtP("+") || self.AtP("-") || self.AtP("*") || self.AtP("/") || self.AtP("%")
            || self.AtP("<") || self.AtP(">")) {
            let Token t = self.Advance();
            return Toks.Value(t);
        }
        if (self.At(TK.EqEq) || self.At(TK.NotEq) || self.At(TK.LtEq) || self.At(TK.GtEq)) {
            let Token t = self.Advance();
            return Toks.Value(t);
        }
        if (self.AtP("&") || self.AtP("|") || self.AtP("^") || self.At(TK.Shl) || self.At(TK.Shr)) {
            let Token t = self.Advance();
            return Toks.Value(t);
        }
        if (self.AtP("!") || self.AtP("~")) {
            let Token t = self.Advance();
            return Toks.Value(t);
        }
        if (self.At(TK.Inc) || self.At(TK.Dec)) {
            let Token t = self.Advance();
            return Toks.Value(t);
        }
        if (self.At(TK.LBrack)) {
            self.Advance();
            self.Expect(TK.RBrack);
            return self.Try(TK.Eq) ? "[]=" : "[]";
        }
        if (self.At(TK.As)) { self.Advance(); return "as"; }
        self.Fail("expected an operator symbol, found " + self.Found());
        return "+";
    }

    /*
     * LooksLikeMethod - True if the current position looks like the start of a method declaration.
     * 'func Name' with no return type is a method; 'func(' starts a func-pointer type (a field).
     */
    bool func LooksLikeMethod() {
        if (self.At(TK.Func) && self.PeekKind(1) == TK.Ident) { return true; }
        let int n = self.SkipTypeSpec(0);
        return n >= 0 && self.PeekKind(n) == TK.Func;
    }

    /*
     * ParseOptionalReturnType - Parses an optional return type before 'func'. Returns None when
     * 'func' is immediately followed by an identifier (no return type).
     */
    throws Optional[TypeSpec] func ParseOptionalReturnType() {
        if (self.At(TK.Func) && self.PeekKind(1) == TK.Ident) { return Optional[TypeSpec].None(); }
        let TypeSpec t = self.ParseTypeSpec();
        return Optional.Some(t);
    }

    /*
     * ParseMethodBody - Parses a method body. Either a native C block or a Gata statement block.
     */
    throws MethodBody func ParseMethodBody() {
        if (self.At(TK.NativeContent)) {
            let Token t = self.Advance();
            return MethodBody.NativeMethodBody(new NativeMethodBody(ParseNativeBody(t)));
        }
        let Block b = self.ParseBlock();
        return MethodBody.BlockBody(new BlockBody(b));
    }

    /*
     * ParseMods - Parses zero or more access/storage modifiers into a single flags value. A
     * repeated modifier and the contradictory 'public private' pair are hard errors.
     */
    throws Modifiers func ParseMods() {
        let Modifiers mods = Modifiers.None;
        while (true) {
            let TK k = self.CurKind();
            let Modifiers m = Modifiers.None;
            if (k == TK.Static) { m = Modifiers.Static; }
            else if (k == TK.Public) { m = Modifiers.Public; }
            else if (k == TK.Private) { m = Modifiers.Private; }
            if (m == Modifiers.None) { break; }
            if (Mods.Has(mods, m)) {
                self.Fail("duplicate modifier '" + Toks.Value(self.Cur()) + "'", Codes.ConflictingModifiers());
            }
            mods = Mods.With(mods, m);
            self.Advance();
        }
        if (Mods.Has(mods, Modifiers.Public) && Mods.Has(mods, Modifiers.Private)) {
            self.Fail("'public' and 'private' cannot be combined on one declaration", Codes.ConflictingModifiers());
        }
        return mods;
    }

    /*
     * ParseProcessDeclTop - Parses a process declaration. The mode is written before 'process' and
     * is mandatory: it owns TTY focus and scheduling visibility, so it is not allowed to default
     * silently.
     */
    throws TopLevel func ParseProcessDeclTop() {
        let int s = self.CurStart();
        let String mode = "foreground";
        let bool modeExplicit = false;
        if (self.At(TK.Foreground)) { mode = "foreground"; modeExplicit = true; self.Advance(); }
        else if (self.At(TK.Background)) { mode = "background"; modeExplicit = true; self.Advance(); }
        if (!self.AtValue("process")) {
            self.Fail("expected 'process', found " + self.Found(), Codes.BadDeclHeader());
        }
        self.Advance();
        let String name = self.ExpectValue(TK.Ident);

        if (self.At(TK.Colon)) {
            self.Fail("'" + name + "': the deployment mode is written before 'process'",
                      Codes.MissingProcessMode(),
                      HintList.Of1("write 'foreground process " + name + " { ... }' or 'background process "
                                   + name + " { ... }'"));
        }

        if (!modeExplicit) {
            self.Fail("'" + name + "': process declaration is missing a foreground/background mode",
                      Codes.MissingProcessMode(),
                      HintList.Of1("write 'foreground process " + name + "' or 'background process " + name + "'"));
        }
        self.Expect(TK.LBrace);
        let List[ThreadDecl] threads = new List[ThreadDecl]();
        let List[TopLevel] items = new List[TopLevel]();
        while (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            if (self.AtNestedProcess()) {
                self.Fail("a process cannot be nested inside another process", Codes.InvalidNesting());
            }
            if (self.AtThreadStart()) {
                let ThreadDecl td = self.ParseThreadDecl();
                threads.Add(td);
            } else {
                let TopLevel it = self.ParseProcessItem();
                items.Add(it);
            }
        }
        self.Expect(TK.RBrace);
        let ProcessDecl pd = new ProcessDecl(name, mode, threads, self.To(s));
        pd.items = items;
        return TopLevel.ProcessDecl(pd);
    }

    /*
     * RejectStrayImport - Reports an 'import' written anywhere but the top level of a file.
     * Otherwise it reaches the free-function parser and comes back as "expected a type name,
     * found 'import'".
     */
    throws void func RejectStrayImport() {
        if (self.At(TK.Import)) {
            self.Fail("an 'import' must be at the top level of the file", Codes.TopologyOutsideRealm(),
                      HintList.Of1("move it above the block; imports apply to the whole file"));
        }
    }

    /*
     * RejectStrayThread - Reports a 'thread' outside a process body. 'thread' is contextual, so a
     * stray one otherwise parses as a type name and reports a missing 'func'.
     */
    throws void func RejectStrayThread() {
        if (self.AtValue("thread") && self.PeekKind(1) == TK.Ident && self.PeekKind(2) == TK.LBrace) {
            self.Fail("a 'thread' must be declared inside a 'process' block", Codes.TopologyOutsideRealm(),
                      HintList.Of1("threads are a process's entry points; wrap it in 'foreground process P { ... }'"));
        }
    }

    /*
     * AtThreadStart - True if a thread declaration starts here. A foreground/background prefix is
     * accepted so the resolver can reject it as G043 with a message about modes, rather than the
     * parser rejecting it as an unknown declaration.
     */
    bool func AtThreadStart() {
        return self.AtValue("thread") || self.At(TK.Foreground) || self.At(TK.Background);
    }

    /*
     * AtNestedProcess - True if a process declaration starts here, including the
     * foreground/background-prefixed form that a thread declaration also uses
     */
    bool func AtNestedProcess() {
        if (self.At(TK.Foreground) || self.At(TK.Background)) {
            return self.PeekKind(1) == TK.Ident && Toks.Value(self.Peek(1)) == "process";
        }
        return self.AtProcessStart();
    }

    /*
     * ParseProcessItem - Dispatches a single non-thread declaration inside a process body. A
     * process holds the same declaration forms a realm does, minus the two that cannot nest.
     */
    throws TopLevel func ParseProcessItem() {
        if (self.At(TK.Realm)) { self.Fail("a 'realm' block cannot appear inside a process", Codes.InvalidNesting()); }
        if (self.At(TK.Kernel)) { self.RequireRealmKeyword(); }
        if (self.AtProcessStart()) { self.Fail("a process cannot be nested inside another process", Codes.InvalidNesting()); }
        self.RejectStrayImport();

        let int s = self.CurStart();
        if (self.At(TK.AtEnvironment)) {
            self.Advance();
            return TopLevel.EnvironmentDecl(new EnvironmentDecl(self.To(s)));
        }
        let List[Annotation] anns = self.ParseAnnotations();
        self.RejectStrayImport();
        if (self.AtValue("thread")) { self.RejectAnns(anns, "a thread", false, false, false); }
        if (self.At(TK.NativeContent)) {
            let Token t = self.Advance();
            return TopLevel.NativeBlock(new NativeBlock(ParseNativeBody(t), self.To(s), anns));
        }
        if (self.At(TK.NativeTypeDecl)) { let TopLevel r22 = self.ParseNativeType(anns, s); return r22; }
        if (self.At(TK.AtExtern)) { let TopLevel r23 = self.ParseExternDecl(anns, s); return r23; }
        if (self.At(TK.Enum)) { self.RejectAnns(anns, "an enum"); let TopLevel r24 = self.ParseEnumDecl(anns, s); return r24; }
        if (self.At(TK.Union)) { self.RejectAnns(anns, "a union"); let TopLevel r25 = self.ParseUnionDecl(anns, s); return r25; }
        if (self.At(TK.Class)) { self.RejectAnns(anns, "a class", true, true, true); let TopLevel r26 = self.ParseClassDecl(anns, s); return r26; }
        if (self.At(TK.Module)) { self.RejectAnns(anns, "a module", true, false, true); let TopLevel r27 = self.ParseModuleDecl(anns, s); return r27; }
        if (self.At(TK.Let)) {
            self.RejectAnns(anns, "a process variable", false, false, false);
            let TopLevel r28 = self.ParseProcessVarDecl(s); return r28;
        }
        let TopLevel r29 = self.ParseFreeFuncDecl(anns, s); return r29;
    }

    /*
     * ParseProcessVarDecl - Parses a process-scoped variable
     */
    throws TopLevel func ParseProcessVarDecl(int s) {
        self.Expect(TK.Let);
        let TypeSpec type = self.ParseTypeSpec();
        let String name = self.ExpectValue(TK.Ident);

        let Optional[Expr] init = Optional[Expr].None();
        if (self.Try(TK.Eq)) {
            let Expr iv = self.ParseExpr();
            init = Optional.Some(iv);
        } else {
            self.Fail("process variable '" + name + "' has no initial value", Codes.UninitialisedProcessVar(),
                      HintList.Of2("write 'let <type> " + name + " = <value>;'",
                                   "every thread of the process shares this one variable, so there is no point "
                                   + "later in the program where a first assignment could be known to have run "
                                   + "before a read"));
        }

        self.Expect(TK.Semi);
        return TopLevel.ProcessVarDecl(new ProcessVarDecl(name, type, init, self.To(s)));
    }

    /*
     * ParseThreadDecl - Parses a thread declaration inside a process body. A foreground or
     * background keyword before 'thread' is syntactically accepted and captured in mode; the type
     * resolver rejects it as G043, since threads don't have their own deployment mode, only the
     * process does.
     */
    throws ThreadDecl func ParseThreadDecl() {
        let int s = self.CurStart();
        let Optional[String] mode = Optional[String].None();
        let String modeShown = "";
        if (self.At(TK.Foreground)) { mode = Optional.Some("foreground"); modeShown = "foreground"; self.Advance(); }
        else if (self.At(TK.Background)) { mode = Optional.Some("background"); modeShown = "background"; self.Advance(); }
        if (!self.AtValue("thread")) {
            self.Fail("expected 'thread' after '" + modeShown + "', found " + self.Found(), Codes.BadDeclHeader(),
                      HintList.Of1("a process body may contain classes, modules, enums, unions, functions, and threads"));
        }
        self.Advance();
        let String name = self.ExpectValue(TK.Ident);
        self.Expect(TK.LBrace);
        let EntryFuncDecl entryFn = self.ParseThreadEntry();
        if (!self.At(TK.RBrace)) {
            self.Fail("a thread body must contain a single 'entry func' and nothing else", Codes.BadDeclHeader());
        }
        self.Expect(TK.RBrace);
        return new ThreadDecl(name, mode, entryFn, self.To(s));
    }

    /*
     * ParseThreadEntry - Parses the entry function of a thread. Threads are pure topology, not
     * scopes, so a nested thread or helper function in the body is a hard error, and the fixed
     * void(*)(void*) ABI means return types and access modifiers are rejected too.
     */
    throws EntryFuncDecl func ParseThreadEntry() {
        let int s = self.CurStart();
        if (self.AtValue("thread")) { self.Fail("threads cannot be nested", Codes.InvalidNesting()); }
        let Modifiers mods = self.ParseMods();
        let bool throwsFirst = self.Try(TK.Throws);
        if (!self.Try(TK.Entry)) {
            self.Fail("a thread body must contain a single 'entry func'", Codes.BadDeclHeader());
        }
        if (throwsFirst || self.At(TK.Throws)) {
            self.Fail("a thread entry cannot be 'throws' - the runtime starts it, so there is no caller to receive the error",
                      Codes.BadEntrySignature(),
                      HintList.Of1("handle failure inside the thread: 'let T x = f() catch { assign <fallback>; };'"));
        }
        let Optional[TypeSpec] ret = Optional[TypeSpec].None();
        if (!(self.At(TK.Func) && self.PeekKind(1) == TK.Ident)) {
            let TypeSpec r = self.ParseTypeSpec();
            ret = Optional.Some(r);
        }
        self.Expect(TK.Func);
        if (self.At(TK.Ident)) { self.Advance(); } // entry name is documentation only; the thread names it
        self.Expect(TK.LParen);
        let List[Param] parms = self.ParseParamList();
        self.Expect(TK.RParen);
        match (ret) {
            case Some(r) { self.Fail("a thread entry has no return value; remove the return type", Codes.BadDeclHeader()); }
            case None { }
        }
        if (mods != Modifiers.None) {
            self.Fail("access/storage modifiers have no meaning on a thread entry", Codes.BadDeclHeader());
        }
        if (parms.Length() > 0) {
            self.Fail("a thread entry takes no parameters; pass state through vfields or module data instead",
                      Codes.BadEntrySignature());
        }
        let Block body = self.ParseBlock();
        return new EntryFuncDecl(mods, ret, parms, body, self.To(s));
    }

    /*
     * ParseParamList - Parses a comma-separated parameter list between the surrounding parens
     * (already consumed)
     */
    throws List[Param] func ParseParamList() {
        let List[Param] ps = new List[Param]();
        if (self.At(TK.RParen)) { return ps; }
        let Param p0 = self.ParseParam();
        ps.Add(p0);
        while (self.Try(TK.Comma)) {
            let Param pn = self.ParseParam();
            ps.Add(pn);
        }
        return ps;
    }

    /*
     * ParseParam - Parses a single parameter: an optional ref keyword, a type specifier, and a name
     */
    throws Param func ParseParam() {
        let int s = self.CurStart();
        let bool isRef = self.Try(TK.Ref);
        let TypeSpec type = self.ParseTypeSpec();
        let String name = self.ExpectValue(TK.Ident);
        return new Param(type, name, self.To(s), isRef);
    }

    /*
     * ParseBlock - Parses a brace-delimited block of statements
     */
    public throws Block func ParseBlock() {
        let int s = self.CurStart();
        self.Expect(TK.LBrace);
        let List[Stmt] stmts = new List[Stmt]();
        while (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            let Stmt st = self.ParseStmt();
            stmts.Add(st);
        }
        self.Expect(TK.RBrace);
        return new Block(stmts, self.To(s));
    }

    /*
     * ParseStmt - Dispatches to the correct statement parser based on the current token
     */
    throws Stmt func ParseStmt() {
        self.EnterDepth();
        let Stmt stmt = self.ParseStmtInner();
        self.ExitDepth();
        return stmt;
    }

    throws Stmt func ParseStmtInner() {
        let int s = self.CurStart();
        if (self.At(TK.NativeContent)) {
            let Token t = self.Advance();
            return Stmt.NativeStmt(new NativeStmt(ParseNativeBody(t), self.To(s)));
        }
        if (self.At(TK.LBrace)) {
            let Block b = self.ParseBlock();
            return Stmt.Block(b);
        }
        if (self.At(TK.Let)) { let Stmt r30 = self.ParseLetStmt(s); return r30; }
        if (self.At(TK.If)) { let Stmt r31 = self.ParseIfStmt(s); return r31; }
        if (self.At(TK.While)) { let Stmt r32 = self.ParseWhileStmt(s); return r32; }
        if (self.At(TK.For)) { let Stmt r33 = self.ParseForStmt(s); return r33; }
        if (self.At(TK.Switch)) { let Stmt r34 = self.ParseSwitchStmt(s); return r34; }
        if (self.At(TK.Match)) { let Stmt r35 = self.ParseMatchStmt(s); return r35; }
        if (self.At(TK.Try)) { let Stmt r36 = self.ParseTryCatchStmt(s); return r36; }
        if (self.At(TK.Unsafe)) { let Stmt r37 = self.ParseUnsafeBlock(s); return r37; }
        if (self.At(TK.Defer)) { let Stmt r38 = self.ParseDeferStmt(s); return r38; }
        if (self.At(TK.Return)) {
            self.Advance();
            let Optional[Expr] v = Optional[Expr].None();
            if (!self.At(TK.Semi)) {
                let Expr rv = self.ParseExpr();
                v = Optional.Some(rv);
            }
            self.Expect(TK.Semi);
            return Stmt.ReturnStmt(new ReturnStmt(v, self.To(s)));
        }
        if (self.At(TK.Break)) { self.Advance(); self.Expect(TK.Semi); return Stmt.BreakStmt(new BreakStmt(self.To(s))); }
        if (self.At(TK.Continue)) { self.Advance(); self.Expect(TK.Semi); return Stmt.ContinueStmt(new ContinueStmt(self.To(s))); }

        // Throw and debug statements are not expressions, so they must be handled here instead of
        // in ParseExprOrAssign.
        if (self.At(TK.Throw)) {
            self.Advance();
            self.Expect(TK.Semi);
            return Stmt.ThrowStmt(new ThrowStmt(self.To(s)));
        }

        // `assign v;` terminates a catch handler. Parsed here rather than in ParseExprOrAssign
        // for the same reason as throw: it transfers control, it is not an expression.
        if (self.At(TK.Assign)) {
            self.Advance();
            let Expr value = self.ParseExpr();
            self.Expect(TK.Semi);
            return Stmt.AssignValueStmt(new AssignValueStmt(value, self.To(s)));
        }
        if (self.At(TK.Debug)) {
            self.Advance();
            if (!self.At(TK.StrLit)) {
                self.Fail("'debug' takes a string literal", Codes.Syntax(), HintList.Of1("e.g. debug \"message\";"));
            }
            let Token t = self.Advance();
            self.Expect(TK.Semi);
            return Stmt.DebugStmt(new DebugStmt(Toks.Value(t), self.To(s)));
        }

        // Panic is a statement, not an expression, so it must be handled here instead of in
        // ParseExprOrAssign.
        if (self.At(TK.Panic)) {
            self.Advance();
            if (!self.At(TK.StrLit)) {
                self.Fail("'panic' takes a string literal", Codes.Syntax(), HintList.Of1("e.g. panic \"message\";"));
            }
            let Token t = self.Advance();
            self.Expect(TK.Semi);
            return Stmt.PanicStmt(new PanicStmt(Toks.Value(t), self.To(s)));
        }
        if (self.LooksLikeMissingLet()) {
            let List[String] hints = HintList.Of1("missing 'let'?");
            if (self.At(TK.Ident)) { hints.Add("e.g. 'let " + Toks.Value(self.Cur()) + " ...'"); }
            self.Fail("expected a statement", Codes.MissingLet(), hints);
        }
        let Stmt r39 = self.ParseExprOrAssign(s); return r39;
    }

    /*
     * ParseLetStmt - Parses a let declaration. The type is optional; LooksLikeTypeAndIdent is the
     * single lookahead deciding whether a declared type precedes the name, shared with the
     * for-init form so the two positions can never disagree.
     */
    throws Stmt func ParseLetStmt(int s) {
        let LetStmt ls = self.ParseLetCore(s);
        self.Expect(TK.Semi);
        return Stmt.LetStmt(ls);
    }

    /*
     * ParseLetCore - The body of a let declaration, without its trailing semicolon. C#'s
     * ParseLetStmt and ParseLetNoSemi differ only in that semicolon, so they share this.
     */
    throws LetStmt func ParseLetCore(int s) {
        self.Expect(TK.Let);
        let Optional[TypeSpec] type = Optional[TypeSpec].None();
        if (self.LooksLikeTypeAndIdent()) {
            let TypeSpec t = self.ParseTypeSpec();
            type = Optional.Some(t);
        }
        let String name = self.ExpectValue(TK.Ident);
        let Optional[Expr] init = Optional[Expr].None();
        if (self.Try(TK.Eq)) {
            let Expr iv = self.ParseExpr();
            init = Optional.Some(iv);
        }
        return new LetStmt(type, name, init, self.To(s));
    }

    /*
     * SkipBrackets - The index just past a balanced "[...]" run starting at token offset n, or -1
     * if it never closes before EOF. Used by SkipTypeSpec to jump over generic argument lists.
     */
    int func SkipBrackets(int n) {
        let int depth = 0;
        let bool first = true;
        while (first || depth > 0) {
            first = false;
            let TK k = self.PeekKind(n);
            if (k == TK.EOF) { return -1; }
            if (k == TK.LBrack) { depth = depth + 1; }
            else if (k == TK.RBrack) { depth = depth - 1; }
            n = n + 1;
        }
        return n;
    }

    /*
     * SkipFuncTypeSpec - Lookahead mirror of ParseFuncTypeSpec. The index just past the function
     * pointer type starting at offset n, or -1 if the token stream does not match.
     */
    int func SkipFuncTypeSpec(int n) {
        if (self.PeekKind(n) != TK.Func) { return -1; }
        n = n + 1;
        if (self.PeekKind(n) != TK.LParen) { return -1; }
        n = n + 1;
        if (self.PeekKind(n) != TK.RParen) {
            n = self.SkipTypeSpec(n);
            if (n < 0) { return -1; }
            while (self.PeekKind(n) == TK.Comma) {
                n = n + 1;
                n = self.SkipTypeSpec(n);
                if (n < 0) { return -1; }
            }
        }
        if (self.PeekKind(n) != TK.RParen) { return -1; }
        n = n + 1;
        if (self.PeekKind(n) != TK.Arrow) { return -1; }
        n = n + 1;
        return self.SkipTypeSpec(n);
    }

    /*
     * SkipTypeSpec - Lookahead mirror of ParseTypeSpec. The index just past the type starting at
     * offset n (Peek(0) = Cur), or -1 if offset n is not the start of a valid type.
     */
    int func SkipTypeSpec(int n) {
        while (self.PeekKind(n) == TK.LBrack && self.PeekKind(n + 1) == TK.IntLit && self.PeekKind(n + 2) == TK.RBrack) {
            n = n + 3;
        }
        let TK k = self.PeekKind(n);
        if (k == TK.Func) {
            n = self.SkipFuncTypeSpec(n);
            if (n < 0) { return -1; }
        } else if (IsPrim(k)) {
            n = n + 1;
        } else if (k == TK.Ident || k == TK.ColonColon || k == TK.Kernel || k == TK.Userspace) {
            if (k == TK.ColonColon) { n = n + 1; }
            else if (k == TK.Kernel || k == TK.Userspace) {
                if (self.PeekKind(n + 1) != TK.Dot) { return -1; }
                n = n + 2;
            }
            if (self.PeekKind(n) != TK.Ident) { return -1; }
            n = n + 1;
            while (self.PeekKind(n) == TK.Dot && self.PeekKind(n + 1) == TK.Ident) { n = n + 2; }
            if (self.PeekKind(n) == TK.LBrack) {
                n = self.SkipBrackets(n);
                if (n < 0) { return -1; }
            }
        } else {
            return -1;
        }
        while (self.PeekKind(n) == TK.Punct && Toks.Value(self.Peek(n)) == "*") { n = n + 1; }
        return n;
    }

    /*
     * LooksLikeMissingLet - True if the current position looks like a type spec immediately
     * followed by an identifier, which is always a missing 'let' and never valid expression
     * syntax. Pure lookahead; never consumes tokens.
     */
    bool func LooksLikeMissingLet() {
        if (!self.At(TK.Ident) && !self.At(TK.LBrack)) { return false; }
        let int n = self.SkipTypeSpec(0);
        return n >= 0 && self.PeekKind(n) == TK.Ident;
    }

    /*
     * LooksLikeTypeAndIdent - True if the current position looks like a type specifier followed by
     * an identifier, meaning the let statement has an explicit type annotation
     */
    bool func LooksLikeTypeAndIdent() {
        if (IsPrim(self.CurKind())) { return true; }
        if (self.At(TK.Func)) { return true; }
        if (self.At(TK.LBrack) && self.PeekKind(1) == TK.IntLit && self.PeekKind(2) == TK.RBrack) { return true; }
        if (self.At(TK.ColonColon)) { return true; }
        if (self.At(TK.Kernel) || self.At(TK.Userspace)) { return self.PeekKind(1) == TK.Dot; }
        if (!self.At(TK.Ident)) { return false; }
        return self.PeekKind(1) == TK.Ident
            || self.PeekKind(1) == TK.LBrack
            || (self.PeekKind(1) == TK.Punct && Toks.Value(self.Peek(1)) == "*");
    }

    /*
     * ParseIfStmt - Parses an if/else statement. The then and else branches are full statements,
     * so a bare block, a single statement, or a nested if are all valid without extra rules.
     */
    throws Stmt func ParseIfStmt(int s) {
        self.Expect(TK.If);
        self.Expect(TK.LParen);
        let Expr cond = self.ParseExpr();
        self.NoAssignHere("an 'if' condition", self.At(TK.Eq) ? "did you mean '=='?" : "assign before the 'if' instead");
        self.Expect(TK.RParen);
        let Stmt then = self.ParseStmt();
        let Optional[Stmt] els = Optional[Stmt].None();
        if (self.Try(TK.Else)) {
            let Stmt e = self.ParseStmt();
            els = Optional.Some(e);
        }
        return Stmt.IfStmt(new IfStmt(cond, then, els, self.To(s)));
    }

    /*
     * ParseWhileStmt - Parses a while loop. The condition is parenthesised; the body is a full
     * statement.
     */
    throws Stmt func ParseWhileStmt(int s) {
        self.Expect(TK.While);
        self.Expect(TK.LParen);
        let Expr cond = self.ParseExpr();
        self.NoAssignHere("a 'while' condition", self.At(TK.Eq) ? "did you mean '=='?" : "move the update into the loop body");
        self.Expect(TK.RParen);
        let Stmt body = self.ParseStmt();
        return Stmt.WhileStmt(new WhileStmt(cond, body, self.To(s)));
    }

    /*
     * ParseForStmt - Parses a for loop. Disambiguates between 'for x in col { }' (ForInStmt, no
     * parens) and the C-style 'for (init; cond; step) { }' (ForStmt) by peeking for the 'in'
     * keyword.
     */
    throws Stmt func ParseForStmt(int s) {
        self.Expect(TK.For);

        // for x in col { } -- range loop, no parens
        if (self.At(TK.Ident) && self.PeekKind(1) == TK.In) {
            let Token vt = self.Advance();
            self.Advance(); // consume 'in'
            let Expr coll = self.ParseExpr();
            let Block body = self.ParseBlock();
            return Stmt.ForInStmt(new ForInStmt(Toks.Value(vt), coll, body, self.To(s)));
        }

        // C-style for (init; cond; step) { }
        self.Expect(TK.LParen);

        if ((self.At(TK.Ident) && self.PeekKind(1) == TK.In)
            || (self.At(TK.Let) && self.PeekKind(1) == TK.Ident && self.PeekKind(2) == TK.In)) {
            self.Fail("a 'for ... in' loop is written without parentheses", Codes.Syntax(),
                      HintList.Of2("write 'for x in xs { ... }'",
                                   "the parenthesised form is the C-style loop, which takes "
                                   + "'for (init; condition; step)'"));
        }

        let Optional[Stmt] init = Optional[Stmt].None();
        if (!self.At(TK.Semi)) {
            if (self.At(TK.Let)) {
                let int ls = self.CurStart();
                let LetStmt l = self.ParseLetCore(ls);
                init = Optional.Some(Stmt.LetStmt(l));
            } else {
                let Stmt c = self.ParseForClause();
                init = Optional.Some(c);
            }
        }
        self.Expect(TK.Semi);
        let Optional[Expr] cond = Optional[Expr].None();
        if (!self.At(TK.Semi)) {
            let Expr c = self.ParseExpr();
            cond = Optional.Some(c);
            self.NoAssignHere("the loop condition", self.At(TK.Eq) ? "did you mean '=='?" : "move the update into the loop body");
        }
        self.Expect(TK.Semi);
        let Optional[Stmt] step = Optional[Stmt].None();
        if (!self.At(TK.RParen)) {
            if (self.At(TK.Let)) { self.Fail("cannot declare a variable in the for-loop step"); }
            let Stmt st = self.ParseForClause();
            step = Optional.Some(st);
        }
        self.Expect(TK.RParen);
        let Block body = self.ParseBlock();
        return Stmt.ForStmt(new ForStmt(init, cond, step, body, self.To(s)));
    }

    /*
     * ParseForClause - Parses a for-loop init or step clause without a trailing semicolon: an
     * expression, optionally promoted to an assignment when an assignment operator follows.
     */
    throws Stmt func ParseForClause() {
        let int es = self.CurStart();
        let Expr lhs = self.ParseExpr();
        if (IsAssignTk(self.CurKind())) {
            let AssignOp op = AssignOpOf(self.CurKind());
            self.Advance();
            let Expr rhs = self.ParseExpr();
            return Stmt.AssignStmt(new AssignStmt(lhs, op, rhs, self.To(es)));
        }
        return Stmt.ExprStmt(new ExprStmt(lhs, self.To(es)));
    }

    /*
     * ParseTryCatchStmt - Parses a try/catch statement. Both the try and catch branches are blocks.
     */
    throws Stmt func ParseTryCatchStmt(int s) {
        self.Expect(TK.Try);
        let Block tryBlock = self.ParseBlock();
        self.Expect(TK.Catch);
        let Block catchBlock = self.ParseBlock();
        return Stmt.TryCatchStmt(new TryCatchStmt(tryBlock, catchBlock, self.To(s)));
    }

    /*
     * ParseUnsafeBlock - Parses an unsafe block. Pointer operations inside are permitted; the type
     * checker rejects them everywhere else.
     */
    throws Stmt func ParseUnsafeBlock(int s) {
        self.Expect(TK.Unsafe);
        let Block block = self.ParseBlock();
        return Stmt.UnsafeBlock(new UnsafeBlock(block.stmts, self.To(s)));
    }

    /*
     * ParseDeferStmt - Parses a defer statement. The deferred action is a single statement that
     * runs on every exit from the enclosing block, in LIFO order with other defers.
     */
    throws Stmt func ParseDeferStmt(int s) {
        self.Expect(TK.Defer);
        let Stmt action = self.ParseStmt();
        return Stmt.DeferStmt(new DeferStmt(action, self.To(s)));
    }

    /*
     * ParseExprOrAssign - Parses an expression statement or assignment. After parsing the
     * left-hand expression, any assignment operator promotes the result to an AssignStmt;
     * otherwise it's an ExprStmt.
     */
    throws Stmt func ParseExprOrAssign(int s) {
        let Expr expr = self.ParseExpr();
        if (IsAssignTk(self.CurKind())) {
            let AssignOp op = AssignOpOf(self.CurKind());
            self.Advance();
            let Expr val = self.ParseExpr();
            self.Expect(TK.Semi);
            return Stmt.AssignStmt(new AssignStmt(expr, op, val, self.To(s)));
        }
        self.Expect(TK.Semi);
        return Stmt.ExprStmt(new ExprStmt(expr, self.To(s)));
    }

    /*
     * ParseExpr - Entry point for all expression parsing
     */
    public throws Expr func ParseExpr() { let Expr r40 = self.ParseTernary(); return r40; }

    /*
     * ParseTernary - Parses a ternary conditional. Right-associative so nested ternaries chain
     * without parens. '?' falls through to TK.Punct since it has no dedicated token kind.
     */
    throws Expr func ParseTernary() {
        self.EnterDepth();
        let Expr result = self.ParseTernaryInner();
        self.ExitDepth();
        return result;
    }

    throws Expr func ParseTernaryInner() {
        let int s = self.CurStart();
        let Expr left = self.ParseOr();
        if (!self.AtP("?")) { return left; }
        self.Advance();
        let Expr then = self.ParseExpr();
        if (self.At(TK.ColonColon)) {
            self.Fail("'::' names the root scope and cannot be the ':' of a conditional",
                      Codes.Syntax(), HintList.Of1("put a space after the ':', as in 'c ? a : ::Name'"));
        }
        self.Expect(TK.Colon);
        let Expr els = self.ParseTernary();
        return Expr.TernaryExpr(new TernaryExpr(left, then, els, self.To(s)));
    }

    /*
     * ParseOr - Parses '||' chains
     */
    throws Expr func ParseOr() {
        let int s = self.CurStart();
        let Expr left = self.ParseAnd();
        while (self.At(TK.Or)) {
            self.Advance();
            let Expr right = self.ParseAnd();
            left = Expr.BinExpr(new BinExpr(BinOp.Or, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseAnd - Parses '&&' chains
     */
    throws Expr func ParseAnd() {
        let int s = self.CurStart();
        let Expr left = self.ParseBitOr();
        while (self.At(TK.And)) {
            self.Advance();
            let Expr right = self.ParseBitOr();
            left = Expr.BinExpr(new BinExpr(BinOp.And, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseBitOr - Parses bitwise '|' chains
     */
    throws Expr func ParseBitOr() {
        let int s = self.CurStart();
        let Expr left = self.ParseBitXor();
        while (self.AtP("|")) {
            self.Advance();
            let Expr right = self.ParseBitXor();
            left = Expr.BinExpr(new BinExpr(BinOp.BitOr, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseBitXor - Parses bitwise '^' chains
     */
    throws Expr func ParseBitXor() {
        let int s = self.CurStart();
        let Expr left = self.ParseBitAnd();
        while (self.AtP("^")) {
            self.Advance();
            let Expr right = self.ParseBitAnd();
            left = Expr.BinExpr(new BinExpr(BinOp.BitXor, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseBitAnd - Parses bitwise '&' chains
     */
    throws Expr func ParseBitAnd() {
        let int s = self.CurStart();
        let Expr left = self.ParseEquality();
        while (self.AtP("&")) {
            self.Advance();
            let Expr right = self.ParseEquality();
            left = Expr.BinExpr(new BinExpr(BinOp.BitAnd, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseEquality - Parses '==' and '!=' chains
     */
    throws Expr func ParseEquality() {
        let int s = self.CurStart();
        let Expr left = self.ParseRelational();
        while (self.At(TK.EqEq) || self.At(TK.NotEq)) {
            let BinOp op = self.At(TK.EqEq) ? BinOp.Eq : BinOp.Ne;
            self.Advance();
            let Expr right = self.ParseRelational();
            left = Expr.BinExpr(new BinExpr(op, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseRelational - Parses relational comparisons: less-than, greater-than, and their equal
     * variants
     */
    throws Expr func ParseRelational() {
        let int s = self.CurStart();
        let Expr left = self.ParseShift();
        while (self.AtP("<") || self.AtP(">") || self.At(TK.LtEq) || self.At(TK.GtEq)) {
            let BinOp op = self.AtP("<") ? BinOp.Lt : self.AtP(">") ? BinOp.Gt : self.At(TK.LtEq) ? BinOp.Le : BinOp.Ge;
            self.Advance();
            let Expr right = self.ParseShift();
            left = Expr.BinExpr(new BinExpr(op, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseShift - Parses '<<' and '>>' chains
     */
    throws Expr func ParseShift() {
        let int s = self.CurStart();
        let Expr left = self.ParseAdditive();
        while (self.At(TK.Shl) || self.At(TK.Shr)) {
            let BinOp op = self.At(TK.Shl) ? BinOp.Shl : BinOp.Shr;
            self.Advance();
            let Expr right = self.ParseAdditive();
            left = Expr.BinExpr(new BinExpr(op, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseAdditive - Parses '+' and '-' chains
     */
    throws Expr func ParseAdditive() {
        let int s = self.CurStart();
        let Expr left = self.ParseMultiplicative();
        while (self.AtP("+") || self.AtP("-")) {
            let BinOp op = self.AtP("+") ? BinOp.Add : BinOp.Sub;
            self.Advance();
            let Expr right = self.ParseMultiplicative();
            left = Expr.BinExpr(new BinExpr(op, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseMultiplicative - Parses '*', '/', and '%' chains
     */
    throws Expr func ParseMultiplicative() {
        let int s = self.CurStart();
        let Expr left = self.ParseAs();
        while (self.AtP("*") || self.AtP("/") || self.AtP("%")) {
            let BinOp op = self.AtP("*") ? BinOp.Mul : self.AtP("/") ? BinOp.Div : BinOp.Mod;
            self.Advance();
            let Expr right = self.ParseAs();
            left = Expr.BinExpr(new BinExpr(op, left, right, self.To(s)));
        }
        return left;
    }

    /*
     * ParseAs - Parses 'expr as Type' casts. Tighter than '*' so 'x * y as T' means
     * 'x * (y as T)'. User-defined type casts use 'as'; primitive casts use the C-style
     * '(PrimType)' form.
     */
    throws Expr func ParseAs() {
        let int s = self.CurStart();
        let Expr expr = self.ParseUnary();
        while (self.At(TK.As)) {
            self.Advance();
            let TypeSpec target = self.ParseTypeSpec();
            expr = Expr.CastExpr(new CastExpr(target, expr, self.To(s)));
        }
        return expr;
    }

    /*
     * ParseUnary - Parses prefix unary operators. '&' and '*' are only legal inside unsafe blocks
     * but are accepted here; the type checker enforces the restriction.
     */
    throws Expr func ParseUnary() {
        self.EnterDepth();
        let Expr result = self.ParseUnaryInner();
        self.ExitDepth();
        return result;
    }

    throws Expr func ParseUnaryInner() {
        let int s = self.CurStart();
        if (self.AtP("!")) { self.Advance(); let Expr o = self.ParseUnary(); return Expr.UnaryExpr(new UnaryExpr(UnOp.Not, o, self.To(s))); }
        if (self.AtP("~")) { self.Advance(); let Expr o = self.ParseUnary(); return Expr.UnaryExpr(new UnaryExpr(UnOp.BitNot, o, self.To(s))); }
        if (self.AtP("-")) { self.Advance(); let Expr o = self.ParseUnary(); return Expr.UnaryExpr(new UnaryExpr(UnOp.Neg, o, self.To(s))); }
        if (self.AtP("&")) { self.Advance(); let Expr o = self.ParseUnary(); return Expr.AddrOfExpr(new AddrOfExpr(o, self.To(s))); }
        if (self.AtP("*")) { self.Advance(); let Expr o = self.ParseUnary(); return Expr.DerefExpr(new DerefExpr(o, self.To(s))); }
        let Expr r41 = self.ParsePostfix(); return r41;
    }

    /*
     * ParsePostfix - Parses postfix operators: '++', '--', '.member', '[index]', and '(args)' call
     */
    throws Expr func ParsePostfix() {
        let int s = self.CurStart();
        let Expr expr = self.ParsePrimary();
        while (true) {
            if (self.At(TK.Inc)) {
                self.Advance();
                expr = Expr.PostfixExpr(new PostfixExpr(PostfixOp.Inc, expr, self.To(s)));
            } else if (self.At(TK.Dec)) {
                self.Advance();
                expr = Expr.PostfixExpr(new PostfixExpr(PostfixOp.Dec, expr, self.To(s)));
            } else if (self.At(TK.Dot)) {
                self.Advance();
                let String member = self.ExpectValue(TK.Ident);
                expr = Expr.MemberAccessExpr(new MemberAccessExpr(expr, member, self.To(s)));
            } else if (self.At(TK.LBrack)) {
                expr = self.ParseBracketed(expr, s);
            } else if (self.At(TK.LParen)) {
                self.Advance();
                let List[Expr] args = self.ParseArgList();
                self.Expect(TK.RParen);
                expr = Expr.CallExpr(new CallExpr(expr, args, self.To(s)));
            } else if (self.At(TK.Catch)) {
                if (!IsCallExpr(expr)) {
                    self.Fail("'catch' here must follow a call to a 'throws' function", Codes.Syntax(),
                              HintList.Of1("e.g. let int x = Parse(s) catch { assign 0; };"));
                }
                self.Advance();
                let Block handler = self.ParseBlock();
                expr = Expr.CatchCallExpr(new CatchCallExpr(expr, handler, self.To(s)));
            } else {
                break;
            }
        }
        return expr;
    }

    /*
     * ParseBracketed - Parses '[ ... ]' after an expression: an index, a generic type reference,
     * or a node carrying both for the resolver. Only 'Ident[...].' can be a type, and a failed
     * reading is rolled back whole - cursor, depth and generic-use registrations.
     */
    throws Expr func ParseBracketed(Expr expr, int s) {
        self.RejectExplicitTypeArgs();

        let IdentExpr id = null;
        match (expr) {
            case IdentExpr(x) { id = x; }
            default { }
        }
        if (id == null) { let Expr r42 = self.ParseIndexRest(expr, s); return r42; }

        let Snapshot start = self.Mark();

        // The type reading. It needs a '.' after the brackets: 'Maybe[int]' on its own is a type
        // in value position, which is never legal, and reading it as one only worsens the error.
        let List[NamedSpec] typeArgs = null;
        let Snapshot typeEnd = start;
        let List[GenericUse] typeUses = new List[GenericUse]();
        try {
            self.Advance();
            let List[NamedSpec] args = new List[NamedSpec]();
            let NamedSpec a0 = self.ParseTypeName();
            args.Add(a0);
            while (self.Try(TK.Comma)) {
                let NamedSpec an = self.ParseTypeName();
                args.Add(an);
            }
            if (self.At(TK.RBrack)) {
                self.Advance();
                if (self.At(TK.Dot)) {
                    typeArgs = args;
                    typeEnd = self.Mark();
                    typeUses = self.GuTake(start.uses);
                }
            }
        } catch {
            // not a type list; the index reading stands alone
        }

        self.Rewind(start);
        if (typeArgs == null) { let Expr r43 = self.ParseIndexRest(expr, s); return r43; }

        // The index reading, from the same starting token.
        let Optional[Expr] indexForm = Optional[Expr].None();
        try {
            self.Advance();
            let Expr idx = self.ParseExpr();
            if (self.At(TK.RBrack)) {
                self.Advance();
                indexForm = Optional.Some(idx);
            }
        } catch {
            // not an expression
        }

        // Back to the end of the TYPE reading, but with the generic uses it recorded dropped, so
        // re-adding them below cannot double-count.
        self.RewindParts(typeEnd.pos, typeEnd.end, typeEnd.depth, start.uses);
        self.gu.AddRange(typeUses);

        let List[String] outerArgs = new List[String]();
        let int i = 0;
        while (i < typeArgs.Length()) { outerArgs.Add(typeArgs.Get(i).Mangled()); i = i + 1; }
        self.gu.Add(new GenericUse(id.name, outerArgs, self.To(s), Optional.Some(typeArgs.Clone())));

        return Expr.GenericTypeRefExpr(new GenericTypeRefExpr(id.name, typeArgs, indexForm, self.To(s)));
    }

    /*
     * RejectExplicitTypeArgs - Reports an attempt to pass explicit type arguments to a call, as in
     * 'Sort[int](xs)'
     */
    throws void func RejectExplicitTypeArgs() {
        let int i = self.pp + 1;
        let int end = self.tokens.Length();
        let bool sawPrim = false;
        let int depth = 1;
        while (i < end) {
            let TK k = Toks.Kind(self.tokens.Get(i));
            if (k == TK.LBrack) { depth = depth + 1; }
            else if (k == TK.RBrack) {
                depth = depth - 1;
                if (depth == 0) { break; }
            }
            else if (IsTypeKeyword(k)) { sawPrim = true; }
            else if (k == TK.LParen || k == TK.Semi || k == TK.LBrace) { return; } // not a bracket group at all
            i = i + 1;
        }
        if (!sawPrim || i >= end || Toks.Kind(self.tokens.Get(i)) != TK.RBrack) { return; }
        if (i + 1 >= end || Toks.Kind(self.tokens.Get(i + 1)) != TK.LParen) { return; }

        self.Fail("a function call cannot take explicit type arguments", Codes.ExplicitTypeArgs(),
                  HintList.Of2("type parameters are inferred from the argument types, so write 'f(x)' rather "
                               + "than 'f[T](x)'",
                               "if the element at an index is what you meant to call, the index has to be an "
                               + "expression - a type name is not one"));
    }

    /*
     * Mark - Everything a speculative parse may advance, so it can be put back exactly
     */
    Snapshot func Mark() { return new Snapshot(self.pp, self.pe, self.depth, self.gu.Length()); }

    /*
     * Rewind - Restores the parser to a snapshot. Depth is part of it because a failed parse
     * unwinds past every ExitDepth, and the leak is cumulative: 195 ordinary 'a[0].x' expressions
     * reached MaxDepth and were rejected as nested too deeply.
     */
    void func Rewind(Snapshot m) { self.RewindParts(m.pos, m.end, m.depth, m.uses); }

    /*
     * RewindParts - Rewind to an explicit set of components. Stands in for C#'s
     * `typeEnd with { Uses = start.Uses }`, which Gata has no record-copy syntax for.
     */
    void func RewindParts(int pos, int end, int depth, int uses) {
        self.pp = pos;
        self.pe = end;
        self.depth = depth;
        self.GuTruncate(uses);
    }

    /*
     * ParseIndexRest - Parses the remainder of an index expression, with '[' as the current token
     */
    throws Expr func ParseIndexRest(Expr obj, int s) {
        self.Advance();
        let Expr idx = self.ParseExpr();
        self.Expect(TK.RBrack);
        return Expr.IndexExpr(new IndexExpr(obj, idx, self.To(s)));
    }

    /*
     * ParseArgList - Parses a comma-separated argument list terminated by ')'
     */
    throws List[Expr] func ParseArgList() {
        let List[Expr] args = new List[Expr]();
        if (self.At(TK.RParen)) { return args; }
        let Expr a0 = self.ParseArg();
        args.Add(a0);
        while (self.Try(TK.Comma)) {
            let Expr an = self.ParseArg();
            args.Add(an);
        }
        return args;
    }

    /*
     * ParseArg - Parses a single call argument. 'ref' is only valid at the call-argument level,
     * not as a general unary prefix, so it is handled here rather than in ParseUnary.
     */
    throws Expr func ParseArg() {
        let int s = self.CurStart();
        if (self.Try(TK.Ref)) {
            let Expr t = self.ParseExpr();
            return Expr.RefArgExpr(new RefArgExpr(t, self.To(s)));
        }
        let Expr r44 = self.ParseExpr(); return r44;
    }

    /*
     * ParsePrimary - Parses a primary expression. EnterDepth guards against pathological nesting
     * like ((((((...)))))) producing a stack overflow instead of a clean diagnostic.
     */
    throws Expr func ParsePrimary() {
        self.EnterDepth();
        let Expr result = self.ParsePrimaryInner();
        self.ExitDepth();
        return result;
    }

    /*
     * ParsePrimaryInner - Dispatches to the correct primary form: literal, ident, sizeof, default,
     * new, array literal, grouped expression, primitive cast, or interpolated string
     */
    throws Expr func ParsePrimaryInner() {
        let int s = self.CurStart();

        // A scope qualifier swallows the dotted run after it: which segment ends the scope, which
        // is the name, and which are member accesses is a question only the scope tree can answer.
        match (self.ParseScopeQualifier()) {
            case Some(scope) { let Expr r45 = self.ParseScopedName(scope, s); return r45; }
            case None { }
        }

        // Literals and identifiers are all single-token forms.
        if (self.At(TK.IntLit)) { let Token t = self.Advance(); return Expr.IntLitExpr(new IntLitExpr(Toks.Value(t), Toks.Span(t))); }
        if (self.At(TK.FloatLit)) { let Token t = self.Advance(); return Expr.FloatLitExpr(new FloatLitExpr(Toks.Value(t), Toks.Span(t))); }
        if (self.At(TK.BoolLit)) { let Token t = self.Advance(); return Expr.BoolLitExpr(new BoolLitExpr(Toks.Value(t), Toks.Span(t))); }
        if (self.At(TK.CharLit)) {
            let Token t = self.Advance();
            // The lexer stores a char literal's decoded CODEPOINT as decimal text.
            return Expr.CharLitExpr(new CharLitExpr(Int.Parse(Toks.Value(t)), Toks.Span(t)));
        }
        if (self.At(TK.StrLit)) { let Token t = self.Advance(); return Expr.StrLitExpr(new StrLitExpr(Toks.Value(t), Toks.Span(t))); }
        if (self.At(TK.Null)) { self.Advance(); return Expr.NullExpr(new NullExpr(self.To(s))); }
        if (self.At(TK.InterpStrStart)) { let Expr r46 = self.ParseInterpStr(s); return r46; }

        // sizeof(Type) and default(Type) are special forms that take a type specifier in
        // parentheses.
        if (self.At(TK.Sizeof)) {
            self.Advance();
            self.Expect(TK.LParen);
            let TypeSpec t = self.ParseTypeSpec();
            self.Expect(TK.RParen);
            return Expr.SizeofExpr(new SizeofExpr(t, self.To(s)));
        }
        if (self.At(TK.Default)) {
            self.Advance();
            self.Expect(TK.LParen);
            let TypeSpec t = self.ParseTypeSpec();
            self.Expect(TK.RParen);
            return Expr.DefaultExpr(new DefaultExpr(t, self.To(s)));
        }

        // 'new Type(...)' or 'new Type[...]' or 'new Type' for fixed-size arrays.
        if (self.At(TK.New)) { let Expr r47 = self.ParseNewExpr(s); return r47; }

        // [elem1, elem2, ...] or [] for an empty array.
        if (self.At(TK.LBrack)) {
            self.Advance();
            let List[Expr] elems = new List[Expr]();
            if (self.At(TK.RBrack)) { self.Advance(); return Expr.ArrayLitExpr(new ArrayLitExpr(elems, self.To(s))); }
            let Expr e0 = self.ParseExpr();
            elems.Add(e0);
            while (self.Try(TK.Comma)) {
                let Expr en = self.ParseExpr();
                elems.Add(en);
            }
            self.Expect(TK.RBrack);
            return Expr.ArrayLitExpr(new ArrayLitExpr(elems, self.To(s)));
        }

        // Parenthesised expression or primitive cast. Unambiguous because the type must be a
        // primitive keyword or identifier and the cast must be followed by a unary expression.
        // User-defined types are not allowed here - they would collide with a grouped expression.
        if (self.At(TK.LParen)) {
            self.Advance();
            // (PrimType) expr is an unambiguous C-style cast. User-type casts use 'as'.
            if (IsPrim(self.CurKind())) {
                let TypeSpec targetType = self.ParseTypeSpec();
                self.Expect(TK.RParen);
                let Expr v = self.ParseUnary();
                return Expr.CastExpr(new CastExpr(targetType, v, self.To(s)));
            }
            let Expr e = self.ParseExpr();
            self.Expect(TK.RParen);
            return e;
        }

        if (self.At(TK.Ident)) { let Token t = self.Advance(); return Expr.IdentExpr(new IdentExpr(Toks.Value(t), Toks.Span(t))); }

        self.Fail("expected an expression, found " + self.Found());
        return Expr.NullExpr(new NullExpr(self.To(s))); // unreachable
    }

    /*
     * ParseScopedName - The dotted run after a scope qualifier, with the qualifier already consumed
     */
    throws Expr func ParseScopedName(List[String] scope, int s) {
        let List[String] path = new List[String]();
        let String head = self.ExpectIdent("a scope or declaration name");
        path.Add(head);
        while (self.At(TK.Dot) && self.PeekKind(1) == TK.Ident) {
            self.Advance();
            let Token t = self.Advance();
            path.Add(Toks.Value(t));
        }

        if (self.At(TK.LBrack)) {
            let List[String] outer = scope.Clone();
            let int i = 0;
            while (i < path.Length() - 1) { outer.Add(path.Get(i)); i = i + 1; }
            let NamedSpec spec = self.FinishTypeName(path.Last(), Optional.Some(outer), s);
            let List[String] members = new List[String]();
            while (self.At(TK.Dot) && self.PeekKind(1) == TK.Ident) {
                self.Advance();
                let Token t = self.Advance();
                members.Add(Toks.Value(t));
            }
            let ScopedNameExpr sn = new ScopedNameExpr(scope, members, self.To(s));
            sn.generic = Optional.Some(spec);
            return Expr.ScopedNameExpr(sn);
        }
        return Expr.ScopedNameExpr(new ScopedNameExpr(scope, path, self.To(s)));
    }

    /*
     * ParseInterpStr - Parses an interpolated string. The lexer emits InterpStrStart, then
     * alternating StrLit and Punct("{") ... Punct("}") pairs for embedded expressions, then
     * InterpStrEnd.
     */
    throws Expr func ParseInterpStr(int s) {
        self.Advance(); // consume InterpStrStart
        let List[Expr] parts = new List[Expr]();
        while (!self.At(TK.InterpStrEnd) && !self.At(TK.EOF)) {
            if (self.At(TK.StrLit)) {
                let Token t = self.Advance();
                parts.Add(Expr.StrLitExpr(new StrLitExpr(Toks.Value(t), Toks.Span(t))));
            } else if (self.AtP("{")) {
                self.Advance();
                let Expr e = self.ParseExpr();
                parts.Add(e);
                if (!self.AtP("}")) {
                    self.Fail("expected '}' to close the interpolated expression, found " + self.Found());
                }
                self.Advance();
            } else {
                break;
            }
        }
        self.Expect(TK.InterpStrEnd);
        return Expr.InterpStrExpr(new InterpStrExpr(parts, self.To(s)));
    }

    /*
     * ParseNewExpr - Parses a 'new' expression. An optional constructor arg list and an optional
     * collection initializer may each follow the type spec, independently. A bare 'new Type'
     * parses too; the resolver rejects it with NewOnNonClass for anything but a class.
     */
    throws Expr func ParseNewExpr(int s) {
        self.Expect(TK.New);
        let TypeSpec type = self.ParseTypeSpec();
        let List[Expr] args = new List[Expr]();
        if (self.At(TK.LParen)) {
            self.Advance();
            args = self.ParseArgList();
            self.Expect(TK.RParen);
        }
        if (self.At(TK.LBrace)) {
            let List[Expr] ci = self.ParseCollectionInit(TK.RBrace);
            return Expr.NewExpr(new NewExpr(type, args, ci, self.To(s)));
        }
        if (self.At(TK.LBrack)) {
            let List[Expr] ci = self.ParseCollectionInit(TK.RBrack);
            return Expr.NewExpr(new NewExpr(type, args, ci, self.To(s)));
        }
        return Expr.NewExpr(new NewExpr(type, args, new List[Expr](), self.To(s)));
    }

    /*
     * ParseCollectionInit - Parses a delimited, comma-separated element list for a 'new'
     * collection initializer
     */
    throws List[Expr] func ParseCollectionInit(TK close) {
        self.Advance(); // opening delimiter
        let List[Expr] elems = new List[Expr]();
        if (self.At(close)) { self.Advance(); return elems; }
        let Expr e0 = self.ParseExpr();
        elems.Add(e0);
        while (self.Try(TK.Comma)) {
            let Expr en = self.ParseExpr();
            elems.Add(en);
        }
        self.Expect(close);
        return elems;
    }

    /*
     * ParseSwitchStmt - Parses a switch statement. Each 'case' arm carries one or more
     * comma-separated labels and a block body. An optional 'default' arm catches all unmatched
     * values.
     */
    throws Stmt func ParseSwitchStmt(int s) {
        self.Expect(TK.Switch);
        self.Expect(TK.LParen);
        let Expr scrut = self.ParseExpr();
        self.Expect(TK.RParen);
        self.Expect(TK.LBrace);
        let List[SwitchCase] cases = new List[SwitchCase]();
        let Optional[Block] def = Optional[Block].None();
        let bool haveDef = false;
        while (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            if (self.At(TK.Default)) {
                self.Advance();
                if (haveDef) { self.Fail("'switch' already has a 'default' arm; remove one", Codes.DuplicateName()); }
                let Block d = self.ParseBlock();
                def = Optional.Some(d);
                haveDef = true;
                continue;
            }
            let int cs = self.CurStart();
            self.Expect(TK.Case);
            let List[Expr] labels = new List[Expr]();
            let Expr l0 = self.ParseExpr();
            labels.Add(l0);
            while (self.Try(TK.Comma)) {
                let Expr ln = self.ParseExpr();
                labels.Add(ln);
            }
            let Block body = self.ParseBlock();
            cases.Add(new SwitchCase(labels, body, self.To(cs)));
        }
        self.Expect(TK.RBrace);
        return Stmt.SwitchStmt(new SwitchStmt(scrut, cases, def, self.To(s)));
    }

    /*
     * ParseMatchStmt - Parses a match statement. Each 'case' arm names a union variant and
     * optionally binds its payload vfields. An optional 'default' arm catches unmatched variants.
     */
    throws Stmt func ParseMatchStmt(int s) {
        self.Expect(TK.Match);
        self.Expect(TK.LParen);
        let Expr scrut = self.ParseExpr();
        self.Expect(TK.RParen);
        self.Expect(TK.LBrace);
        let List[MatchCase] cases = new List[MatchCase]();
        let Optional[Block] def = Optional[Block].None();
        let bool haveDef = false;
        while (!self.At(TK.RBrace) && !self.At(TK.EOF)) {
            if (self.At(TK.Default)) {
                self.Advance();
                if (haveDef) { self.Fail("'match' already has a 'default' arm; remove one", Codes.DuplicateName()); }
                let Block d = self.ParseBlock();
                def = Optional.Some(d);
                haveDef = true;
                continue;
            }
            let int cs = self.CurStart();
            self.Expect(TK.Case);
            let String variant = self.ExpectValue(TK.Ident);
            let List[String] binds = new List[String]();
            if (self.At(TK.LParen)) {
                self.Advance();
                if (!self.At(TK.RParen)) {
                    let String b0 = self.ExpectValue(TK.Ident);
                    binds.Add(b0);
                    while (self.Try(TK.Comma)) {
                        let String bn = self.ExpectValue(TK.Ident);
                        binds.Add(bn);
                    }
                }
                self.Expect(TK.RParen);
            }
            let Block body = self.ParseBlock();
            cases.Add(new MatchCase(variant, binds, body, self.To(cs)));
        }
        self.Expect(TK.RBrace);
        return Stmt.MatchStmt(new MatchStmt(scrut, cases, def, self.To(s)));
    }
}

/*
 * ParseNativeBody - Wraps a raw native block token into a NativeBody
 */
NativeBody func ParseNativeBody(Token tok) { return new NativeBody(Toks.Value(tok)); }

/*
 * IsCallExpr - True when the expression is a plain call, the only thing a 'catch' handler may
 * attach to (C#'s `expr is not CallExpr`)
 */
bool func IsCallExpr(Expr e) {
    match (e) {
        case CallExpr(x) { return true; }
        default { return false; }
    }
}

/*
 * IsAssignTk - True if the token kind is '=' or any compound assignment operator
 */
bool func IsAssignTk(TK k) {
    return k == TK.Eq || k == TK.PlusEq || k == TK.MinusEq || k == TK.StarEq || k == TK.SlashEq
        || k == TK.PercentEq || k == TK.AmpEq || k == TK.PipeEq || k == TK.CaretEq
        || k == TK.ShlEq || k == TK.ShrEq;
}

/*
 * AssignOpOf - Maps an assignment-operator token kind to its AssignOp value. C# throws on any
 * other kind; every caller guards with IsAssignTk first, so plain '=' is the safe fallback.
 */
AssignOp func AssignOpOf(TK k) {
    if (k == TK.PlusEq)    { return AssignOp.AddAssign; }
    if (k == TK.MinusEq)   { return AssignOp.SubAssign; }
    if (k == TK.StarEq)    { return AssignOp.MulAssign; }
    if (k == TK.SlashEq)   { return AssignOp.DivAssign; }
    if (k == TK.PercentEq) { return AssignOp.ModAssign; }
    if (k == TK.AmpEq)     { return AssignOp.AndAssign; }
    if (k == TK.PipeEq)    { return AssignOp.OrAssign; }
    if (k == TK.CaretEq)   { return AssignOp.XorAssign; }
    if (k == TK.ShlEq)     { return AssignOp.ShlAssign; }
    if (k == TK.ShrEq)     { return AssignOp.ShrAssign; }
    return AssignOp.Assign;
}

/*
 * IsPrim - True if the token kind is one of the primitive type keywords
 */
bool func IsPrim(TK k) {
    return k == TK.TBool || k == TK.TInt || k == TK.TChar || k == TK.TFloat
        || k == TK.TDouble || k == TK.TShort || k == TK.TVoid || k == TK.TPrim;
}

/*
 * IsTypeKeyword - True for a token that can only ever begin a type. The primitive spellings are
 * split across several kinds rather than sharing one, so every branch has to be named.
 */
bool func IsTypeKeyword(TK k) {
    return k == TK.TPrim || k == TK.TInt || k == TK.TBool || k == TK.TChar || k == TK.TFloat
        || k == TK.TDouble || k == TK.TShort || k == TK.TVoid;
}

/*
 * PrimName - Maps a primitive token to its canonical type name string. TPrim tokens carry their
 * own value (eg. "uint64"), so those fall through to the default.
 */
String func PrimName(Token t) {
    let TK k = Toks.Kind(t);
    if (k == TK.TBool)   { return "bool"; }
    if (k == TK.TInt)    { return "int"; }
    if (k == TK.TChar)   { return "char"; }
    if (k == TK.TFloat)  { return "float"; }
    if (k == TK.TDouble) { return "double"; }
    if (k == TK.TShort)  { return "short"; }
    if (k == TK.TVoid)   { return "void"; }
    return Toks.Value(t);
}

/*
 * StripQuotes - Drops one leading and one trailing '"' from a string-literal token's raw text
 * (C#'s value.Trim('"'))
 */
String func StripQuotes(String raw) {
    let int start = 0;
    let int end = raw.Length();
    while (start < end && raw.CharAt(start) == '"') { start = start + 1; }
    while (end > start && raw.CharAt(end - 1) == '"') { end = end - 1; }
    return raw.Substring(start, end - start);
}

/*
 * GenericInstance - The mangled name of a generic instantiation: Base_Arg1_Arg2
 *
 * TODO(Mangler.g): C#'s Mangler.GenericInstance also files the composed name in the NameTable so
 * diagnostics can spell it back as 'Base[Arg1, Arg2]'. Same gap as Specs.Flatten in Ast.g; route
 * both through Mangler.GenericInstance once Backend/Mangler.g lands.
 */
String func GenericInstance(String baseName, List[String] args) {
    let StringBuilder sb = new StringBuilder();
    sb.Put(baseName);
    let int i = 0;
    while (i < args.Length()) {
        sb.AppendChar('_');
        sb.Put(args.Get(i));
        i = i + 1;
    }
    return sb.ToString();
}

/*
 * KindName - Maps a token kind to the human-readable form used in "expected X" messages
 */
String func KindName(TK k) {
    if (k == TK.Ident) { return "an identifier"; }
    if (k == TK.IntLit) { return "an integer literal"; }
    if (k == TK.FloatLit) { return "a float literal"; }
    if (k == TK.StrLit) { return "a string literal"; }
    if (k == TK.InterpStrEnd) { return "the closing '\"' of the interpolated string"; }
    if (k == TK.LParen) { return "'('"; }
    if (k == TK.RParen) { return "')'"; }
    if (k == TK.LBrace) { return "'{'"; }
    if (k == TK.RBrace) { return "'}'"; }
    if (k == TK.LBrack) { return "'['"; }
    if (k == TK.RBrack) { return "']'"; }
    if (k == TK.Semi) { return "';'"; }
    if (k == TK.Comma) { return "','"; }
    if (k == TK.Colon) { return "':'"; }
    if (k == TK.ColonColon) { return "'::'"; }
    if (k == TK.Dot) { return "'.'"; }
    if (k == TK.Eq) { return "'='"; }
    if (k == TK.Arrow) { return "'->'"; }
    if (k == TK.EOF) { return "end of file"; }
    return "'" + TkLower(k) + "'";
}

/*
 * TkLower - The lowercased spelling of a token kind's own name, standing in for C#'s
 * k.ToString().ToLowerInvariant() - Gata has no runtime reflection over enum names.
 */
String func TkLower(TK k) {
        if (k == TK.Ident) { return "ident"; }
        if (k == TK.IntLit) { return "intlit"; }
        if (k == TK.FloatLit) { return "floatlit"; }
        if (k == TK.StrLit) { return "strlit"; }
        if (k == TK.BoolLit) { return "boollit"; }
        if (k == TK.InterpStrStart) { return "interpstrstart"; }
        if (k == TK.InterpStrEnd) { return "interpstrend"; }
        if (k == TK.CharLit) { return "charlit"; }
        if (k == TK.NativeContent) { return "nativecontent"; }
        if (k == TK.NativeTypeDecl) { return "nativetypedecl"; }
        if (k == TK.Import) { return "import"; }
        if (k == TK.Realm) { return "realm"; }
        if (k == TK.Kernel) { return "kernel"; }
        if (k == TK.Userspace) { return "userspace"; }
        if (k == TK.Foreground) { return "foreground"; }
        if (k == TK.Background) { return "background"; }
        if (k == TK.Class) { return "class"; }
        if (k == TK.Module) { return "module"; }
        if (k == TK.Func) { return "func"; }
        if (k == TK.Static) { return "static"; }
        if (k == TK.Public) { return "public"; }
        if (k == TK.Private) { return "private"; }
        if (k == TK.Entry) { return "entry"; }
        if (k == TK.Throws) { return "throws"; }
        if (k == TK.Operator) { return "operator"; }
        if (k == TK.As) { return "as"; }
        if (k == TK.Fields) { return "vfields"; }
        if (k == TK.Ref) { return "ref"; }
        if (k == TK.AtIntrinsic) { return "atintrinsic"; }
        if (k == TK.AtPreamble) { return "atpreamble"; }
        if (k == TK.AtExtern) { return "atextern"; }
        if (k == TK.AtEnvironment) { return "atenvironment"; }
        if (k == TK.AtKeep) { return "atkeep"; }
        if (k == TK.AtBuiltin) { return "atbuiltin"; }
        if (k == TK.AtShadows) { return "atshadows"; }
        if (k == TK.Return) { return "return"; }
        if (k == TK.If) { return "if"; }
        if (k == TK.Else) { return "else"; }
        if (k == TK.While) { return "while"; }
        if (k == TK.For) { return "for"; }
        if (k == TK.In) { return "in"; }
        if (k == TK.Break) { return "break"; }
        if (k == TK.Continue) { return "continue"; }
        if (k == TK.Switch) { return "switch"; }
        if (k == TK.Case) { return "case"; }
        if (k == TK.Try) { return "try"; }
        if (k == TK.Catch) { return "catch"; }
        if (k == TK.New) { return "new"; }
        if (k == TK.Let) { return "let"; }
        if (k == TK.Null) { return "null"; }
        if (k == TK.Unsafe) { return "unsafe"; }
        if (k == TK.Throw) { return "throw"; }
        if (k == TK.Sizeof) { return "sizeof"; }
        if (k == TK.Default) { return "default"; }
        if (k == TK.Enum) { return "enum"; }
        if (k == TK.Debug) { return "debug"; }
        if (k == TK.Panic) { return "panic"; }
        if (k == TK.Defer) { return "defer"; }
        if (k == TK.Match) { return "match"; }
        if (k == TK.Union) { return "union"; }
        if (k == TK.Assign) { return "assign"; }
        if (k == TK.TBool) { return "tbool"; }
        if (k == TK.TInt) { return "tint"; }
        if (k == TK.TChar) { return "tchar"; }
        if (k == TK.TFloat) { return "tfloat"; }
        if (k == TK.TDouble) { return "tdouble"; }
        if (k == TK.TShort) { return "tshort"; }
        if (k == TK.TVoid) { return "tvoid"; }
        if (k == TK.TPrim) { return "tprim"; }
        if (k == TK.PlusEq) { return "pluseq"; }
        if (k == TK.MinusEq) { return "minuseq"; }
        if (k == TK.StarEq) { return "stareq"; }
        if (k == TK.SlashEq) { return "slasheq"; }
        if (k == TK.PercentEq) { return "percenteq"; }
        if (k == TK.AmpEq) { return "ampeq"; }
        if (k == TK.PipeEq) { return "pipeeq"; }
        if (k == TK.CaretEq) { return "careteq"; }
        if (k == TK.ShlEq) { return "shleq"; }
        if (k == TK.ShrEq) { return "shreq"; }
        if (k == TK.EqEq) { return "eqeq"; }
        if (k == TK.NotEq) { return "noteq"; }
        if (k == TK.LtEq) { return "lteq"; }
        if (k == TK.GtEq) { return "gteq"; }
        if (k == TK.And) { return "and"; }
        if (k == TK.Or) { return "or"; }
        if (k == TK.Inc) { return "inc"; }
        if (k == TK.Dec) { return "dec"; }
        if (k == TK.Arrow) { return "arrow"; }
        if (k == TK.Shl) { return "shl"; }
        if (k == TK.Shr) { return "shr"; }
        if (k == TK.LParen) { return "lparen"; }
        if (k == TK.RParen) { return "rparen"; }
        if (k == TK.LBrace) { return "lbrace"; }
        if (k == TK.RBrace) { return "rbrace"; }
        if (k == TK.LBrack) { return "lbrack"; }
        if (k == TK.RBrack) { return "rbrack"; }
        if (k == TK.Semi) { return "semi"; }
        if (k == TK.Comma) { return "comma"; }
        if (k == TK.Colon) { return "colon"; }
        if (k == TK.ColonColon) { return "coloncolon"; }
        if (k == TK.Dot) { return "dot"; }
        if (k == TK.Eq) { return "eq"; }
        if (k == TK.Punct) { return "punct"; }
        if (k == TK.EOF) { return "eof"; }
    return "?";
}
