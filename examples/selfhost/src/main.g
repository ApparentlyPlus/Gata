/*
 * selfhost - proof-of-life for the self-hosting scaffold: exercises File.g and Dir.g end to end
 * against the real filesystem through env.selfhost.g's floor. Stands in for the compiler driver
 * until that gets written.
 */
import "selfhostlib/Console.g";
import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Result.g";
import "selfhostlib/File.g";
import "selfhostlib/Dir.g";
import "selfhostlib/Sys.g";
import "selfhostlib/Args.g";
import "src/Diagnostics/Diagnostic.g";
import "src/Syntax/Token.g";
import "src/Syntax/Ast.g";
import "src/Syntax/Lexer.g";
import "src/Syntax/Parser.g";
import "src/IR/Ir.g";
import "src/Semantics/ScopeTree.g";
import "src/Semantics/ScopeBinder.g";
import "src/Backend/Mangler.g";
import "src/Semantics/SignatureKey.g";
import "src/Semantics/SymbolTable.g";
import "src/Semantics/Monomorphizer.g";
import "src/Diagnostics/SourceText.g";

realm userspace {
    entry func Main() {
        if (Args.Argc() > 1) {
            CheckOne(Args.Arg(1));
            Sys.Exit(0);
        }

        let String path = "selfhost_scratch.txt";
        let String payload = "hello from a self-hosted appa\n";

        Console.PrintLine("write=" + (File.Write(path, payload) as String));
        Console.PrintLine("exists=" + (File.Exists(path) as String));

        match (File.Read(path)) {
            case Ok(contents) { Console.PrintLine("read=" + contents); }
            case Err(msg)     { Console.PrintLineErr("error=" + msg); }
        }

        let String missing = "selfhost_does_not_exist.txt";
        Console.PrintLine("missing.exists=" + (File.Exists(missing) as String));
        match (File.Read(missing)) {
            case Ok(contents) { Console.PrintLine("missing.read=" + contents); }
            case Err(msg)     { Console.PrintLineErr("missing.error=" + msg); }
        }

        let String dir = "selfhost_scratch_dir";
        Console.PrintLine("mkdir=" + (Dir.MakeDir(dir) as String));
        Console.PrintLine("isdir=" + (Dir.IsDir(dir) as String));

        let String nested = dir + "/nested.txt";
        File.Write(nested, "nested\n");
        let List[String] entries = Dir.List(dir);
        Console.PrintLine("entrycount=" + (entries.Length() as String));
        let int i = 0;
        while (i < entries.Length()) { Console.PrintLine("entry=" + entries.Get(i)); i = i + 1; }

        Console.PrintLine("cwdlen>0=" + ((Dir.Cwd().Length() > 0) as String));

        Console.PrintLine("cleanup=" + (Dir.DeleteRecursive(dir) as String));
        Console.PrintLine("gone=" + (!Dir.IsDir(dir) as String));
        Dir.DeleteFile(path);

        Console.PrintLine("argc=" + (Args.Argc() as String));
        let int a = 0;
        while (a < Args.Argc()) { Console.PrintLine("argv[" + (a as String) + "]=" + Args.Arg(a)); a = a + 1; }

        LexSmoke();
        AstSmoke();
        ParseSmoke();
        ParseTree();
        IrSmoke();
        ManglerSmoke();
        BindSmoke();

        Sys.Exit(0);
    }

    /*
     * LexSmoke - Runs the ported Lexer over a snippet touching every token family, so the token
     * stream is exercised at runtime rather than only type-checked. Without a call like this the
     * whole Lexer is dead code and never reaches the emitted C.
     */
    void func LexSmoke() {
        let String source = "class C { public int f = 0x1Fu; }\n" +
                            "func M(int a) { let char c = '\\n'; let String s = $\"v={a}\"; " +
                            "if (a >= 1) { a <<= 2; } return; }\n";

        let Lexer lx = new Lexer(source);
        let List[Token] toks = lx.Tokenize() catch {
            Console.PrintLineErr("lex.error=" + PErr.Message(lx.lastErr) + " [" + PErr.Code(lx.lastErr) + "]");
            return;
        };

        Console.PrintLine("lex.count=" + (toks.Length() as String));

        // The char literal '\n' must carry its decimal CODEPOINT, the way Parser.cs int.Parse'es it
        let int i = 0;
        while (i < toks.Length()) {
            let Token t = toks.Get(i);
            if (Toks.Kind(t) == TK.CharLit) { Console.PrintLine("lex.charlit=" + Toks.Value(t)); }
            if (Toks.Kind(t) == TK.IntLit) { Console.PrintLine("lex.intlit=" + Toks.Value(t)); }
            if (Toks.Kind(t) == TK.ShlEq) { Console.PrintLine("lex.shleq=" + Toks.Value(t)); }
            if (Toks.Kind(t) == TK.InterpStrStart) { Console.PrintLine("lex.interp.start"); }
            i = i + 1;
        }
        Console.PrintLine("lex.last=" + ((Toks.Kind(toks.Get(toks.Length() - 1)) == TK.EOF) as String));

        // A deliberate failure, to prove the ParseError sink round-trips
        let Lexer bad = new Lexer("let x = '\\q';");
        let List[Token] _ignored = bad.Tokenize() catch {
            Console.PrintLine("lex.fail=" + PErr.Code(bad.lastErr) + " @" + (TS.Start(PErr.Span(bad.lastErr)) as String) +
                              " :: " + PErr.Message(bad.lastErr));
            assign new List[Token]();
        };
    }

    /*
     * AstSmoke - Builds a small AST by hand and walks it, so the node types are exercised at
     * runtime (recursive unions through class refs, Optional-valued fields, ARC over List[Expr])
     * rather than only type-checked. Stands in for the Parser until that gets written.
     *
     * Models:  let List[int] xs = 1 + 2 * 3;
     */
    void func AstSmoke() {
        let TextSpan sp = TextSpan.Span(0, 1);

        // 2 * 3
        let Expr two = Expr.IntLitExpr(new IntLitExpr("2", sp));
        let Expr three = Expr.IntLitExpr(new IntLitExpr("3", sp));
        let Expr mul = Expr.BinExpr(new BinExpr(BinOp.Mul, two, three, sp));

        // 1 + (2 * 3)
        let Expr one = Expr.IntLitExpr(new IntLitExpr("1", sp));
        let Expr add = Expr.BinExpr(new BinExpr(BinOp.Add, one, mul, sp));

        // List[int]
        let List[NamedSpec] targs = new List[NamedSpec]();
        targs.Add(new NamedSpec("int", new List[NamedSpec](), sp));
        let NamedSpec listOfInt = new NamedSpec("List", targs, sp);
        Console.PrintLine("ast.mangled=" + listOfInt.Mangled());
        Console.PrintLine("ast.spec=" + Specs.ToSpecString(TypeSpec.PtrSpec(
            new PtrSpec(TypeSpec.NamedSpec(listOfInt), sp))));

        // let xs = <add>;
        let Stmt letXs = Stmt.LetStmt(new LetStmt(
            Optional.Some(TypeSpec.NamedSpec(listOfInt)), "xs", Optional.Some(add), sp));

        let List[Stmt] body = new List[Stmt]();
        body.Add(letXs);
        body.Add(Stmt.ReturnStmt(new ReturnStmt(Optional[Expr].None(), sp)));
        let Block blk = new Block(body, sp);

        Console.PrintLine("ast.stmts=" + (blk.stmts.Length() as String));
        Console.PrintLine("ast.render=" + RenderStmt(blk.stmts.Get(0)));
        Console.PrintLine("ast.span0=" + (TS.Start(Stmts.Span(blk.stmts.Get(0))) as String));

        // The operator tables
        Console.PrintLine("ast.binsym=" + Ops.BinSym(BinOp.Shl) + Ops.AssignSym(AssignOp.ShlAssign));
        match (Ops.BaseOp(AssignOp.XorAssign)) {
            case Some(b) { Console.PrintLine("ast.baseop=" + Ops.BinSym(b)); }
            case None    { Console.PrintLine("ast.baseop=none"); }
        }
        match (Ops.BaseOp(AssignOp.Assign)) {
            case Some(b) { Console.PrintLine("ast.plainbase=" + Ops.BinSym(b)); }
            case None    { Console.PrintLine("ast.plainbase=none"); }
        }
        Console.PrintLine("ast.arity-neg=" + (OperatorRules.RequiredArity("-", 0) as String) +
                          " arity-sub=" + (OperatorRules.RequiredArity("-", 1) as String) +
                          " defret=" + OperatorRules.DefaultReturn("==", "Money"));

        let Modifiers m = Mods.With(Mods.With(Mods.Empty(), Modifiers.Public), Modifiers.Static);
        Console.PrintLine("ast.mods pub=" + (Mods.Has(m, Modifiers.Public) as String) +
                          " priv=" + (Mods.Has(m, Modifiers.Private) as String) +
                          " after-drop=" + (Mods.Has(Mods.Without(m, Modifiers.Static), Modifiers.Static) as String));
    }

    /*
     * RenderStmt - Spells a statement back out, the smallest walk that proves the recursive
     * unions and their Optional-valued fields round-trip
     */
    String func RenderStmt(Stmt s) {
        match (s) {
            case LetStmt(x) {
                let String ty = "";
                match (x.type) { case Some(t) { ty = Specs.ToSpecString(t) + " "; } case None { } }
                let String rhs = "";
                match (x.init) { case Some(e) { rhs = " = " + RenderExpr(e); } case None { } }
                return "let " + ty + x.name + rhs + ";";
            }
            case ReturnStmt(x) {
                match (x.value) {
                    case Some(e) { return "return " + RenderExpr(e) + ";"; }
                    case None    { return "return;"; }
                }
            }
            default { return "<stmt>"; }
        }
    }

    /*
     * RenderExpr - Spells an expression back out, parenthesizing every binary node
     */
    String func RenderExpr(Expr e) {
        match (e) {
            case IntLitExpr(x) { return x.value; }
            case BinExpr(x)    { return "(" + RenderExpr(x.left) + " " + Ops.BinSym(x.op) + " " + RenderExpr(x.right) + ")"; }
            default            { return "<expr>"; }
        }
    }

    /*
     * ParseSmoke - Runs the ported Parser over a snippet touching most of the grammar and prints a
     * shape summary, so a structural regression shows up as a changed count rather than silence.
     */
    void func ParseSmoke() {
        let String source =
            "import \"selfhostlib/String.g\";\n" +
            "@environment\n" +
            "enum Dir { North, East = 2, South }\n" +
            "union Shape { Circle(double r), Rect(double w, double h), Point }\n" +
            "@keep class Box[T] { public T v; int n = 3; c = 'x';\n" +
            "  func _init() { self.n = 0; }\n" +
            "  public operator bool func ==(Box[T] o) { return self.n == o.n; }\n" +
            "  public T func Get(int i) native { return self.v; }\n" +
            "  fields { volatile int head; }\n" +
            "}\n" +
            "module M { public static int func Sq(int x) { return x * x; } }\n" +
            "@extern void func _env_yield();\n" +
            "native type Handle { void* p; }\n" +
            "private throws int func Parse(String s) {\n" +
            "  let [3]int a = [1, 2, 3];\n" +
            "  let func(int, int) -> int fp = null;\n" +
            "  let Map[String, List[int]] m = new Map[String, List[int]]() { };\n" +
            "  let int v = Parse(s) catch { assign 0; };\n" +
            "  for (let int i = 0; i < 10; i++) { v += i; }\n" +
            "  for x in a { debug \"hi\"; }\n" +
            "  while (true) { if (v > 2) { break; } else { continue; } }\n" +
            "  switch (v) { case 0, 1 { } default { } }\n" +
            "  match (Shape.Point()) { case Circle(r) { } case Rect(w, h) { } case Point { } }\n" +
            "  unsafe { let int* p = &v; defer _env_yield(); v = *p; }\n" +
            "  try { Parse(s); } catch { }\n" +
            "  let String t = $\"v={v} and {a[0]}\";\n" +
            "  let int z = v > 1 ? (v as int) : ::Parse(t) catch { assign 0; };\n" +
            "  let usize sz = sizeof(int); let Dir d = default(Dir);\n" +
            "  throw;\n" +
            "}\n" +
            "realm userspace {\n" +
            "  foreground process App { let int ticks = 0; thread Ui { entry func Run() { } } }\n" +
            "  entry func Main() { }\n" +
            "}\n";

        match (ParseSource(source)) {
            case Err(msg) { Console.PrintLineErr("parse.error=" + msg); return; }
            case Ok(prog) {
                Console.PrintLine("parse.items=" + (prog.items.Length() as String));
                Console.PrintLine("parse.genericuses=" + (prog.genericUses.Length() as String));
                Console.PrintLine("parse.scopedrefs=" + (prog.hasScopedRefs as String));
                let int i = 0;
                let StringBuilder sb = new StringBuilder();
                while (i < prog.items.Length()) {
                    if (i > 0) { sb.Put(","); }
                    sb.Put(TopName(prog.items.Get(i)));
                    i = i + 1;
                }
                Console.PrintLine("parse.kinds=" + sb.ToString());
            }
        }

        // Diagnostics still land where they should
        ExpectFail("realm banana { }", "parse.badrealm");
        ExpectFail("int func F() { let int x = 1 }", "parse.nosemi");
        ExpectFail("class C { public int f; } class D { void func G() { G(1,); } }", "parse.trailing");
        ExpectFail("void func F() { let int a = Sort[int](xs); }", "parse.typeargs");
        ExpectFail("process P { }", "parse.strayprocess");
    }

    /*
     * ParseTree - Lexes and parses every .g file the selfhost project is itself written in. A
     * self-hosted front end that cannot read its own source is not a front end yet, so this is the
     * real test: appa accepts all of these, and so must this port.
     */
    void func ParseTree() {
        let List[String] roots = new List[String]();
        roots.Add("selfhostlib");
        roots.Add("src");
        roots.Add("src/Diagnostics");
        roots.Add("src/Syntax");
        roots.Add("src/IR");
        roots.Add("src/Backend");

        let int okCount = 0;
        let int failCount = 0;
        let int totalTokens = 0;
        let int totalItems = 0;

        let int r = 0;
        while (r < roots.Length()) {
            let String dir = roots.Get(r);
            let List[String] entries = Dir.List(dir);
            let int i = 0;
            while (i < entries.Length()) {
                let String name = entries.Get(i);
                if (name.EndsWith(".g")) {
                    let String path = dir + "/" + name;
                    match (File.Read(path)) {
                        case Err(msg) { Console.PrintLineErr("tree.unreadable=" + path); failCount = failCount + 1; }
                        case Ok(text) {
                            let Lexer lx = new Lexer(text);
                            let List[Token] toks = lx.Tokenize() catch {
                                Console.PrintLineErr("tree.LEX " + path + ": " + PErr.Message(lx.lastErr));
                                failCount = failCount + 1;
                                assign new List[Token]();
                            };
                            if (toks.Length() > 0) {
                                totalTokens = totalTokens + toks.Length();
                                let Parser ps = new Parser(toks, new Mangler());
                                let Program prog = ps.ParseProgram() catch {
                                    Console.PrintLineErr("tree.PARSE " + path + ":" +
                                        (TS.Start(PErr.Span(ps.lastErr)) as String) + " [" +
                                        PErr.Code(ps.lastErr) + "] " + PErr.Message(ps.lastErr));
                                    failCount = failCount + 1;
                                    assign new Program(new List[TopLevel]());
                                };
                                if (prog.items.Length() > 0) {
                                    okCount = okCount + 1;
                                    totalItems = totalItems + prog.items.Length();
                                }
                            }
                        }
                    }
                }
                i = i + 1;
            }
            r = r + 1;
        }

        Console.PrintLine("tree.filesOk=" + (okCount as String) + " failed=" + (failCount as String));
        Console.PrintLine("tree.tokens=" + (totalTokens as String) + " topLevelItems=" + (totalItems as String));
    }

    /*
     * ExpectFail - Asserts that a snippet is rejected, and prints the code it was rejected with
     */
    void func ExpectFail(String src, String label) {
        match (ParseSource(src)) {
            case Ok(prog) { Console.PrintLineErr(label + "=UNEXPECTEDLY-ACCEPTED"); }
            case Err(msg) { Console.PrintLine(label + "=" + msg); }
        }
    }

    /*
     * IrSmoke - Exercises the IR type model: the interning table's identity guarantee, the
     * structural manglings, and the C spellings.
     */
    void func IrSmoke() {
        let IrTypeTable t = new IrTypeTable();
        let Mangler mg = new Mangler();
        let IrType a = t.Ptr(t.Int());
        let IrType b = t.Ptr(t.Prim("int"));
        Console.PrintLine("ir.interned=" + ((a == b) as String) + " eq=" + (Types.TypeEq(a, b) as String));

        let List[IrType] ps = new List[IrType]();
        ps.Add(t.Int());
        ps.Add(t.Str());
        let IrType fp = t.FuncPtr(t.Bool(), ps);
        Console.PrintLine("ir.fnptr=" + Types.MangledName(fp));

        let IrType arr = t.Array(t.Ptr(t.Char()), 4);
        Console.PrintLine("ir.arr=" + Types.MangledName(arr) + " c=" + mg.CType(arr));
        Console.PrintLine("ir.result=" + Types.MangledName(t.Result(t.Void())) +
                          " cname=" + mg.CType(t.Result(t.Void())));
        Console.PrintLine("ir.str=" + (Types.IsString(t.Str()) as String) +
                          " uns=" + (Types.IsUnsigned(t.Prim("usize")) as String) +
                          " rank=" + (PrimTypes.Rank("double") as String) +
                          " bits=" + (PrimTypes.IntBits("uint64") as String) +
                          " toc=" + PrimTypes.ToC("byte"));

        // A class, an enum and a union of one name are three types; MangledName alone cannot tell
        // them apart, which is why the intern key carries a kind tag.
        let IrType c1 = t.ClassRef("Foo");
        let IrType e1 = t.EnumType("Foo");
        let IrType u1 = t.UnionType("Foo");
        Console.PrintLine("ir.tagged=" + ((c1 == e1) as String) + ((c1 == u1) as String) +
                          " keys=" + Types.Key(c1) + "/" + Types.Key(e1) + "/" + Types.Key(u1));

        let IrExpr lit = IrExpr.IrLitInt(new IrLitInt(7 as int64, t.Int(), Optional[String].None()));
        let IrExpr sum = IrExpr.IrBinOp(new IrBinOp(BinOp.Add, lit, lit, t.Int()));
        Console.PrintLine("ir.exprtype=" + Types.MangledName(Exprs2.TypeOf(sum)));

        let List[IrStmt] body = new List[IrStmt]();
        body.Add(IrStmt.IrReturn(new IrReturn(Optional.Some(sum))));
        let IrModule m = new IrModule(new List[IrNativeBlock](), new List[IrNativeType](),
            new List[IrClass](), new List[IrFunction](), new List[IrProcess](), new List[IrType](),
            new List[IrEnum](), new List[IrType](), new List[IrUnion]());
        Console.PrintLine("ir.module kernel=" + (m.HasKernelRealm() as String) +
                          " user=" + (m.HasUserRealm() as String) +
                          " stmts=" + (body.Length() as String));
    }

    /*
     * BindSmoke - Runs lex -> parse -> ScopeBinder over sources that exercise every diagnostic the
     * binder owns, and renders one of them through DiagnosticBag so SourceText and Render are
     * exercised too. This is the first point in the port where a whole front-end slice runs.
     */
    void func BindSmoke() {
        // A clean program: the shadow is declared, so nothing is reported.
        Bound("ok", "int func Step() { return 1; }\n" +
                    "realm kernel {\n" +
                    "  @shadows int func Step() { return 2; }\n" +
                    "  entry func Main() { let int z = ::Step(); }\n" +
                    "}\n");

        // An unmarked shadow
        Bound("unmarked", "int func Step() { return 1; }\n" +
                          "realm kernel { int func Step() { return 2; } entry func Main() { } }\n");

        // '@shadows' that displaces nothing
        Bound("nothing", "realm kernel { @shadows int func Never() { return 0; } entry func Main() { } }\n");

        // '@shadows' at the top level, which has no enclosing scope
        Bound("stray", "@shadows int func Loose() { return 0; }\n");

        // One name, two meanings, in one scope
        Bound("twomeanings", "realm kernel { class Job { public int n; } int func Job() { return 1; } entry func Main() { } }\n");

        // Two processes of one name in one realm
        Bound("dupproc", "realm userspace {\n" +
                         "  foreground process App { thread A { entry func R() { } } }\n" +
                         "  foreground process App { thread B { entry func R() { } } }\n" +
                         "}\n");

        // These two reach the binder only through the rewrite sweep, which drives
        // ResolveScopedExpr/ResolveScopedType. Before Monomorphizer.g they reported nothing.
        Bound("sideways", "realm userspace { int func Helper() { return 1; } }\n" +
                          "realm kernel { entry func Main() { let int z = userspace.Helper(); } }\n");
        Bound("unknownin", "realm kernel { entry func Main() { let int z = kernel.Missing(); } }\n");
        Bound("qualok", "realm kernel { int func Step() { return 1; }\n" +
                        "  entry func Main() { let int z = kernel.Step(); } }\n");

        // The resolvers are still driven directly too, for the shapes the parser cannot produce.
        QualifierSmoke();
        MonoSmoke();

        // Rendering, with the source snippet and caret
        RenderOne("realm kernel { int func Step() { return 2; } entry func Main() { } }\n" +
                  "int func Step() { return 1; }\n");
    }

    /*
     * QualifierSmoke - Drives ResolveScopedExpr directly.
     */
    void func QualifierSmoke() {
        let String src = "int func Root() { return 0; }\n" +
                         "realm userspace { int func Helper() { return 1; } }\n" +
                         "realm kernel { entry func Main() { } }\n";
        match (ParseSource(src)) {
            case Err(msg) { Console.PrintLineErr("qual=PARSE-FAILED " + msg); }
            case Ok(prog) {
                let SourceSet set = new SourceSet();
                set.Add("case.g", src);
                let DiagnosticBag bag = new DiagnosticBag(set);
                let ScopeBinder binder = new ScopeBinder(bag, new Mangler());
                let List[ProgramFile] files = new List[ProgramFile]();
                files.Add(new ProgramFile("case.g", prog));
                let ScopeBindResult r = binder.Bind(files, null);

                // kScope/uScope, not kernel/userspace: both are hard keywords.
                let ScopeId kScope = r.tree.Intern(Sc.Root(), "kernel", Realm.Kernel);
                let ScopeId uScope = r.tree.Intern(Sc.Root(), "userspace", Realm.User);
                let TextSpan sp = TextSpan.Span(0, 3);

                // resolves: userspace.Helper, read from inside userspace
                Qual(binder, r, uScope, "userspace", "Helper", sp, "qual.ok");
                // resolves: ::Root, read from anywhere
                Qual(binder, r, kScope, "", "Root", sp, "qual.root");
                // no such scope
                Qual(binder, r, kScope, "banana", "Step", sp, "qual.noscope");
                // sideways: userspace does not enclose kernel
                Qual(binder, r, kScope, "userspace", "Helper", sp, "qual.sideways");
                // the scope exists and encloses, but declares no such name
                Qual(binder, r, kScope, "kernel", "Missing", sp, "qual.unknownin");

                // 'userspace.Nope.Thing' - the walk stops at the first segment that names no
                // child, so the complaint is about 'Nope', not about 'Thing'
                let List[String] uscope = new List[String]();
                uscope.Add("userspace");
                let List[String] deep = new List[String]();
                deep.Add("Nope");
                deep.Add("Thing");
                let Expr nested = binder.ResolveScopedExpr(
                    new ScopedNameExpr(uscope, deep, sp), r.tree, r.index, uScope, "case.g");
                match (nested) {
                    case PoisonExpr(px) { Console.PrintLine("qual.nested=<poisoned>"); }
                    default { Console.PrintLine("qual.nested=<resolved>"); }
                }

                let int i = 0;
                while (i < bag.Count()) {
                    let Diagnostic d = bag.All().Get(i);
                    Console.PrintLine("qual.diag=" + Diags.Code(d) + ": " + Diags.Message(d));
                    i = i + 1;
                }
            }
        }
    }

    /*
     * Qual - Resolves one written qualifier and prints what it became
     */
    void func Qual(ScopeBinder binder, ScopeBindResult r, ScopeId from, String scopeSeg, String name,
                   TextSpan sp, String label) {
        let List[String] scope = new List[String]();
        if (scopeSeg.Length() > 0) { scope.Add(scopeSeg); }
        let List[String] path = new List[String]();
        path.Add(name);
        let ScopedNameExpr sn = new ScopedNameExpr(scope, path, sp);
        let Expr got = binder.ResolveScopedExpr(sn, r.tree, r.index, from, "case.g");
        match (got) {
            case IdentExpr(id) { Console.PrintLine(label + "=" + id.name); }
            case PoisonExpr(px) { Console.PrintLine(label + "=<poisoned>"); }
            default { Console.PrintLine(label + "=<other>"); }
        }
    }

    /*
     * ManglerSmoke - The naming rules, and the NameTable round-trip that lets a flat instance name
     * be spelled back the way the author wrote it
     */
    void func ManglerSmoke() {
        let Mangler m = new Mangler();

        let List[String] args = new List[String]();
        args.Add("int");
        let String inst = m.GenericInstance("List", args);
        Console.PrintLine("mg.inst=" + inst + " display=" + m.DisplayName(inst));

        let List[String] nested = new List[String]();
        nested.Add(inst);
        nested.Add("String");
        let String outer = m.GenericInstance("Map", nested);
        Console.PrintLine("mg.nested=" + outer + " display=" + m.DisplayName(outer));

        // Stamped vs merely composed
        Console.PrintLine("mg.stampedBefore=" + (m.InstancesOf("List").Length() as String));
        m.RegisterGenericInstance(inst);
        Console.PrintLine("mg.stampedAfter=" + (m.InstancesOf("List").Length() as String));
        match (m.TryGetGenericInstance(inst)) {
            case Some(k) { Console.PrintLine("mg.split=" + GK.Base(k) + "/" + String.Join(GK.Args(k), ",")); }
            case None { Console.PrintLine("mg.split=none"); }
        }

        Console.PrintLine("mg.class=" + m.Class("Point") + " enum=" + m.EnumName("Dir")
                          + " union=" + m.UnionName("Shape") + " retain=" + m.UnionRetain("Shape"));
        Console.PrintLine("mg.local=" + Mangle.Local("int") + "/" + Mangle.Local("count")
                          + " op=" + Mangle.OpSuffix("[]=") + "/" + Mangle.OpSuffix("<<")
                          + " mtn=" + Mangle.MangleTypeName("List[int]*")
                          + " res=" + Mangle.MangleTypeName("  **  "));

        // The scope token comes from the one hash ScopeTree and Mangler share
        let ScopeTree tree = new ScopeTree();
        m.SetScopes(tree);
        let ScopeId k2 = tree.Intern(Sc.Root(), "kernel", Realm.Kernel);
        let String q = tree.Qualify(k2, "Config");
        Console.PrintLine("mg.scoped=" + q + " sanitized=" + m.Sanitize(q)
                          + " display=" + m.DisplayName(q));
    }

    /*
     * MonoSmoke - Stamps a generic class and a generic union, and checks the template is replaced
     * by exactly the instances that were asked for
     */
    void func MonoSmoke() {
        let String src = "class Box[T] { public T v; func _init() { } public T func Get() { return self.v; } }\n" +
                         "union Maybe[V] { Found(V v), Missing }\n" +
                         "int func Use() {\n" +
                         "  let Box[int] a = new Box[int]();\n" +
                         "  let Box[String] b = new Box[String]();\n" +
                         "  let Box[int] c = new Box[int]();\n" +
                         "  let Maybe[int] d = Maybe[int].Missing();\n" +
                         "  return 0;\n" +
                         "}\n" +
                         "realm userspace { entry func Main() { } }\n";
        match (ParseSource(src)) {
            case Err(msg) { Console.PrintLineErr("mono=PARSE-FAILED " + msg); }
            case Ok(prog) {
                let SourceSet set = new SourceSet();
                set.Add("case.g", src);
                let DiagnosticBag bag = new DiagnosticBag(set);
                let Mangler m = new Mangler();
                let Monomorphizer mono = new Monomorphizer(bag, m);
                let List[ProgramFile] files = new List[ProgramFile]();
                files.Add(new ProgramFile("case.g", prog));

                let StringMap[String] stamped = mono.Process(files, null);
                let List[String] keys = stamped.Keys();
                Algorithms.SortBy(keys, StrLess);
                Console.PrintLine("mono.stamped=" + String.Join(keys, ","));
                Console.PrintLine("mono.errors=" + (bag.ErrorCount() as String));

                let StringBuilder sb = new StringBuilder();
                let int i = 0;
                while (i < prog.items.Length()) {
                    if (i > 0) { sb.Put(","); }
                    sb.Put(TopName(prog.items.Get(i)) + ":" + DeclName(prog.items.Get(i)));
                    i = i + 1;
                }
                Console.PrintLine("mono.items=" + sb.ToString());
                Console.PrintLine("mono.display=" + m.DisplayName("Box_int") + "/" + m.DisplayName("Maybe_int"));
            }
        }

        // A bad instantiation is reported, not stamped
        MonoErr("class Box[T] { public T v; func _init() { } }\n" +
                "int func Use() { let Box[int, int] a = new Box[int, int](); return 0; }\n" +
                "realm userspace { entry func Main() { } }\n", "mono.arity");
        MonoErr("class Box[T] { public T v; func _init() { } }\n" +
                "int func Use() { let Box[void] a = new Box[void](); return 0; }\n" +
                "realm userspace { entry func Main() { } }\n", "mono.void");
        MonoErr("class Box[T, T] { public T v; func _init() { } }\n" +
                "realm userspace { entry func Main() { } }\n", "mono.duptp");
    }

    /*
     * MonoErr - Runs the Monomorphizer over a source expected to be rejected
     */
    void func MonoErr(String src, String label) {
        match (ParseSource(src)) {
            case Err(msg) { Console.PrintLineErr(label + "=PARSE-FAILED " + msg); }
            case Ok(prog) {
                let SourceSet set = new SourceSet();
                set.Add("case.g", src);
                let DiagnosticBag bag = new DiagnosticBag(set);
                let Monomorphizer mono = new Monomorphizer(bag, new Mangler());
                let List[ProgramFile] files = new List[ProgramFile]();
                files.Add(new ProgramFile("case.g", prog));
                mono.Process(files, null);
                if (bag.Count() == 0) { Console.PrintLine(label + "=UNEXPECTEDLY-ACCEPTED"); return; }
                let Diagnostic d = bag.All().Get(0);
                Console.PrintLine(label + "=" + Diags.Code(d) + ": " + Diags.Message(d));
            }
        }
    }

    /*
     * Bound - Lexes, parses and binds one source, printing every diagnostic as "CODE: message"
     */
    void func Bound(String label, String src) {
        match (ParseSource(src)) {
            case Err(msg) { Console.PrintLineErr("bind." + label + "=PARSE-FAILED " + msg); }
            case Ok(prog) {
                let SourceSet set = new SourceSet();
                set.Add("case.g", src);
                let DiagnosticBag bag = new DiagnosticBag(set);
                let ScopeBinder binder = new ScopeBinder(bag, new Mangler());
                let List[ProgramFile] files = new List[ProgramFile]();
                files.Add(new ProgramFile("case.g", prog));
                binder.Bind(files, null);

                if (bag.Count() == 0) { Console.PrintLine("bind." + label + "=clean"); return; }
                let int i = 0;
                while (i < bag.Count()) {
                    let Diagnostic d = bag.All().Get(i);
                    Console.PrintLine("bind." + label + "=" + Diags.Code(d) + ": " + Diags.Message(d));
                    i = i + 1;
                }
            }
        }
    }

    /*
     * RenderOne - Renders the first diagnostic of a source with its snippet, proving SourceText's
     * line lookup and DiagnosticBag.Render work end to end
     */
    void func RenderOne(String src) {
        match (ParseSource(src)) {
            case Err(msg) { Console.PrintLineErr("render=PARSE-FAILED"); }
            case Ok(prog) {
                let SourceSet set = new SourceSet();
                set.Add("case.g", src);
                let DiagnosticBag bag = new DiagnosticBag(set);
                let ScopeBinder binder = new ScopeBinder(bag, new Mangler());
                let List[ProgramFile] files = new List[ProgramFile]();
                files.Add(new ProgramFile("case.g", prog));
                binder.Bind(files, null);
                if (bag.Count() == 0) { Console.PrintLine("render=none"); return; }
                Console.PrintLine("render:");
                Console.PrintLine(bag.Render(bag.All().Get(0)));
                Console.PrintLine("render.errors=" + (bag.ErrorCount() as String) +
                                  " warnings=" + (bag.WarningCount() as String) +
                                  " line=" + (bag.LineOf(bag.All().Get(0)) as String));
            }
        }
    }
}

/*
 * ParseSource - Lex then parse one source string, reporting the first failure as "CODE: message"
 */
Result[Program, String] func ParseSource(String source) {
    let Lexer lx = new Lexer(source);
    let List[Token] toks = lx.Tokenize() catch {
        return Result[Program, String].Err(PErr.Code(lx.lastErr) + ": " + PErr.Message(lx.lastErr));
    };
    let Parser ps = new Parser(toks, new Mangler());
    let Program prog = ps.ParseProgram() catch {
        return Result[Program, String].Err(PErr.Code(ps.lastErr) + ": " + PErr.Message(ps.lastErr));
    };
    return Result[Program, String].Ok(prog);
}

/*
 * TopName - The C# subclass name a top-level declaration stands for, for the shape summary
 */
String func TopName(TopLevel t) {
    match (t) {
        case ImportDecl(x)      { return "Import"; }
        case EnvironmentDecl(x) { return "Env"; }
        case NativeBlock(x)     { return "Native"; }
        case ClassDecl(x)       { return x.isModule ? "Module" : "Class"; }
        case ContextDecl(x)     { return "Realm"; }
        case FuncDecl(x)        { return "Func"; }
        case ProcessDecl(x)     { return "Process"; }
        case ProcessVarDecl(x)  { return "ProcVar"; }
        case ExternFuncDecl(x)  { return "Extern"; }
        case NativeTypeDecl(x)  { return "NativeType"; }
        case EnumDecl(x)        { return "Enum"; }
        case UnionDecl(x)       { return "Union"; }
    }
}

/*
 * CheckOne - Lexes and parses one file, printing "OK <items>" or the first diagnostic
 */
void func CheckOne(String path) {
    match (File.Read(path)) {
        case Err(msg) { Console.PrintLine("UNREADABLE"); }
        case Ok(text) {
            match (ParseSource(text)) {
                case Ok(prog) { Console.PrintLine("OK " + (prog.items.Length() as String)); }
                case Err(msg) { Console.PrintLine(msg); }
            }
        }
    }
}

/*
 * DeclName - The written name of a top-level declaration, for the shape summary
 */
String func DeclName(TopLevel t) {
    match (t) {
        case ClassDecl(x)      { return x.name; }
        case UnionDecl(x)      { return x.name; }
        case EnumDecl(x)       { return x.name; }
        case FuncDecl(x)       { return x.name; }
        case ContextDecl(x)    { return NameOfRealm(x.kind); }
        default { return "-"; }
    }
}
