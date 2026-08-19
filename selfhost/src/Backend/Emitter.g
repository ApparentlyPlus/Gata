/*
 * Emitter.g - IR to C: the pass that actually generates the emitted C source
 *
 * Ports Appa/src/Backend/Emitter.cs.
 *
 * Ten writers, one per section of the output, which Layout then composes into translation units.
 * Which writer a declaration lands in IS the translation-unit decision: kernel-visible things go to
 * the _k* writers, user-visible ones to the _u* writers, and anything both realms can see goes to
 * the shared header. A library class small enough to be self-contained goes there whole.
 *
 * PORTING NOTES
 *
 * C#'s `using (w.Block(...))` becomes an explicit `w.Block(...)` / `w.End(...)` pair; see the note
 * at the top of CodeWriter.g. The pairs are kept adjacent so the shape stays readable without the
 * compiler enforcing them.
 *
 * `HashSet<EmitKey>` keys on the WRITER's identity, so two units may each carry their own copy of
 * one typedef. Gata has no object identity hash, so each writer is given a stable name at
 * construction and the key is that name plus the kind plus the declaration name - the same
 * partition, spelled differently.
 *
 * `EmitAggregateTypes` uses a local recursive function closing over `pending` and `visiting`; with
 * no closures those two become fields for the duration of the walk.
 *
 * The C# `Write` overloads take a StringBuilder; here they take the CodeWriter and append through
 * Put, because a line under composition is already writing into the writer's own buffer.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Int.g";
import "src/Diagnostics/TextSpan.g";
import "src/Diagnostics/Diagnostic.g";
import "src/Syntax/Ast.g";
import "src/IR/Ir.g";
import "src/IR/ManagedTypes.g";
import "src/Semantics/SymbolTable.g";
import "src/Backend/Mangler.g";
import "src/Backend/CodeWriter.g";

/*
 * Everything the emitter produced, handed to Layout to compose into files.
 */
class EmitOutput {
    public String sharedHeader;
    public String kernelPreamble;
    public String kernelTypes;
    public String kernelFwd;
    public String kernelFuncs;
    public String kernelBoot;
    public String userPreamble;
    public String userTypes;
    public String userFwd;
    public String userFuncs;
    public List[IrProcess] processes;
    public bool hasKernelRealm;
    public bool hasUserRealm;
    public Optional[String] userEntryCName;

    func _init(String sharedHeader, String kernelPreamble, String kernelTypes, String kernelFwd,
               String kernelFuncs, String kernelBoot, String userPreamble, String userTypes,
               String userFwd, String userFuncs, List[IrProcess] processes, bool hasKernelRealm,
               bool hasUserRealm, Optional[String] userEntryCName) {
        self.sharedHeader = sharedHeader;
        self.kernelPreamble = kernelPreamble;
        self.kernelTypes = kernelTypes;
        self.kernelFwd = kernelFwd;
        self.kernelFuncs = kernelFuncs;
        self.kernelBoot = kernelBoot;
        self.userPreamble = userPreamble;
        self.userTypes = userTypes;
        self.userFwd = userFwd;
        self.userFuncs = userFuncs;
        self.processes = processes;
        self.hasKernelRealm = hasKernelRealm;
        self.hasUserRealm = hasUserRealm;
        self.userEntryCName = userEntryCName;
    }
}

/*
 * A named writer. C# keys its per-unit dedup set on the CodeWriter reference itself; Gata cannot
 * hash object identity, so each writer carries the name that stands in for it.
 */
class NamedWriter {
    public String id;
    public CodeWriter w;
    func _init(String id) { self.id = id; self.w = new CodeWriter(); }
}

/*
 * One aggregate awaiting emission in EmitAggregateTypes' dependency walk. C# holds `object` and
 * type-switches; a union names the three possibilities outright.
 */
union Aggregate {
    ArrayAgg(IrType t),
    FuncPtrAgg(IrType t),
    UnionAgg(IrUnion u)
}

class Emitter {
    IrModule m;
    DiagnosticBag diag;
    Mangler mangler;
    IrTypeTable t;

    public NamedWriter sharedH;
    public NamedWriter kPre;
    public NamedWriter kTypes;
    public NamedWriter kFwd;
    public NamedWriter kFuncs;
    public NamedWriter kBoot;
    public NamedWriter uPre;
    public NamedWriter uTypes;
    public NamedWriter uFwd;
    public NamedWriter uFunc;

    // Per-writer type dedup: each distinct (writer, kind, name) is emitted exactly once into that
    // translation unit.
    StringSet emitted;

    ManagedTypes managed;

    // Roles with no @intrinsic binding anywhere; each is reported once.
    StringSet missingRoles;

    // The C struct behind a String value, named by every string literal in the program.
    String stringStruct;

    // Indexes built on first ask
    StringMap[IrClass] classIndex;
    StringMap[IrUnion] unionIndex;
    bool indexed;

    // EmitAggregateTypes' walk state. Fields rather than locals because C# expresses the walk as a
    // local function closing over both, and Gata has no closures.
    StringMap[Aggregate] pending;
    StringSet visiting;

    func _init(IrModule m, DiagnosticBag diag, IrTypeTable t, Mangler mangler) {
        self.m = m;
        self.diag = diag;
        self.mangler = mangler;
        self.t = t;
        self.sharedH = new NamedWriter("sharedH");
        self.kPre    = new NamedWriter("kPre");
        self.kTypes  = new NamedWriter("kTypes");
        self.kFwd    = new NamedWriter("kFwd");
        self.kFuncs  = new NamedWriter("kFuncs");
        self.kBoot   = new NamedWriter("kBoot");
        self.uPre    = new NamedWriter("uPre");
        self.uTypes  = new NamedWriter("uTypes");
        self.uFwd    = new NamedWriter("uFwd");
        self.uFunc   = new NamedWriter("uFunc");
        self.emitted = new StringSet();
        self.managed = new ManagedTypes(m);
        self.missingRoles = new StringSet();
        self.stringStruct = Emitter.TrimStars(mangler.CType(t.ClassRef("String")));
        self.classIndex = new StringMap[IrClass]();
        self.unionIndex = new StringMap[IrUnion]();
        self.indexed = false;
        self.pending = new StringMap[Aggregate]();
        self.visiting = new StringSet();
    }

    /*
     * TrimStars - Drops trailing '*' from a C type spelling, turning 'gata_String*' into the struct
     * name a string literal macro needs
     */
    public static String func TrimStars(String s) {
        let int n = s.Length();
        while (n > 0 && s.CharAt(n - 1) == '*') { n = n - 1; }
        return s.Substring(0, n);
    }

    /*
     * FirstInto - True the first time this (writer, kind, name) is seen, suppressing a duplicate
     * declaration inside one translation unit
     */
    bool func FirstInto(NamedWriter w, String kind, String name) {
        return self.emitted.AddNew(w.id + "" + kind + "" + name);
    }

    bool func IsManaged(IrType ty) { return self.managed.IsManaged(ty); }

    /*
     * RetainCall - The C statement retaining one value: the runtime intrinsic for a class
     * reference, the union's generated retain for a managed union
     */
    String func RetainCall(IrType ty, String operand) {
        match (ty) {
            case IrUnionType(ut) { return self.mangler.UnionRetain(ut.name) + "(" + operand + ");"; }
            default { return self.Intrinsic(Roles.Retain()) + "(" + operand + ");"; }
        }
    }

    /*
     * ReleaseCall - The releasing counterpart of RetainCall
     */
    String func ReleaseCall(IrType ty, String operand) {
        match (ty) {
            case IrUnionType(ut) { return self.mangler.UnionRelease(ut.name) + "(" + operand + ");"; }
            default { return self.Intrinsic(Roles.Release()) + "(" + operand + ");"; }
        }
    }

    String func CT(IrType ty) { return self.mangler.CType(ty); }

    /*
     * Build - Emits every section and hands them back for Layout to compose into files
     */
    public EmitOutput func Build() {
        self.EmitRefCountMode();
        self.EmitForwardTypedefs();
        self.EmitEnums();
        self.EmitAggregateTypes();
        self.EmitIntrinsicProtos();
        self.EmitUnionArc();
        self.EmitUnionEq();
        self.EmitResultTypedefs();

        let int nb = 0;
        while (nb < self.m.nativeBlocks.Length()) { self.EmitNativeBlock(self.m.nativeBlocks.Get(nb)); nb = nb + 1; }

        let int nt = 0;
        while (nt < self.m.nativeTypes.Length()) { self.EmitNativeType(self.m.nativeTypes.Get(nt)); nt = nt + 1; }

        let int c = 0;
        while (c < self.m.classes.Length()) { self.EmitClass(self.m.classes.Get(c)); c = c + 1; }

        let int f = 0;
        while (f < self.m.freeFunctions.Length()) { self.EmitFreeFunc(self.m.freeFunctions.Get(f)); f = f + 1; }

        let int p = 0;
        while (p < self.m.processes.Length()) {
            let IrProcess proc = self.m.processes.Get(p);
            self.EmitProcessState(proc);
            let int th = 0;
            while (th < proc.threads.Length()) { self.EmitThread(proc.threads.Get(th), proc); th = th + 1; }
            p = p + 1;
        }

        let Optional[String] userEntry = Optional[String].None();
        let int e = 0;
        while (e < self.m.freeFunctions.Length()) {
            let IrFunction fn = self.m.freeFunctions.Get(e);
            if (fn.isEntry && fn.vis == Visibility.User) { userEntry = Optional.Some(fn.cName); e = self.m.freeFunctions.Length(); }
            e = e + 1;
        }

        return new EmitOutput(
            self.sharedH.w.Text(),
            self.kPre.w.Text(), self.kTypes.w.Text(), self.kFwd.w.Text(), self.kFuncs.w.Text(), self.kBoot.w.Text(),
            self.uPre.w.Text(), self.uTypes.w.Text(), self.uFwd.w.Text(), self.uFunc.w.Text(),
            self.m.processes, self.m.HasKernelRealm(), self.m.HasUserRealm(), userEntry);
    }

    // --- Reference-counting mode -------------------------------------------------------------

    /*
     * EmitRefCountMode - Tells the runtime whether its reference counts have to be atomic, by
     * defining GATA_RC_ATOMIC in the shared header when this program contains any concurrency
     */
    void func EmitRefCountMode() {
        let bool concurrent = self.m.processes.Length() > 0;
        let CodeWriter w = self.sharedH.w;
        if (concurrent) {
            w.Line("// This program declares processes, so reference counts must be atomic.");
        } else {
            w.Line("// No process is declared, so no two contexts can hold one reference.");
        }
        w.Line("#ifndef GATA_RC_ATOMIC");
        w.Line("#define GATA_RC_ATOMIC " + (concurrent ? "1" : "0"));
        w.Line("#endif");
        w.Line("");
    }

    // --- Forward typedefs --------------------------------------------------------------------

    /*
     * EmitForwardTypedefs - Forward-declares every Gata class struct in the shared header, so any
     * file can use a class pointer before its full struct is defined
     */
    void func EmitForwardTypedefs() {
        let bool any = false;
        let int i = 0;
        while (i < self.m.classes.Length()) {
            let IrClass cls = self.m.classes.Get(i);
            if (self.FirstInto(self.sharedH, "T", cls.name)) {
                self.sharedH.w.Line("typedef struct " + cls.cName + " " + cls.cName + ";");
                any = true;
            }
            i = i + 1;
        }
        if (any) { self.sharedH.w.Line(""); }
    }

    // --- Enums and unions --------------------------------------------------------------------

    /*
     * EmitEnums - One C typedef enum per declared Gata enum, into the shared header
     */
    void func EmitEnums() {
        let int i = 0;
        while (i < self.m.enums.Length()) {
            let IrEnum e = self.m.enums.Get(i);
            let StringBuilder sb = new StringBuilder();
            sb.Append("typedef enum { ");
            let int j = 0;
            while (j < e.members.Length()) {
                if (j > 0) { sb.Append(", "); }
                let IrEnumMember mem = e.members.Get(j);
                sb.Append(self.mangler.EnumMember(e.name, mem.name));
                match (mem.cValue) { case Some(v) { sb.Append(" = "); sb.Append(v); } case None { } }
                j = j + 1;
            }
            sb.Append(" } ");
            sb.Append(e.cName);
            sb.Append(";");
            self.sharedH.w.Line(sb.ToString());
            i = i + 1;
        }
        if (self.m.enums.Length() > 0) { self.sharedH.w.Line(""); }
    }

    /*
     * EmitUnion - One tagged-union struct: a tag integer plus a C union of per-variant payload
     * structs. Called by EmitAggregateTypes once every type this union stores by value is defined.
     */
    void func EmitUnion(IrUnion u) {
        let CodeWriter w = self.sharedH.w;
        w.Block("typedef struct {");
        w.Line("int __tag;");

        let bool hasFields = false;
        let int j = 0;
        while (j < u.variants.Length()) {
            if (u.variants.Get(j).variantFields.Length() > 0) { hasFields = true; }
            j = j + 1;
        }

        if (hasFields) {
            w.Block("union {");
            let int k = 0;
            while (k < u.variants.Length()) {
                let IrUnionVariant v = u.variants.Get(k);
                if (v.variantFields.Length() > 0) {
                    let StringBuilder sb = new StringBuilder();
                    sb.Append("struct { ");
                    let int f = 0;
                    while (f < v.variantFields.Length()) {
                        let IrParam fld = v.variantFields.Get(f);
                        sb.Append(self.CT(fld.type));
                        sb.Append(" ");
                        sb.Append(Mangle.Member(fld.name));
                        sb.Append("; ");
                        f = f + 1;
                    }
                    sb.Append("} ");
                    sb.Append(Mangle.Member(v.name));
                    sb.Append(";");
                    w.Line(sb.ToString());
                }
                k = k + 1;
            }
            w.End("} payload;");
        }
        w.End("} " + u.cName + ";");
    }

    // --- Fixed-array types -------------------------------------------------------------------

    /*
     * EmitArrayType - The C struct wrapper for one fixed-array type
     */
    void func EmitArrayType(IrType a) {
        match (a) {
            case IrArrayType(x) {
                self.sharedH.w.Line("typedef struct { " + self.CT(x.elem) + " _[" + Int.ToString(x.size) +
                                    "]; } " + self.CT(a) + ";");
            }
            default { }
        }
    }

    // --- Result types ------------------------------------------------------------------------

    /*
     * EmitResultTypedefs - A Result_T struct per throws return type, forward-declaring any class
     * pointer they reference so the shared header stays self-contained
     */
    void func EmitResultTypedefs() {
        let StringSet forwarded = new StringSet();
        // Registration order, not hash order - see SymbolTable.resultTypedefOrder.
        let List[String] keys = self.m.symbols.resultTypedefOrder;
        let int i = 0;
        while (i < keys.Length()) {
            let String inner = self.m.symbols.resultTypedefs.Get(keys.Get(i));
            if (self.m.symbols.IsClass(inner)) {
                if (forwarded.AddNew(inner) && self.FirstInto(self.sharedH, "T", inner)) {
                    let String cn = self.mangler.Class(inner);
                    self.sharedH.w.Line("typedef struct " + cn + " " + cn + ";");
                }
            }
            i = i + 1;
        }
        if (forwarded.Length() > 0) { self.sharedH.w.Line(""); }

        let int j = 0;
        while (j < keys.Length()) {
            let String resultType = keys.Get(j);
            let String inner = self.m.symbols.resultTypedefs.Get(resultType);
            let String ct = self.m.symbols.CType(inner, self.mangler);
            if (self.FirstInto(self.sharedH, "S", resultType)) {
                self.sharedH.w.Line("typedef struct { " + ct + " value; bool has_error; } " + resultType + ";");
            }
            j = j + 1;
        }
        if (keys.Length() > 0) { self.sharedH.w.Line(""); }
    }

    // --- Function pointer types --------------------------------------------------------------

    /*
     * EmitFuncPtrType - The C typedef for one function-pointer type
     */
    void func EmitFuncPtrType(IrType ft) {
        match (ft) {
            case IrFuncPtrType(f) {
                let StringBuilder sb = new StringBuilder();
                sb.Append("typedef ");
                sb.Append(self.CT(f.ret));
                sb.Append(" (*");
                sb.Append(self.CT(ft));
                sb.Append(")(");
                if (f.params.Length() == 0) {
                    sb.Append("void");
                } else {
                    let int j = 0;
                    while (j < f.params.Length()) {
                        if (j > 0) { sb.Append(", "); }
                        sb.Append(self.CT(f.params.Get(j)));
                        j = j + 1;
                    }
                }
                sb.Append(");");
                self.sharedH.w.Line(sb.ToString());
            }
            default { }
        }
    }

    // --- Aggregate type ordering -------------------------------------------------------------

    /*
     * EmitAggregateTypes - Every fixed-array, function-pointer and union typedef, in dependency
     * order so a struct is never named before it is defined
     */
    void func EmitAggregateTypes() {
        let List[String] order = new List[String]();

        let int a = 0;
        while (a < self.m.arrayTypes.Length()) {
            let IrType at = self.m.arrayTypes.Get(a);
            match (at) {
                case IrArrayType(x) {
                    if (x.size > 0) {
                        let String key = self.CT(at);
                        if (!self.pending.Has(key)) { self.pending.Put(key, Aggregate.ArrayAgg(at)); order.Add(key); }
                    }
                }
                default { }
            }
            a = a + 1;
        }
        let int f = 0;
        while (f < self.m.funcPtrTypes.Length()) {
            let IrType ft = self.m.funcPtrTypes.Get(f);
            let String key = self.CT(ft);
            if (!self.pending.Has(key)) { self.pending.Put(key, Aggregate.FuncPtrAgg(ft)); order.Add(key); }
            f = f + 1;
        }
        let int u = 0;
        while (u < self.m.unions.Length()) {
            let IrUnion un = self.m.unions.Get(u);
            if (!self.pending.Has(un.cName)) { self.pending.Put(un.cName, Aggregate.UnionAgg(un)); order.Add(un.cName); }
            u = u + 1;
        }

        if (order.Length() == 0) { return; }

        let bool any = false;
        let int i = 0;
        while (i < order.Length()) {
            if (self.EmitAggregate(order.Get(i))) { any = true; }
            i = i + 1;
        }
        if (any) { self.sharedH.w.Line(""); }
    }

    /*
     * EmitAggregate - One aggregate and everything it depends on first.
     *
     * 'visiting' holds the names currently on the DFS stack. A cycle among them means a struct that
     * contains itself, which the resolver already rejected; breaking here only stops this pass from
     * recursing forever on IR it was handed anyway.
     */
    bool func EmitAggregate(String cname) {
        match (self.pending.Find(cname)) {
            case None { return false; }
            case Some(item) {
                if (!self.visiting.AddNew(cname)) { return false; }

                let List[String] deps = self.DependenciesOf(item);
                let int i = 0;
                while (i < deps.Length()) { self.EmitAggregate(deps.Get(i)); i = i + 1; }
                self.visiting.Remove(cname);

                // Re-check: a cycle can bring us back here after the dependency walk.
                if (!self.pending.Has(cname)) { return false; }
                self.pending.Remove(cname);

                match (item) {
                    case ArrayAgg(at)   { self.EmitArrayType(at); }
                    case FuncPtrAgg(ft) { self.EmitFuncPtrType(ft); }
                    case UnionAgg(un)   { self.EmitUnion(un); }
                }
                self.FirstInto(self.sharedH, "S", cname);
                return true;
            }
        }
    }

    /*
     * DependenciesOf - The C type names an aggregate needs defined before it can be emitted: its
     * element type, its signature types, or its variant field types
     */
    List[String] func DependenciesOf(Aggregate item) {
        let List[String] r = new List[String]();
        match (item) {
            case ArrayAgg(at) {
                match (at) { case IrArrayType(x) { r.Add(self.CT(x.elem)); } default { } }
            }
            case FuncPtrAgg(ft) {
                match (ft) {
                    case IrFuncPtrType(f) {
                        r.Add(self.CT(f.ret));
                        let int i = 0;
                        while (i < f.params.Length()) { r.Add(self.CT(f.params.Get(i))); i = i + 1; }
                    }
                    default { }
                }
            }
            case UnionAgg(un) {
                let int v = 0;
                while (v < un.variants.Length()) {
                    let IrUnionVariant vv = un.variants.Get(v);
                    let int k = 0;
                    while (k < vv.variantFields.Length()) { r.Add(self.CT(vv.variantFields.Get(k).type)); k = k + 1; }
                    v = v + 1;
                }
            }
        }
        return r;
    }

    /*
     * EmitUnionArc - The retain/release pair for every managed union. The tag decides what to
     * count, so the pair is per type and generated like a class destructor. By value, so retain
     * composes in expression position; prototypes first, as a union may hold one.
     */
    void func EmitUnionArc() {
        let List[IrUnion] managedUnions = new List[IrUnion]();
        let int i = 0;
        while (i < self.m.unions.Length()) {
            let IrUnion u = self.m.unions.Get(i);
            if (self.managed.IsManagedUnion(u.name)) { managedUnions.Add(u); }
            i = i + 1;
        }
        if (managedUnions.Length() == 0) { return; }

        let int j = 0;
        while (j < managedUnions.Length()) {
            let IrUnion u = managedUnions.Get(j);
            self.sharedH.w.Line("static inline " + u.cName + " " + self.mangler.UnionRetain(u.name) +
                                "(" + u.cName + " _v);");
            self.sharedH.w.Line("static inline void " + self.mangler.UnionRelease(u.name) +
                                "(" + u.cName + " _v);");
            j = j + 1;
        }
        self.sharedH.w.Line("");

        let int k = 0;
        while (k < managedUnions.Length()) {
            self.EmitUnionArcBody(managedUnions.Get(k), true);
            self.EmitUnionArcBody(managedUnions.Get(k), false);
            k = k + 1;
        }
    }

    /*
     * EmitUnionArcBody - One half of a managed union's retain/release pair. The two differ only in
     * the per-field call and the return, so they share this body rather than drifting apart.
     */
    void func EmitUnionArcBody(IrUnion u, bool retain) {
        let String name = retain ? self.mangler.UnionRetain(u.name) : self.mangler.UnionRelease(u.name);
        let String sig = retain ? ("static inline " + u.cName + " " + name + "(" + u.cName + " _v)")
                                : ("static inline void " + name + "(" + u.cName + " _v)");
        let CodeWriter w = self.sharedH.w;

        w.Block(sig + " {");
        w.Block("switch (_v.__tag) {");
        let int i = 0;
        while (i < u.variants.Length()) {
            let IrUnionVariant v = u.variants.Get(i);
            let List[IrParam] managedFields = new List[IrParam]();
            let int f = 0;
            while (f < v.variantFields.Length()) {
                let IrParam p = v.variantFields.Get(f);
                if (self.IsManaged(p.type)) { managedFields.Add(p); }
                f = f + 1;
            }
            if (managedFields.Length() > 0) {
                // The variant INDEX, not the tag enumerator: __tag is a plain int, and every other
                // site that writes or tests it uses the index too.
                let StringBuilder sb = new StringBuilder();
                sb.Append("case ");
                sb.Append(Int.ToString(i));
                sb.Append(": ");
                let int g = 0;
                while (g < managedFields.Length()) {
                    let IrParam p = managedFields.Get(g);
                    let String operand = "_v.payload." + Mangle.Member(v.name) + "." + Mangle.Member(p.name);
                    sb.Append(retain ? self.RetainCall(p.type, operand) : self.ReleaseCall(p.type, operand));
                    sb.Append(" ");
                    g = g + 1;
                }
                sb.Append("break;");
                w.Line(sb.ToString());
            }
            i = i + 1;
        }
        // Variants holding nothing managed land here. Always emitted: a switch whose every case was
        // skipped above would otherwise be an empty statement.
        w.Line("default: break;");
        w.End("}");
        if (retain) { w.Line("return _v;"); }
        w.End("}");
        w.Blank();
    }

    /*
     * EmitUnionEq - Each union's structural equality: tags first, then one comparison per field of
     * the live variant, by whatever '==' already means for that field's own type. memcmp would be
     * wrong, not just slow - it reads the payload's inactive members and its padding.
     */
    void func EmitUnionEq() {
        if (self.m.unions.Length() == 0) { return; }
        let int i = 0;
        while (i < self.m.unions.Length()) {
            let IrUnion u = self.m.unions.Get(i);
            self.sharedH.w.Line("static inline bool " + self.mangler.UnionEq(u.name) +
                                "(" + u.cName + " _a, " + u.cName + " _b);");
            i = i + 1;
        }
        self.sharedH.w.Line("");

        let int j = 0;
        while (j < self.m.unions.Length()) {
            let IrUnion u = self.m.unions.Get(j);
            if (self.EqEmittableIn(u, Visibility.Kernel)) { self.EmitUnionEqBody(u, self.kFuncs.w); }
            if (self.EqEmittableIn(u, Visibility.User))   { self.EmitUnionEqBody(u, self.uFunc.w); }
            j = j + 1;
        }
    }

    /*
     * EqEmittableIn - True when every '==' this union's equality calls is declared in the given
     * inRealm. A class inside 'userspace { }' is emitted only into uproc.c, so a kernel-side body
     * would call an undeclared function - a warning on the pinned gcc 7, fatal on anything newer.
     */
    bool func EqEmittableIn(IrUnion u, Visibility inRealm) {
        return self.EqVisit(u, new StringSet(), inRealm);
    }

    bool func EqVisit(IrUnion u, StringSet seen, Visibility inRealm) {
        if (!seen.AddNew(u.name)) { return true; }
        let int i = 0;
        while (i < u.variants.Length()) {
            let IrUnionVariant v = u.variants.Get(i);
            let int f = 0;
            while (f < v.variantFields.Length()) {
                if (!self.EqReachable(v.variantFields.Get(f).type, inRealm)) { return false; }
                f = f + 1;
            }
            i = i + 1;
        }
        return true;
    }

    bool func EqReachable(IrType ty, Visibility inRealm) {
        match (ty) {
            case IrArrayType(a) { return self.EqReachable(a.elem, inRealm); }
            case IrUnionType(nested) {
                match (self.UnionByName(nested.name)) {
                    case Some(n) { return self.EqVisit(n, new StringSet(), inRealm); }
                    case None { return true; }
                }
            }
            case IrClassRef(cr) {
                match (self.ClassEqOperator(cr.className)) {
                    case None { return true; }
                    case Some(op) {
                        match (self.ClassByName(cr.className)) {
                            case None { return true; }
                            case Some(cls) {
                                if (inRealm == Visibility.Kernel) { return cls.vis != Visibility.User; }
                                return cls.vis != Visibility.Kernel;
                            }
                        }
                    }
                }
            }
            default { return true; }
        }
    }

    /*
     * EmitUnionEqBody - One union's equality body, into the given writer
     */
    void func EmitUnionEqBody(IrUnion u, CodeWriter w) {
        w.Block("static inline bool " + self.mangler.UnionEq(u.name) +
                "(" + u.cName + " _a, " + u.cName + " _b) {");
        w.Line("if (_a.__tag != _b.__tag) return false;");
        w.Block("switch (_a.__tag) {");
        let int i = 0;
        while (i < u.variants.Length()) {
            let IrUnionVariant v = u.variants.Get(i);
            if (v.variantFields.Length() > 0) {
                let List[String] terms = new List[String]();
                let int f = 0;
                while (f < v.variantFields.Length()) {
                    let IrParam p = v.variantFields.Get(f);
                    let String base = ".payload." + Mangle.Member(v.name) + "." + Mangle.Member(p.name);
                    terms.Add(self.EqTerm(p.type, "_a" + base, "_b" + base));
                    f = f + 1;
                }
                w.Line("case " + Int.ToString(i) + ": return " + String.Join(terms, " && ") + ";");
            }
            i = i + 1;
        }
        // Payload-free variants, and any variant whose fields all compared trivially.
        w.Line("default: return true;");
        w.End("}");
        w.End("}");
        w.Blank();
    }

    /*
     * EqTerm - A C expression comparing two values, applying the same rule '==' on that type would
     */
    String func EqTerm(IrType ty, String a, String b) {
        match (ty) {
            case IrUnionType(ut) { return self.mangler.UnionEq(ut.name) + "(" + a + ", " + b + ")"; }
            case IrArrayType(arr) {
                if (arr.size > 0) {
                    let List[String] terms = new List[String]();
                    let int i = 0;
                    while (i < arr.size) {
                        let String idx = "._[" + Int.ToString(i) + "]";
                        terms.Add(self.EqTerm(arr.elem, a + idx, b + idx));
                        i = i + 1;
                    }
                    if (terms.Length() == 0) { return "true"; }
                    return "(" + String.Join(terms, " && ") + ")";
                }
                return "(" + a + " == " + b + ")";
            }
            case IrClassRef(cr) {
                match (self.ClassEqOperator(cr.className)) {
                    case Some(opCName) { return opCName + "(" + a + ", " + b + ")"; }
                    case None { return "(" + a + " == " + b + ")"; }
                }
            }
            default { return "(" + a + " == " + b + ")"; }
        }
    }

    /*
     * BuildIndexes - The class and union name indexes, built once on first ask
     */
    void func BuildIndexes() {
        if (self.indexed) { return; }
        self.indexed = true;
        let int i = 0;
        while (i < self.m.classes.Length()) {
            let IrClass c = self.m.classes.Get(i);
            if (!self.classIndex.Has(c.name)) { self.classIndex.Put(c.name, c); }
            i = i + 1;
        }
        let int j = 0;
        while (j < self.m.unions.Length()) {
            let IrUnion u = self.m.unions.Get(j);
            if (!self.unionIndex.Has(u.name)) { self.unionIndex.Put(u.name, u); }
            j = j + 1;
        }
    }

    Optional[IrClass] func ClassByName(String name) { self.BuildIndexes(); return self.classIndex.Find(name); }
    Optional[IrUnion] func UnionByName(String name) { self.BuildIndexes(); return self.unionIndex.Find(name); }

    /*
     * ClassEqOperator - The cName of the class's bool-returning '==' overload, or none if it
     * declares one - in which case its references compare by address, as they do anywhere else
     */
    Optional[String] func ClassEqOperator(String className) {
        match (self.ClassByName(className)) {
            case None { return Optional[String].None(); }
            case Some(cls) {
                let int i = 0;
                while (i < cls.operators.Length()) {
                    let IrOperator op = cls.operators.Get(i);
                    if (op.op == "==" && op.params.Length() == 1) {
                        match (op.returnType) {
                            case IrPrimType(pt) { if (pt.cName == "bool") { return Optional.Some(op.cName); } }
                            default { }
                        }
                    }
                    i = i + 1;
                }
                return Optional[String].None();
            }
        }
    }

    // --- Native blocks -----------------------------------------------------------------------

    /*
     * EmitNativeBlock - Raw C into the preamble, types or boot section its tag names, then routed to
     * the kernel or user writer by visibility
     */
    void func EmitNativeBlock(IrNativeBlock nb) {
        let String t = Emitter.TrimC(nb.c);
        let NamedWriter kw = self.kTypes;
        let NamedWriter uw = self.uTypes;
        let bool hasUser = true;
        if (nb.section == NativeSection.Preamble) { kw = self.kPre; uw = self.uPre; }
        if (nb.section == NativeSection.Boot) { kw = self.kBoot; hasUser = false; }

        if (nb.vis == Visibility.Kernel) { Emitter.PutNative(kw.w, t); return; }
        if (nb.vis == Visibility.User) { if (hasUser) { Emitter.PutNative(uw.w, t); } return; }
        Emitter.PutNative(kw.w, t);
        if (hasUser) { Emitter.PutNative(uw.w, t); }
    }

    /*
     * PutNative - One native body plus the blank line that follows it
     */
    public static void func PutNative(CodeWriter w, String body) {
        w.Line(body);
        w.Line("");
    }

    /*
     * EmitNativeType - A native struct and its typedef, into the writer its visibility names
     */
    void func EmitNativeType(IrNativeType nt) {
        if (nt.vis == Visibility.Kernel) { self.EmitNativeTypeTo(self.kTypes, nt); return; }
        if (nt.vis == Visibility.User)   { self.EmitNativeTypeTo(self.uTypes, nt); return; }
        self.EmitNativeTypeTo(self.sharedH, nt);
    }

    void func EmitNativeTypeTo(NamedWriter nw, IrNativeType nt) {
        if (!self.FirstInto(nw, "N", nt.name)) { return; }
        let CodeWriter w = nw.w;
        w.Line("typedef struct " + nt.cName + " " + nt.cName + ";");
        w.Block("struct " + nt.cName + " {");
        w.Line(Emitter.TrimC(nt.c));
        w.End("};");
        w.Blank();
    }

    // --- Classes -----------------------------------------------------------------------------

    /*
     * EmitClass - Routes a class to the right emitter: module, self-contained library class, or
     * concrete class
     */
    void func EmitClass(IrClass cls) {
        if (cls.isModule) { self.EmitModule(cls); return; }

        if (!cls.isLib) {
            let bool isKernel = cls.vis == Visibility.Kernel;
            self.EmitConcreteClass(cls, isKernel ? self.kTypes : self.uTypes,
                                        isKernel ? self.kFwd   : self.uFwd,
                                        isKernel ? self.kFuncs : self.uFunc, false);
            return;
        }

        let bool toKernel = cls.vis != Visibility.User;
        let bool toUser   = cls.vis != Visibility.Kernel;

        if (Emitter.CanLiveInSharedHeader(cls) && toKernel && toUser) {
            self.EmitLibClass(cls);
            return;
        }
        if (toKernel) { self.EmitConcreteClass(cls, self.kTypes, self.kFwd, self.kFuncs, true); }
        if (toUser)   { self.EmitConcreteClass(cls, self.uTypes, self.uFwd, self.uFunc, true); }
    }

    /*
     * EmitModule - A module becomes per-file static-inline functions, with no struct and no
     * allocator: it has no instances
     */
    void func EmitModule(IrClass cls) {
        let bool toKernel = cls.vis != Visibility.User;
        let bool toUser   = cls.vis != Visibility.Kernel;
        if (toKernel) { self.EmitModuleInto(cls, self.kTypes.w, self.kFuncs.w); }
        if (toUser)   { self.EmitModuleInto(cls, self.uTypes.w, self.uFunc.w); }
    }

    void func EmitModuleInto(IrClass cls, CodeWriter types, CodeWriter funcs) {
        let int i = 0;
        while (i < cls.methods.Length()) {
            types.Line("static inline " + self.MethodSig(cls.methods.Get(i)) + ";");
            i = i + 1;
        }
        types.Line("");
        let int j = 0;
        while (j < cls.methods.Length()) { self.EmitFunctionBody(cls.methods.Get(j), funcs, true); j = j + 1; }
    }

    /*
     * EmitConcreteClass - A class into the given writers. A library class uses static-inline
     * functions; a context class uses ordinary linkage with separate forward declarations.
     */
    void func EmitConcreteClass(IrClass cls, NamedWriter typesNW, NamedWriter fwdNW,
                                NamedWriter funcsNW, bool isLib) {
        let String prefix = isLib ? "static inline " : "";
        let CodeWriter types = typesNW.w;
        let CodeWriter fwd = fwdNW.w;
        let CodeWriter funcs = funcsNW.w;

        if (self.FirstInto(typesNW, "T", cls.name)) {
            types.Line("typedef struct " + cls.cName + " " + cls.cName + ";");
            types.Line("");
        }

        if (self.FirstInto(typesNW, "S", cls.name)) {
            types.Block("struct " + cls.cName + " {");
            self.EmitObjHeader(types);
            let int r = 0;
            while (r < cls.rawFields.Length()) { types.Line(Emitter.TrimC(cls.rawFields.Get(r).c)); r = r + 1; }
            let int f = 0;
            while (f < cls.classFields.Length()) {
                let IrField fl = cls.classFields.Get(f);
                types.Line(self.CT(fl.type) + " " + Mangle.Member(fl.name) + "; /* field */");
                f = f + 1;
            }
            types.End("};");
            types.Blank();
        }

        if (isLib) {
            let int i = 0;
            while (i < cls.methods.Length()) { types.Line(prefix + self.MethodSig(cls.methods.Get(i)) + ";"); i = i + 1; }
            let int o = 0;
            while (o < cls.operators.Length()) { types.Line(prefix + self.OperatorSig(cls.operators.Get(o)) + ";"); o = o + 1; }
            if (self.NeedsDtor(cls)) { types.Line(prefix + self.DtorSig(cls) + ";"); }
            types.Line(prefix + self.AllocatorSig(cls) + ";");
            types.Line("");
        } else {
            fwd.Line(self.AllocatorSig(cls) + ";");
            match (Emitter.InitOf(cls)) { case Some(init) { types.Line(self.MethodSig(init) + ";"); } case None { } }
            if (self.NeedsDtor(cls)) { types.Line(self.DtorSig(cls) + ";"); }
        }

        self.EmitAllocator(cls, isLib ? funcs : types, isLib);

        let int mi = 0;
        while (mi < cls.methods.Length()) {
            let IrFunction mm = cls.methods.Get(mi);
            if (!isLib) { fwd.Line(self.MethodSig(mm) + ";"); }
            self.EmitFunctionBody(mm, funcs, isLib);
            mi = mi + 1;
        }
        let int oi = 0;
        while (oi < cls.operators.Length()) {
            let IrOperator op = cls.operators.Get(oi);
            if (!isLib) { fwd.Line(self.OperatorSig(op) + ";"); }
            self.EmitOperatorBody(op, funcs, isLib);
            oi = oi + 1;
        }
        self.EmitDtor(cls, funcs, isLib);
    }

    /*
     * EmitLibClass - A fully self-contained library class, whole, into the shared header
     */
    void func EmitLibClass(IrClass cls) {
        let CodeWriter w = self.sharedH.w;

        if (self.FirstInto(self.sharedH, "T", cls.name)) {
            w.Line("typedef struct " + cls.cName + " " + cls.cName + ";");
            w.Line("");
        }

        if (self.FirstInto(self.sharedH, "S", cls.name)) {
            w.Block("struct " + cls.cName + " {");
            self.EmitObjHeader(w);
            let int r = 0;
            while (r < cls.rawFields.Length()) { w.Line(cls.rawFields.Get(r).c); r = r + 1; }
            let int f = 0;
            while (f < cls.classFields.Length()) {
                let IrField fl = cls.classFields.Get(f);
                w.Line(self.CT(fl.type) + " " + Mangle.Member(fl.name) + "; /* field */");
                f = f + 1;
            }
            w.End("};");
            w.Blank();
        }

        let int i = 0;
        while (i < cls.methods.Length()) { w.Line("static inline " + self.MethodSig(cls.methods.Get(i)) + ";"); i = i + 1; }
        let int o = 0;
        while (o < cls.operators.Length()) { w.Line("static inline " + self.OperatorSig(cls.operators.Get(o)) + ";"); o = o + 1; }
        if (self.NeedsDtor(cls)) { w.Line("static inline " + self.DtorSig(cls) + ";"); }
        w.Line("static inline " + self.AllocatorSig(cls) + ";");
        w.Line("");

        let int mi = 0;
        while (mi < cls.methods.Length()) { self.EmitFunctionBody(cls.methods.Get(mi), w, true); mi = mi + 1; }
        let int oi = 0;
        while (oi < cls.operators.Length()) { self.EmitOperatorBody(cls.operators.Get(oi), w, true); oi = oi + 1; }
        self.EmitDtor(cls, w, true);
        self.EmitAllocator(cls, w, true);
    }

    /*
     * CanLiveInSharedHeader - True when a library class names nothing from the ARC runtime, so both
     * translation units can carry one copy of it
     */
    public static bool func CanLiveInSharedHeader(IrClass cls) {
        let int i = 0;
        while (i < cls.methods.Length()) {
            let IrFunction mm = cls.methods.Get(i);
            match (mm.body) { case Some(b) { return false; } case None { } }
            if (Emitter.ReferencesRuntime(mm.returnType)) { return false; }
            if (Emitter.MentionsString(mm.native)) { return false; }
            let int j = 0;
            while (j < mm.params.Length()) {
                if (Emitter.ReferencesRuntime(mm.params.Get(j).type)) { return false; }
                j = j + 1;
            }
            i = i + 1;
        }

        let int o = 0;
        while (o < cls.operators.Length()) {
            let IrOperator op = cls.operators.Get(o);
            match (op.body) { case Some(b) { return false; } case None { } }
            if (Emitter.ReferencesRuntime(op.returnType)) { return false; }
            if (Emitter.MentionsString(op.native)) { return false; }
            let int j = 0;
            while (j < op.params.Length()) {
                if (Emitter.ReferencesRuntime(op.params.Get(j).type)) { return false; }
                j = j + 1;
            }
            o = o + 1;
        }

        let int r = 0;
        while (r < cls.rawFields.Length()) {
            if (Emitter.MentionsString(Optional.Some(cls.rawFields.Get(r).c))) { return false; }
            r = r + 1;
        }

        if (cls.fieldInits.Length() > 0) { return false; }

        let int f = 0;
        while (f < cls.classFields.Length()) {
            if (Emitter.ReferencesRuntime(cls.classFields.Get(f).type)) { return false; }
            f = f + 1;
        }
        return true;
    }

    /*
     * ReferencesRuntime - True if the type names an ARC-managed class, or a pointer to one
     */
    public static bool func ReferencesRuntime(IrType ty) {
        match (ty) {
            case IrClassRef(x) { return true; }
            case IrPtrType(p)  { return Emitter.ReferencesRuntime(p.inner); }
            default { return false; }
        }
    }

    /*
     * MentionsString - True if raw C text names the String type or a string runtime helper
     */
    public static bool func MentionsString(Optional[String] c) {
        match (c) {
            case None { return false; }
            case Some(text) { return text.Contains("gata_String") || text.Contains("gata_str_"); }
        }
    }

    // --- Allocators and destructors ----------------------------------------------------------

    /*
     * EmitAllocator - The allocator for one class: raw memory, zeroed, header stamped, field
     * initialisers, then _init
     */
    void func EmitAllocator(IrClass cls, CodeWriter w, bool isLib) {
        let String prefix = isLib ? "static inline " : "";
        let String dtorArg = self.NeedsDtor(cls) ? self.mangler.Dtor(cls.name) : "0";
        w.Block(prefix + self.AllocatorSig(cls) + " {");
        w.Line(cls.cName + "* __o = (" + cls.cName + "*)" + self.Intrinsic(Roles.Alloc()) +
               "(sizeof(" + cls.cName + "));");
        w.Line("*__o = (" + cls.cName + "){0};");
        w.Line(self.Intrinsic(Roles.ObjInit()) + "(__o, " + dtorArg + ");");

        let int f = 0;
        while (f < cls.classFields.Length()) {
            let IrField fl = cls.classFields.Get(f);
            match (cls.fieldInits.Find(fl.name)) {
                case Some(init) {
                    w.Open();
                    w.Put("__o->");
                    w.Put(Mangle.Member(fl.name));
                    w.Put(" = ");
                    self.Write(init, w);
                    w.Put(";");
                    w.Close();
                }
                case None { }
            }
            f = f + 1;
        }

        if (cls.hasInit) {
            match (Emitter.InitOf(cls)) {
                case Some(ctor) {
                    let StringBuilder args = new StringBuilder();
                    args.Append("__o");
                    let int p = 0;
                    while (p < ctor.params.Length()) {
                        args.Append(", ");
                        args.Append(Mangle.Local(ctor.params.Get(p).name));
                        p = p + 1;
                    }
                    w.Line(ctor.cName + "(" + args.ToString() + ");");
                }
                case None { }
            }
        }
        w.Line("return __o;");
        w.End("}");
        w.Blank();
    }

    /*
     * EmitDtor - The destructor, when the class owns managed references or declares a finalizer
     */
    void func EmitDtor(IrClass cls, CodeWriter w, bool isLib) {
        if (!self.NeedsDtor(cls)) { return; }
        let String prefix = isLib ? "static inline " : "";
        w.Block(prefix + self.DtorSig(cls) + " {");
        w.Line(cls.cName + "* self = (" + cls.cName + "*)_vp;");
        match (Emitter.DeinitOf(cls)) { case Some(d) { w.Line(d.cName + "(self);"); } case None { } }
        let int f = 0;
        while (f < cls.classFields.Length()) {
            let IrField fl = cls.classFields.Get(f);
            if (self.IsManaged(fl.type)) {
                w.Line(self.ReleaseCall(fl.type, "self->" + Mangle.Member(fl.name)));
            }
            f = f + 1;
        }
        w.End("}");
        w.Blank();
    }

    /*
     * NeedsDtor - True when the class has managed fields or a user finalizer
     */
    bool func NeedsDtor(IrClass cls) {
        match (Emitter.DeinitOf(cls)) { case Some(d) { return true; } case None { } }
        let int i = 0;
        while (i < cls.classFields.Length()) {
            if (self.IsManaged(cls.classFields.Get(i).type)) { return true; }
            i = i + 1;
        }
        return false;
    }

    public static Optional[IrFunction] func DeinitOf(IrClass cls) {
        let int i = 0;
        while (i < cls.methods.Length()) {
            if (cls.methods.Get(i).name == Lifecycle.Deinit()) { return Optional.Some(cls.methods.Get(i)); }
            i = i + 1;
        }
        return Optional[IrFunction].None();
    }

    public static Optional[IrFunction] func InitOf(IrClass cls) {
        let int i = 0;
        while (i < cls.methods.Length()) {
            if (cls.methods.Get(i).name == Lifecycle.Init()) { return Optional.Some(cls.methods.Get(i)); }
            i = i + 1;
        }
        return Optional[IrFunction].None();
    }

    /*
     * EmitObjHeader - The ARC header, always the first struct member, so any managed pointer
     * aliases its header at offset 0
     */
    void func EmitObjHeader(CodeWriter w) {
        w.Line(self.Intrinsic(Roles.ObjHeader()) + " __gata_obj; /* arc header */");
    }

    // --- Signatures --------------------------------------------------------------------------

    /*
     * ParamCType - A parameter's C type, with one more level of indirection for a ref parameter
     */
    String func ParamCType(IrParam p) {
        return p.isRef ? (self.CT(p.type) + "*") : self.CT(p.type);
    }

    /*
     * MethodSig - The full C signature of a method, including the implicit self parameter
     */
    String func MethodSig(IrFunction mm) {
        let String ret = mm.isThrows ? self.CT(self.t.Result(mm.returnType)) : self.CT(mm.returnType);
        let StringBuilder sb = new StringBuilder();
        sb.Append(ret);
        sb.Append(" ");
        sb.Append(mm.cName);
        sb.Append("(");

        let bool hasParams = false;
        if (!mm.isStatic) {
            match (mm.ownerClass) {
                case Some(owner) { sb.Append(self.mangler.Class(owner)); sb.Append("* self"); hasParams = true; }
                case None { }
            }
        }
        let int i = 0;
        while (i < mm.params.Length()) {
            if (hasParams) { sb.Append(", "); }
            let IrParam p = mm.params.Get(i);
            sb.Append(self.ParamCType(p));
            sb.Append(" ");
            sb.Append(Mangle.Local(p.name));
            hasParams = true;
            i = i + 1;
        }
        sb.Append(")");
        return sb.ToString();
    }

    /*
     * OperatorSig - The full C signature of an operator overload, with a self parameter for every
     * one except a static 'as' - a factory, where self does not exist yet
     */
    public String func OperatorSig(IrOperator o) {
        let StringBuilder sb = new StringBuilder();
        sb.Append(self.CT(o.returnType));
        sb.Append(" ");
        sb.Append(o.cName);
        sb.Append("(");
        let bool needsComma = false;
        if (!o.isStatic) {
            sb.Append(self.mangler.Class(o.ownerClass));
            sb.Append("* self");
            needsComma = true;
        }
        let int i = 0;
        while (i < o.params.Length()) {
            let IrParam p = o.params.Get(i);
            if (needsComma) { sb.Append(", "); }
            sb.Append(self.ParamCType(p));
            sb.Append(" ");
            sb.Append(Mangle.Local(p.name));
            needsComma = true;
            i = i + 1;
        }
        sb.Append(")");
        return sb.ToString();
    }

    /*
     * AllocatorSig - The allocator's C signature, threading through any constructor parameters
     */
    String func AllocatorSig(IrClass cls) {
        let StringBuilder sb = new StringBuilder();
        sb.Append(cls.cName);
        sb.Append("* ");
        sb.Append(self.mangler.Allocator(cls.name));
        sb.Append("(");
        let bool wrote = false;
        match (Emitter.InitOf(cls)) {
            case Some(init) {
                let int i = 0;
                while (i < init.params.Length()) {
                    if (i > 0) { sb.Append(", "); }
                    let IrParam p = init.params.Get(i);
                    sb.Append(self.ParamCType(p));
                    sb.Append(" ");
                    sb.Append(Mangle.Local(p.name));
                    wrote = true;
                    i = i + 1;
                }
            }
            case None { }
        }
        if (!wrote) { sb.Append("void"); }
        sb.Append(")");
        return sb.ToString();
    }

    String func DtorSig(IrClass cls) { return "void " + self.mangler.Dtor(cls.name) + "(void* _vp)"; }

    /*
     * FuncSig - The full C signature of a free function
     */
    String func FuncSig(IrFunction fn) {
        let String ret = fn.isThrows ? self.CT(self.t.Result(fn.returnType)) : self.CT(fn.returnType);
        let StringBuilder sb = new StringBuilder();
        sb.Append(ret);
        sb.Append(" ");
        sb.Append(fn.cName);
        sb.Append("(");
        let int i = 0;
        while (i < fn.params.Length()) {
            if (i > 0) { sb.Append(", "); }
            let IrParam p = fn.params.Get(i);
            sb.Append(self.ParamCType(p));
            sb.Append(" ");
            sb.Append(Mangle.Local(p.name));
            i = i + 1;
        }
        sb.Append(")");
        return sb.ToString();
    }

    // --- Free functions ----------------------------------------------------------------------

    /*
     * EmitFreeFunc - A free function into the units its flags call for: an entry function into its
     * own inRealm, which is what lets a Hosted user entry become program.c's main(); a library
     * function static-inline into both; anything else into its inRealm.
     */
    void func EmitFreeFunc(IrFunction fn) {
        if (fn.isEntry) {
            let CodeWriter entryFwd   = fn.vis == Visibility.User ? self.uFwd.w  : self.kFwd.w;
            let CodeWriter entryFuncs = fn.vis == Visibility.User ? self.uFunc.w : self.kFuncs.w;
            entryFwd.Line("void " + fn.cName + "(void);");
            entryFuncs.Line("void " + fn.cName + "(void)");
            match (fn.body) { case Some(b) { self.EmitBlock(b, entryFuncs); } case None { } }
            entryFuncs.Line("");
            return;
        }

        if (fn.isLib) {
            self.kFwd.w.Line("static inline " + self.FuncSig(fn) + ";");
            self.uFwd.w.Line("static inline " + self.FuncSig(fn) + ";");
            match (fn.body) {
                case None {
                    self.EmitLibFreeFuncNative(fn, self.kFuncs.w);
                    self.EmitLibFreeFuncNative(fn, self.uFunc.w);
                }
                case Some(b) {
                    self.kFuncs.w.Line("static inline " + self.FuncSig(fn));
                    self.EmitBlock(b, self.kFuncs.w);
                    self.kFuncs.w.Line("");
                    self.uFunc.w.Line("static inline " + self.FuncSig(fn));
                    self.EmitBlock(b, self.uFunc.w);
                    self.uFunc.w.Line("");
                }
            }
            return;
        }

        let bool isKernel = fn.vis == Visibility.Kernel;
        let CodeWriter fwd   = isKernel ? self.kFwd.w   : self.uFwd.w;
        let CodeWriter funcs = isKernel ? self.kFuncs.w : self.uFunc.w;
        fwd.Line(self.FuncSig(fn) + ";");
        match (fn.body) {
            case None {
                let String body = Emitter.TrimC(Emitter.OrEmpty(fn.native));
                funcs.Line(self.FuncSig(fn));
                funcs.Braces();
                funcs.Line(body);
                funcs.EndBrace();
                funcs.Blank();
            }
            case Some(b) {
                funcs.Line(self.FuncSig(fn));
                self.EmitBlock(b, funcs);
                funcs.Line("");
            }
        }
    }

    /*
     * OrEmpty - An optional raw C body, or the empty string
     */
    public static String func OrEmpty(Optional[String] s) {
        match (s) { case Some(x) { return x; } case None { return ""; } }
    }

    void func EmitLibFreeFuncNative(IrFunction fn, CodeWriter w) {
        let String body = Emitter.TrimC(Emitter.OrEmpty(fn.native));
        w.Line("static inline " + self.FuncSig(fn));
        w.Braces();
        w.Line(body);
        w.EndBrace();
        w.Blank();
    }

    /*
     * EmitProcessState - A process's variables become statics in its inRealm's translation unit, plus
     * the generated function that assigns them and the gate its threads race on
     */
    void func EmitProcessState(IrProcess proc) {
        if (proc.state.Length() == 0) { return; }

        let bool toKernelTU = false;
        match (proc.stateInit) { case Some(si) { toKernelTU = si.vis == Visibility.Kernel; } case None { } }
        let CodeWriter types = toKernelTU ? self.kTypes.w : self.uTypes.w;

        let int i = 0;
        while (i < proc.state.Length()) {
            let IrProcessVar v = proc.state.Get(i);
            types.Line("static " + self.CT(v.type) + " " + v.cName + ";");
            i = i + 1;
        }
        match (proc.stateInit) {
            case Some(si) { types.Line("static volatile int " + Emitter.GateName(si) + " = 0;"); }
            case None { }
        }
        types.Blank();

        match (proc.stateInit) {
            case None { }
            case Some(init) {
                match (init.body) {
                    case None { }
                    case Some(body) {
                        let CodeWriter w = toKernelTU ? self.kFuncs.w : self.uFunc.w;
                        w.Line("static void " + init.cName + "(void)");
                        self.EmitBlock(body, w);
                        w.Blank();
                        w.Line("static void " + Emitter.EnterName(init) + "(void)");
                        w.Braces();
                        w.Line("int _st = 0;");
                        w.Line("if (__atomic_compare_exchange_n(&" + Emitter.GateName(init) + ", &_st, 1, 0, " +
                               "__ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE))");
                        w.Braces();
                        w.Line(init.cName + "();");
                        w.Line("__atomic_store_n(&" + Emitter.GateName(init) + ", 2, __ATOMIC_RELEASE);");
                        w.Line("return;");
                        w.EndBrace();
                        w.Line("// Another thread got there first; wait for it to finish publishing.");
                        w.Line("while (__atomic_load_n(&" + Emitter.GateName(init) + ", __ATOMIC_ACQUIRE) != 2) { }");
                        w.EndBrace();
                        w.Blank();
                    }
                }
            }
        }
    }

    /*
     * GateName - The gate a process's threads race on to decide which one initialises its state
     */
    public static String func GateName(IrFunction stateInit) { return stateInit.cName + "_gate"; }

    /*
     * EnterName - The function each of a process's threads calls before its own body
     */
    public static String func EnterName(IrFunction stateInit) { return stateInit.cName + "_enter"; }

    /*
     * EmitThread - A thread's entry function into its inRealm writer, with a forward declaration
     * alongside it
     */
    void func EmitThread(IrThread th, IrProcess owner) {
        match (th.entryFunc) {
            case None { }
            case Some(entryFn) {
                let bool toKernelTU = entryFn.vis == Visibility.Kernel;
                let CodeWriter fwd = toKernelTU ? self.kFwd.w : self.uFwd.w;
                fwd.Line("void " + entryFn.cName + "(void* arg);");
                let CodeWriter w = toKernelTU ? self.kFuncs.w : self.uFunc.w;
                w.Line("void " + entryFn.cName + "(void* arg)");
                w.Braces();
                match (owner.stateInit) { case Some(si) { w.Line(Emitter.EnterName(si) + "();"); } case None { } }
                match (entryFn.body) {
                    case Some(b) {
                        let int i = 0;
                        while (i < b.stmts.Length()) { self.EmitStmt(b.stmts.Get(i), w); i = i + 1; }
                    }
                    case None { }
                }
                w.EndBrace();
                w.Blank();
            }
        }
    }

    // --- Blocks and statements ---------------------------------------------------------------

    /*
     * EmitFunctionBody - A method body, native C text or a lowered IR block
     */
    void func EmitFunctionBody(IrFunction mm, CodeWriter w, bool isLib) {
        let String prefix = isLib ? "static inline " : "";
        match (mm.body) {
            case None {
                let String body = Emitter.TrimC(Emitter.OrEmpty(mm.native));
                w.Line(prefix + self.MethodSig(mm));
                w.Braces();
                w.Line(body);
                w.EndBrace();
                w.Blank();
            }
            case Some(b) {
                w.Line(prefix + self.MethodSig(mm));
                self.EmitBlock(b, w);
                w.Line("");
            }
        }
    }

    /*
     * EmitOperatorBody - An operator body, native C text or a lowered IR block
     */
    void func EmitOperatorBody(IrOperator o, CodeWriter w, bool isLib) {
        let String prefix = isLib ? "static inline " : "";
        match (o.body) {
            case None {
                let String body = Emitter.TrimC(Emitter.OrEmpty(o.native));
                w.Line(prefix + self.OperatorSig(o));
                w.Braces();
                w.Line(body);
                w.EndBrace();
                w.Blank();
            }
            case Some(b) {
                w.Line(prefix + self.OperatorSig(o));
                self.EmitBlock(b, w);
                w.Line("");
            }
        }
    }

    /*
     * EmitBlock - Every statement of a block, inside a C brace pair
     */
    void func EmitBlock(IrBlock b, CodeWriter w) {
        w.Braces();
        let int i = 0;
        while (i < b.stmts.Length()) { self.EmitStmt(b.stmts.Get(i), w); i = i + 1; }
        w.EndBrace();
    }

    /*
     * EmitStmt - One IR statement to C
     */
    void func EmitStmt(IrStmt s, CodeWriter w) {
        match (s) {
            case IrGoto(g)        { w.Line("goto " + g.label + ";"); }
            case IrLabel(l)       { w.Line(l.name + ":;"); }
            case IrNativeStmt(ns) { w.Line(Emitter.TrimC(ns.c)); }
            case IrBlock(b)       { self.EmitBlock(b, w); }
            case IrUnsafeBlock(u) { self.EmitBlock(u.body, w); }
            case IrDeclVar(dv)    { self.EmitDeclVar(dv, w); }
            case IrAssign(a) {
                w.Open();
                self.WriteAssign(a, w);
                w.Put(";");
                w.Close();
            }
            case IrExprStmt(es) {
                w.Open();
                self.Write(es.expr, w);
                w.Put(";");
                w.Close();
            }
            case IrReturn(rs) {
                match (rs.value) {
                    case None { w.Line("return;"); }
                    case Some(v) {
                        w.Open();
                        w.Put("return ");
                        self.Write(v, w);
                        w.Put(";");
                        w.Close();
                    }
                }
            }
            case IrBreak(x)    { w.Line("break;"); }
            case IrContinue(x) { w.Line("continue;"); }
            case IrDebug(d)    { w.Line(self.m.symbols.FloorName(Roles.EnvDebug()) + "(" + Emitter.NoTrigraphs(d.raw) + ");"); }
            case IrPanic(p)    { w.Line(self.m.symbols.FloorName(Roles.EnvPanic()) + "(" + Emitter.NoTrigraphs(p.raw) + ");"); }
            case IrIf(ifs)     { self.EmitIf(ifs, w); }
            case IrWhile(ws) {
                w.Open();
                w.Put("while (");
                self.WriteCond(ws.cond, w);
                w.Put(")");
                w.Close();
                self.EmitBlock(ws.body, w);
            }
            case IrFor(fr)     { self.EmitFor(fr, w); }
            // Desugar and Ownership removed match, switch, try and defer before this pass ran.
            default { }
        }
    }

    /*
     * EmitDeclVar - A local declaration, with a default when nothing initialises it
     */
    void func EmitDeclVar(IrDeclVar dv, CodeWriter w) {
        w.Open();
        self.WriteDecl(dv, w, true);
        w.Put(";");
        w.Close();
    }

    /*
     * WriteDecl - A declaration without its terminator. A statement declaration with no initialiser
     * still takes a default, so no local is read before it is written; a for-init does not, which is
     * the only reason this is a parameter.
     */
    void func WriteDecl(IrDeclVar dv, CodeWriter w, bool withDefault) {
        w.Put(self.CT(dv.type));
        w.Put(" ");
        w.Put(Mangle.Local(dv.name));
        match (dv.init) {
            case Some(init) { w.Put(" = "); self.Write(init, w); return; }
            case None { }
        }
        if (!withDefault) { return; }
        let bool aggregate = false;
        match (dv.type) {
            case IrArrayType(x) { aggregate = true; }
            case IrUnionType(x) { aggregate = true; }
            default { }
        }
        if (aggregate) { w.Put(" = {0}"); return; }
        if (self.IsManaged(dv.type)) { w.Put(" = NULL"); }
    }

    /*
     * WriteAssign - An assignment without its terminator
     */
    void func WriteAssign(IrAssign a, CodeWriter w) {
        self.Write(a.target, w);
        w.Put(" ");
        w.Put(Ops.AssignSym(a.op));
        w.Put(" ");
        self.Write(a.value, w);
    }

    /*
     * EmitIf - An if with an optional else
     */
    void func EmitIf(IrIf ifs, CodeWriter w) {
        w.Open();
        w.Put("if (");
        self.WriteCond(ifs.cond, w);
        w.Put(")");
        w.Close();
        self.EmitBlock(ifs.then, w);
        match (ifs.otherwise) {
            case Some(e) { w.Line("else"); self.EmitBlock(e, w); }
            case None { }
        }
    }

    /*
     * EmitFor - A C-style for loop
     */
    void func EmitFor(IrFor fr, CodeWriter w) {
        w.Open();
        w.Put("for (");
        match (fr.init) {
            case Some(istmt) {
                match (istmt) {
                    case IrDeclVar(dv)  { self.WriteDecl(dv, w, false); }
                    case IrAssign(aa)   { self.WriteAssign(aa, w); }
                    case IrExprStmt(e)  { self.Write(e.expr, w); }
                    default { }
                }
            }
            case None { }
        }
        w.Put("; ");
        match (fr.cond) { case Some(c) { self.WriteCond(c, w); } case None { } }
        w.Put("; ");
        match (fr.step) {
            case Some(sstmt) {
                match (sstmt) {
                    case IrAssign(sa)  { self.WriteAssign(sa, w); }
                    case IrExprStmt(e) { self.Write(e.expr, w); }
                    default { }
                }
            }
            case None { }
        }
        w.Put(")");
        w.Close();
        self.EmitBlock(fr.body, w);
    }

    // --- Expressions -------------------------------------------------------------------------

    /*
     * Write - One IR expression to C. Every node kind must be fully resolved before it gets here.
     */
    void func Write(IrExpr e, CodeWriter w) {
        match (e) {
            case IrLitInt(li) {
                match (li.cText) {
                    case Some(text) { w.Put(text); }
                    case None { w.Put(Long.ToString(li.value)); }
                }
            }
            case IrLitChar(lc)  { w.Put(Int.ToString(lc.codepoint)); }
            case IrLitFloat(lf) { w.Put(lf.raw); }
            case IrLitBool(lb)  { w.Put(lb.value ? "true" : "false"); }
            case IrLitString(ls) {
                w.Put("GATA_STRLIT(");
                w.Put(self.stringStruct);
                w.Put(", ");
                w.Put(Emitter.NoTrigraphs(ls.raw));
                w.Put(")");
            }
            case IrLitNull(x)   { w.Put("NULL"); }
            case IrEnumConst(ec){ w.Put(self.mangler.EnumMember(ec.enumName, ec.member)); }
            case IrVar(v) {
                if (v.isRef) { w.Put("(*"); w.Put(Mangle.Local(v.name)); w.Put(")"); }
                else { w.Put(Mangle.Local(v.name)); }
            }
            case IrGlobal(g)    { w.Put(g.cName); }
            case IrSelfExpr(x)  { w.Put("self"); }

            case IrFieldLoad(fl) {
                self.Write(fl.obj, w);
                let bool byValue = false;
                match (Exprs2.TypeOf(fl.obj)) {
                    case IrUnionType(x)  { byValue = true; }
                    case IrResultType(x) { byValue = true; }
                    default { }
                }
                w.Put(byValue ? "." : "->");
                w.Put(Mangle.Member(fl.field));
            }

            case IrIndex(ix) {
                let bool boxed = false;
                match (Exprs2.TypeOf(ix.obj)) { case IrArrayType(x) { boxed = true; } default { } }
                if (boxed) { w.Put("("); }
                self.Write(ix.obj, w);
                w.Put(boxed ? ")._[" : "[");
                self.Write(ix.idx, w);
                w.Put("]");
            }

            case IrStaticCall(sc) {
                w.Put(sc.cName);
                w.Put("(");
                self.WriteArgs(sc.args, w, Optional[IrExpr].None());
                w.Put(")");
            }

            case IrInstanceCall(ic) {
                w.Put(ic.cName);
                w.Put("(");
                self.WriteArgs(ic.args, w, Optional.Some(ic.recv));
                w.Put(")");
            }

            case IrBinOp(bo) {
                let Optional[String] narrowed = self.NarrowTo(bo.type);
                match (narrowed) { case Some(n) { w.Put("(("); w.Put(n); w.Put(")"); } case None { } }
                w.Put("(");
                self.Write(bo.left, w);
                w.Put(" ");
                w.Put(Ops.BinSym(bo.op));
                w.Put(" ");
                self.Write(bo.right, w);
                w.Put(")");
                match (narrowed) { case Some(n) { w.Put(")"); } case None { } }
            }

            case IrTernary(tn) {
                w.Put("(");
                self.Write(tn.cond, w);
                w.Put(" ? ");
                self.Write(tn.then, w);
                w.Put(" : ");
                self.Write(tn.otherwise, w);
                w.Put(")");
            }

            case IrUnaryOp(uo) {
                let Optional[String] narrowed = self.NarrowTo(uo.type);
                match (narrowed) { case Some(n) { w.Put("(("); w.Put(n); w.Put(")"); } case None { } }
                w.Put("(");
                w.Put(Ops.UnSym(uo.op));
                self.Write(uo.operand, w);
                w.Put(")");
                match (narrowed) { case Some(n) { w.Put(")"); } case None { } }
            }

            case IrPostfix(pf) {
                w.Put("(");
                self.Write(pf.operand, w);
                w.Put(Ops.PostSym(pf.op));
                w.Put(")");
            }

            case IrCast(c) {
                w.Put("((");
                w.Put(self.CT(c.to));
                w.Put(")");
                self.Write(c.value, w);
                w.Put(")");
            }

            case IrNew(n) {
                w.Put(self.mangler.Allocator(n.className));
                w.Put("(");
                self.WriteArgs(n.args, w, Optional[IrExpr].None());
                w.Put(")");
            }

            case IrArrayLit(al) {
                w.Put("(");
                w.Put(self.CT(al.arrType));
                w.Put("){ { ");
                self.WriteArgs(al.elems, w, Optional[IrExpr].None());
                w.Put(" } }");
            }

            case IrAddrOf(ao) {
                w.Put("(&");
                self.Write(ao.target, w);
                w.Put(")");
            }

            case IrDeref(dr) {
                w.Put("(*");
                self.Write(dr.ptr, w);
                w.Put(")");
            }

            case IrSizeof(so) {
                w.Put("sizeof(");
                w.Put(self.CT(so.of));
                w.Put(")");
            }

            case IrStructLit(sl) {
                w.Put("(");
                w.Put(self.CT(sl.structType));
                w.Put("){ ");
                let int i = 0;
                while (i < sl.structFields.Length()) {
                    if (i > 0) { w.Put(", "); }
                    w.Put(".");
                    w.Put(sl.structFields.Get(i).field);
                    w.Put(" = ");
                    self.Write(sl.structFields.Get(i).value, w);
                    i = i + 1;
                }
                w.Put(" }");
            }

            case IrDefault(df) {
                let bool aggregate = Emitter.IsAggregate(df.of);
                w.Put(aggregate ? "(" : "((");
                w.Put(self.CT(df.of));
                w.Put(aggregate ? "){ 0 }" : ")0)");
            }

            case IrFuncRef(fr) { w.Put(fr.cName); }

            case IrIndirectCall(ic2) {
                w.Put("(");
                self.Write(ic2.target, w);
                w.Put(")(");
                self.WriteArgs(ic2.args, w, Optional[IrExpr].None());
                w.Put(")");
            }

            case IrUnionConstruct(uc) { self.WriteUnionConstruct(uc, w); }

            case IrUnionField(uf) {
                self.Write(uf.target, w);
                w.Put(".payload.");
                w.Put(self.UnionVariantName(Exprs2.TypeOf(uf.target), uf.variantIndex));
                w.Put(".");
                w.Put(Mangle.Member(uf.field));
            }

            default { }
        }
    }

    /*
     * WriteCond - A bool-typed binary operator in condition position needs no narrowing cast and no
     * parentheses of its own; anything else writes normally
     */
    void func WriteCond(IrExpr e, CodeWriter w) {
        match (e) {
            case IrBinOp(bo) {
                let bool isBool = false;
                match (bo.type) { case IrPrimType(p) { isBool = p.cName == "bool"; } default { } }
                if (isBool) {
                    self.Write(bo.left, w);
                    w.Put(" ");
                    w.Put(Ops.BinSym(bo.op));
                    w.Put(" ");
                    self.Write(bo.right, w);
                    return;
                }
            }
            default { }
        }
        self.Write(e, w);
    }

    /*
     * NarrowTo - The C type an operator result is pinned to, so the arithmetic happens in the domain
     * Gata says rather than the one C's own promotions would pick. None when the type is boolean or
     * not numeric and C already agrees.
     */
    Optional[String] func NarrowTo(IrType ty) {
        match (ty) {
            case IrPrimType(p) {
                if (Types.IsNumeric(ty) && p.cName != "bool") { return Optional.Some(self.CT(ty)); }
                return Optional[String].None();
            }
            default { return Optional[String].None(); }
        }
    }

    /*
     * WriteArgs - A comma-separated argument list, with an optional leading receiver
     */
    void func WriteArgs(List[IrExpr] args, CodeWriter w, Optional[IrExpr] receiver) {
        let bool hasRecv = false;
        match (receiver) { case Some(r) { self.Write(r, w); hasRecv = true; } case None { } }
        let int i = 0;
        while (i < args.Length()) {
            if (hasRecv || i > 0) { w.Put(", "); }
            self.Write(args.Get(i), w);
            i = i + 1;
        }
    }

    /*
     * WriteUnionConstruct - The tag plus the payload compound literal
     */
    void func WriteUnionConstruct(IrUnionConstruct uc, CodeWriter w) {
        let String uname = "";
        match (uc.type) { case IrUnionType(ut) { uname = ut.name; } default { } }
        match (self.m.UnionNamed(uname)) {
            case None { w.Put("0"); }
            case Some(un) {
                let IrUnionVariant variant = un.variants.Get(uc.variantIndex);
                w.Put("(");
                w.Put(self.CT(uc.type));
                w.Put("){ .__tag = ");
                w.Put(Int.ToString(uc.variantIndex));
                if (variant.variantFields.Length() == 0) { w.Put(" }"); return; }

                w.Put(", .payload.");
                w.Put(Mangle.Member(variant.name));
                w.Put(" = { ");
                let int n = variant.variantFields.Length();
                if (uc.args.Length() < n) { n = uc.args.Length(); }
                let int i = 0;
                while (i < n) {
                    if (i > 0) { w.Put(", "); }
                    w.Put(".");
                    w.Put(Mangle.Member(variant.variantFields.Get(i).name));
                    w.Put(" = ");
                    self.Write(uc.args.Get(i), w);
                    i = i + 1;
                }
                w.Put(" } }");
            }
        }
    }

    /*
     * UnionVariantName - The struct field name for a union variant at the given index
     */
    String func UnionVariantName(IrType unionType, int idx) {
        match (unionType) {
            case IrUnionType(ut) {
                match (self.m.UnionNamed(ut.name)) {
                    case Some(un) { return Mangle.Member(un.variants.Get(idx).name); }
                    case None { return "?"; }
                }
            }
            default { return "?"; }
        }
    }

    // --- Intrinsic prototypes ----------------------------------------------------------------

    /*
     * EmitIntrinsicProtos - A static-inline prototype in the shared header for every free function
     * carrying an @intrinsic role binding, so any unit can call the runtime through it
     */
    void func EmitIntrinsicProtos() {
        let bool any = false;
        let int i = 0;
        while (i < self.m.freeFunctions.Length()) {
            let IrFunction fn = self.m.freeFunctions.Get(i);
            let bool hasIntrinsic = false;
            let int j = 0;
            while (j < fn.annotations.Length()) {
                match (fn.annotations.Get(j)) {
                    case IntrinsicAnnotation(x) { hasIntrinsic = true; }
                    default { }
                }
                j = j + 1;
            }
            if (hasIntrinsic && self.FirstInto(self.sharedH, "P", fn.cName)) {
                self.sharedH.w.Line("static inline " + self.FuncSig(fn) + ";");
                any = true;
            }
            i = i + 1;
        }
        if (any) { self.sharedH.w.Line(""); }
    }

    // --- Utilities ---------------------------------------------------------------------------

    /*
     * NoTrigraphs - Escapes '?' inside a string literal handed to C, so '??/' and friends are not
     * read as trigraphs
     */
    public static String func NoTrigraphs(String raw) {
        if (raw.Contains("?")) { return raw.Replace("?", "\\?"); }
        return raw;
    }

    /*
     * TrimC - Strips the uniform leading indentation from raw C text, so an embedded native body
     * re-indents correctly at whatever depth the writer is currently at
     */
    public static String func TrimC(String raw) {
        if (Emitter.IsBlank(raw)) { return ""; }

        let List[String] lines = Emitter.SplitLines(raw);

        let int minI = 2147483647;
        let int i = 0;
        while (i < lines.Length()) {
            let String line = lines.Get(i);
            if (!Emitter.IsBlank(line)) {
                let int k = 0;
                while (k < line.Length() && (line.CharAt(k) == ' ' || line.CharAt(k) == '\t')) { k = k + 1; }
                if (k < minI) { minI = k; }
            }
            i = i + 1;
        }
        if (minI == 2147483647) { minI = 0; }

        let StringBuilder sb = new StringBuilder();
        let int j = 0;
        while (j < lines.Length()) {
            let String line = lines.Get(j);
            if (Emitter.IsBlank(line)) {
                sb.Append("\n");
            } else {
                let String sliced = line.Length() > minI ? line.Substring(minI, line.Length() - minI) : line;
                sb.Append(sliced);
                sb.Append("\n");
            }
            j = j + 1;
        }

        let String out = sb.ToString();
        let int end = out.Length();
        while (end > 0 && Emitter.IsSpaceChar(out.CharAt(end - 1))) { end = end - 1; }
        return out.Substring(0, end);
    }

    /*
     * SplitLines - Raw text as lines, each with any trailing carriage return removed. C# walks the
     * span with IndexOf('\n'); the shape is the same, materialised.
     */
    public static List[String] func SplitLines(String raw) {
        let List[String] lines = new List[String]();
        let int offset = 0;
        while (offset < raw.Length()) {
            let int next = raw.IndexOf("\n", offset);
            let String line = "";
            if (next >= 0) {
                line = raw.Substring(offset, next - offset);
                offset = next + 1;
            } else {
                line = raw.Substring(offset, raw.Length() - offset);
                offset = raw.Length();
            }
            lines.Add(CodeWriter.TrimCR(line));
        }
        return lines;
    }

    public static bool func IsSpaceChar(char c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r';
    }

    /*
     * IsBlank - True for text that is empty or entirely whitespace
     */
    public static bool func IsBlank(String s) {
        let int i = 0;
        while (i < s.Length()) {
            if (!Emitter.IsSpaceChar(s.CharAt(i))) { return false; }
            i = i + 1;
        }
        return true;
    }

    /*
     * IsAggregate - The IR types that lower to a C struct rather than a scalar. Fixed arrays,
     * unions and throws Results are all struct-wrapped by this pass; a class reference is a pointer
     * and everything else is a primitive.
     */
    public static bool func IsAggregate(IrType ty) {
        match (ty) {
            case IrArrayType(x)  { return true; }
            case IrUnionType(x)  { return true; }
            case IrResultType(x) { return true; }
            default { return false; }
        }
    }

    /*
     * Intrinsic - The C symbol bound to a runtime role. Unlike Ownership's silent fallback this one
     * reports, because by emission time a missing role means the output would not link.
     */
    String func Intrinsic(String role) {
        match (self.m.symbols.IntrinsicOrNull(role)) {
            case Some(n) { return n; }
            case None {
                if (self.missingRoles.AddNew(role)) {
                    self.diag.Error(Codes.MissingIntrinsic(), "<runtime>", TS.NoneSpan(),
                                    "no libgata symbol provides @intrinsic(" + role + ")");
                }
                return "/*MISSING_INTRINSIC:" + role + "*/";
            }
        }
    }
}
