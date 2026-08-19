/*
 * CapabilityScan.g - which platform capabilities the image actually needs
 *
 * Ports Appa/src/Lowering/CapabilityScan.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "src/IR/Ir.g";
import "src/Semantics/SymbolTable.g";
import "src/Lowering/IrWalker.g";

class CapabilityScan {
    IrModule m;

    public bool mem;
    public bool input;
    public bool threads;
    public bool time;

    // Every callable body in the module, by the C name a call site would use
    StringMap[IrFunction] funcs;
    StringMap[IrOperator] ops;

    // Bodies already queued, so a recursive or mutually recursive call terminates
    StringSet seen;
    List[IrStmt] work;

    // The floor binds whose call IS the capability, resolved once
    String readName;
    String allocName;
    String timeName;

    func _init(IrModule m) {
        self.m = m;
        self.mem = false;
        self.input = false;
        self.threads = false;
        self.time = false;
        self.funcs = new StringMap[IrFunction]();
        self.ops = new StringMap[IrOperator]();
        self.seen = new StringSet();
        self.work = new List[IrStmt]();
        self.readName = m.symbols.FloorName(Roles.EnvRead());
        self.allocName = m.symbols.FloorName(Roles.EnvAlloc());
        self.timeName = m.symbols.FloorName(Roles.EnvTime());
    }

    /*
     * Run - Scans from every entry point and leaves the four flags set
     */
    public void func Run() {
        // Index everything callable first: the walk resolves a call by C name
        let int c = 0;
        while (c < self.m.classes.Length()) {
            let IrClass cls = self.m.classes.Get(c);
            let int i = 0;
            while (i < cls.methods.Length()) {
                self.funcs.Put(cls.methods.Get(i).cName, cls.methods.Get(i));
                i = i + 1;
            }
            let int o = 0;
            while (o < cls.operators.Length()) {
                self.ops.Put(cls.operators.Get(o).cName, cls.operators.Get(o));
                o = o + 1;
            }
            c = c + 1;
        }
        let int f = 0;
        while (f < self.m.freeFunctions.Length()) {
            self.funcs.Put(self.m.freeFunctions.Get(f).cName, self.m.freeFunctions.Get(f));
            f = f + 1;
        }

        // Declaring a process is itself the demand for threads
        self.threads = self.m.processes.Length() > 0;

        let int e = 0;
        while (e < self.m.freeFunctions.Length()) {
            let IrFunction fn = self.m.freeFunctions.Get(e);
            if (fn.isEntry) { self.Enter(fn.cName, fn.body); }
            e = e + 1;
        }

        let int p = 0;
        while (p < self.m.processes.Length()) {
            let IrProcess proc = self.m.processes.Get(p);
            match (proc.stateInit) {
                case Some(si) { self.Enter(si.cName, si.body); }
                case None { }
            }
            let int t = 0;
            while (t < proc.threads.Length()) {
                match (proc.threads.Get(t).entryFunc) {
                    case Some(en) { self.Enter(en.cName, en.body); }
                    case None { }
                }
                t = t + 1;
            }
            p = p + 1;
        }

        // A destructor is called by the runtime at refcount zero, so nothing in the program
        // names it and reachability alone would miss it
        let int dc = 0;
        while (dc < self.m.classes.Length()) {
            let IrClass cls = self.m.classes.Get(dc);
            let int i = 0;
            while (i < cls.methods.Length()) {
                let IrFunction mm = cls.methods.Get(i);
                if (mm.name == Lifecycle.Deinit()) { self.Enter(mm.cName, mm.body); }
                i = i + 1;
            }
            dc = dc + 1;
        }

        let IrWalk[CapabilityScan] w =
            new IrWalk[CapabilityScan](self, CapStmt, CapExpr);
        while (self.work.Length() > 0) {
            let IrStmt s = self.work.Get(0);
            self.work.RemoveAt(0);
            w.WalkStmt(s);
        }
    }

    /*
     * Enter - Queues a body for walking, once
     */
    public void func Enter(String cname, Optional[IrBlock] body) {
        match (body) {
            case Some(b) {
                if (self.seen.AddNew(cname)) { self.work.Add(IrStmt.IrBlock(b)); }
            }
            case None { }
        }
    }

    /*
     * Call - Records what calling a C name implies, and follows into the body when the module
     * has one
     */
    public void func Call(String cname) {
        if (cname == self.readName)  { self.input = true; }
        if (cname == self.allocName) { self.mem = true; }
        if (cname == self.timeName)  { self.time = true; }

        match (self.funcs.Find(cname)) {
            case Some(f) { self.Enter(cname, f.body); return; }
            case None { }
        }
        match (self.ops.Find(cname)) {
            case Some(o) { self.Enter(cname, o.body); }
            case None { }
        }
    }

    public void func NeedMem() { self.mem = true; }
}

/*
 * CapStmt - A for-in carries implicit Length and Get calls that appear nowhere in the expression
 * tree, so they are followed here
 */
bool func CapStmt(IrWalk[CapabilityScan] w, IrStmt s) {
    match (s) {
        case IrForIn(fi) {
            w.state.Call(fi.lenCName);
            w.state.Call(fi.getCName);
        }
        default { }
    }
    return true;
}

/*
 * CapExpr - The expressions that imply a capability, or name something to follow
 */
bool func CapExpr(IrWalk[CapabilityScan] w, IrExpr e) {
    match (e) {
        case IrNew(n) { w.state.NeedMem(); }
        case IrNewInit(ni) {
            w.state.NeedMem();
            w.state.Call(ni.addCName);
        }
        case IrStaticCall(sc)         { w.state.Call(sc.cName); }
        case IrInstanceCall(ic)       { w.state.Call(ic.cName); }
        case IrThrowsCall(tc)         { w.state.Call(tc.cName); }
        case IrThrowsInstanceCall(ti) { w.state.Call(ti.cName); }
        case IrFuncRef(fr)            { w.state.Call(fr.cName); }
        default { }
    }
    return true;
}
