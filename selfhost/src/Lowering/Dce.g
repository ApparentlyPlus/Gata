/*
 * Dce.g - dead code elimination
 *
 * Ports Appa/src/Lowering/Dce.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "src/Syntax/Ast.g";
import "src/IR/Ir.g";
import "src/Semantics/SymbolTable.g";
import "src/Lowering/IrWalker.g";

class Dce {
    IrModule m;

    // The unit each callable C name belongs to. A method's unit is its CLASS, not itself.
    StringMap[String] unitOf;
    StringMap[IrClass] classes;
    StringMap[IrFunction] funcs;

    StringSet live;
    List[String] work;

    // Fixed-array and function-pointer types live code still names, by mangled name
    StringSet liveComposites;

    func _init(IrModule m) {
        self.m = m;
        self.unitOf = new StringMap[String]();
        self.classes = new StringMap[IrClass]();
        self.funcs = new StringMap[IrFunction]();
        self.live = new StringSet();
        self.work = new List[String]();
        self.liveComposites = new StringSet();
    }

    /*
     * UnitKey - A unit token. C# uses a (name, isFunction) record; one string with a kind prefix
     * says the same thing and can key a StringSet directly.
     */
    String func UnitKey(String name, bool isFunction) {
        return (isFunction ? "f:" : "c:") + name;
    }

    /*
     * Root - Marks a unit live and queues it for scanning, once
     */
    public void func Root(String unit) {
        if (self.live.AddNew(unit)) { self.work.Add(unit); }
    }

    /*
     * Ref - Marks live whatever unit owns a called C name
     */
    public void func Ref(String cname) {
        match (self.unitOf.Find(cname)) {
            case Some(u) { self.Root(u); }
            case None { }
        }
    }

    /*
     * Run - Eliminates what nothing reaches, rewriting the module's lists in place
     */
    public void func Run() {
        // The walker holds this Dce as its state, so a field here would be a reference cycle
        // (WARNING G101): neither object's count would ever reach zero. It is a local threaded
        // through the Mark chain instead, which keeps ownership running one way and lets the whole
        // walker go when Run returns.
        let IrWalk[Dce] walker = new IrWalk[Dce](self, DceStmt, DceExpr);

        // Index every callable name against the unit that owns it
        let int c = 0;
        while (c < self.m.classes.Length()) {
            let IrClass cls = self.m.classes.Get(c);
            self.classes.Put(cls.name, cls);
            let String classKey = self.UnitKey(cls.name, false);
            let int i = 0;
            while (i < cls.methods.Length()) {
                self.unitOf.Put(cls.methods.Get(i).cName, classKey);
                i = i + 1;
            }
            let int o = 0;
            while (o < cls.operators.Length()) {
                self.unitOf.Put(cls.operators.Get(o).cName, classKey);
                o = o + 1;
            }
            c = c + 1;
        }
        let int f = 0;
        while (f < self.m.freeFunctions.Length()) {
            let IrFunction fn = self.m.freeFunctions.Get(f);
            self.unitOf.Put(fn.cName, self.UnitKey(fn.cName, true));
            self.funcs.Put(fn.cName, fn);
            f = f + 1;
        }

        // --- the roots ------------------------------------------------------------------------
        let int e = 0;
        while (e < self.m.freeFunctions.Length()) {
            let IrFunction fn = self.m.freeFunctions.Get(e);
            if (fn.isEntry) { self.Root(self.UnitKey(fn.cName, true)); }
            e = e + 1;
        }

        let int p = 0;
        while (p < self.m.processes.Length()) {
            let IrProcess proc = self.m.processes.Get(p);
            match (proc.stateInit) { case Some(si) { self.MarkFunc(walker, si); } case None { } }
            let int v = 0;
            while (v < proc.state.Length()) { self.MarkType(proc.state.Get(v).type); v = v + 1; }
            let int t = 0;
            while (t < proc.threads.Length()) {
                match (proc.threads.Get(t).entryFunc) {
                    case Some(en) { self.MarkFunc(walker, en); }
                    case None { }
                }
                t = t + 1;
            }
            p = p + 1;
        }

        // The ARC intrinsics are called by generated code, which this walk never sees
        self.RefRole(Roles.Alloc());
        self.RefRole(Roles.Retain());
        self.RefRole(Roles.Release());
        self.RefRole(Roles.ObjInit());

        // A union is emitted whole and never pruned, so every payload type is live. Without this
        // the payload struct still names, say, an Arr_int_4 whose typedef was dropped for having
        // no reference from live code.
        let int u = 0;
        while (u < self.m.unions.Length()) {
            let IrUnion un = self.m.unions.Get(u);
            let int vi = 0;
            while (vi < un.variants.Length()) {
                let List[IrParam] payload = un.variants.Get(vi).variantFields;
                let int fi = 0;
                while (fi < payload.Length()) { self.MarkType(payload.Get(fi).type); fi = fi + 1; }
                vi = vi + 1;
            }
            u = u + 1;
        }

        // '@keep' is the escape hatch for a symbol only native text references
        let int kc = 0;
        while (kc < self.m.classes.Length()) {
            if (self.m.classes.Get(kc).keep) {
                self.Root(self.UnitKey(self.m.classes.Get(kc).name, false));
            }
            kc = kc + 1;
        }
        let int kf = 0;
        while (kf < self.m.freeFunctions.Length()) {
            let IrFunction fn = self.m.freeFunctions.Get(kf);
            if (HasKeepAnnotation(fn.annotations)) { self.Root(self.UnitKey(fn.cName, true)); }
            kf = kf + 1;
        }

        // --- the walk -------------------------------------------------------------------------
        while (self.work.Length() > 0) {
            let String unit = self.work.Get(0);
            self.work.RemoveAt(0);
            self.ScanUnit(walker, unit);
        }

        // --- the prune ------------------------------------------------------------------------
        self.PruneClasses();
        self.PruneFunctions();
        self.PruneComposites(self.m.arrayTypes);
        self.PruneComposites(self.m.funcPtrTypes);
    }

    /*
     * RefRole - Marks live whatever a role is bound to, when anything bound it
     */
    void func RefRole(String role) {
        match (self.m.symbols.IntrinsicOrNull(role)) {
            case Some(cn) { self.Ref(cn); }
            case None { }
        }
    }

    /*
     * PruneClasses - Drops every class nothing reached
     */
    void func PruneClasses() {
        let List[IrClass] kept = new List[IrClass]();
        let int i = 0;
        while (i < self.m.classes.Length()) {
            let IrClass c = self.m.classes.Get(i);
            if (self.live.Has(self.UnitKey(c.name, false))) { kept.Add(c); }
            i = i + 1;
        }
        self.m.classes.Clear();
        let int j = 0;
        while (j < kept.Length()) { self.m.classes.Add(kept.Get(j)); j = j + 1; }
    }

    /*
     * PruneFunctions - Drops every free function nothing reached. An entry point survives
     * regardless: it is what the runtime calls into.
     */
    void func PruneFunctions() {
        let List[IrFunction] kept = new List[IrFunction]();
        let int i = 0;
        while (i < self.m.freeFunctions.Length()) {
            let IrFunction f = self.m.freeFunctions.Get(i);
            if (f.isEntry || self.live.Has(self.UnitKey(f.cName, true))) { kept.Add(f); }
            i = i + 1;
        }
        self.m.freeFunctions.Clear();
        let int j = 0;
        while (j < kept.Length()) { self.m.freeFunctions.Add(kept.Get(j)); j = j + 1; }
    }

    /*
     * PruneComposites - Drops every array or function-pointer type live code no longer names
     */
    void func PruneComposites(List[IrType] types) {
        let List[IrType] kept = new List[IrType]();
        let int i = 0;
        while (i < types.Length()) {
            if (self.liveComposites.Has(Types.MangledName(types.Get(i)))) { kept.Add(types.Get(i)); }
            i = i + 1;
        }
        types.Clear();
        let int j = 0;
        while (j < kept.Length()) { types.Add(kept.Get(j)); j = j + 1; }
    }

    /*
     * ScanUnit - Marks everything one live unit reaches
     */
    void func ScanUnit(IrWalk[Dce] walker, String unit) {
        let String name = unit.Substring(2, unit.Length() - 2);
        if (unit.StartsWith("f:")) {
            match (self.funcs.Find(name)) { case Some(f) { self.MarkFunc(walker, f); } case None { } }
            return;
        }
        match (self.classes.Find(name)) { case Some(c) { self.MarkClass(walker, c); } case None { } }
    }

    /*
     * MarkClass - A class keeps its field types, its field initialisers, and every method and
     * operator it declares
     */
    void func MarkClass(IrWalk[Dce] walker, IrClass c) {
        let int i = 0;
        while (i < c.classFields.Length()) { self.MarkType(c.classFields.Get(i).type); i = i + 1; }

        let List[String] keys = c.fieldInits.Keys();
        let int k = 0;
        while (k < keys.Length()) {
            match (c.fieldInits.Find(keys.Get(k))) {
                case Some(e) { walker.WalkExpr(e); }
                case None { }
            }
            k = k + 1;
        }

        let int j = 0;
        while (j < c.methods.Length()) { self.MarkFunc(walker, c.methods.Get(j)); j = j + 1; }
        let int o = 0;
        while (o < c.operators.Length()) { self.MarkOperator(walker, c.operators.Get(o)); o = o + 1; }
    }

    /*
     * MarkFunc - A function's signature types and its body
     */
    public void func MarkFunc(IrWalk[Dce] walker, IrFunction f) {
        self.MarkType(f.returnType);
        let int i = 0;
        while (i < f.params.Length()) { self.MarkType(f.params.Get(i).type); i = i + 1; }
        match (f.body) { case Some(b) { walker.WalkStmt(IrStmt.IrBlock(b)); } case None { } }
    }

    /*
     * MarkOperator - The same, for an operator overload
     */
    void func MarkOperator(IrWalk[Dce] walker, IrOperator o) {
        self.MarkType(o.returnType);
        let int i = 0;
        while (i < o.params.Length()) { self.MarkType(o.params.Get(i).type); i = i + 1; }
        match (o.body) { case Some(b) { walker.WalkStmt(IrStmt.IrBlock(b)); } case None { } }
    }

    /*
     * MarkType - Roots every unit a type reference depends on, and records the composite types
     * that need a typedef emitted
     */
    public void func MarkType(IrType ty) {
        match (ty) {
            case IrClassRef(cr) { self.Root(self.UnitKey(cr.className, false)); }
            case IrPtrType(p)   { self.MarkType(p.inner); }
            case IrArrayType(a) {
                self.liveComposites.AddNew(Types.MangledName(ty));
                self.MarkType(a.elem);
            }
            case IrResultType(r) { self.MarkType(r.inner); }
            case IrFuncPtrType(fp) {
                self.liveComposites.AddNew(Types.MangledName(ty));
                self.MarkType(fp.ret);
                let int i = 0;
                while (i < fp.params.Length()) { self.MarkType(fp.params.Get(i)); i = i + 1; }
            }
            default { }
        }
    }

    /*
     * RootClass - Marks a class live by name
     */
    public void func RootClass(String name) { self.Root(self.UnitKey(name, false)); }
}

/*
 * HasKeepAnnotation - True when a declaration carries '@keep'
 */
bool func HasKeepAnnotation(List[Annotation] anns) {
    let int i = 0;
    while (i < anns.Length()) {
        match (anns.Get(i)) { case KeepAnnotation(k) { return true; } default { } }
        i = i + 1;
    }
    return false;
}

/*
 * DceStmt - The statements that name a type or call something the expression tree does not show
 */
bool func DceStmt(IrWalk[Dce] w, IrStmt s) {
    match (s) {
        case IrDeclVar(d) { w.state.MarkType(d.type); }
        case IrForIn(fi) {
            // The Length and Get calls a for-in compiles to appear nowhere in the tree
            w.state.Ref(fi.lenCName);
            w.state.Ref(fi.getCName);
            w.state.MarkType(fi.elemType);
        }
        default { }
    }
    return true;
}

/*
 * DceExpr - The expressions that reach a unit or name a composite type
 */
bool func DceExpr(IrWalk[Dce] w, IrExpr e) {
    match (e) {
        case IrStaticCall(sc)         { w.state.Ref(sc.cName); }
        case IrInstanceCall(ic)       { w.state.Ref(ic.cName); }
        case IrThrowsCall(tc)         { w.state.Ref(tc.cName); }
        case IrThrowsInstanceCall(ti) { w.state.Ref(ti.cName); }
        case IrNew(n)                 { w.state.RootClass(n.className); }
        case IrNewInit(ni) {
            w.state.RootClass(ni.className);
            w.state.Ref(ni.addCName);
        }
        case IrCast(c)      { w.state.MarkType(c.to); }
        case IrArrayLit(al) { w.state.MarkType(al.arrType); }
        case IrSizeof(so)   { w.state.MarkType(so.of); }
        case IrDefault(df)  { w.state.MarkType(df.of); }
        // A function used only as a value must still be kept, or a callback registration hands
        // out a pointer to a symbol that was dropped
        case IrFuncRef(fr)  { w.state.Ref(fr.cName); }
        default { }
    }
    return true;
}
