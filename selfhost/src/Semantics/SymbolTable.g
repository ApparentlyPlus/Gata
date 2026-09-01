/*
 * SymbolTable.g - the declaration registry: classes, fields, methods, free functions, operators,
 * enums and unions
 *
 * Ports Appa/src/Semantics/SymbolTable.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "src/Syntax/Ast.g";
import "src/IR/Ir.g";
import "src/Backend/Mangler.g";

enum SymKind { Class, Field, Method, FreeFunc, Operator }

/*
 * The closed vocabulary of compiler runtime roles. A libgata symbol annotated @intrinsic(<role>)
 * fills the role; the compiler emits the bound C name. This module IS the compiler-runtime
 * contract surface.
 */
module Roles {
    public String func Alloc() { return "alloc"; }
    public String func Retain() { return "retain"; }
    public String func Release() { return "release"; }
    public String func ObjHeader() { return "obj_header"; }
    public String func ObjInit() { return "obj_init"; }
    public String func StringifyInt() { return "stringify_int"; }
    public String func StringifyLong() { return "stringify_long"; }
    public String func StringifyUint() { return "stringify_uint"; }
    public String func StringifyFloat() { return "stringify_float"; }
    public String func StringifyChar() { return "stringify_char"; }

    // The environment floor's C names, bound to their @extern declaration in libgata.

    public String func EnvDebug() { return "env_debug"; }
    public String func EnvPanic() { return "env_panic"; }
    public String func EnvProcCreate() { return "env_proc_create"; }
    public String func EnvProcHide() { return "env_proc_hide"; }
    public String func EnvThreadSpawn() { return "env_thread_spawn"; }
    public String func EnvRead() { return "env_read"; }
    public String func EnvAlloc() { return "env_alloc"; }
    public String func EnvTime() { return "env_time"; }

    /*
     * All - Every role name
     */
    public List[String] func All() {
        let List[String] r = new List[String]();
        r.Add(Roles.Alloc()); r.Add(Roles.Retain()); r.Add(Roles.Release());
        r.Add(Roles.ObjHeader()); r.Add(Roles.ObjInit());
        r.Add(Roles.StringifyInt()); r.Add(Roles.StringifyLong()); r.Add(Roles.StringifyUint());
        r.Add(Roles.StringifyFloat()); r.Add(Roles.StringifyChar());
        r.Add(Roles.EnvDebug()); r.Add(Roles.EnvPanic()); r.Add(Roles.EnvProcCreate());
        r.Add(Roles.EnvProcHide()); r.Add(Roles.EnvThreadSpawn()); r.Add(Roles.EnvRead());
        r.Add(Roles.EnvAlloc()); r.Add(Roles.EnvTime());
        return r;
    }

    /*
     * IsRole - True for a name in the closed role vocabulary
     */
    public bool func IsRole(String r) { return Roles.All().Contains(r); }

    /*
     * FloorDefault - The canonical floor C name for an environment role, or "" for a role that has none.
     */
    public String func FloorDefault(String role) {
        if (role == Roles.EnvDebug()) { return "_env_dbg"; }
        if (role == Roles.EnvPanic()) { return "_env_panic"; }
        if (role == Roles.EnvProcCreate()) { return "_env_proc_create"; }
        if (role == Roles.EnvProcHide()) { return "_env_proc_hide"; }
        if (role == Roles.EnvThreadSpawn()) { return "_env_thread_spawn"; }
        if (role == Roles.EnvRead()) { return "_env_read"; }
        if (role == Roles.EnvAlloc()) { return "_env_alloc"; }
        if (role == Roles.EnvTime()) { return "_env_time_ns"; }
        return "";
    }
}

/*
 * The lifecycle methods the compiler itself invokes from generated code.
 */
module Lifecycle {
    public String func Init() { return "_init"; }
    public String func Deinit() { return "_deinit"; }
}

/*
 * The closed vocabulary of compiler builtin types.
 */
module BuiltinTypes {
    public String func Str() { return "String"; }
    public String func StringBuilder() { return "StringBuilder"; }
    public String func Process() { return "Process"; }
    public String func Thread() { return "Thread"; }

    public List[String] func All() {
        let List[String] r = new List[String]();
        r.Add(BuiltinTypes.Str());
        r.Add(BuiltinTypes.StringBuilder());
        r.Add(BuiltinTypes.Process());
        r.Add(BuiltinTypes.Thread());
        return r;
    }

    public bool func IsBuiltin(String n) { return BuiltinTypes.All().Contains(n); }
}

/*
 * The signature of a method or free function as collected from the AST.
 */
class MethodSig {
    public Optional[TypeSpec] returnType;
    public List[Param] params;
    public bool isStatic;
    public bool isThrows;
    public bool isEntry;
    public List[Annotation] annotations;
    public bool isExtern;
    func _init(Optional[TypeSpec] returnType, List[Param] params, bool isStatic, bool isThrows,
               bool isEntry, List[Annotation] annotations, bool isExtern) {
        self.returnType = returnType;
        self.params = params;
        self.isStatic = isStatic;
        self.isThrows = isThrows;
        self.isEntry = isEntry;
        self.annotations = annotations;
        self.isExtern = isExtern;
    }
}

/*
 * A single declared symbol with its kind, declared type (None for void or for symbols that are not
 * values, like classes), and optionally its method signature.
 */
class Symbol {
    public String name;
    public SymKind kind;
    public Optional[TypeSpec] type;
    public Optional[String] owner;
    public Optional[MethodSig] sig;
    public String cName;
    public String declFile;
    func _init(String name, SymKind kind, Optional[TypeSpec] type, Optional[String] owner,
               Optional[MethodSig] sig) {
        self.name = name;
        self.kind = kind;
        self.type = type;
        self.owner = owner;
        self.sig = sig;
        self.cName = "";
        self.declFile = "";
    }

    /*
     * Signature - The symbol's signature; every symbol this is asked of has one
     */
    public MethodSig func Signature() {
        match (self.sig) { case Some(s) { return s; } case None { return null; } }
    }
}

class SymbolTable {
    StringMap[Symbol] classes;
    StringMap[Symbol] fieldMap;
    StringMap[List[Symbol]] methods;
    StringMap[List[Symbol]] funcs;
    StringMap[List[Symbol]] operators;

    // File-local free functions
    StringMap[List[Symbol]] privateFuncs;

    // Result_T typedefs needed by throws functions
    public StringMap[String] resultTypedefs;

    // The same keys in REGISTRATION order
    public List[String] resultTypedefOrder;

    // Declaring source files seen during collection.
    public StringSet modules;

    // role -> bound C symbol name, from @intrinsic annotations.
    public StringMap[String] intrinsics;

    // builtin type name -> bound Gata declaration name, from @builtin annotations.
    public StringMap[String] builtins;

    // Enum types. Globally visible like primitives.
    public StringMap[StringSet] enums;

    // Union types. Globally visible and not generic.
    public StringMap[List[UnionVariant]] unions;

    // Class/method members declared private
    public StringSet privateMembers;

    func _init() {
        self.classes = new StringMap[Symbol]();
        self.fieldMap = new StringMap[Symbol]();
        self.methods = new StringMap[List[Symbol]]();
        self.funcs = new StringMap[List[Symbol]]();
        self.operators = new StringMap[List[Symbol]]();
        self.privateFuncs = new StringMap[List[Symbol]]();
        self.resultTypedefs = new StringMap[String]();
        self.resultTypedefOrder = new List[String]();
        self.modules = new StringSet();
        self.intrinsics = new StringMap[String]();
        self.builtins = new StringMap[String]();
        self.enums = new StringMap[StringSet]();
        self.unions = new StringMap[List[UnionVariant]]();
        self.privateMembers = new StringSet();
    }

    /*
     * Primitives - Every accepted primitive spelling
     */
    public List[String] func Primitives() { return PrimTypes.Spellings(); }

    /*
     * ResolveBuiltinType - The IR type for a builtin name (String/StringBuilder/Process/Thread) if
     * libgata declared it via @builtin, or None if unbound.
     */
    public Optional[IrType] func ResolveBuiltinType(String name, IrTypeTable t) {
        match (self.builtins.Find(name)) {
            case None { return Optional[IrType].None(); }
            case Some(bound) {
                if (name == BuiltinTypes.Str()) { return Optional.Some(t.Str()); }
                if (name == BuiltinTypes.StringBuilder()) { return Optional.Some(t.ClassRef(bound)); }
                if (name == BuiltinTypes.Process() || name == BuiltinTypes.Thread()) {
                    return Optional.Some(t.Ptr(t.Void()));
                }
                return Optional[IrType].None();
            }
        }
    }

    /*
     * IntrinsicOrNull - The C name bound to the given intrinsic role, or None if unbound
     */
    public Optional[String] func IntrinsicOrNull(String role) { return self.intrinsics.Find(role); }

    /*
     * FloorName - Resolves an environment floor role to a C name: whatever libgata bound to it, or
     * the role's canonical floor name when nothing did.
     */
    public String func FloorName(String role) {
        match (self.IntrinsicOrNull(role)) {
            case Some(n) { return n; }
            case None { return Roles.FloorDefault(role); }
        }
    }

    /*
     * RegisterClass - Registers a class declaration from the given source file
     */
    public void func RegisterClass(String name, String declFile, Mangler m) {
        let Symbol s = new Symbol(name, SymKind.Class, Optional[TypeSpec].None(),
                                  Optional[String].None(), Optional[MethodSig].None());
        s.cName = m.Class(name);
        s.declFile = declFile;
        self.classes.Put(name, s);
    }

    /*
     * RegisterField - Registers a field on the named class
     */
    public void func RegisterField(String cls, String field, TypeSpec type) {
        let Symbol s = new Symbol(field, SymKind.Field, Optional.Some(type), Optional.Some(cls),
                                  Optional[MethodSig].None());
        self.fieldMap.Put(MemberKey(cls, field), s);
    }

    /*
     * RegisterMethod - Registers a method overload on the named class
     */
    public void func RegisterMethod(String cls, String name, MethodSig sig) {
        let Symbol s = new Symbol(name, SymKind.Method, sig.returnType, Optional.Some(cls),
                                  Optional.Some(sig));
        Bucket(self.methods, MemberKey(cls, name)).Add(s);
    }

    /*
     * RegisterFreeFunc - Registers a free function overload from the given source file
     */
    public void func RegisterFreeFunc(String name, MethodSig sig, String declFile) {
        let Symbol s = new Symbol(name, SymKind.FreeFunc, sig.returnType, Optional[String].None(),
                                  Optional.Some(sig));
        s.declFile = declFile;
        Bucket(self.funcs, name).Add(s);
    }

    /*
     * RegisterPrivateFunc - Registers a file-local (private) free function from the given file
     */
    public void func RegisterPrivateFunc(String file, String name, MethodSig sig) {
        let Symbol s = new Symbol(name, SymKind.FreeFunc, sig.returnType, Optional[String].None(),
                                  Optional.Some(sig));
        s.declFile = file;
        Bucket(self.privateFuncs, MemberKey(file, name)).Add(s);
    }

    /*
     * RegisterOperator - Registers an operator overload. Every operator but 'as' has one
     * declaration per (class, symbol) in a well-formed program, the caller rejecting duplicates.
     */
    public void func RegisterOperator(String cls, String op, Optional[TypeSpec] returnType, List[Param] params) {
        let MethodSig sig = new MethodSig(returnType, params, false, false, false, new List[Annotation](), false);
        let Symbol s = new Symbol(op, SymKind.Operator, returnType, Optional.Some(cls), Optional.Some(sig));
        Bucket(self.operators, MemberKey(cls, op)).Add(s);
    }

    /*
     * RegisterThrows - Records that a throws function returns the given type, ensuring a Result typedef is emitted.
     */
    public void func RegisterThrows(Optional[TypeSpec] returnType) {
        let String inner = ResultInnerName(returnType);
        let String key = "Result_" + inner;
        if (!self.resultTypedefs.Has(key)) {
            self.resultTypedefs.Put(key, inner);
            self.resultTypedefOrder.Add(key);
        }
    }

    /*
     * RegisterEnum - Registers an enum type and its member names
     */
    public void func RegisterEnum(String name, List[String] members) {
        let StringSet set = new StringSet();
        let int i = 0;
        while (i < members.Length()) { set.AddNew(members.Get(i)); i = i + 1; }
        self.enums.Put(name, set);
    }

    /*
     * RegisterUnion - Registers a union type and its variants
     */
    public void func RegisterUnion(String name, List[UnionVariant] variants) {
        self.unions.Put(name, variants);
    }

    /*
     * AssignCNames - Assigns C names to all methods and free functions once all declarations are collected.
     */
    public void func AssignCNames(Mangler m) {
        let List[String] mkeys = self.methods.Keys();
        let int i = 0;
        while (i < mkeys.Length()) {
            let String key = mkeys.Get(i);
            i = i + 1;
            let List[Symbol] list = self.methods.Get(key);
            let bool ov = list.Length() > 1;
            let String owner = KeyOwner(key);
            let String name = KeyMember(key);
            let int j = 0;
            while (j < list.Length()) {
                let Symbol s = list.Get(j);
                j = j + 1;
                s.cName = m.Method(owner, name, s.Signature().params, ov);
                self.RebindIntrinsics(s);
            }
        }

        let List[String] fkeys = self.funcs.Keys();
        i = 0;
        while (i < fkeys.Length()) {
            let String name = fkeys.Get(i);
            i = i + 1;
            let List[Symbol] list = self.funcs.Get(name);
            let bool ov = self.FuncOverloads(name).Length() > 1;
            let int j = 0;
            while (j < list.Length()) {
                let Symbol s = list.Get(j);
                j = j + 1;
                let MethodSig sig = s.Signature();
                s.cName = m.FreeFunc(name, sig.params, ov, sig.isEntry, sig.isExtern);
                self.RebindIntrinsics(s);
            }
        }

        let List[String] pkeys = self.privateFuncs.Keys();
        i = 0;
        while (i < pkeys.Length()) {
            let String key = pkeys.Get(i);
            i = i + 1;
            let List[Symbol] list = self.privateFuncs.Get(key);
            let bool ov = list.Length() > 1;
            let String token = Mangle.FileToken(KeyOwner(key));
            let String name = KeyMember(key);
            let int j = 0;
            while (j < list.Length()) {
                let Symbol s = list.Get(j);
                j = j + 1;
                s.cName = m.PrivateFreeFunc(token, name, s.Signature().params, ov);
            }
        }

        let List[String] okeys = self.operators.Keys();
        i = 0;
        while (i < okeys.Length()) {
            let String key = okeys.Get(i);
            i = i + 1;
            let List[Symbol] list = self.operators.Get(key);
            let bool ov = list.Length() > 1;
            let String owner = KeyOwner(key);
            let String op = KeyMember(key);
            let int j = 0;
            while (j < list.Length()) {
                let Symbol s = list.Get(j);
                j = j + 1;
                s.cName = m.Operator(owner, op, s.Signature().params, ov);
            }
        }
    }

    /*
     * RebindIntrinsics - Points a symbol's @intrinsic roles at its final CName.
     */
    void func RebindIntrinsics(Symbol s) {
        let List[Annotation] anns = s.Signature().annotations;
        let int i = 0;
        while (i < anns.Length()) {
            match (anns.Get(i)) {
                case IntrinsicAnnotation(ia) {
                    if (self.intrinsics.Has(ia.role)) { self.intrinsics.Put(ia.role, s.cName); }
                }
                default { }
            }
            i = i + 1;
        }
    }

    public bool func IsEnum(String name) { return self.enums.Has(name); }

    /*
     * IsEnumMember - True if the member belongs to the named enum
     */
    public bool func IsEnumMember(String e, String mem) {
        match (self.enums.Find(e)) {
            case Some(ms) { return ms.Has(mem); }
            case None { return false; }
        }
    }

    public bool func IsUnion(String name) { return self.unions.Has(name); }

    /*
     * UnionDef - The variant list for the named union, or None if not declared
     */
    public Optional[List[UnionVariant]] func UnionDef(String name) { return self.unions.Find(name); }

    public bool func IsClass(String name) { return self.classes.Has(name); }

    /*
     * ClassModule - The source file that declared the named class, or None if not found
     */
    public Optional[String] func ClassModule(String name) {
        match (self.classes.Find(name)) {
            case Some(s) { return Optional.Some(s.declFile); }
            case None { return Optional[String].None(); }
        }
    }

    /*
     * LookupMethod - The last registered overload of the named method, or None if not found
     */
    public Optional[Symbol] func LookupMethod(String cls, String method) {
        return Last(self.methods, MemberKey(cls, method));
    }

    /*
     * Externs - Every '@extern' declaration in the build, as symbols carrying name and cName
     */
    public List[Symbol] func Externs() {
        let List[Symbol] out = new List[Symbol]();
        let List[String] keys = self.funcs.Keys();
        let int i = 0;
        while (i < keys.Length()) {
            let List[Symbol] list = self.funcs.Get(keys.Get(i));
            i = i + 1;
            let int j = 0;
            while (j < list.Length()) {
                let Symbol s = list.Get(j);
                j = j + 1;
                if (s.Signature().isExtern) { out.Add(s); }
            }
        }
        return out;
    }

    /*
     * LookupFreeFunc - The last registered non-entry overload of the named free function, or the
     * last of any kind, or None if not found
     */
    public Optional[Symbol] func LookupFreeFunc(String name) {
        match (self.funcs.Find(name)) {
            case None { return Optional[Symbol].None(); }
            case Some(l) {
                let int i = l.Length() - 1;
                while (i >= 0) {
                    if (!l.Get(i).Signature().isEntry) { return Optional.Some(l.Get(i)); }
                    i = i - 1;
                }
                return Optional.Some(l.Last());
            }
        }
    }

    /*
     * LookupOperator - The last registered overload of the given operator on the class, or None.
     */
    public Optional[Symbol] func LookupOperator(String cls, String op) {
        return Last(self.operators, MemberKey(cls, op));
    }

    /*
     * LookupOperator - The overload of the given operator with the given parameter count, or None.
     */
    public Optional[Symbol] func LookupOperator(String cls, String op, int arity) {
        match (self.operators.Find(MemberKey(cls, op))) {
            case None { return Optional[Symbol].None(); }
            case Some(l) {
                let int i = l.Length() - 1;
                while (i >= 0) {
                    if (l.Get(i).Signature().params.Length() == arity) { return Optional.Some(l.Get(i)); }
                    i = i - 1;
                }
                return Optional[Symbol].None();
            }
        }
    }

    /*
     * OperatorOverloads - All overloads of the named operator on the given class
     */
    public List[Symbol] func OperatorOverloads(String cls, String op) {
        return All(self.operators, MemberKey(cls, op));
    }

    public bool func IsOverloadedOperator(String cls, String op) {
        return self.OperatorOverloads(cls, op).Length() > 1;
    }

    /*
     * MethodOverloads - All overloads of the named method on the given class
     */
    public List[Symbol] func MethodOverloads(String cls, String method) {
        return All(self.methods, MemberKey(cls, method));
    }

    /*
     * FuncDeclarations - Every registration of the named free function, one per declaring file,
     * before any collapsing of overloads
     */
    public List[Symbol] func FuncDeclarations(String name) { return All(self.funcs, name); }

    /*
     * FuncOverloads - All callable overloads of the named free function
     */
    public List[Symbol] func FuncOverloads(String name) {
        let List[Symbol] l = All(self.funcs, name);
        if (l.Length() == 0) { return l; }

        let List[Symbol] callable = new List[Symbol]();
        let int i = 0;
        while (i < l.Length()) {
            if (!l.Get(i).Signature().isEntry) { callable.Add(l.Get(i)); }
            i = i + 1;
        }
        if (callable.Length() == 0) { callable = l.Clone(); }

        if (callable.Length() > 1) {
            let StringSet seen = new StringSet();
            let List[Symbol] kept = new List[Symbol]();
            let int j = 0;
            while (j < callable.Length()) {
                let Symbol s = callable.Get(j);
                j = j + 1;
                if (s.cName.Length() == 0 || seen.AddNew(s.cName)) { kept.Add(s); }
            }
            callable = kept;
        }
        return callable;
    }

    public bool func IsOverloadedMethod(String cls, String method) {
        return self.MethodOverloads(cls, method).Length() > 1;
    }

    public bool func IsOverloadedFunc(String name) { return self.FuncOverloads(name).Length() > 1; }

    /*
     * MethodNames - The distinct method names declared directly on the given class/module, for
     * "did you mean" suggestions when a lookup misses
     */
    public List[String] func MethodNames(String cls) {
        let List[String] out = new List[String]();
        let List[String] keys = self.methods.Keys();
        let int i = 0;
        while (i < keys.Length()) {
            let String key = keys.Get(i);
            i = i + 1;
            if (KeyOwner(key) == cls) { out.Add(KeyMember(key)); }
        }
        return out;
    }

    /*
     * FieldType - The declared type of the named field, or None if not found
     */
    public Optional[TypeSpec] func FieldType(String cls, String field) {
        match (self.fieldMap.Find(MemberKey(cls, field))) {
            case Some(s) { return s.type; }
            case None { return Optional[TypeSpec].None(); }
        }
    }

    public bool func IsField(String cls, String field) { return self.fieldMap.Has(MemberKey(cls, field)); }

    /*
     * MarkPrivateMember - Records that a member on the given owner was declared private
     */
    public void func MarkPrivateMember(String owner, String member) {
        self.privateMembers.AddNew(MemberKey(owner, member));
    }

    public bool func IsPrivateMember(String owner, String member) {
        return self.privateMembers.Has(MemberKey(owner, member));
    }

    /*
     * LookupPrivateFunc - The last registered overload of the named file-local function, or None
     */
    public Optional[Symbol] func LookupPrivateFunc(String file, String name) {
        return Last(self.privateFuncs, MemberKey(file, name));
    }

    /*
     * PrivateFuncOverloads - All overloads of the named file-local function
     */
    public List[Symbol] func PrivateFuncOverloads(String file, String name) {
        return All(self.privateFuncs, MemberKey(file, name));
    }

    /*
     * CType - The C type string for a Gata type name
     */
    public String func CType(String t, Mangler m) {
        if (t == null || t.Length() == 0 || t == "void") { return "void"; }
        if (PrimTypes.IsPrim(t)) { return PrimTypes.ToC(t); }
        if ((t == BuiltinTypes.Process() || t == BuiltinTypes.Thread()) && self.builtins.Has(t)) {
            return "void*";
        }
        if (self.IsEnum(t)) { return m.EnumName(t); }
        if (self.IsUnion(t)) { return m.UnionName(t); }
        return m.Class(t) + "*";
    }
}

/*
 * MemberKey - Identifies a class member by its owning class and member name, or a file-local
 * function by its file and name. Joined by the unit separator, which no identifier or path holds.
 */
String func MemberKey(String owner, String member) {
    return owner + String.FromChar(31 as char) + member;
}

/*
 * KeyOwner - The owner half of a MemberKey
 */
String func KeyOwner(String key) {
    let int at = key.IndexOfChar(31 as char);
    if (at < 0) { return key; }
    return key.Substring(0, at);
}

/*
 * KeyMember - The member half of a MemberKey
 */
String func KeyMember(String key) {
    let int at = key.IndexOfChar(31 as char);
    if (at < 0) { return ""; }
    return key.Substring(at + 1, key.Length() - (at + 1));
}

/*
 * Bucket - The symbol list for a key, created on first use
 */
List[Symbol] func Bucket(StringMap[List[Symbol]] d, String key) {
    match (d.Find(key)) {
        case Some(l) { return l; }
        case None {
            let List[Symbol] l = new List[Symbol]();
            d.Put(key, l);
            return l;
        }
    }
}

/*
 * All - Every symbol registered under a key, or an empty list
 */
List[Symbol] func All(StringMap[List[Symbol]] d, String key) {
    match (d.Find(key)) {
        case Some(l) { return l; }
        case None { return new List[Symbol](); }
    }
}

/*
 * Last - The last symbol registered under a key, or None
 */
Optional[Symbol] func Last(StringMap[List[Symbol]] d, String key) {
    match (d.Find(key)) {
        case Some(l) { return l.Length() > 0 ? Optional.Some(l.Last()) : Optional[Symbol].None(); }
        case None { return Optional[Symbol].None(); }
    }
}

/*
 * ResultInnerName - The single source of truth for the inner-type token of a Result_T typedef
 * name, mirroring Types.ResultName's IrType-side derivation
 */
String func ResultInnerName(Optional[TypeSpec] t) {
    match (t) {
        case None { return "int"; }
        case Some(spec) {
            match (spec) {
                case NamedSpec(n) {
                    if (n.name == "void" && n.args.Length() == 0) { return "int"; }
                    return n.Mangled();
                }
                default { return Mangle.MangleTypeName(Specs.ToSpecString(spec)); }
            }
        }
    }
}
