/*
 * SymbolCollector.g - every declaration in the build, registered before anything is typed
 *
 * Ports Appa/src/Semantics/SymbolCollector.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "src/Diagnostics/TextSpan.g";
import "src/Diagnostics/Diagnostic.g";
import "src/Syntax/Ast.g";
import "src/Syntax/NativeC.g";
import "src/Semantics/ScopeBinder.g";
import "src/Semantics/SignatureKey.g";
import "src/Semantics/SymbolTable.g";
import "src/Semantics/TypeResolver.g";
import "src/Backend/Mangler.g";

/*
 * What pass 1 produces.
 */
class CollectionResult {
    public SymbolTable sym;
    public StringSet hasInit;
    public StringSet preDefinedStructs;
    public StringSet opaqueFieldClasses;
    public DiagnosticBag diag;

    func _init(SymbolTable sym, StringSet hasInit, StringSet preDefinedStructs,
               StringSet opaqueFieldClasses, DiagnosticBag diag) {
        self.sym = sym;
        self.hasInit = hasInit;
        self.preDefinedStructs = preDefinedStructs;
        self.opaqueFieldClasses = opaqueFieldClasses;
        self.diag = diag;
    }
}

/*
 * Walks every parsed program and fills a SymbolTable. One instance per build; call Collect once.
 */
class SymbolCollector {
    DiagnosticBag diag;
    Mangler mangler;

    SymbolTable sym;
    StringSet hasInit;
    StringSet declaredTypes;
    StringSet preDefinedStructs;
    StringSet opaqueFieldClasses;
    StringSet declaredFieldNames;
    StringSet declaredMethodNames; 
    StringSet declaredMethodSigs;
    StringSet declaredAsConversions;
    StringSet declaredOperatorSigs;
    StringSet declaredFuncs;
    StringSet declaredFuncSigs;
    StringSet declaredPrivateFuncSigs;
    StringSet externFuncs;
    StringMap[String] externShapes;

    func _init(DiagnosticBag diag, Mangler mangler) {
        self.diag = diag;
        self.mangler = mangler;
        self.sym = new SymbolTable();
        self.hasInit = new StringSet();
        self.declaredTypes = new StringSet();
        self.preDefinedStructs = new StringSet();
        self.opaqueFieldClasses = new StringSet();
        self.declaredFieldNames = new StringSet();
        self.declaredMethodNames = new StringSet();
        self.declaredMethodSigs = new StringSet();
        self.declaredAsConversions = new StringSet();
        self.declaredOperatorSigs = new StringSet();
        self.declaredFuncs = new StringSet();
        self.declaredFuncSigs = new StringSet();
        self.declaredPrivateFuncSigs = new StringSet();
        self.externFuncs = new StringSet();
        self.externShapes = new StringMap[String]();
    }

    /*
     * Collect - Runs pass 1 over every program and returns the populated symbol table
     */
    public CollectionResult func Collect(List[ProgramFile] programs) {
        let int p = 0;
        while (p < programs.Length()) {
            let ProgramFile pf = programs.Get(p);
            let int i = 0;
            while (i < pf.prog.items.Length()) {
                self.P1Top(pf.prog.items.Get(i), pf.path);
                i = i + 1;
            }
            p = p + 1;
        }
        self.sym.AssignCNames(self.mangler);

        return new CollectionResult(self.sym, self.hasInit, self.preDefinedStructs, self.opaqueFieldClasses, self.diag);
    }

    /*
     * P1Top - Dispatches one top-level item.
     */
    void func P1Top(TopLevel item, String file) {
        match (item) {
            case NativeBlock(nb) {
                let int i = 0;
                while (i < nb.annotations.Length()) {
                    match (nb.annotations.Get(i)) {
                        case IntrinsicAnnotation(ia) {
                            self.diag.Error(Codes.WrongAnnotationKind(), file, nb.span,
                                "only '@preamble' is valid here, not '@intrinsic'");
                        }
                        default { }
                    }
                    i = i + 1;
                }
                self.ScanNativeForStructs(nb.body.c);
            }
            case NativeTypeDecl(nd) { self.P1NativeType(nd, file); }
            case ClassDecl(cd) { self.P1Class(cd, file); }
            case ContextDecl(ctx) {
                let int i = 0;
                while (i < ctx.items.Length()) { self.P1Top(ctx.items.Get(i), file); i = i + 1; }
            }
            case ProcessDecl(proc) {
                let int i = 0;
                while (i < proc.items.Length()) { self.P1Top(proc.items.Get(i), file); i = i + 1; }
            }
            case FuncDecl(fd) { self.P1Func(fd, file); }
            case ExternFuncDecl(ed) { self.P1Extern(ed, file); }
            case EnumDecl(ed) {
                self.DeclareType(ed.name, file, ed.span);
                let List[String] names = new List[String]();
                let int i = 0;
                while (i < ed.members.Length()) {
                    names.Add(ed.members.Get(i).name);
                    i = i + 1;
                }
                self.sym.RegisterEnum(ed.name, names);
            }
            case UnionDecl(ud) {
                self.DeclareType(ud.name, file, ud.span);
                self.sym.RegisterUnion(ud.name, ud.variants);
            }
            default { }
        }
    }

    /*
     * DeclareType - Claims a type name for the build, reporting a duplicate.
     */
    void func DeclareType(String name, String file, TextSpan span) {
        if (!self.declaredTypes.AddNew(name)) {
            self.diag.Error(Codes.DuplicateName(), file, span,
                "type '" + self.mangler.DisplayName(name) + "' is already declared");
        }
    }

    /*
     * BindIntrinsics - Binds any @intrinsic(role) or @builtin(name) on a declaration to the C name
     * the declaration is emitted under, validating the role and rejecting a double bind.
     */
    void func BindIntrinsics(List[Annotation] anns, String cName, String file, TextSpan span,
                             bool allowKeep, bool allowBuiltin, bool allowShadows) {
        let int i = 0;
        while (i < anns.Length()) {
            match (anns.Get(i)) {
                case ShadowsAnnotation(sa) {
                    if (!allowShadows) {
                        self.diag.Error(Codes.WrongAnnotationKind(), file, span,
                            "'@shadows' has no effect here; it belongs on a declaration inside a realm or process");
                    }
                }
                case KeepAnnotation(ka) {
                    if (!allowKeep) {
                        self.diag.Error(Codes.WrongAnnotationKind(), file, span,
                            "'@keep' has no effect here; it only matters on a free function or a class");
                    }
                }
                case BuiltinAnnotation(ba) {
                    if (!allowBuiltin) {
                        self.diag.Error(Codes.WrongAnnotationKind(), file, span,
                            "'@builtin' has no effect here; it only matters on a class or native type");
                    } else if (!BuiltinTypes.IsBuiltin(ba.name)) {
                        self.diag.Error(Codes.UnknownIntrinsic(), file, span,
                            "unknown @builtin type '" + ba.name + "'");
                    } else {
                        self.BindSlot(self.sym.builtins, "@builtin", ba.name, cName, file, span);
                    }
                }
                case IntrinsicAnnotation(ia) {
                    if (!Roles.IsRole(ia.role)) {
                        self.diag.Error(Codes.UnknownIntrinsic(), file, span,
                            "unknown @intrinsic role '" + ia.role + "'");
                    } else {
                        self.BindSlot(self.sym.intrinsics, "@intrinsic", ia.role, cName, file, span);
                    }
                }
                default {
                    self.diag.Error(Codes.WrongAnnotationKind(), file, span,
                        "only '@intrinsic' is valid here, not '@preamble'");
                }
            }
            i = i + 1;
        }
    }

    /*
     * BindSlot - Binds one role or builtin slot to a C name. Rebinding a slot to the SAME name is
     * silent, which is what lets a declaration be seen twice without becoming an error.
     */
    void func BindSlot(StringMap[String] table, String kind, String slot, String cName, String file, TextSpan span) {
        match (table.Find(slot)) {
            case Some(prev) {
                if (prev != cName) {
                    self.diag.Error(Codes.DuplicateIntrinsic(), file, span,
                        kind + "(" + slot + ") is already bound to '" + prev + "'");
                }
            }
            case None { table.Put(slot, cName); }
        }
    }

    /*
     * P1Class - Registers a class or module and all of its fields, methods and operators
     */
    void func P1Class(ClassDecl cd, String file) {
        self.DeclareType(cd.name, file, cd.span);
        self.sym.RegisterClass(cd.name, file, self.mangler);
        if (cd.isModule) { self.sym.modules.AddNew(cd.name); }
        self.BindIntrinsics(cd.annotations, cd.name, file, cd.span, true, true, true);

        let int i = 0;
        while (i < cd.members.Length()) {
            match (cd.members.Get(i)) {
                case FieldsBlock(fb) { self.opaqueFieldClasses.AddNew(cd.name); }
                case FieldDecl(fd) { self.P1Field(cd, fd, file); }
                case MethodDecl(md) { self.P1Method(cd, md, file); }
                case OperatorDecl(od) { self.P1Operator(cd, od, file); }
            }
            i = i + 1;
        }
    }

    /*
     * P1Field - Registers one field. A field's type has to be known now, before any body is
     * resolved, so an inferred one is read straight off its literal initializer.
     */
    void func P1Field(ClassDecl cd, FieldDecl fd, String file) {
        if (cd.isModule) {
            self.diag.Error(Codes.ModuleField(), file, fd.span,
                "module '" + self.mangler.DisplayName(cd.name) + "' cannot declare the field '" +
                fd.name + "' - modules are stateless; use a class for instance state");
            return;
        }

        if (!self.declaredFieldNames.AddNew(MemberKey(cd.name, fd.name)) ||
            self.declaredMethodNames.Has(MemberKey(cd.name, fd.name))) {
            self.diag.Error(Codes.DuplicateName(), file, fd.span,
                "'" + self.mangler.DisplayName(cd.name) + "' already declares a member '" + fd.name + "'");
        }

        self.sym.RegisterField(cd.name, fd.name, self.FieldType(fd));

        if (!Mods.Has(fd.modifiers, Modifiers.Public)) {
            self.sym.MarkPrivateMember(cd.name, fd.name);
        }
    }

    /*
     * FieldType - The written type, else the one its literal initializer infers, else int
     */
    TypeSpec func FieldType(FieldDecl fd) {
        match (fd.type) {
            case Some(t) { return t; }
            case None {
                match (Literals.InferFieldTypeSpec(fd.init)) {
                    case Some(t) { return t; }
                    case None    { return Specs.NamedAt("int", fd.span); }
                }
            }
        }
    }

    /*
     * P1Method - Registers one method, and binds any @intrinsic it carries
     */
    void func P1Method(ClassDecl cd, MethodDecl md, String file) {
        if (self.declaredFieldNames.Has(MemberKey(cd.name, md.name))) {
            self.diag.Error(Codes.DuplicateName(), file, md.span,
                "'" + self.mangler.DisplayName(cd.name) + "' already declares a member '" + md.name + "'");
            return;
        }
        if (!self.declaredMethodSigs.AddNew(MemberKey(cd.name, SigKey.Of(md.name, md.params)))) {
            self.diag.Error(Codes.DuplicateName(), file, md.span,
                "'" + self.mangler.DisplayName(cd.name) + "' already declares '" + md.name +
                "' with the same parameter types");
            return;
        }

        self.declaredMethodNames.AddNew(MemberKey(cd.name, md.name));

        // Every member of a module is static whether or not it says so
        let bool isStatic = Mods.Has(md.modifiers, Modifiers.Static) || cd.isModule;
        let MethodSig sig = new MethodSig(md.returnType, md.params, isStatic, md.isThrows, md.isEntry, md.annotations, false);
        self.sym.RegisterMethod(cd.name, md.name, sig);

        if (!Mods.Has(md.modifiers, Modifiers.Public)) {
            self.sym.MarkPrivateMember(cd.name, md.name);
        }

        self.BindIntrinsics(md.annotations,
            self.mangler.Method(cd.name, md.name, md.params, false), file, md.span,
            false, false, false);

        if ((md.name == Lifecycle.Init() || md.name == Lifecycle.Deinit()) && md.isThrows) {
            self.diag.Error(Codes.LifecycleThrows(), file, md.span,
                "'" + md.name + "' cannot be 'throws'; it is called by generated allocator/" +
                "destructor code that cannot handle a Result");
        }

        if (md.name == Lifecycle.Init()) { self.hasInit.AddNew(cd.name); }

        if (md.isThrows) { self.sym.RegisterThrows(md.returnType); }
    }

    /*
     * P1Operator - Registers one operator overload.
     */
    void func P1Operator(ClassDecl cd, OperatorDecl od, String file) {
        let bool isAs = od.op == "as" && od.params.Length() == 1;
        let bool fresh = isAs
            ? self.declaredAsConversions.AddNew(MemberKey(cd.name, SigKey.Of("as", od.params)))
            : self.declaredOperatorSigs.AddNew(
                  MemberKey(cd.name, od.op + "|" + (od.params.Length() as String)));

        if (!fresh) {
            self.diag.Error(Codes.DuplicateName(), file, od.span, isAs
                ? "'" + self.mangler.DisplayName(cd.name) + "' already declares a conversion from '" +
                  self.mangler.DisplayName(Specs.ToSpecString(od.params.Get(0).type)) + "'"
                : "'" + self.mangler.DisplayName(cd.name) + "' already declares operator '" + od.op + "'");
            return;
        }

        let Optional[TypeSpec] retType = self.OperatorReturn(od, cd.name);
        self.sym.RegisterOperator(cd.name, od.op, retType, od.params);

        if (!Mods.Has(od.modifiers, Modifiers.Public)) {
            self.sym.MarkPrivateMember(cd.name, "operator " + od.op);
        }
    }

    /*
     * OperatorReturn - An operator's written return type, or the default for its symbol
     */
    Optional[TypeSpec] func OperatorReturn(OperatorDecl od, String cls) {
        match (od.returnType) {
            case Some(t) { return od.returnType; }
            case None {
                return Optional.Some(
                    Specs.NamedAt(OperatorRules.DefaultReturn(od.op, cls), od.span));
            }
        }
    }

    /*
     * P1Func - Registers a free function, private or public.
     */
    void func P1Func(FuncDecl fd, String file) {
        if (Mods.Has(fd.modifiers, Modifiers.Static)) {
            self.diag.Error(Codes.StaticOnFreeFunc(), file, fd.span,
                "'static' has no meaning on the free function '" +
                self.mangler.DisplayName(fd.name) + "' - it is never an instance member");
        }

        if (fd.genericParams.Length() > 0) { return; }

        let MethodSig sig = new MethodSig(fd.returnType, fd.params, true, fd.isThrows, fd.isEntry, fd.annotations, false);

        if (Mods.Has(fd.modifiers, Modifiers.Private)) {
            if (!self.declaredPrivateFuncSigs.AddNew(MemberKey(file, SigKey.Of(fd.name, fd.params)))) {
                self.diag.Error(Codes.DuplicateName(), file, fd.span,
                    "private function '" + self.mangler.DisplayName(fd.name) +
                    "' is already declared in this file with the same parameter types");
                return;
            }
            self.sym.RegisterPrivateFunc(file, fd.name, sig);
            if (fd.isThrows) { self.sym.RegisterThrows(fd.returnType); }
            return;
        }

        if (!self.declaredFuncSigs.AddNew(
                SigKey.Of(fd.name, fd.params) + "|" + (fd.isEntry as String))) {
            self.diag.Error(Codes.DuplicateName(), file, fd.span,
                "function '" + self.mangler.DisplayName(fd.name) +
                "' is already declared with the same parameter types");
            return;
        }

        self.declaredFuncs.AddNew(fd.name);
        self.sym.RegisterFreeFunc(fd.name, sig, file);
        self.BindIntrinsics(fd.annotations,
            self.mangler.FreeFunc(fd.name, fd.params, false, fd.isEntry, false),
            file, fd.span, true, false, !fd.isEntry);
        if (fd.isThrows) { self.sym.RegisterThrows(fd.returnType); }
    }

    /*
     * P1NativeType - Registers a native type: a C struct given a Gata name.
     */
    void func P1NativeType(NativeTypeDecl nd, String file) {
        self.DeclareType(nd.name, file, nd.span);
        self.sym.RegisterClass(nd.name, file, self.mangler);
        self.preDefinedStructs.AddNew(nd.name);
        self.BindIntrinsics(nd.annotations, self.mangler.Class(nd.name), file, nd.span,
                            false, true, true);
    }

    /*
     * ScanNativeForStructs - Records the struct names a native block already defines
     */
    void func ScanNativeForStructs(String raw) {
        let List[String] names = NativeC.ScanStructs(raw);
        let int i = 0;
        while (i < names.Length()) {
            self.preDefinedStructs.AddNew(names.Get(i));
            i = i + 1;
        }
    }

    /*
     * P1Extern - Registers an @extern forward declaration.
     */
    void func P1Extern(ExternFuncDecl ed, String file) {
        if (self.declaredFuncs.Has(ed.name)) {
            if (!self.externFuncs.Has(ed.name)) {
                self.diag.Error(Codes.DuplicateName(), file, ed.span,
                    "'" + self.mangler.DisplayName(ed.name) + "' is already declared as a function");
            }
        } else {
            self.declaredFuncs.AddNew(ed.name);
            self.externFuncs.AddNew(ed.name);
        }

        let MethodSig sig = new MethodSig(ed.returnType, ed.params, true, false, false, Anns.Empty(), true);

        let String shape = ExternShape(ed);
        match (self.externShapes.Find(ed.name)) {
            case Some(first) {
                if (first != shape) {
                    let List[String] hints = new List[String]();
                    hints.Add("the other declaration reads '" + first + "'");
                    hints.Add("an '@extern' names one C symbol, so every declaration of it has to " +
                              "describe the same function");
                    self.diag.Error(Codes.DuplicateName(), file, ed.span,
                        "'" + self.mangler.DisplayName(ed.name) +
                        "' is already declared '@extern' with a different signature", hints);
                }
            }
            case None { self.externShapes.Put(ed.name, shape); }
        }

        self.sym.RegisterFreeFunc(ed.name, sig, file);
        self.BindIntrinsics(ed.annotations, ed.name, file, ed.span, false, false, true);
    }
}

/*
 * ExternShape - An extern declaration's signature as text, for comparing one declaration of a name against another
 */
String func ExternShape(ExternFuncDecl ed) {
    let StringBuilder sb = new StringBuilder();
    match (ed.returnType) {
        case Some(t) { sb.Put(Specs.ToSpecString(t)); }
        case None { sb.Put("void"); }
    }
    sb.Put(" func ");
    sb.Put(ed.name);
    sb.AppendChar('(');
    let int i = 0;
    while (i < ed.params.Length()) {
        if (i > 0) { sb.Put(", "); }
        let Param p = ed.params.Get(i);
        if (p.isRef) { sb.Put("ref "); }
        sb.Put(Specs.ToSpecString(p.type));
        i = i + 1;
    }
    sb.AppendChar(')');
    return sb.ToString();
}
