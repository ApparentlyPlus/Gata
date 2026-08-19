/*
 * Ownership.g - ARC insertion, defer ordering, and the throws/Result lowering
 *
 * Ports Appa/src/Lowering/Ownership.cs. The last pass before the emitter, and the one the memory
 * model actually lives in: everything section 21 of the reference promises is decided here and
 * nowhere else. Nothing downstream inserts a retain or a release.
 *
 * Three jobs, interleaved because they share the frame stack:
 *
 *   ARC      every managed local is registered as an OWNER of its frame, and every exit from that
 *            frame - falling off the end, return, break, continue, throw - releases the owners it
 *            accumulated, innermost frame outward. A producer (new, a literal string, a call
 *            returning a managed value) hands back +1; a borrow gets retained on the way into
 *            storage that will outlive the expression.
 *   defer    the action is kept UNLOWERED on its frame and re-lowered at every splice site, so
 *            each occurrence gets its own hoisted temp names. Defers run before the frame's
 *            releases, so a defer can still read a local ARC is about to drop.
 *   throws   a throwing call is bound to a Result temp, its has_error tested, and the failure
 *            path either jumps to the enclosing try's catch label or returns an error Result.
 *
 * PORTING NOTES
 *
 * C# rebuilds with `record with`; the port's IR nodes are mutable classes, so the equivalent is an
 * in-place field write and a return of the same reference. That is the same divergence IrRewriter
 * already makes, and it is safe here for the same reason: nothing holds a second reference to a
 * body while this pass is walking it.
 *
 * `Stack<Frame>` becomes a List used as a stack. C#'s `_frames.ToArray()` enumerates a Stack from
 * the TOP down, which is the innermost-outward order every exit path depends on - so ReleaseForExit
 * below walks the list backwards, and getting that direction wrong would release an outer frame's
 * owners before an inner one's.
 *
 * `List<T>.RemoveRange` has no equivalent in List.g, so the two scratch lists are trimmed with a
 * TruncatePre/TruncateCl pair. Every use is 'drop everything added after this mark', which is what
 * those two do.
 *
 * `IrType.Bool` and friends are static in C#; here they are interned through the IrTypeTable the
 * pipeline threads, so the same shape stays one object. Mangler is an instance for the same reason
 * it is one in TypeResolver.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Optional.g";
import "src/IR/Ir.g";
import "src/IR/ManagedTypes.g";
import "src/Semantics/SymbolTable.g";
import "src/Backend/Mangler.g";

/*
 * One lexical scope of the lowered IR: what it owns, and what it deferred.
 */
class OwnFrame {
    public List[OwnedLocal] owners;
    public List[IrStmt] defers;
    public bool loop;
    public bool tryFrame;

    func _init(bool loop, bool tryFrame) {
        self.owners = new List[OwnedLocal]();
        self.defers = new List[IrStmt]();
        self.loop = loop;
        self.tryFrame = tryFrame;
    }

    public void func AddOwner(String name, IrType type) { self.owners.Add(new OwnedLocal(name, type)); }

    /*
     * AddDefer - Prepended, so defers run LIFO against the others already in this frame
     */
    public void func AddDefer(IrStmt action) { self.defers.Insert(0, action); }
}

/*
 * A (name, type) pair. C# uses a tuple; a union payload or a list element needs a real type here.
 */
class OwnedLocal {
    public String name;
    public IrType type;
    func _init(String name, IrType type) { self.name = name; self.type = type; }
}

/*
 * The frame predicates the exit paths stop on. C# passes lambdas; Gata has function pointers and no
 * closures, so they are three free functions and ReleaseForExit takes one.
 */
bool func FrameIsLoop(OwnFrame f) { return f.loop; }
bool func FrameIsTry(OwnFrame f)  { return f.tryFrame; }
bool func FrameNever(OwnFrame _f) { return false; }

class Ownership {
    IrModule m;
    ManagedTypes managed;
    IrTypeTable t;
    Mangler mangler;

    String retainName;
    String releaseName;

    int seq;

    List[OwnFrame] frames;
    bool nextFrameIsLoop;
    bool inTry;
    String catchLabel;
    bool inThrowsFunc;
    Optional[IrType] resultType;
    IrType returnType;

    // The storage an 'assign' inside the current catch handler writes to, and whether that storage
    // already holds a value a store has to release first. A declaration's target starts null and
    // must not be released.
    Optional[IrExpr] assignTarget;
    bool assignTargetOwns;

    // Inside 'unsafe', ARC steps aside for the whole block: no owning stores, no owner tracking, no
    // consume-retains, no producer hoisting. Exits still release owners from enclosing SAFE frames.
    bool inUnsafe;

    // Side effects to emit before the statement being lowered, and temps to release after it.
    List[IrStmt] pre;
    List[OwnedLocal] cl;

    func _init(IrModule m, IrTypeTable t, Mangler mangler) {
        self.m = m;
        self.managed = new ManagedTypes(m);
        self.t = t;
        self.mangler = mangler;
        self.retainName = Ownership.Role(m, Roles.Retain());
        self.releaseName = Ownership.Role(m, Roles.Release());
        self.seq = 0;
        self.frames = new List[OwnFrame]();
        self.nextFrameIsLoop = false;
        self.inTry = false;
        self.catchLabel = "";
        self.inThrowsFunc = false;
        self.resultType = Optional[IrType].None();
        self.returnType = t.Void();
        self.assignTarget = Optional[IrExpr].None();
        self.assignTargetOwns = false;
        self.inUnsafe = false;
        self.pre = new List[IrStmt]();
        self.cl = new List[OwnedLocal]();
    }

    /*
     * Role - The intrinsic symbol bound to a role, or a 'gata_MISSING_*' placeholder. Silent by
     * design: this pass runs over stdlib-free input too, and a real build has
     * Pipeline.ValidateIntrinsics demand the whole role set before emission.
     */
    public static String func Role(IrModule m, String role) {
        match (m.symbols.IntrinsicOrNull(role)) {
            case Some(n) { return n; }
            case None { return "gata_MISSING_" + role; }
        }
    }

    /*
     * IsManaged - True if the type participates in reference counting: a managed class reference,
     * or a union whose live variant may hold one
     */
    bool func IsManaged(IrType ty) { return self.managed.IsManaged(ty); }

    /*
     * IsProducer - True if the expression hands back a value already at +1
     */
    bool func IsProducer(IrExpr e) {
        match (e) {
            case IrNew(x)          { return true; }
            case IrNewInit(x)      { return true; }
            case IrLitString(x)    { return true; }
            case IrCast(x)         { return self.IsProducer(x.value); }
            case IrStaticCall(x)   { return self.IsManaged(x.type); }
            case IrInstanceCall(x) { return self.IsManaged(x.type); }
            case IrIndirectCall(x) { return self.IsManaged(x.type); }
            case IrTernary(x)      { return self.IsManaged(x.type); }
            default { return false; }
        }
    }

    /*
     * Tmp - A unique temporary name. The '__' prefix is reserved against author-written locals.
     */
    String func Tmp(String prefix) {
        let String n = prefix + Int.ToString(self.seq);
        self.seq = self.seq + 1;
        return n;
    }

    /*
     * TruncatePre / TruncateCl - Drop everything added to a scratch list after a mark. Stands in
     * for C#'s List.RemoveRange, which List.g does not have; every call site in the original is
     * this shape.
     */
    void func TruncatePre(int mark) {
        while (self.pre.Length() > mark) { self.pre.RemoveLast(); }
    }
    void func TruncateCl(int mark) {
        while (self.cl.Length() > mark) { self.cl.RemoveLast(); }
    }

    /*
     * FlushPre - Move the side effects recorded since 'mark' into the output, and forget them
     */
    void func FlushPre(int mark, List[IrStmt] outs) {
        let int i = mark;
        while (i < self.pre.Length()) { outs.Add(self.pre.Get(i)); i = i + 1; }
        self.TruncatePre(mark);
    }

    /*
     * FlushCl - Release the borrowed temps recorded since 'mark', and forget them
     */
    void func FlushCl(int mark, List[IrStmt] outs) {
        let int i = mark;
        while (i < self.cl.Length()) {
            let OwnedLocal o = self.cl.Get(i);
            outs.Add(self.ReleaseStmt(Ownership.VarOf(o)));
            i = i + 1;
        }
        self.TruncateCl(mark);
    }

    /*
     * VarOf - An IrVar expression naming a tracked local
     */
    public static IrExpr func VarOf(OwnedLocal o) {
        return IrExpr.IrVar(new IrVar(o.name, o.type, false));
    }

    /*
     * Var - An IrVar expression by name and type
     */
    IrExpr func Var(String name, IrType ty) { return IrExpr.IrVar(new IrVar(name, ty, false)); }

    // --- Result shapes ----------------------------------------------------------------------
    //
    // The two Result fields the throws lowering reads and writes. Spelled once here so the struct's
    // shape lives in exactly two places: this pass and the emitter's Result typedefs.

    String func ResultValueField()    { return "value"; }
    String func ResultHasErrorField() { return "has_error"; }

    /*
     * ResultValueOf - 'res.value' for a Result-typed temp, typed as the underlying value
     */
    IrExpr func ResultValueOf(String res, IrType rt, IrType inner) {
        return IrExpr.IrFieldLoad(new IrFieldLoad(self.Var(res, rt), self.ResultValueField(), inner));
    }

    /*
     * ResultHasErrorOf - 'res.has_error' for a Result-typed temp
     */
    IrExpr func ResultHasErrorOf(String res, IrType rt) {
        return IrExpr.IrFieldLoad(new IrFieldLoad(self.Var(res, rt), self.ResultHasErrorField(), self.t.Bool()));
    }

    /*
     * ResultInner - The value type inside a Result. Every caller reaches it through a type the
     * resolver already built as a Result, so a non-Result here would be a bug upstream.
     */
    IrType func ResultInner(IrType rt) {
        match (rt) {
            case IrResultType(x) { return x.inner; }
            default { return self.t.Void(); }
        }
    }

    IrType func CurrentResultType() {
        match (self.resultType) { case Some(r) { return r; } case None { return self.t.Void(); } }
    }

    /*
     * ErrorResult - The '(Result_T){ .has_error = true }' literal a failed throws call returns. The
     * value field is deliberately omitted: C zero-initialises it.
     */
    IrExpr func ErrorResult() {
        let List[IrFieldInit] fs = new List[IrFieldInit]();
        fs.Add(new IrFieldInit(self.ResultHasErrorField(),
                               IrExpr.IrLitBool(new IrLitBool(true, self.t.Bool()))));
        return IrExpr.IrStructLit(new IrStructLit(self.CurrentResultType(), fs));
    }

    /*
     * OkResult - The success Result for a throws function's return, with or without a value
     */
    IrExpr func OkResult(Optional[IrExpr] value) {
        let List[IrFieldInit] fs = new List[IrFieldInit]();
        match (value) {
            case Some(v) { fs.Add(new IrFieldInit(self.ResultValueField(), v)); }
            case None { }
        }
        fs.Add(new IrFieldInit(self.ResultHasErrorField(),
                               IrExpr.IrLitBool(new IrLitBool(false, self.t.Bool()))));
        return IrExpr.IrStructLit(new IrStructLit(self.CurrentResultType(), fs));
    }

    /*
     * IfThen - 'if (cond) { body }', the single-armed branch this pass emits everywhere
     */
    IrStmt func IfThen(IrExpr cond, List[IrStmt] body) {
        return IrStmt.IrIf(new IrIf(cond, new IrBlock(body), Optional[IrBlock].None()));
    }

    /*
     * Not - Logical negation of a bool-typed expression
     */
    IrExpr func Not(IrExpr e) {
        return IrExpr.IrUnaryOp(new IrUnaryOp(UnOp.Not, e, self.t.Bool()));
    }

    /*
     * The per-try error flag. One is declared at the top of each try block; nested throwing calls
     * inside that block set it, and the block's tail tests it to reach the catch label.
     */
    String func HasErrorFlag() { return "__has_error"; }
    IrExpr func HasErrorVar() { return self.Var(self.HasErrorFlag(), self.t.Bool()); }

    /*
     * The induction variable both for-in shapes count with. A nested for-in re-declares it in its
     * own C for-scope, which shadows the outer one.
     */
    String func IndexName() { return "__fi"; }
    IrExpr func IndexVar() { return self.Var(self.IndexName(), self.t.Int()); }

    /*
     * CountedFor - 'for (int __fi = 0; __fi < limit; __fi++) body', the loop both for-in shapes
     * iterate with
     */
    IrStmt func CountedFor(IrExpr limit, IrBlock body) {
        let IrStmt init = IrStmt.IrDeclVar(new IrDeclVar(self.IndexName(), self.t.Int(),
            Optional.Some(IrExpr.IrLitInt(new IrLitInt(0, self.t.Int(), Optional[String].None())))));
        let IrExpr cond = IrExpr.IrBinOp(new IrBinOp(BinOp.Lt, self.IndexVar(), limit, self.t.Bool()));
        let IrStmt step = IrStmt.IrExprStmt(new IrExprStmt(
            IrExpr.IrPostfix(new IrPostfix(PostfixOp.Inc, self.IndexVar(), self.t.Int()))));
        return IrStmt.IrFor(new IrFor(Optional.Some(init), Optional.Some(cond), Optional.Some(step), body));
    }

    // --- Entry ------------------------------------------------------------------------------

    /*
     * Run - Lowers every body in the module. In place, unlike C#'s rebuild: the lists and the nodes
     * are the same objects the caller handed in.
     */
    public void func Run() {
        let int c = 0;
        while (c < self.m.classes.Length()) { self.LowerClass(self.m.classes.Get(c)); c = c + 1; }

        let int f = 0;
        while (f < self.m.freeFunctions.Length()) { self.LowerFunction(self.m.freeFunctions.Get(f)); f = f + 1; }

        let int p = 0;
        while (p < self.m.processes.Length()) { self.LowerProcess(self.m.processes.Get(p)); p = p + 1; }
    }

    /*
     * LowerClass - Every method and operator the class declares
     */
    void func LowerClass(IrClass c) {
        let int i = 0;
        while (i < c.methods.Length()) { self.LowerFunction(c.methods.Get(i)); i = i + 1; }
        let int j = 0;
        while (j < c.operators.Length()) { self.LowerOperator(c.operators.Get(j)); j = j + 1; }
    }

    /*
     * LowerProcess - Every thread entry, plus the state initialiser
     */
    void func LowerProcess(IrProcess p) {
        let int i = 0;
        while (i < p.threads.Length()) {
            match (p.threads.Get(i).entryFunc) {
                case Some(en) { self.LowerFunction(en); }
                case None { }
            }
            i = i + 1;
        }
        match (p.stateInit) { case Some(si) { self.LowerFunction(si); } case None { } }
    }

    /*
     * LowerFunction - One body, remembering whether it is a throws function so 'return' and 'throw'
     * know what shape to produce. A throws function that can fall off its end gets a trailing
     * success Result, because the C function has to return something on that path.
     */
    void func LowerFunction(IrFunction f) {
        match (f.body) {
            case None { }
            case Some(b) {
                let bool prevThrows = self.inThrowsFunc;
                let Optional[IrType] prevResult = self.resultType;
                let IrType prevReturn = self.returnType;

                self.returnType = f.returnType;
                if (f.isThrows) {
                    self.inThrowsFunc = true;
                    self.resultType = Optional.Some(self.t.Result(f.returnType));
                }

                let IrBlock lowered = self.LowerBlock(b);
                if (f.isThrows) {
                    let bool endsReturned = lowered.stmts.Length() > 0 &&
                                            Ownership.IsReturn(lowered.stmts.Get(lowered.stmts.Length() - 1));
                    if (!endsReturned) {
                        lowered.stmts.Add(IrStmt.IrReturn(new IrReturn(Optional.Some(self.OkResult(Optional[IrExpr].None())))));
                    }
                }
                f.body = Optional.Some(lowered);

                self.inThrowsFunc = prevThrows;
                self.resultType = prevResult;
                self.returnType = prevReturn;
            }
        }
    }

    /*
     * LowerOperator - An operator body, which is never throws
     */
    void func LowerOperator(IrOperator o) {
        match (o.body) {
            case None { }
            case Some(b) { o.body = Optional.Some(self.LowerBlock(b)); }
        }
    }

    /*
     * IsReturn - Whether a statement is a return, for the fell-off-the-end check
     */
    public static bool func IsReturn(IrStmt s) {
        match (s) { case IrReturn(x) { return true; } default { return false; } }
    }

    /*
     * IsExit - Whether a statement already left the block, so the frame's releases would be dead
     * code after it
     */
    public static bool func IsExit(IrStmt s) {
        match (s) {
            case IrReturn(x)   { return true; }
            case IrBreak(x)    { return true; }
            case IrContinue(x) { return true; }
            default { return false; }
        }
    }

    // --- Blocks and frames -------------------------------------------------------------------

    /*
     * LowerBlock - Push a frame, lower into it, release its owners, pop
     */
    IrBlock func LowerBlock(IrBlock b) {
        let OwnFrame frame = new OwnFrame(self.nextFrameIsLoop, false);
        self.nextFrameIsLoop = false;
        self.frames.Add(frame);

        let List[IrStmt] outs = new List[IrStmt]();
        let int i = 0;
        while (i < b.stmts.Length()) { self.LowerStmt(b.stmts.Get(i), outs); i = i + 1; }

        let bool alreadyExited = outs.Length() > 0 && Ownership.IsExit(outs.Get(outs.Length() - 1));
        if (!alreadyExited) { self.ReleaseFrame(frame, outs); }
        self.frames.RemoveLast();

        let IrBlock lowered = new IrBlock(outs);
        lowered.span = b.span;
        return lowered;
    }

    /*
     * LowerBodyInto - Lower a block's statements into an existing output list, pushing no frame.
     * The caller owns the frame in every case that uses this.
     */
    void func LowerBodyInto(IrBlock b, List[IrStmt] outs) {
        let int i = 0;
        while (i < b.stmts.Length()) { self.LowerStmt(b.stmts.Get(i), outs); i = i + 1; }
    }

    /*
     * ReleaseFrame - Splice this frame's defers in LIFO order, then release its owning locals in
     * reverse declaration order. That order matters: a defer can still read a local ARC is about to
     * drop. Defers are re-lowered at each splice site, so every occurrence gets its own temp names.
     */
    void func ReleaseFrame(OwnFrame f, List[IrStmt] outs) {
        let int d = 0;
        while (d < f.defers.Length()) { self.LowerStmt(f.defers.Get(d), outs); d = d + 1; }

        let int i = f.owners.Length() - 1;
        while (i >= 0) {
            outs.Add(self.ReleaseStmt(Ownership.VarOf(f.owners.Get(i))));
            i = i - 1;
        }
    }

    /*
     * ReleaseForExit - Release frames innermost outward until stopAfter says to stop; used by
     * return, break, continue and throw.
     *
     * C# snapshots the stack first because ReleaseFrame re-lowers defers and a block-bodied one
     * pushes a frame that would invalidate the enumerator. The same hazard exists here, so the
     * frames are copied into a local list before the walk rather than indexed live.
     */
    void func ReleaseForExit(List[IrStmt] outs, func(OwnFrame) -> bool stopAfter) {
        let List[OwnFrame] snapshot = new List[OwnFrame]();
        let int i = self.frames.Length() - 1;
        while (i >= 0) { snapshot.Add(self.frames.Get(i)); i = i - 1; }

        let int j = 0;
        while (j < snapshot.Length()) {
            let OwnFrame f = snapshot.Get(j);
            self.ReleaseFrame(f, outs);
            if (stopAfter(f)) { return; }
            j = j + 1;
        }
    }

    /*
     * RegisterOwner - Record a local as owned by the current frame. Skipped inside unsafe, where
     * lifetimes are the author's.
     */
    void func RegisterOwner(String name, IrType ty) {
        if (self.inUnsafe) { return; }
        if (self.frames.Length() > 0) { self.frames.Get(self.frames.Length() - 1).AddOwner(name, ty); }
    }

    /*
     * ReleaseStmt - A release call. A class goes to the runtime intrinsic, a managed union to its
     * own generated release - both plain static calls, so every exit path gets union support
     * without a union case of its own.
     */
    IrStmt func ReleaseStmt(IrExpr e) {
        let String fn = self.releaseName;
        match (Exprs2.TypeOf(e)) {
            case IrUnionType(ut) { fn = self.mangler.UnionRelease(ut.name); }
            default { }
        }
        let List[IrExpr] args = new List[IrExpr]();
        args.Add(e);
        return IrStmt.IrExprStmt(new IrExprStmt(
            IrExpr.IrStaticCall(new IrStaticCall(fn, self.t.Void(), args))));
    }

    /*
     * Retain - A retain call, returning an expression that owns the value. The generated union
     * retain returns the union by value, so it composes here exactly as the runtime intrinsic does
     * for a pointer.
     */
    IrExpr func Retain(IrExpr e) {
        let IrType ty = Exprs2.TypeOf(e);
        let String fn = self.retainName;
        match (ty) {
            case IrUnionType(ut) { fn = self.mangler.UnionRetain(ut.name); }
            default { }
        }
        let List[IrExpr] args = new List[IrExpr]();
        args.Add(e);
        let IrStaticCall call = new IrStaticCall(fn, ty, args);
        call.span = Exprs2.SpanOf(e);
        return IrExpr.IrStaticCall(call);
    }

    /*
     * LowerDefer - Register the UNLOWERED action with the enclosing frame, for splicing at every
     * exit. Kept unlowered so each splice site re-lowers it fresh with its own temp names.
     */
    void func LowerDefer(IrDefer d) {
        if (self.frames.Length() > 0) { self.frames.Get(self.frames.Length() - 1).AddDefer(d.action); }
    }

    // --- Statements --------------------------------------------------------------------------

    /*
     * LowerStmt - Dispatch one statement into the output list
     */
    void func LowerStmt(IrStmt s, List[IrStmt] outs) {
        match (s) {
            case IrNativeStmt(x) { outs.Add(s); }
            case IrGoto(x)       { outs.Add(s); }
            case IrLabel(x)      { outs.Add(s); }
            case IrDebug(x)      { outs.Add(s); }
            case IrPanic(x)      { outs.Add(s); }
            case IrBlock(b)      { outs.Add(IrStmt.IrBlock(self.LowerBlock(b))); }
            case IrUnsafeBlock(u) {
                let bool prev = self.inUnsafe;
                self.inUnsafe = true;
                outs.Add(IrStmt.IrBlock(self.LowerBlock(u.body)));
                self.inUnsafe = prev;
            }
            case IrThrow(x)       { self.LowerThrow(outs); }
            case IrAssignValue(av){ self.LowerAssignValue(av, outs); }
            case IrDeclVar(dv)    { self.LowerDecl(dv, outs); }
            case IrAssign(a)      { self.LowerAssign(a, outs); }
            case IrExprStmt(es)   { self.LowerExprStmt(es, outs); }
            case IrReturn(r)      { self.LowerReturn(r, outs); }
            case IrBreak(x)       { self.ReleaseForExit(outs, FrameIsLoop); outs.Add(IrStmt.IrBreak(new IrBreak())); }
            case IrContinue(x)    { self.ReleaseForExit(outs, FrameIsLoop); outs.Add(IrStmt.IrContinue(new IrContinue())); }
            case IrIf(i)          { self.LowerIf(i, outs); }
            case IrWhile(w)       { self.LowerWhile(w, outs); }
            case IrFor(fr)        { self.LowerFor(fr, outs); }
            case IrForIn(fi)      { self.LowerForIn(fi, outs); }
            case IrTryCatch(tc)   { self.LowerTryCatch(tc, outs); }
            case IrDefer(d)       { self.LowerDefer(d); }
            // Desugar removed match and switch before this pass ran; anything left is a bug there.
            default { outs.Add(s); }
        }
    }

    /*
     * IsThrowsCall - A bare throwing call, the shape that needs a Result temp bound around it
     */
    bool func IsThrowsCall(IrExpr e) {
        match (e) {
            case IrThrowsCall(x)         { return true; }
            case IrThrowsInstanceCall(x) { return true; }
            default { return false; }
        }
    }

    /*
     * LowerDecl - A local declaration. Four shapes: an inline catch handler, a bare throwing call,
     * no initialiser at all, and the ordinary case.
     */
    void func LowerDecl(IrDeclVar dv, List[IrStmt] outs) {
        let bool managed = self.IsManaged(dv.type);

        match (dv.init) {
            case None {
                // The emitter NULL/{0}-initialises a managed or array local, so the bare
                // declaration is already correct - it just has to be tracked as an owner.
                outs.Add(IrStmt.IrDeclVar(dv));
                if (managed) { self.RegisterOwner(dv.name, dv.type); }
                return;
            }
            case Some(initExpr) {
                match (initExpr) {
                    case IrCatchCall(cc) { self.LowerCatchDecl(dv, cc, managed, outs); return; }
                    default { }
                }

                if (self.IsThrowsCall(initExpr)) {
                    let int preStart = self.pre.Length();
                    let int clStart = self.cl.Length();
                    let IrExpr call = self.FlattenThrows(initExpr);
                    self.FlushPre(preStart, outs);

                    let IrType rt = Exprs2.TypeOf(initExpr);
                    let IrType inner = self.ResultInner(rt);
                    let String res = "__res_" + dv.name;
                    outs.Add(IrStmt.IrDeclVar(new IrDeclVar(res, rt, Optional.Some(call))));
                    self.FlushCl(clStart, outs);

                    self.ThrowsCheck(res, rt, outs);
                    outs.Add(IrStmt.IrDeclVar(new IrDeclVar(dv.name, dv.type,
                        Optional.Some(self.ResultValueOf(res, rt, inner)))));
                    if (managed) { self.RegisterOwner(dv.name, dv.type); }
                    return;
                }

                let int pStart = self.pre.Length();
                let int cStart = self.cl.Length();
                // Exactly one of the two - Flatten records hoists and borrowed temps as a side
                // effect, so calling it twice would emit the initializer's work twice.
                let IrExpr init = managed ? self.Consume(initExpr) : self.Flatten(initExpr, false);
                self.FlushPre(pStart, outs);

                let IrDeclVar decl = new IrDeclVar(dv.name, dv.type, Optional.Some(init));
                decl.span = dv.span;
                outs.Add(IrStmt.IrDeclVar(decl));

                self.FlushCl(cStart, outs);
                if (managed) { self.RegisterOwner(dv.name, dv.type); }
            }
        }
    }

    /*
     * LowerCatchDecl - 'let T x = f() catch { ... };' becomes a bare 'T x;' plus an if/else over the
     * Result, with 'assign v' becoming 'x = v'. x belongs to the ENCLOSING block - which is the
     * whole point of the inline form, since a try block would trap it - and starts null, so the
     * give-up path is safe.
     */
    void func LowerCatchDecl(IrDeclVar dv, IrCatchCall cc, bool managed, List[IrStmt] outs) {
        let int preStart = self.pre.Length();
        let int clStart = self.cl.Length();
        let IrExpr call = self.FlattenThrows(cc.call);
        self.FlushPre(preStart, outs);

        // Declared first, so both arms of the branch below store into the same enclosing local.
        let IrDeclVar decl = new IrDeclVar(dv.name, dv.type, Optional[IrExpr].None());
        decl.span = dv.span;
        outs.Add(IrStmt.IrDeclVar(decl));
        if (managed) { self.RegisterOwner(dv.name, dv.type); }

        self.CatchBranch(cc, self.Var(dv.name, dv.type), "__res_" + dv.name, call, clStart, false, outs);
    }

    /*
     * LowerCatchAssign - The same, onto storage that already exists
     */
    void func LowerCatchAssign(IrAssign a, IrCatchCall cc, List[IrStmt] outs) {
        let int preStart = self.pre.Length();
        let int clStart = self.cl.Length();

        let IrExpr target = self.Flatten(a.target, false);
        let IrExpr call = self.FlattenThrows(cc.call);
        self.FlushPre(preStart, outs);

        let bool owns = self.IsManaged(Exprs2.TypeOf(a.target)) && !self.inUnsafe;
        self.CatchBranch(cc, target, self.Tmp("__res_asg"), call, clStart, owns, outs);
    }

    /*
     * CatchBranch - The branch both catch forms share: bind the Result, then either run the handler
     * or store the value the call produced. Whichever arm stores, it stores into the same target.
     */
    void func CatchBranch(IrCatchCall cc, IrExpr target, String res, IrExpr call,
                          int clStart, bool ownsOldValue, List[IrStmt] outs) {
        let IrType rt = Exprs2.TypeOf(cc.call);
        let IrType inner = self.ResultInner(rt);
        outs.Add(IrStmt.IrDeclVar(new IrDeclVar(res, rt, Optional.Some(call))));
        self.FlushCl(clStart, outs);

        // The handler's own frame
        let Optional[IrExpr] prevTarget = self.assignTarget;
        let bool prevOwns = self.assignTargetOwns;
        self.assignTarget = Optional.Some(target);
        self.assignTargetOwns = ownsOldValue;

        let List[IrStmt] handlerStmts = new List[IrStmt]();
        let OwnFrame handlerFrame = new OwnFrame(false, false);
        self.frames.Add(handlerFrame);
        self.LowerBodyInto(cc.handler, handlerStmts);
        self.ReleaseFrame(handlerFrame, handlerStmts);
        self.frames.RemoveLast();

        self.assignTarget = prevTarget;
        self.assignTargetOwns = prevOwns;

        // Success arm: the call already handed back a +1 value.
        let List[IrStmt] okStmts = new List[IrStmt]();
        self.StoreInto(target, self.ResultValueOf(res, rt, inner),
                       ownsOldValue && self.IsManaged(Exprs2.TypeOf(target)), okStmts);

        outs.Add(IrStmt.IrIf(new IrIf(self.ResultHasErrorOf(res, rt), new IrBlock(handlerStmts),
                                      Optional.Some(new IrBlock(okStmts)))));
    }

    /*
     * LowerCatchExprStmt - 'f() catch { ... };' in statement position, where the result is
     * discarded. No variable, so the resolver already rejected 'assign' here. The success arm still
     * releases the +1 nothing else will own; the failure arm must not, since value was never set.
     */
    void func LowerCatchExprStmt(IrCatchCall cc, List[IrStmt] outs) {
        let int preStart = self.pre.Length();
        let int clStart = self.cl.Length();
        let IrExpr call = self.FlattenThrows(cc.call);
        self.FlushPre(preStart, outs);

        let IrType rt = Exprs2.TypeOf(cc.call);
        let IrType inner = self.ResultInner(rt);
        let String res = self.Tmp("__res_tmp_");
        outs.Add(IrStmt.IrDeclVar(new IrDeclVar(res, rt, Optional.Some(call))));
        self.FlushCl(clStart, outs);

        let List[IrStmt] handlerStmts = new List[IrStmt]();
        let OwnFrame handlerFrame = new OwnFrame(false, false);
        self.frames.Add(handlerFrame);
        self.LowerBodyInto(cc.handler, handlerStmts);
        self.ReleaseFrame(handlerFrame, handlerStmts);
        self.frames.RemoveLast();

        if (self.IsManaged(inner)) {
            let List[IrStmt] okStmts = new List[IrStmt]();
            okStmts.Add(self.ReleaseStmt(self.ResultValueOf(res, rt, inner)));
            outs.Add(IrStmt.IrIf(new IrIf(self.ResultHasErrorOf(res, rt), new IrBlock(handlerStmts),
                                          Optional.Some(new IrBlock(okStmts)))));
            return;
        }
        outs.Add(self.IfThen(self.ResultHasErrorOf(res, rt), handlerStmts));
    }

    /*
     * LowerAssignValue - 'assign v;' stores into the storage its handler belongs to. A managed value
     * is consumed (+1) so the target owns it, matching what the success arm gets from the call.
     */
    void func LowerAssignValue(IrAssignValue av, List[IrStmt] outs) {
        let IrExpr target = self.Var("__no_assign_target", self.t.Void());
        match (self.assignTarget) { case Some(tg) { target = tg; } case None { } }

        let int preStart = self.pre.Length();
        let int clStart = self.cl.Length();

        let bool managed = self.IsManaged(Exprs2.TypeOf(target));
        let IrExpr value = managed ? self.Consume(av.value) : self.Flatten(av.value, false);
        self.FlushPre(preStart, outs);

        self.StoreInto(target, value, managed && self.assignTargetOwns, outs);
        self.FlushCl(clStart, outs);
    }

    /*
     * StoreInto - Store an already-owned (+1) value into a target. When the target already holds a
     * value the old one is released first, THROUGH A TEMP, so that self-assignment does not free
     * the value being stored.
     */
    void func StoreInto(IrExpr target, IrExpr value, bool releaseOld, List[IrStmt] outs) {
        if (!releaseOld) {
            outs.Add(IrStmt.IrAssign(new IrAssign(target, AssignOp.Assign, value)));
            return;
        }
        let IrType ty = Exprs2.TypeOf(target);
        let String tmp = self.Tmp("__cas");
        outs.Add(IrStmt.IrDeclVar(new IrDeclVar(tmp, ty, Optional.Some(value))));
        outs.Add(self.ReleaseStmt(target));
        outs.Add(IrStmt.IrAssign(new IrAssign(target, AssignOp.Assign, self.Var(tmp, ty))));
    }

    /*
     * LowerAssign - An assignment. An owning store to a managed target releases the old value.
     */
    void func LowerAssign(IrAssign a, List[IrStmt] outs) {
        match (a.value) {
            case IrCatchCall(cc) { self.LowerCatchAssign(a, cc, outs); return; }
            default { }
        }
        if (self.IsThrowsCall(a.value)) { self.LowerThrowsAssign(a, outs); return; }

        let int preStart = self.pre.Length();
        let int clStart = self.cl.Length();
        let IrType targetType = Exprs2.TypeOf(a.target);

        if (a.op == AssignOp.Assign && self.IsManaged(targetType) && !self.inUnsafe) {
            // Owning store: release the old value, install the new (+1) one.
            let IrExpr tgt = self.Flatten(a.target, false);
            let IrExpr val = self.Consume(a.value);
            self.FlushPre(preStart, outs);

            let String tmp = self.Tmp("__asg");
            outs.Add(IrStmt.IrDeclVar(new IrDeclVar(tmp, targetType, Optional.Some(val))));
            outs.Add(self.ReleaseStmt(tgt));
            outs.Add(IrStmt.IrAssign(new IrAssign(tgt, AssignOp.Assign, self.Var(tmp, targetType))));

            self.FlushCl(clStart, outs);
            return;
        }

        let IrExpr t2 = self.Flatten(a.target, false);
        let IrExpr v2 = self.Flatten(a.value, false);
        self.FlushPre(preStart, outs);

        let IrAssign asg = new IrAssign(t2, a.op, v2);
        asg.span = a.span;
        outs.Add(IrStmt.IrAssign(asg));
        self.FlushCl(clStart, outs);
    }

    /*
     * LowerThrowsAssign - 'x = f();' where f throws and no handler is attached. The Result is bound,
     * the failure path taken by ThrowsCheck, and only THEN is the value stored - so a propagating
     * failure leaves the target holding whatever it held before.
     */
    void func LowerThrowsAssign(IrAssign a, List[IrStmt] outs) {
        let int preStart = self.pre.Length();
        let int clStart = self.cl.Length();

        let IrExpr target = self.Flatten(a.target, false);
        let IrExpr call = self.FlattenThrows(a.value);
        self.FlushPre(preStart, outs);

        let IrType rt = Exprs2.TypeOf(a.value);
        let IrType inner = self.ResultInner(rt);
        let String res = self.Tmp("__res_asg");
        outs.Add(IrStmt.IrDeclVar(new IrDeclVar(res, rt, Optional.Some(call))));
        self.FlushCl(clStart, outs);

        self.ThrowsCheck(res, rt, outs);
        let bool owns = self.IsManaged(Exprs2.TypeOf(a.target)) && !self.inUnsafe &&
                        self.IsManaged(Exprs2.TypeOf(target));
        self.StoreInto(target, self.ResultValueOf(res, rt, inner), owns, outs);
    }

    /*
     * LowerExprStmt - An expression statement, releasing any hoisted temps and checking for throws
     */
    void func LowerExprStmt(IrExprStmt es, List[IrStmt] outs) {
        match (es.expr) {
            case IrCatchCall(scc) { self.LowerCatchExprStmt(scc, outs); return; }
            default { }
        }

        if (self.IsThrowsCall(es.expr)) {
            let int pStart = self.pre.Length();
            let int cStart = self.cl.Length();
            let IrExpr call = self.FlattenThrows(es.expr);
            self.FlushPre(pStart, outs);

            let IrType ert = Exprs2.TypeOf(es.expr);
            let IrType inner = self.ResultInner(ert);
            let String res = self.Tmp("__res_tmp_");
            outs.Add(IrStmt.IrDeclVar(new IrDeclVar(res, ert, Optional.Some(call))));
            self.FlushCl(cStart, outs);

            self.ThrowsCheck(res, ert, outs);
            if (self.IsManaged(inner)) { outs.Add(self.ReleaseStmt(self.ResultValueOf(res, ert, inner))); }
            return;
        }

        let int p2 = self.pre.Length();
        let int c2 = self.cl.Length();
        let IrExpr e = self.Flatten(es.expr, false);
        self.FlushPre(p2, outs);

        // A hoisted producer is already a temp this pass will release; emitting the statement too
        // would evaluate it twice.
        if (!(self.IsProducer(es.expr) && self.IsManaged(Exprs2.TypeOf(es.expr)))) {
            let IrExprStmt st = new IrExprStmt(e);
            st.span = es.span;
            outs.Add(IrStmt.IrExprStmt(st));
        }
        self.FlushCl(c2, outs);
    }

    /*
     * LowerReturn - Release every frame out to the function boundary, then return. The value is
     * bound to a temp FIRST, so the releases cannot free what is about to be returned.
     */
    void func LowerReturn(IrReturn rs, List[IrStmt] outs) {
        match (rs.value) {
            case None {
                self.ReleaseForExit(outs, FrameNever);
                if (self.inThrowsFunc) {
                    outs.Add(IrStmt.IrReturn(new IrReturn(Optional.Some(self.OkResult(Optional[IrExpr].None())))));
                } else {
                    outs.Add(IrStmt.IrReturn(new IrReturn(Optional[IrExpr].None())));
                }
            }
            case Some(v) {
                let int pStart = self.pre.Length();
                let int cStart = self.cl.Length();
                let IrType vt = Exprs2.TypeOf(v);
                let bool managed = self.IsManaged(vt);
                let IrExpr val = managed ? self.Consume(v) : self.Flatten(v, false);
                self.FlushPre(pStart, outs);

                let IrType retType = vt;
                if (Types.IsVoid(vt)) { retType = self.returnType; }
                let String tmp = self.Tmp("__ret");
                outs.Add(IrStmt.IrDeclVar(new IrDeclVar(tmp, retType, Optional.Some(val))));
                self.FlushCl(cStart, outs);

                self.ReleaseForExit(outs, FrameNever);
                let IrExpr retVar = self.Var(tmp, retType);
                if (self.inThrowsFunc) {
                    outs.Add(IrStmt.IrReturn(new IrReturn(Optional.Some(self.OkResult(Optional.Some(retVar))))));
                } else {
                    outs.Add(IrStmt.IrReturn(new IrReturn(Optional.Some(retVar))));
                }
            }
        }
    }

    /*
     * LowerIf - The condition may itself allocate, in which case it cannot stay inside the 'if'
     * header: the temps would have nowhere to be released. Then the condition is bound first.
     */
    void func LowerIf(IrIf ifs, List[IrStmt] outs) {
        let int pStart = self.pre.Length();
        let int cStart = self.cl.Length();
        let IrExpr cond = self.Flatten(ifs.cond, false);
        let int pCount = self.pre.Length() - pStart;
        let int cCount = self.cl.Length() - cStart;

        if (pCount == 0 && cCount == 0) {
            // 'then' first, then 'else'. C# lowers both as arguments to the IrIf constructor, which
            // it evaluates left to right; the temp counter is a sequence, so doing the else first
            // here would number every temp inside the two arms the other way round.
            let IrBlock thenBlk = self.LowerBlock(ifs.then);
            let Optional[IrBlock] els = Optional[IrBlock].None();
            match (ifs.otherwise) { case Some(e) { els = Optional.Some(self.LowerBlock(e)); } case None { } }
            let IrIf node = new IrIf(cond, thenBlk, els);
            node.span = ifs.span;
            outs.Add(IrStmt.IrIf(node));
            return;
        }

        self.FlushPre(pStart, outs);
        let String cv = self.Tmp("__if");
        outs.Add(IrStmt.IrDeclVar(new IrDeclVar(cv, self.t.Bool(), Optional.Some(cond))));
        self.FlushCl(cStart, outs);

        let IrBlock thenBlk2 = self.LowerBlock(ifs.then);
        let Optional[IrBlock] els2 = Optional[IrBlock].None();
        match (ifs.otherwise) { case Some(e) { els2 = Optional.Some(self.LowerBlock(e)); } case None { } }
        outs.Add(IrStmt.IrIf(new IrIf(self.Var(cv, self.t.Bool()), thenBlk2, els2)));
    }

    /*
     * LowerWhile - Same problem as LowerIf, but the condition is re-evaluated every turn, so the
     * hoisted form becomes 'while (true) { <cond side effects>; if (!c) break; <body> }'.
     */
    void func LowerWhile(IrWhile ws, List[IrStmt] outs) {
        let int pStart = self.pre.Length();
        let int cStart = self.cl.Length();
        let IrExpr cond = self.Flatten(ws.cond, false);
        let int pCount = self.pre.Length() - pStart;
        let int cCount = self.cl.Length() - cStart;

        if (pCount == 0 && cCount == 0) {
            self.nextFrameIsLoop = true;
            let IrWhile node = new IrWhile(cond, self.LowerBlock(ws.body));
            node.span = ws.span;
            outs.Add(IrStmt.IrWhile(node));
            return;
        }

        let List[IrStmt] inner = new List[IrStmt]();
        self.FlushPre(pStart, inner);

        let String cv = self.Tmp("__wh");
        inner.Add(IrStmt.IrDeclVar(new IrDeclVar(cv, self.t.Bool(), Optional.Some(cond))));
        self.FlushCl(cStart, inner);

        let List[IrStmt] brk = new List[IrStmt]();
        brk.Add(IrStmt.IrBreak(new IrBreak()));
        inner.Add(self.IfThen(self.Not(self.Var(cv, self.t.Bool())), brk));

        self.nextFrameIsLoop = true;
        inner.Add(IrStmt.IrBlock(self.LowerBlock(ws.body)));
        outs.Add(IrStmt.IrWhile(new IrWhile(
            IrExpr.IrLitBool(new IrLitBool(true, self.t.Bool())), new IrBlock(inner))));
    }

    /*
     * LowerFor - A C-style for. It stays a real 'for' only when nothing about it needs sequencing:
     * no managed init, no allocating condition, and a step that lowered to a single simple
     * statement. Otherwise the whole thing becomes a block around a 'while (true)', with the step
     * moved to the TOP of the body behind a first-iteration flag so 'continue' still runs it.
     */
    void func LowerFor(IrFor fr, List[IrStmt] outs) {
        let bool initManaged = false;
        match (fr.init) {
            case Some(istmt) {
                match (istmt) {
                    case IrDeclVar(idv) { initManaged = self.IsManaged(idv.type); }
                    default { }
                }
            }
            case None { }
        }

        let int cpStart = self.pre.Length();
        let int ccStart = self.cl.Length();
        let Optional[IrExpr] cond = Optional[IrExpr].None();
        match (fr.cond) { case Some(c) { cond = Optional.Some(self.Flatten(c, false)); } case None { } }
        let int cpCount = self.pre.Length() - cpStart;
        let int ccCount = self.cl.Length() - ccStart;

        let List[IrStmt] stepOut = new List[IrStmt]();
        match (fr.step) { case Some(st) { self.LowerStmt(st, stepOut); } case None { } }
        let bool stepSimple = stepOut.Length() == 0 ||
                              (stepOut.Length() == 1 && Ownership.IsSimpleStep(stepOut.Get(0)));

        if (!initManaged && cpCount == 0 && ccCount == 0 && stepSimple) {
            self.TruncatePre(cpStart);
            self.TruncateCl(ccStart);

            let Optional[IrStmt] init = Optional[IrStmt].None();
            match (fr.init) {
                case Some(istmt) { if (Ownership.IsForInit(istmt)) { init = Optional.Some(istmt); } }
                case None { }
            }
            let Optional[IrStmt] step = Optional[IrStmt].None();
            if (stepOut.Length() == 1) { step = Optional.Some(stepOut.Get(0)); }

            self.nextFrameIsLoop = true;
            let IrFor node = new IrFor(init, cond, step, self.LowerBlock(fr.body));
            node.span = fr.span;
            outs.Add(IrStmt.IrFor(node));
            return;
        }

        let List[IrStmt] outer = new List[IrStmt]();
        let OwnFrame frame = new OwnFrame(false, false);
        self.frames.Add(frame);
        match (fr.init) { case Some(istmt) { self.LowerStmt(istmt, outer); } case None { } }

        let List[IrStmt] loop = new List[IrStmt]();
        if (stepOut.Length() > 0) {
            let String firstFlag = self.Tmp("__first");
            let IrExpr flagVar = self.Var(firstFlag, self.t.Bool());
            outer.Add(IrStmt.IrDeclVar(new IrDeclVar(firstFlag, self.t.Bool(),
                Optional.Some(IrExpr.IrLitBool(new IrLitBool(true, self.t.Bool()))))));
            loop.Add(self.IfThen(self.Not(flagVar), stepOut));
            loop.Add(IrStmt.IrAssign(new IrAssign(flagVar, AssignOp.Assign,
                IrExpr.IrLitBool(new IrLitBool(false, self.t.Bool())))));
        }

        match (fr.cond) {
            case Some(c) {
                let int i = 0;
                while (i < cpCount) { loop.Add(self.pre.Get(cpStart + i)); i = i + 1; }
                let String cv = self.Tmp("__fc");
                match (cond) {
                    case Some(cx) { loop.Add(IrStmt.IrDeclVar(new IrDeclVar(cv, self.t.Bool(), Optional.Some(cx)))); }
                    case None { }
                }
                let int j = 0;
                while (j < ccCount) { loop.Add(self.ReleaseStmt(Ownership.VarOf(self.cl.Get(ccStart + j)))); j = j + 1; }
                let List[IrStmt] brk = new List[IrStmt]();
                brk.Add(IrStmt.IrBreak(new IrBreak()));
                loop.Add(self.IfThen(self.Not(self.Var(cv, self.t.Bool())), brk));
            }
            case None { }
        }

        self.TruncatePre(cpStart);
        self.TruncateCl(ccStart);

        self.nextFrameIsLoop = true;
        loop.Add(IrStmt.IrBlock(self.LowerBlock(fr.body)));
        outer.Add(IrStmt.IrWhile(new IrWhile(
            IrExpr.IrLitBool(new IrLitBool(true, self.t.Bool())), new IrBlock(loop))));
        self.ReleaseFrame(frame, outer);
        self.frames.RemoveLast();
        outs.Add(IrStmt.IrBlock(new IrBlock(outer)));
    }

    /*
     * IsSimpleStep - A lowered step that can stay in a C for-header
     */
    public static bool func IsSimpleStep(IrStmt s) {
        match (s) {
            case IrExprStmt(x) { return true; }
            case IrAssign(x)   { return true; }
            default { return false; }
        }
    }

    /*
     * IsForInit - An init clause a C for-header accepts
     */
    public static bool func IsForInit(IrStmt s) {
        match (s) {
            case IrDeclVar(x)  { return true; }
            case IrAssign(x)   { return true; }
            case IrExprStmt(x) { return true; }
            default { return false; }
        }
    }

    /*
     * LowerForIn - Two shapes. A fixed array counts to a known size and indexes directly; a
     * collection class counts to Length() and reads through Get(). The element is retained when the
     * element type is managed, because the binding outlives the call that produced it.
     */
    void func LowerForIn(IrForIn fi, List[IrStmt] outs) {
        let int pStart = self.pre.Length();
        let int cStart = self.cl.Length();
        let IrType colType = Exprs2.TypeOf(fi.collection);

        if (fi.arraySize >= 0) {
            let IrExpr acol = self.Flatten(fi.collection, false);
            self.FlushPre(pStart, outs);

            let String av = self.Tmp("__arr");
            outs.Add(IrStmt.IrDeclVar(new IrDeclVar(av, colType, Optional.Some(acol))));
            self.FlushCl(cStart, outs);

            let List[IrStmt] body = new List[IrStmt]();
            let OwnFrame frame = new OwnFrame(true, false);
            self.frames.Add(frame);

            let IrExpr elem = IrExpr.IrIndex(new IrIndex(self.Var(av, colType), self.IndexVar(), fi.elemType));
            if (self.IsManaged(fi.elemType)) {
                body.Add(IrStmt.IrDeclVar(new IrDeclVar(fi.varName, fi.elemType, Optional.Some(self.Retain(elem)))));
                self.RegisterOwner(fi.varName, fi.elemType);
            } else {
                body.Add(IrStmt.IrDeclVar(new IrDeclVar(fi.varName, fi.elemType, Optional.Some(elem))));
            }
            self.LowerBodyInto(fi.body, body);
            self.ReleaseFrame(frame, body);
            self.frames.RemoveLast();

            outs.Add(self.CountedFor(
                IrExpr.IrLitInt(new IrLitInt(fi.arraySize as int64, self.t.Int(), Optional[String].None())),
                new IrBlock(body)));
            return;
        }

        let IrExpr col = self.Consume(fi.collection);
        self.FlushPre(pStart, outs);

        let bool colManaged = self.IsManaged(colType);
        let String cv = self.Tmp("__col");
        outs.Add(IrStmt.IrDeclVar(new IrDeclVar(cv, colType, Optional.Some(col))));
        self.FlushCl(cStart, outs);

        let IrExpr colVar = self.Var(cv, colType);
        let List[IrStmt] b2 = new List[IrStmt]();
        let OwnFrame f2 = new OwnFrame(true, false);
        self.frames.Add(f2);

        let List[IrExpr] getArgs = new List[IrExpr]();
        getArgs.Add(colVar);
        getArgs.Add(self.IndexVar());
        b2.Add(IrStmt.IrDeclVar(new IrDeclVar(fi.varName, fi.elemType,
            Optional.Some(IrExpr.IrStaticCall(new IrStaticCall(fi.getCName, fi.elemType, getArgs))))));
        if (self.IsManaged(fi.elemType)) { self.RegisterOwner(fi.varName, fi.elemType); }
        self.LowerBodyInto(fi.body, b2);
        self.ReleaseFrame(f2, b2);
        self.frames.RemoveLast();

        let List[IrExpr] lenArgs = new List[IrExpr]();
        lenArgs.Add(colVar);
        outs.Add(self.CountedFor(
            IrExpr.IrStaticCall(new IrStaticCall(fi.lenCName, self.t.Int(), lenArgs)), new IrBlock(b2)));
        if (colManaged) { outs.Add(self.ReleaseStmt(colVar)); }
    }

    /*
     * LowerTryCatch - There is no C 'try', so this becomes a flag, a label and two gotos. Throwing
     * calls inside the try body set __has_error and jump straight to the catch label; the body's
     * tail tests the flag for the ones that fell through.
     */
    void func LowerTryCatch(IrTryCatch tc, List[IrStmt] outs) {
        let String catchLbl = "__catch_" + Int.ToString(tc.seq);
        let String endLbl = "__end_" + Int.ToString(tc.seq);

        let List[IrStmt] tryStmts = new List[IrStmt]();
        tryStmts.Add(IrStmt.IrDeclVar(new IrDeclVar(self.HasErrorFlag(), self.t.Bool(),
            Optional.Some(IrExpr.IrLitBool(new IrLitBool(false, self.t.Bool()))))));

        let bool prevInTry = self.inTry;
        let String prevLabel = self.catchLabel;
        self.inTry = true;
        self.catchLabel = catchLbl;

        let OwnFrame tryFrame = new OwnFrame(false, true);
        self.frames.Add(tryFrame);
        self.LowerBodyInto(tc.tryBlock, tryStmts);
        self.ReleaseFrame(tryFrame, tryStmts);
        self.frames.RemoveLast();

        self.inTry = prevInTry;
        self.catchLabel = prevLabel;

        let List[IrStmt] jump = new List[IrStmt]();
        jump.Add(IrStmt.IrGoto(new IrGoto(catchLbl)));
        tryStmts.Add(self.IfThen(self.HasErrorVar(), jump));
        outs.Add(IrStmt.IrBlock(new IrBlock(tryStmts)));

        outs.Add(IrStmt.IrGoto(new IrGoto(endLbl)));
        outs.Add(IrStmt.IrLabel(new IrLabel(catchLbl)));

        let List[IrStmt] catchStmts = new List[IrStmt]();
        let OwnFrame catchFrame = new OwnFrame(false, false);
        self.frames.Add(catchFrame);
        self.LowerBodyInto(tc.catchBlock, catchStmts);
        self.ReleaseFrame(catchFrame, catchStmts);
        self.frames.RemoveLast();

        outs.Add(IrStmt.IrBlock(new IrBlock(catchStmts)));
        outs.Add(IrStmt.IrLabel(new IrLabel(endLbl)));
    }

    /*
     * ThrowsCheck - The error branch after a throwing call's Result is bound. Inside a try it routes
     * to the catch label; otherwise it propagates upward as an error Result.
     */
    void func ThrowsCheck(String res, IrType rt, List[IrStmt] outs) {
        let List[IrStmt] branch = new List[IrStmt]();
        if (self.inTry) {
            outs.Add(IrStmt.IrAssign(new IrAssign(self.HasErrorVar(), AssignOp.Assign,
                                                  self.ResultHasErrorOf(res, rt))));
            self.ReleaseForExit(branch, FrameIsTry);
            branch.Add(IrStmt.IrGoto(new IrGoto(self.catchLabel)));
            outs.Add(self.IfThen(self.HasErrorVar(), branch));
            return;
        }
        self.ReleaseForExit(branch, FrameNever);
        branch.Add(IrStmt.IrReturn(new IrReturn(Optional.Some(self.ErrorResult()))));
        outs.Add(self.IfThen(self.ResultHasErrorOf(res, rt), branch));
    }

    /*
     * LowerThrow - Release owners out to the catch or function boundary, then jump to the handler
     */
    void func LowerThrow(List[IrStmt] outs) {
        if (self.inTry) {
            self.ReleaseForExit(outs, FrameIsTry);
            outs.Add(IrStmt.IrGoto(new IrGoto(self.catchLabel)));
            return;
        }
        match (self.resultType) {
            case Some(r) {
                self.ReleaseForExit(outs, FrameNever);
                outs.Add(IrStmt.IrReturn(new IrReturn(Optional.Some(self.ErrorResult()))));
            }
            case None { }
        }
    }

    // --- Expression flattening ---------------------------------------------------------------

    /*
     * Flatten - Reduce an expression to something C can evaluate in one place, hoisting managed
     * producers in BORROW position into temps this pass will release. 'owned' says the caller is
     * taking the +1, so no hoist is needed.
     *
     * The long inline rewrite below is the port's in-place equivalent of C#'s 'with' cascade: each
     * arm flattens the node's children and writes them back into the same node.
     */
    IrExpr func Flatten(IrExpr e, bool owned) {
        match (e) {
            case IrNewInit(ni) {
                let IrExpr v = self.LowerNewInit(ni);
                if (!owned) { self.cl.Add(new OwnedLocal(Ownership.NameOfVar(v), Exprs2.TypeOf(v))); }
                return v;
            }
            case IrTernary(tern) { return self.FlattenTernary(tern, owned); }
            default { }
        }

        match (e) {
            case IrStaticCall(sc)   { sc.args = self.FlattenArgs(sc.args); }
            case IrInstanceCall(ic) { ic.recv = self.Flatten(ic.recv, false); ic.args = self.FlattenArgs(ic.args); }
            case IrThrowsCall(tc)   { tc.args = self.FlattenArgs(tc.args); }
            case IrThrowsInstanceCall(ti) { ti.recv = self.Flatten(ti.recv, false); ti.args = self.FlattenArgs(ti.args); }
            case IrNew(n)           { n.args = self.FlattenArgs(n.args); }
            case IrCast(c)          { c.value = self.Flatten(c.value, true); }
            case IrFieldLoad(fl)    { fl.obj = self.Flatten(fl.obj, false); }
            case IrIndex(ix)        { ix.obj = self.Flatten(ix.obj, false); ix.idx = self.Flatten(ix.idx, false); }
            case IrBinOp(b)         { b.left = self.Flatten(b.left, false); b.right = self.Flatten(b.right, false); }
            case IrUnaryOp(u)       { u.operand = self.Flatten(u.operand, false); }
            case IrPostfix(pf)      { pf.operand = self.Flatten(pf.operand, false); }
            case IrAddrOf(a)        { a.target = self.Flatten(a.target, false); }
            case IrDeref(d)         { d.ptr = self.Flatten(d.ptr, false); }
            case IrIndirectCall(ic2){ ic2.target = self.Flatten(ic2.target, false); ic2.args = self.FlattenArgs(ic2.args); }
            case IrUnionConstruct(uc) { uc.args = self.FlattenArgs(uc.args); }
            case IrUnionField(uf)   { uf.target = self.Flatten(uf.target, false); }
            // literals, IrVar, IrSelfExpr, IrArrayLit, IrFuncRef have nothing to flatten
            default { }
        }

        if (self.IsProducer(e)) {
            if (owned || self.inUnsafe) { return e; }
            return self.Hoist(e, Exprs2.TypeOf(e));
        }
        return e;
    }

    /*
     * NameOfVar - The name inside an IrVar. Only ever called on one this pass just built.
     */
    public static String func NameOfVar(IrExpr e) {
        match (e) { case IrVar(v) { return v.name; } default { return ""; } }
    }

    /*
     * FlattenArgs - Every argument in borrow position
     */
    List[IrExpr] func FlattenArgs(List[IrExpr] args) {
        let List[IrExpr] result = new List[IrExpr]();
        let int i = 0;
        while (i < args.Length()) { result.Add(self.Flatten(args.Get(i), false)); i = i + 1; }
        return result;
    }

    /*
     * FlattenTernary - A ternary evaluates ONE arm, so an arm's hoists must never spill into the
     * unconditional pre list - they would run whichever way the branch went. Arms with nothing to
     * sequence stay inline as a real C conditional; otherwise both arms materialise into a temp
     * through an if/else, owned at +1 and released by the caller's frame.
     */
    IrExpr func FlattenTernary(IrTernary t, bool owned) {
        let IrExpr cond = self.Flatten(t.cond, false);
        let bool managed = self.IsManaged(t.type) && !self.inUnsafe;

        let int thenPreStart = self.pre.Length();
        let int thenClStart = self.cl.Length();
        let IrExpr tv = managed ? self.Consume(t.then) : self.Flatten(t.then, owned);
        let int thenPreCount = self.pre.Length() - thenPreStart;
        let int thenClCount = self.cl.Length() - thenClStart;

        let int elsePreStart = self.pre.Length();
        let int elseClStart = self.cl.Length();
        let IrExpr ev = managed ? self.Consume(t.otherwise) : self.Flatten(t.otherwise, owned);
        let int elsePreCount = self.pre.Length() - elsePreStart;
        let int elseClCount = self.cl.Length() - elseClStart;

        // Fast path: nothing to sequence, so it stays a pure C conditional expression.
        if (!managed && thenPreCount == 0 && thenClCount == 0 && elsePreCount == 0 && elseClCount == 0) {
            self.TruncatePre(thenPreStart);
            self.TruncateCl(thenClStart);
            t.cond = cond;
            t.then = tv;
            t.otherwise = ev;
            return IrExpr.IrTernary(t);
        }

        let String tmp = self.Tmp("__tern");
        let IrExpr tgt = self.Var(tmp, t.type);
        self.pre.Insert(thenPreStart, IrStmt.IrDeclVar(new IrDeclVar(tmp, t.type, Optional[IrExpr].None())));
        let int thenPre = thenPreStart + 1;
        let int elsePre = elsePreStart + 1;

        let List[IrStmt] thenStmts = new List[IrStmt]();
        let int i = 0;
        while (i < thenPreCount) { thenStmts.Add(self.pre.Get(thenPre + i)); i = i + 1; }
        thenStmts.Add(IrStmt.IrAssign(new IrAssign(tgt, AssignOp.Assign, tv)));
        let int j = 0;
        while (j < thenClCount) { thenStmts.Add(self.ReleaseStmt(Ownership.VarOf(self.cl.Get(thenClStart + j)))); j = j + 1; }

        let List[IrStmt] elseStmts = new List[IrStmt]();
        let int k = 0;
        while (k < elsePreCount) { elseStmts.Add(self.pre.Get(elsePre + k)); k = k + 1; }
        elseStmts.Add(IrStmt.IrAssign(new IrAssign(tgt, AssignOp.Assign, ev)));
        let int l = 0;
        while (l < elseClCount) { elseStmts.Add(self.ReleaseStmt(Ownership.VarOf(self.cl.Get(elseClStart + l)))); l = l + 1; }

        self.TruncatePre(thenPre);
        self.TruncateCl(thenClStart);

        self.pre.Add(IrStmt.IrIf(new IrIf(cond, new IrBlock(thenStmts),
                                          Optional.Some(new IrBlock(elseStmts)))));

        // Borrowed: the caller's statement is what releases it.
        if (managed && !owned) { self.cl.Add(new OwnedLocal(tmp, t.type)); }
        return tgt;
    }

    /*
     * Consume - Flatten in OWNED position: a producer already hands back +1, anything else is a
     * borrow that has to be retained before storage takes it.
     */
    IrExpr func Consume(IrExpr e) {
        let IrExpr s = self.Flatten(e, true);
        if (self.IsManaged(Exprs2.TypeOf(e)) && !self.IsProducer(e) && !self.inUnsafe) {
            return self.Retain(s);
        }
        return s;
    }

    /*
     * Hoist - Bind a producer to a temp so the statement can reference it twice and release it once
     */
    IrExpr func Hoist(IrExpr inline, IrType ty) {
        let String tmp = self.Tmp("__a");
        self.pre.Add(IrStmt.IrDeclVar(new IrDeclVar(tmp, ty, Optional.Some(inline))));
        self.cl.Add(new OwnedLocal(tmp, ty));
        return self.Var(tmp, ty);
    }

    /*
     * FlattenThrows - A throwing call becomes an ORDINARY call returning the Result struct. Every
     * caller binds what comes back to a temp, so nothing here hoists.
     */
    IrExpr func FlattenThrows(IrExpr e) {
        match (e) {
            case IrThrowsCall(tc) {
                let IrStaticCall call = new IrStaticCall(tc.cName, tc.type, self.FlattenArgs(tc.args));
                call.span = tc.span;
                return IrExpr.IrStaticCall(call);
            }
            case IrThrowsInstanceCall(ti) {
                let IrInstanceCall call = new IrInstanceCall(self.Flatten(ti.recv, false), ti.cName,
                                                             ti.type, self.FlattenArgs(ti.args));
                call.span = ti.span;
                return IrExpr.IrInstanceCall(call);
            }
            default { return e; }
        }
    }

    /*
     * LowerNewInit - A collection initialiser becomes an allocation followed by one Add call per
     * element. Returns the collection temp, which is a +1 producer like any other 'new'.
     */
    IrExpr func LowerNewInit(IrNewInit ni) {
        let String v = self.Tmp("__ci");
        let IrType ct = self.t.ClassRef(ni.className);
        let int acStart = self.cl.Length();
        let List[IrExpr] args = self.FlattenArgs(ni.args);
        let int acCount = self.cl.Length() - acStart;

        self.pre.Add(IrStmt.IrDeclVar(new IrDeclVar(v, ct,
            Optional.Some(IrExpr.IrNew(new IrNew(ni.className, args, ct))))));

        let int i = 0;
        while (i < acCount) { self.pre.Add(self.ReleaseStmt(Ownership.VarOf(self.cl.Get(acStart + i)))); i = i + 1; }
        self.TruncateCl(acStart);

        let int e = 0;
        while (e < ni.inits.Length()) {
            let IrExpr el = ni.inits.Get(e);
            let IrType elType = Exprs2.TypeOf(el);
            let int ecStart = self.cl.Length();
            let IrExpr es = self.Flatten(el, true);
            let int ecCount = self.cl.Length() - ecStart;

            if (self.IsProducer(el) && self.IsManaged(elType)) {
                // The element arrives at +1 and Add takes its own reference, so this scope has to
                // give its one back - through a temp, since the call needs to name it.
                let String e2 = self.Tmp("__e");
                self.pre.Add(IrStmt.IrDeclVar(new IrDeclVar(e2, elType, Optional.Some(es))));
                let List[IrExpr] addArgs = new List[IrExpr]();
                addArgs.Add(self.Var(v, ct));
                addArgs.Add(self.Var(e2, elType));
                self.pre.Add(IrStmt.IrExprStmt(new IrExprStmt(
                    IrExpr.IrStaticCall(new IrStaticCall(ni.addCName, self.t.Void(), addArgs)))));
                self.pre.Add(self.ReleaseStmt(self.Var(e2, elType)));
            } else {
                let List[IrExpr] addArgs = new List[IrExpr]();
                addArgs.Add(self.Var(v, ct));
                addArgs.Add(es);
                self.pre.Add(IrStmt.IrExprStmt(new IrExprStmt(
                    IrExpr.IrStaticCall(new IrStaticCall(ni.addCName, self.t.Void(), addArgs)))));
            }

            let int c = 0;
            while (c < ecCount) { self.pre.Add(self.ReleaseStmt(Ownership.VarOf(self.cl.Get(ecStart + c)))); c = c + 1; }
            self.TruncateCl(ecStart);
            e = e + 1;
        }
        return self.Var(v, ct);
    }
}
