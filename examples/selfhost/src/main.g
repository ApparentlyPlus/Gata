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

realm userspace {
    entry func Main() {
        // `selfhost <file.g>` parses just that file and prints OK or "CODE: message", so the port
        // can be diffed against the C# appa over a corpus. No argument runs the smoke suite.
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
                                let Parser ps = new Parser(toks);
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
}

/*
 * ParseSource - Lex then parse one source string, reporting the first failure as "CODE: message"
 */
Result[Program, String] func ParseSource(String source) {
    let Lexer lx = new Lexer(source);
    let List[Token] toks = lx.Tokenize() catch {
        return Result[Program, String].Err(PErr.Code(lx.lastErr) + ": " + PErr.Message(lx.lastErr));
    };
    let Parser ps = new Parser(toks);
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
