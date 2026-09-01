/*
 * IrRewriter.g - the one IR rewrite, written once and reused by every lowering pass
 *
 * Ports Appa/src/Lowering/IrRewriter.cs.
 *
 * The rewriting counterpart to IrWalker: same generic-plus-hook shape, because Gata has neither
 * inheritance nor closures, and the same reasoning applies. A pass supplies its state and up to
 * two hooks, each returning the node to put in place of the one it was handed.
 *
 *   func(IrRewrite[S], IrStmt) -> IrStmt   return s unchanged to keep it
 *
 * ONE DIFFERENCE FROM C#, AND IT IS DELIBERATE. C#'s IR nodes are records, so its rewriter is
 * copy-on-write: every Update* builds a replacement with `with`, and returns the original when
 * nothing changed, which is what makes `Run` able to hand back the very same module. Here the IR
 * nodes are ordinary mutable classes, so the structural recursion assigns each rewritten child
 * back into its parent instead. That is shorter, it cannot lose a node's span the way rebuilding
 * one by hand can, and identity preservation becomes automatic rather than something forty
 * ReferenceEquals checks have to maintain.
 *
 * What it costs: a pass can no longer read the original tree after rewriting part of it. No pass
 * does - Desugar and Densifier both rewrite bottom-up and never look back - and a pass that needed
 * to would have to copy first, which is worth being explicit about rather than getting for free.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Optional.g";
import "src/IR/Ir.g";
import "src/Lowering/NodeCoverage.g";

class IrRewrite[S] {
    public S state;
    public func(IrRewrite[S], IrStmt) -> IrStmt onStmt;
    public func(IrRewrite[S], IrExpr) -> IrExpr onExpr;

    func _init(S state, func(IrRewrite[S], IrStmt) -> IrStmt onStmt,
               func(IrRewrite[S], IrExpr) -> IrExpr onExpr) {
        self.state = state;
        self.onStmt = onStmt;
        self.onExpr = onExpr;
    }

    /*
     * Run - Rewrites every body in a module: class methods and operators, field initialisers, free
     * functions, and each process's threads and state initialiser
     */
    public void func Run(IrModule m) {
        let int i = 0;
        while (i < m.classes.Length()) { self.RewriteClass(m.classes.Get(i)); i = i + 1; }
        let int j = 0;
        while (j < m.freeFunctions.Length()) {
            self.RewriteFunction(m.freeFunctions.Get(j));
            j = j + 1;
        }
        let int k = 0;
        while (k < m.processes.Length()) { self.RewriteProcess(m.processes.Get(k)); k = k + 1; }
    }

    /*
     * RewriteClass - Every field initialiser, method and operator of a class
     */
    public void func RewriteClass(IrClass c) {
        let int i = 0;
        while (i < c.classFields.Length()) {
            let IrField f = c.classFields.Get(i);
            match (f.init) { case Some(e) { f.init = Optional.Some(self.Expr(e)); } case None { } }
            i = i + 1;
        }

        // fieldInits holds the same expressions again, keyed by name, for the allocator to emit
        let List[String] keys = c.fieldInits.Keys();
        let int k = 0;
        while (k < keys.Length()) {
            match (c.fieldInits.Find(keys.Get(k))) {
                case Some(e) { c.fieldInits.Put(keys.Get(k), self.Expr(e)); }
                case None { }
            }
            k = k + 1;
        }

        let int j = 0;
        while (j < c.methods.Length()) { self.RewriteFunction(c.methods.Get(j)); j = j + 1; }
        let int o = 0;
        while (o < c.operators.Length()) { self.RewriteOperator(c.operators.Get(o)); o = o + 1; }
    }

    /*
     * RewriteFunction - A function's body, if it has one. A native body is raw C and is left alone.
     */
    public void func RewriteFunction(IrFunction f) {
        match (f.body) { case Some(b) { f.body = Optional.Some(self.Block(b)); } case None { } }
    }

    /*
     * RewriteOperator - The same, for an operator overload
     */
    public void func RewriteOperator(IrOperator o) {
        match (o.body) { case Some(b) { o.body = Optional.Some(self.Block(b)); } case None { } }
    }

    /*
     * RewriteProcess - Each thread's entry function, and the generated state initialiser
     */
    public void func RewriteProcess(IrProcess p) {
        let int i = 0;
        while (i < p.threads.Length()) {
            match (p.threads.Get(i).entryFunc) {
                case Some(f) { self.RewriteFunction(f); }
                case None { }
            }
            i = i + 1;
        }
        match (p.stateInit) { case Some(f) { self.RewriteFunction(f); } case None { } }
    }

    /*
     * Block - A block, which is always a block again: the hook may replace the statements inside
     * it, but a body has to stay a body
     */
    public IrBlock func Block(IrBlock b) {
        match (self.Stmt(IrStmt.IrBlock(b))) {
            case IrBlock(nb) { return nb; }
            // A hook that replaced a whole block with something else gets it wrapped back up,
            // which keeps every caller's "a body is a block" assumption true
            default { }
        }
        let List[IrStmt] one = new List[IrStmt]();
        one.Add(self.Stmt(IrStmt.IrBlock(b)));
        let IrBlock wrapped = new IrBlock(one);
        wrapped.span = b.span;
        return wrapped;
    }

    /*
     * Stmt - Rewrites a statement's children, then offers the result to the hook.
     *
     * Children first, so a hook always sees an already-lowered subtree - which is what lets
     * Desugar lower a match inside a switch arm without running twice.
     */
    public IrStmt func Stmt(IrStmt s) {
        self.MapStmtChildren(s);
        if (self.onStmt == null) { return s; }
        return self.onStmt(self, s);
    }

    /*
     * MapStmtChildren - Rewrites each child of a statement in place
     */
    public void func MapStmtChildren(IrStmt s) {
        match (s) {
            case IrBlock(b) {
                let int i = 0;
                while (i < b.stmts.Length()) {
                    b.stmts.Set(i, self.Stmt(b.stmts.Get(i)));
                    i = i + 1;
                }
            }
            case IrUnsafeBlock(u) { u.body = self.Block(u.body); }
            case IrDeclVar(d) {
                match (d.init) { case Some(e) { d.init = Optional.Some(self.Expr(e)); } case None { } }
            }
            case IrAssign(a) {
                a.target = self.Expr(a.target);
                a.value = self.Expr(a.value);
            }
            case IrExprStmt(e) { e.expr = self.Expr(e.expr); }
            case IrReturn(r) {
                match (r.value) { case Some(v) { r.value = Optional.Some(self.Expr(v)); } case None { } }
            }
            case IrIf(i) {
                i.cond = self.Expr(i.cond);
                i.then = self.Block(i.then);
                match (i.otherwise) {
                    case Some(e) { i.otherwise = Optional.Some(self.Block(e)); }
                    case None { }
                }
            }
            case IrWhile(w) {
                w.cond = self.Expr(w.cond);
                w.body = self.Block(w.body);
            }
            case IrFor(f) {
                match (f.init) { case Some(x) { f.init = Optional.Some(self.Stmt(x)); } case None { } }
                match (f.cond) { case Some(c) { f.cond = Optional.Some(self.Expr(c)); } case None { } }
                match (f.step) { case Some(x) { f.step = Optional.Some(self.Stmt(x)); } case None { } }
                f.body = self.Block(f.body);
            }
            case IrForIn(fi) {
                fi.collection = self.Expr(fi.collection);
                fi.body = self.Block(fi.body);
            }
            case IrTryCatch(t) {
                t.tryBlock = self.Block(t.tryBlock);
                t.catchBlock = self.Block(t.catchBlock);
            }
            case IrSwitch(sw) {
                sw.scrutinee = self.Expr(sw.scrutinee);
                let int i = 0;
                while (i < sw.cases.Length()) {
                    let IrSwitchCase c = sw.cases.Get(i);
                    let int j = 0;
                    while (j < c.labels.Length()) {
                        c.labels.Set(j, self.Expr(c.labels.Get(j)));
                        j = j + 1;
                    }
                    c.body = self.Block(c.body);
                    i = i + 1;
                }
                match (sw.otherwise) {
                    case Some(d) { sw.otherwise = Optional.Some(self.Block(d)); }
                    case None { }
                }
            }
            case IrMatch(ms) {
                ms.scrutinee = self.Expr(ms.scrutinee);
                let int i = 0;
                while (i < ms.cases.Length()) {
                    let IrMatchCase c = ms.cases.Get(i);
                    c.body = self.Block(c.body);
                    i = i + 1;
                }
                match (ms.otherwise) {
                    case Some(d) { ms.otherwise = Optional.Some(self.Block(d)); }
                    case None { }
                }
            }
            case IrDefer(d2)       { d2.action = self.Stmt(d2.action); }
            case IrAssignValue(av) { av.value = self.Expr(av.value); }
            // Everything else is in NodeCoverage's inert set and has no children
            default { }
        }
    }

    /*
     * Expr - Rewrites an expression's children, then offers the result to the hook
     */
    public IrExpr func Expr(IrExpr e) {
        self.MapExprChildren(e);
        if (self.onExpr == null) { return e; }
        return self.onExpr(self, e);
    }

    /*
     * MapExprChildren - Rewrites each child of an expression in place
     */
    public void func MapExprChildren(IrExpr e) {
        match (e) {
            case IrFieldLoad(fl) { fl.obj = self.Expr(fl.obj); }
            case IrIndex(ix) {
                ix.obj = self.Expr(ix.obj);
                ix.idx = self.Expr(ix.idx);
            }
            case IrStaticCall(sc) { self.MapArgs(sc.args); }
            case IrInstanceCall(ic) {
                ic.recv = self.Expr(ic.recv);
                self.MapArgs(ic.args);
            }
            case IrThrowsCall(tc) { self.MapArgs(tc.args); }
            case IrThrowsInstanceCall(ti) {
                ti.recv = self.Expr(ti.recv);
                self.MapArgs(ti.args);
            }
            case IrCatchCall(cc) {
                cc.call = self.Expr(cc.call);
                cc.handler = self.Block(cc.handler);
            }
            case IrStructLit(sl) {
                let int i = 0;
                while (i < sl.structFields.Length()) {
                    let IrFieldInit fi = sl.structFields.Get(i);
                    fi.value = self.Expr(fi.value);
                    i = i + 1;
                }
            }
            case IrNew(n) { self.MapArgs(n.args); }
            case IrNewInit(ni) {
                self.MapArgs(ni.args);
                self.MapArgs(ni.inits);
            }
            case IrCast(c) { c.value = self.Expr(c.value); }
            case IrBinOp(b) {
                b.left = self.Expr(b.left);
                b.right = self.Expr(b.right);
            }
            case IrTernary(t) {
                t.cond = self.Expr(t.cond);
                t.then = self.Expr(t.then);
                t.otherwise = self.Expr(t.otherwise);
            }
            case IrUnaryOp(u)  { u.operand = self.Expr(u.operand); }
            case IrPostfix(p)  { p.operand = self.Expr(p.operand); }
            case IrArrayLit(al) { self.MapArgs(al.elems); }
            case IrInterp(ip)  { self.MapArgs(ip.parts); }
            case IrAddrOf(a2)  { a2.target = self.Expr(a2.target); }
            case IrDeref(d3)   { d3.ptr = self.Expr(d3.ptr); }
            case IrIndirectCall(ic2) {
                ic2.target = self.Expr(ic2.target);
                self.MapArgs(ic2.args);
            }
            case IrUnionConstruct(uc) { self.MapArgs(uc.args); }
            case IrUnionField(uf)     { uf.target = self.Expr(uf.target); }
            // Everything else is in NodeCoverage's inert set and has no children
            default { }
        }
    }

    /*
     * MapArgs - Rewrites every expression in a list, in place
     */
    public void func MapArgs(List[IrExpr] args) {
        let int i = 0;
        while (i < args.Length()) {
            args.Set(i, self.Expr(args.Get(i)));
            i = i + 1;
        }
    }
}
