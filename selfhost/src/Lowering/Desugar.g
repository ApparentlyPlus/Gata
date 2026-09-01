/*
 * Desugar.g - the three constructs the backend never sees
 *
 * Ports Appa/src/Lowering/Desugar.cs.
 *
 * Switch, match and string interpolation all lower here, into shapes the emitter already knows how
 * to write. Everything downstream - ownership, dead-code elimination, the emitter itself - is
 * spared three node kinds it would otherwise have to reason about.
 *
 *   switch      -> a scrutinee temp, then an if/else-if chain of equality tests
 *   match       -> the same, discriminating on the union's __tag field, with payload bindings
 *   $"a{b}c"    -> one '+' for two parts, a StringBuilder for three or more
 *
 * All three run bottom-up, so a match nested in a switch arm is already lowered by the time the
 * arm itself is.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Int.g";
import "src/Diagnostics/Diagnostic.g";
import "src/Diagnostics/TextSpan.g";
import "src/Syntax/Ast.g";
import "src/IR/Ir.g";
import "src/Semantics/SymbolTable.g";
import "src/Lowering/IrRewriter.g";
import "src/Backend/Mangler.g";

class Desugar {
    SymbolTable sym;
    DiagnosticBag diag;
    Mangler mangler;
    IrTypeTable t;
    int seq;

    func _init(SymbolTable sym, DiagnosticBag diag, Mangler mangler, IrTypeTable t) {
        self.sym = sym;
        self.diag = diag;
        self.mangler = mangler;
        self.t = t;
        self.seq = 0;
    }

    /*
     * Run - Lowers every body in the module
     */
    public void func Run(IrModule m) {
        let IrRewrite[Desugar] r = new IrRewrite[Desugar](self, DesugarStmt, DesugarExpr);
        r.Run(m);
    }

    /*
     * Fresh - A unique temporary name. The '__' prefix is reserved against author-written locals,
     * so a scrutinee temp can never collide with one.
     */
    String func Fresh(String prefix) {
        let String n = prefix + Int.ToString(self.seq);
        self.seq = self.seq + 1;
        return n;
    }

    /*
     * AsBlock - A statement as a block, without wrapping one that already is
     */
    IrBlock func AsBlock(IrStmt s) {
        match (s) { case IrBlock(b) { return b; } default { } }
        let List[IrStmt] one = new List[IrStmt]();
        one.Add(s);
        return new IrBlock(one);
    }

    /*
     * LowerMatch - A match becomes a scrutinee temp plus a tag-comparison if/else-if chain.
     *
     * The temp matters: the scrutinee is evaluated ONCE, however many arms test it, and every
     * payload binding reads out of that one value.
     */
    public IrStmt func LowerMatch(IrMatch ms) {
        let List[IrStmt] stmts = new List[IrStmt]();
        let IrType st = Exprs2.TypeOf(ms.scrutinee);
        let String v = self.Fresh("__mt");
        let IrExpr vr = IrExpr.IrVar(new IrVar(v, st, false));
        stmts.Add(IrStmt.IrDeclVar(new IrDeclVar(v, st, Optional.Some(ms.scrutinee))));

        // An exhaustive defaultless match needs no test on its LAST arm: nothing else can be the
        // tag by then, and testing it would leave a fall-through path the emitter cannot reach
        let bool closeLastArm = IsNone(ms.otherwise) && self.IsExhaustive(ms);

        let Optional[IrStmt] chain = Optional[IrStmt].None();
        match (ms.otherwise) { case Some(d) { chain = Optional.Some(IrStmt.IrBlock(d)); } case None { } }

        let int i = ms.cases.Length() - 1;
        while (i >= 0) {
            let IrMatchCase c = ms.cases.Get(i);

            // The arm's own bindings come first, reading each payload field out of the temp
            let List[IrStmt] bodyStmts = new List[IrStmt]();
            let int b = 0;
            while (b < c.binds.Length()) {
                let IrMatchBind bd = c.binds.Get(b);
                bodyStmts.Add(IrStmt.IrDeclVar(new IrDeclVar(bd.bindName, bd.type,
                    Optional.Some(IrExpr.IrUnionField(
                        new IrUnionField(vr, c.variantIndex, bd.fieldName, bd.type))))));
                b = b + 1;
            }
            let int k = 0;
            while (k < c.body.stmts.Length()) { bodyStmts.Add(c.body.stmts.Get(k)); k = k + 1; }

            if (closeLastArm && i == ms.cases.Length() - 1) {
                chain = Optional.Some(IrStmt.IrBlock(new IrBlock(bodyStmts)));
                i = i - 1;
                continue;
            }

            let IrExpr tag = IrExpr.IrFieldLoad(new IrFieldLoad(vr, "__tag", self.t.Int()));
            let IrExpr want = IrExpr.IrLitInt(
                new IrLitInt(c.variantIndex as int64, self.t.Int(), Optional[String].None()));
            let IrExpr cond = IrExpr.IrBinOp(new IrBinOp(BinOp.Eq, tag, want, self.t.Bool()));

            let Optional[IrBlock] elseBlk = Optional[IrBlock].None();
            match (chain) { case Some(x) { elseBlk = Optional.Some(self.AsBlock(x)); } case None { } }
            chain = Optional.Some(IrStmt.IrIf(new IrIf(cond, new IrBlock(bodyStmts), elseBlk)));
            i = i - 1;
        }

        match (chain) { case Some(x) { stmts.Add(x); } case None { } }
        let IrBlock out = new IrBlock(stmts);
        out.span = ms.span;
        return IrStmt.IrBlock(out);
    }

    /*
     * IsExhaustive - True when a match names every variant of its union exactly once.
     *
     * Always true for a defaultless match in a clean build - G039 saw to that - but re-derived
     * here because this pass also runs over IR from a source that failed to resolve, where the
     * arms may cover nothing at all.
     */
    bool func IsExhaustive(IrMatch ms) {
        let String uname = "";
        match (ms.unionT) { case IrUnionType(u) { uname = u.name; } default { return false; } }

        match (self.sym.UnionDef(uname)) {
            case None { return false; }
            case Some(variants) {
                if (ms.cases.Length() != variants.Length()) { return false; }
                let StringSet seen = new StringSet();
                let int i = 0;
                while (i < ms.cases.Length()) {
                    let int idx = ms.cases.Get(i).variantIndex;
                    if (idx < 0 || idx >= variants.Length()) { return false; }
                    if (!seen.AddNew(Int.ToString(idx))) { return false; }
                    i = i + 1;
                }
                return true;
            }
        }
    }

    /*
     * LowerSwitch - A switch becomes a scrutinee temp plus an equality if/else-if chain.
     *
     * There is no fallthrough to model, and break/continue inside an arm already target the
     * enclosing loop, so the chain is a faithful rendering rather than an approximation.
     */
    public IrStmt func LowerSwitch(IrSwitch sw) {
        let List[IrStmt] stmts = new List[IrStmt]();
        let IrType st = Exprs2.TypeOf(sw.scrutinee);
        let String v = self.Fresh("__sw");
        let IrExpr vr = IrExpr.IrVar(new IrVar(v, st, false));
        stmts.Add(IrStmt.IrDeclVar(new IrDeclVar(v, st, Optional.Some(sw.scrutinee))));

        let Optional[IrStmt] chain = Optional[IrStmt].None();
        match (sw.otherwise) { case Some(d) { chain = Optional.Some(IrStmt.IrBlock(d)); } case None { } }

        let int i = sw.cases.Length() - 1;
        while (i >= 0) {
            let IrSwitchCase c = sw.cases.Get(i);

            // Several labels on one arm fold into a chain of '||'
            let IrExpr cond = IrExpr.IrBinOp(
                new IrBinOp(BinOp.Eq, vr, c.labels.Get(0), self.t.Bool()));
            let int j = 1;
            while (j < c.labels.Length()) {
                let IrExpr next = IrExpr.IrBinOp(
                    new IrBinOp(BinOp.Eq, vr, c.labels.Get(j), self.t.Bool()));
                cond = IrExpr.IrBinOp(new IrBinOp(BinOp.Or, cond, next, self.t.Bool()));
                j = j + 1;
            }

            let Optional[IrBlock] elseBlk = Optional[IrBlock].None();
            match (chain) { case Some(x) { elseBlk = Optional.Some(self.AsBlock(x)); } case None { } }
            chain = Optional.Some(IrStmt.IrIf(new IrIf(cond, c.body, elseBlk)));
            i = i - 1;
        }

        match (chain) { case Some(x) { stmts.Add(x); } case None { } }
        let IrBlock out = new IrBlock(stmts);
        out.span = sw.span;
        return IrStmt.IrBlock(out);
    }

    /*
     * LowerInterp - An interpolated string becomes concatenation.
     *
     * One part passes through; two fold into a single '+'; three or more go through ONE
     * StringBuilder rather than a chain of '+' that would copy the whole accumulated string at
     * every fold. The builder comes from @builtin(StringBuilder), with '+' as the fallback when
     * the build has no builder bound.
     */
    public IrExpr func LowerInterp(IrInterp ip) {
        if (ip.parts.Length() == 0) {
            let IrLitString empty = new IrLitString("\"\"", self.t.Str());
            empty.span = ip.span;
            return IrExpr.IrLitString(empty);
        }

        if (ip.parts.Length() >= 3) {
            match (self.BuilderParts()) {
                case Some(bp) { return self.BuildThroughBuilder(ip, bp); }
                case None { }
            }
        }

        let IrExpr acc = ip.parts.Get(0);
        let String concat = self.Concat(ip.span);
        let int i = 1;
        while (i < ip.parts.Length()) {
            let List[IrExpr] args = new List[IrExpr]();
            args.Add(acc);
            args.Add(ip.parts.Get(i));
            let IrStaticCall call = new IrStaticCall(concat, self.t.Str(), args);
            call.span = ip.span;
            acc = IrExpr.IrStaticCall(call);
            i = i + 1;
        }
        return acc;
    }

    /*
     * BuilderParts - The StringBuilder class and its Put/ToString methods, when the build binds
     * all three
     */
    Optional[InterpBuilder] func BuilderParts() {
        match (self.sym.builtins.Find(BuiltinTypes.StringBuilder())) {
            case None { return Optional[InterpBuilder].None(); }
            case Some(sbClass) {
                match (self.sym.LookupMethod(sbClass, "Put")) {
                    case None { return Optional[InterpBuilder].None(); }
                    case Some(put) {
                        match (self.sym.LookupMethod(sbClass, "ToString")) {
                            case None { return Optional[InterpBuilder].None(); }
                            case Some(toStr) {
                                return Optional.Some(
                                    new InterpBuilder(sbClass, put.cName, toStr.cName));
                            }
                        }
                    }
                }
            }
        }
    }

    /*
     * BuildThroughBuilder - 'new StringBuilder().Put(a).Put(b).Put(c).ToString()'. Put returns the
     * builder, so the calls chain and only one object is ever allocated.
     */
    IrExpr func BuildThroughBuilder(IrInterp ip, InterpBuilder bp) {
        let IrType cls = self.t.ClassRef(bp.className);
        let IrNew mk = new IrNew(bp.className, new List[IrExpr](), cls);
        mk.span = ip.span;
        let IrExpr sb = IrExpr.IrNew(mk);

        let int i = 0;
        while (i < ip.parts.Length()) {
            let IrInstanceCall put = new IrInstanceCall(sb, bp.putCName, cls,
                                                        self.OneArg(ip.parts.Get(i)));
            put.span = ip.span;
            sb = IrExpr.IrInstanceCall(put);
            i = i + 1;
        }

        let IrInstanceCall fin = new IrInstanceCall(sb, bp.toStringCName, self.t.Str(),
                                                    new List[IrExpr]());
        fin.span = ip.span;
        return IrExpr.IrInstanceCall(fin);
    }

    /*
     * OneArg - A single-element argument list
     */
    List[IrExpr] func OneArg(IrExpr e) {
        let List[IrExpr] a = new List[IrExpr]();
        a.Add(e);
        return a;
    }

    /*
     * Concat - The C name of String's '+' operator, or a diagnostic naming what the build is
     * missing. The file is '<runtime>' because this lowering is the compiler's own, not the
     * author's - there is no source line to point at.
     */
    String func Concat(TextSpan span) {
        let String stringClass = BuiltinTypes.Str();
        match (self.sym.builtins.Find(BuiltinTypes.Str())) {
            case Some(c) { stringClass = c; }
            case None { }
        }
        match (self.sym.LookupOperator(stringClass, "+")) {
            case Some(op) { return op.cName; }
            case None {
                self.diag.Error(Codes.MissingIntrinsic(), "<runtime>", span,
                    "String defines no '+' operator for concatenation");
                return "gata_MISSING_String_concat";
            }
        }
    }
}

/*
 * The three names interpolation needs from the StringBuilder builtin, looked up once
 */
class InterpBuilder {
    public String className;
    public String putCName;
    public String toStringCName;
    func _init(String className, String putCName, String toStringCName) {
        self.className = className;
        self.putCName = putCName;
        self.toStringCName = toStringCName;
    }
}

/*
 * DesugarStmt - Lowers a switch or a match, after its children are already lowered
 */
IrStmt func DesugarStmt(IrRewrite[Desugar] r, IrStmt s) {
    match (s) {
        case IrSwitch(sw) { return r.state.LowerSwitch(sw); }
        case IrMatch(ms)  { return r.state.LowerMatch(ms); }
        default { return s; }
    }
}

/*
 * DesugarExpr - Lowers an interpolated string, after its parts are already lowered
 */
IrExpr func DesugarExpr(IrRewrite[Desugar] r, IrExpr e) {
    match (e) {
        case IrInterp(ip) { return r.state.LowerInterp(ip); }
        default { return e; }
    }
}
