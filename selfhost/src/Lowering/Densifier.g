/*
 * Densifier.g - short names for everything the outside world never sees
 *
 * Ports Appa/src/Lowering/Densifier.cs.
 *
 * Every internal symbol is renamed to a dense base-36 token, which shrinks the emitted C
 * substantially on a large build. What CANNOT be renamed is anything something outside the
 * generated code names for itself:
 *
 *   an entry point       the runtime calls it by name
 *   a '@keep' symbol     native text references it by its readable spelling
 *   an '@extern'         the linker resolves it
 *   enums, unions,
 *   native types         emitted under names native code may spell
 *   process variables    the launcher and the state initialiser both name them
 *
 * Those go into the taken set BEFORE any token is handed out, because the sequence would
 * otherwise walk straight into one: an '@extern' really can be called '__g5', and nothing else
 * would stop the counter from reaching it.
 *
 * The renaming is recorded in a sourcemap - dense token back to the readable name - so a
 * diagnostic or a debugger can undo it.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "src/Syntax/Ast.g";
import "src/IR/Ir.g";
import "src/Semantics/SymbolTable.g";
import "src/Lowering/IrRewriter.g";
import "src/Lowering/Dce.g";
import "src/Backend/Mangler.g";

class Densifier {
    IrModule m;
    Mangler mangler;
    int seq;

    // Names that already mean something in the emitted C, so the sequence must skip them
    StringSet taken;

    func _init(IrModule m, Mangler mangler) {
        self.m = m;
        self.mangler = mangler;
        self.seq = 0;
        self.taken = new StringSet();
    }

    /*
     * Base36 - A non-negative integer in base 36, which is what makes the tokens short
     */
    String func Base36(int v) {
        let String digits = "0123456789abcdefghijklmnopqrstuvwxyz";
        if (v == 0) { return "0"; }
        let String out = "";
        let int n = v;
        while (n > 0) {
            out = String.FromChar(digits.CharAt(n % 36)) + out;
            n = n / 36;
        }
        return out;
    }

    /*
     * Next - The next dense token, skipping any name the program already spells for itself
     */
    String func Next() {
        while (true) {
            let String t = "__g" + self.Base36(self.seq);
            self.seq = self.seq + 1;
            if (!self.taken.Has(t)) { return t; }
        }
    }

    /*
     * Run - Renames every internal symbol and returns the sourcemap from token to readable name.
     * The module is rewritten in place.
     */
    public StringMap[String] func Run() {
        self.CollectTaken();

        let StringMap[String] fn = new StringMap[String]();       // old C name -> dense token
        let StringMap[String] classTok = new StringMap[String]();  // class name -> its C name
        let StringMap[String] src = new StringMap[String]();       // token -> readable name

        // Internal free functions, and every method and operator, get dense names. An entry point
        // or a '@keep' function keeps the readable one.
        let int i = 0;
        while (i < self.m.freeFunctions.Length()) {
            let IrFunction f = self.m.freeFunctions.Get(i);
            if (!f.isEntry && !HasKeepAnnotation(f.annotations)) {
                self.MapFn(fn, src, f.cName, self.mangler.DisplayName(f.name));
            }
            i = i + 1;
        }
        let int c = 0;
        while (c < self.m.classes.Length()) {
            let IrClass cls = self.m.classes.Get(c);
            let String owner = self.mangler.DisplayName(cls.name);
            let int j = 0;
            while (j < cls.methods.Length()) {
                self.MapFn(fn, src, cls.methods.Get(j).cName, owner + "." + cls.methods.Get(j).name);
                j = j + 1;
            }
            let int o = 0;
            while (o < cls.operators.Length()) {
                self.MapFn(fn, src, cls.operators.Get(o).cName,
                           owner + ".operator" + cls.operators.Get(o).op);
                o = o + 1;
            }
            c = c + 1;
        }

        // A '@keep' class keeps its readable C name, so native text referencing the
        // gata_<Name> form still resolves
        let int k = 0;
        while (k < self.m.classes.Length()) {
            let IrClass cls = self.m.classes.Get(k);
            if (cls.keep) {
                classTok.Put(cls.name, cls.cName);
                src.Put(cls.cName, self.mangler.DisplayName(cls.name));
            } else {
                let String d = self.Next();
                classTok.Put(cls.name, d);
                src.Put(d, self.mangler.DisplayName(cls.name));
            }
            k = k + 1;
        }

        // Every call site, for-in binding and function value goes through the map first, while
        // the declarations still carry their old names
        let CallRenamer ren = new CallRenamer(fn);
        let IrRewrite[CallRenamer] rw = new IrRewrite[CallRenamer](ren, RenameStmt, RenameExpr);
        rw.Run(self.m);

        // Then the declarations themselves
        let int rf = 0;
        while (rf < self.m.freeFunctions.Length()) {
            let IrFunction f = self.m.freeFunctions.Get(rf);
            match (fn.Find(f.cName)) { case Some(d) { f.cName = d; } case None { } }
            rf = rf + 1;
        }
        let int rc = 0;
        while (rc < self.m.classes.Length()) {
            let IrClass cls = self.m.classes.Get(rc);
            let int j = 0;
            while (j < cls.methods.Length()) {
                let IrFunction mm = cls.methods.Get(j);
                match (fn.Find(mm.cName)) { case Some(d) { mm.cName = d; } case None { } }
                j = j + 1;
            }
            let int o = 0;
            while (o < cls.operators.Length()) {
                let IrOperator op = cls.operators.Get(o);
                match (fn.Find(op.cName)) { case Some(d) { op.cName = d; } case None { } }
                o = o + 1;
            }
            match (classTok.Find(cls.name)) { case Some(d) { cls.cName = d; } case None { } }
            rc = rc + 1;
        }

        // The intrinsic table names emitted symbols, so it has to follow the rename. This is why
        // IrModule carries the LIVE SymbolTable rather than a copy of one.
        let List[String] roles = self.m.symbols.intrinsics.Keys();
        let int r = 0;
        while (r < roles.Length()) {
            match (self.m.symbols.intrinsics.Find(roles.Get(r))) {
                case Some(old) {
                    match (fn.Find(old)) {
                        case Some(d) { self.m.symbols.intrinsics.Put(roles.Get(r), d); }
                        case None { }
                    }
                }
                case None { }
            }
            r = r + 1;
        }

        // The mangler answers class-name questions after this point, so it needs the new tokens
        self.mangler.SetDense(classTok);
        return src;
    }

    /*
     * MapFn - Assigns one dense token, recording the readable name it stands for
     */
    void func MapFn(StringMap[String] fn, StringMap[String] src, String old, String readable) {
        if (fn.Has(old)) { return; }
        let String d = self.Next();
        fn.Put(old, d);
        src.Put(d, readable);
    }

    /*
     * CollectTaken - Every name the sequence must not hand out
     */
    void func CollectTaken() {
        let List[Symbol] externs = self.m.symbols.Externs();
        let int e = 0;
        while (e < externs.Length()) { self.taken.AddNew(externs.Get(e).cName); e = e + 1; }

        let int f = 0;
        while (f < self.m.freeFunctions.Length()) {
            let IrFunction fn = self.m.freeFunctions.Get(f);
            if (fn.isEntry || HasKeepAnnotation(fn.annotations)) { self.taken.AddNew(fn.cName); }
            f = f + 1;
        }
        let int c = 0;
        while (c < self.m.classes.Length()) {
            if (self.m.classes.Get(c).keep) { self.taken.AddNew(self.m.classes.Get(c).cName); }
            c = c + 1;
        }
        let int en = 0;
        while (en < self.m.enums.Length()) { self.taken.AddNew(self.m.enums.Get(en).cName); en = en + 1; }
        let int u = 0;
        while (u < self.m.unions.Length()) { self.taken.AddNew(self.m.unions.Get(u).cName); u = u + 1; }
        let int nt = 0;
        while (nt < self.m.nativeTypes.Length()) {
            self.taken.AddNew(self.m.nativeTypes.Get(nt).cName);
            nt = nt + 1;
        }
        let int p = 0;
        while (p < self.m.processes.Length()) {
            let IrProcess proc = self.m.processes.Get(p);
            match (proc.stateInit) { case Some(si) { self.taken.AddNew(si.cName); } case None { } }
            let int v = 0;
            while (v < proc.state.Length()) {
                self.taken.AddNew(proc.state.Get(v).cName);
                v = v + 1;
            }
            p = p + 1;
        }
    }
}

/*
 * The old-to-dense map, carried through the rewrite. Anything not in it - an export, an extern, a
 * libc name - is left exactly as it was.
 */
class CallRenamer {
    public StringMap[String] fn;
    func _init(StringMap[String] fn) { self.fn = fn; }

    public String func Map(String c) {
        match (self.fn.Find(c)) { case Some(d) { return d; } case None { return c; } }
    }
}

/*
 * RenameExpr - Every call site and function value
 */
IrExpr func RenameExpr(IrRewrite[CallRenamer] r, IrExpr e) {
    match (e) {
        case IrStaticCall(sc)         { sc.cName = r.state.Map(sc.cName); }
        case IrInstanceCall(ic)       { ic.cName = r.state.Map(ic.cName); }
        case IrThrowsCall(tc)         { tc.cName = r.state.Map(tc.cName); }
        case IrThrowsInstanceCall(ti) { ti.cName = r.state.Map(ti.cName); }
        case IrNewInit(ni)            { ni.addCName = r.state.Map(ni.addCName); }
        case IrFuncRef(fr)            { fr.cName = r.state.Map(fr.cName); }
        default { }
    }
    return e;
}

/*
 * RenameStmt - The Length and Get calls a for-in compiles to, which appear in no expression
 */
IrStmt func RenameStmt(IrRewrite[CallRenamer] r, IrStmt s) {
    match (s) {
        case IrForIn(fi) {
            fi.lenCName = r.state.Map(fi.lenCName);
            fi.getCName = r.state.Map(fi.getCName);
        }
        default { }
    }
    return s;
}
