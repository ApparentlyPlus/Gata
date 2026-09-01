/*
 * IrWalker.g - the one IR traversal, written once and reused by every analysis
 *
 * Ports Appa/src/Lowering/IrWalker.cs.
 *
 * C# spells this as an abstract class whose WalkStmt/WalkExpr are virtual, and every analysis is a
 * subclass overriding the cases it cares about. Gata has neither inheritance nor virtual dispatch,
 * so the same factoring is expressed the other way round: the traversal is a generic class, and an
 * analysis supplies two function pointers plus the state they work on.
 *
 *   class Walk[S]                   S is the analysis's own state class
 *   func(IrWalk[S], IrStmt) -> bool a hook, returning whether to recurse into that node
 *
 * A hook may be null, which means "recurse, look at nothing" - what an analysis that only cares
 * about one of the two node kinds passes for the other. A generic no-op function cannot serve
 * here: taking its address would need explicit type arguments, which a call site cannot write.
 *
 * A hook that returns true is C#'s "do something, then call base". A hook that returns false is
 * "intercept, and do not descend" - and because the hook is handed the walker, it can also descend
 * selectively by calling WalkStmt/WalkExpr on whichever children it chooses, which is what an
 * override that recurses in a custom order does in C#.
 *
 * Gata has no closures, so the state cannot be captured; it is reached through the walker as
 * w.state. That is the only real difference in how an analysis is written.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Optional.g";
import "src/IR/Ir.g";

class IrWalk[S] {
    public S state;
    public func(IrWalk[S], IrStmt) -> bool onStmt;
    public func(IrWalk[S], IrExpr) -> bool onExpr;

    func _init(S state, func(IrWalk[S], IrStmt) -> bool onStmt,
               func(IrWalk[S], IrExpr) -> bool onExpr) {
        self.state = state;
        self.onStmt = onStmt;
        self.onExpr = onExpr;
    }

    /*
     * WalkStmt - Offers a statement to the hook, then descends into its children unless the hook
     * declined. The inert nodes - native statements, goto, label, break, continue, throw, debug,
     * panic - have no children and fall through.
     */
    public void func WalkStmt(IrStmt s) {
        if (self.onStmt != null && !self.onStmt(self, s)) { return; }
        self.WalkStmtChildren(s);
    }

    /*
     * WalkStmtChildren - The children of a statement, without re-offering the node itself. A hook
     * that wants "look at this, then recurse normally" after doing its own work calls this.
     */
    public void func WalkStmtChildren(IrStmt s) {
        match (s) {
            case IrBlock(b) {
                let int i = 0;
                while (i < b.stmts.Length()) { self.WalkStmt(b.stmts.Get(i)); i = i + 1; }
            }
            case IrUnsafeBlock(u) { self.WalkStmt(IrStmt.IrBlock(u.body)); }
            case IrDeclVar(d)     { self.WalkOptExpr(d.init); }
            case IrAssign(a)      { self.WalkExpr(a.target); self.WalkExpr(a.value); }
            case IrExprStmt(e)    { self.WalkExpr(e.expr); }
            case IrReturn(r)      { self.WalkOptExpr(r.value); }
            case IrIf(i) {
                self.WalkExpr(i.cond);
                self.WalkStmt(IrStmt.IrBlock(i.then));
                self.WalkOptBlock(i.otherwise);
            }
            case IrWhile(w) { self.WalkExpr(w.cond); self.WalkStmt(IrStmt.IrBlock(w.body)); }
            case IrFor(f) {
                self.WalkOptStmt(f.init);
                self.WalkOptExpr(f.cond);
                self.WalkOptStmt(f.step);
                self.WalkStmt(IrStmt.IrBlock(f.body));
            }
            case IrForIn(fi) {
                self.WalkExpr(fi.collection);
                self.WalkStmt(IrStmt.IrBlock(fi.body));
            }
            case IrTryCatch(t) {
                self.WalkStmt(IrStmt.IrBlock(t.tryBlock));
                self.WalkStmt(IrStmt.IrBlock(t.catchBlock));
            }
            case IrSwitch(sw) {
                self.WalkExpr(sw.scrutinee);
                let int i = 0;
                while (i < sw.cases.Length()) {
                    let IrSwitchCase c = sw.cases.Get(i);
                    let int j = 0;
                    while (j < c.labels.Length()) { self.WalkExpr(c.labels.Get(j)); j = j + 1; }
                    self.WalkStmt(IrStmt.IrBlock(c.body));
                    i = i + 1;
                }
                self.WalkOptBlock(sw.otherwise);
            }
            case IrMatch(ms) {
                self.WalkExpr(ms.scrutinee);
                let int i = 0;
                while (i < ms.cases.Length()) {
                    self.WalkStmt(IrStmt.IrBlock(ms.cases.Get(i).body));
                    i = i + 1;
                }
                self.WalkOptBlock(ms.otherwise);
            }
            case IrDefer(d2)      { self.WalkStmt(d2.action); }
            case IrAssignValue(av) { self.WalkExpr(av.value); }
            default { }
        }
    }

    /*
     * WalkExpr - Offers an expression to the hook, then descends into its children unless the hook
     * declined. The leaves - literals, variables, enum constants, sizeof, default, func refs -
     * have no children and fall through.
     */
    public void func WalkExpr(IrExpr e) {
        if (self.onExpr != null && !self.onExpr(self, e)) { return; }
        self.WalkExprChildren(e);
    }

    /*
     * WalkExprChildren - The children of an expression, without re-offering the node itself
     */
    public void func WalkExprChildren(IrExpr e) {
        match (e) {
            case IrFieldLoad(fl) { self.WalkExpr(fl.obj); }
            case IrIndex(ix)     { self.WalkExpr(ix.obj); self.WalkExpr(ix.idx); }
            case IrStaticCall(sc) { self.WalkArgs(sc.args); }
            case IrInstanceCall(ic) { self.WalkExpr(ic.recv); self.WalkArgs(ic.args); }
            case IrThrowsCall(tc) { self.WalkArgs(tc.args); }
            case IrThrowsInstanceCall(ti) { self.WalkExpr(ti.recv); self.WalkArgs(ti.args); }
            case IrCatchCall(cc) {
                self.WalkExpr(cc.call);
                self.WalkStmt(IrStmt.IrBlock(cc.handler));
            }
            case IrStructLit(sl) {
                let int i = 0;
                while (i < sl.structFields.Length()) {
                    self.WalkExpr(sl.structFields.Get(i).value);
                    i = i + 1;
                }
            }
            case IrNew(n) { self.WalkArgs(n.args); }
            case IrNewInit(ni) { self.WalkArgs(ni.args); self.WalkArgs(ni.inits); }
            case IrCast(c) { self.WalkExpr(c.value); }
            case IrBinOp(b) { self.WalkExpr(b.left); self.WalkExpr(b.right); }
            case IrTernary(t) {
                self.WalkExpr(t.cond);
                self.WalkExpr(t.then);
                self.WalkExpr(t.otherwise);
            }
            case IrUnaryOp(u) { self.WalkExpr(u.operand); }
            case IrPostfix(p) { self.WalkExpr(p.operand); }
            case IrArrayLit(al) { self.WalkArgs(al.elems); }
            case IrInterp(ip) { self.WalkArgs(ip.parts); }
            case IrAddrOf(a2) { self.WalkExpr(a2.target); }
            case IrDeref(d3) { self.WalkExpr(d3.ptr); }
            case IrIndirectCall(ic2) { self.WalkExpr(ic2.target); self.WalkArgs(ic2.args); }
            case IrUnionConstruct(uc) { self.WalkArgs(uc.args); }
            case IrUnionField(uf) { self.WalkExpr(uf.target); }
            default { }
        }
    }

    /*
     * WalkArgs - Every expression in a list
     */
    public void func WalkArgs(List[IrExpr] args) {
        let int i = 0;
        while (i < args.Length()) { self.WalkExpr(args.Get(i)); i = i + 1; }
    }

    /*
     * WalkOptExpr - An expression that may be absent
     */
    public void func WalkOptExpr(Optional[IrExpr] e) {
        match (e) { case Some(x) { self.WalkExpr(x); } case None { } }
    }

    /*
     * WalkOptStmt - A statement that may be absent
     */
    public void func WalkOptStmt(Optional[IrStmt] s) {
        match (s) { case Some(x) { self.WalkStmt(x); } case None { } }
    }

    /*
     * WalkOptBlock - A block that may be absent
     */
    public void func WalkOptBlock(Optional[IrBlock] b) {
        match (b) { case Some(x) { self.WalkStmt(IrStmt.IrBlock(x)); } case None { } }
    }
}
