/*
 * Mangler.g - every Gata name's C spelling, in one place
 *
 * Ports Appa/src/Backend/Mangler.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Int.g";
import "src/Syntax/Ast.g";
import "src/IR/Ir.g";
import "src/Semantics/ScopeTree.g";
import "src/Backend/NameTable.g";

module Mangle {

    /*
     * KernelEntry - The C name every kernel entry point takes
     */
    public String func KernelEntry() { return "gata_kernelspace_main"; }

    /*
     * IsCReserved - True if the name is a C keyword or a standard macro behaving like one, and so
     * cannot stand as an identifier in emitted C. For the names this compiler cannot rename because
     * the author pinned them to C text of their own.
     */
    public bool func IsCReserved(String name) {
        // C keywords
        if (name == "auto" || name == "break" || name == "case" || name == "char" || name == "const"
            || name == "continue" || name == "default" || name == "do" || name == "double"
            || name == "else" || name == "enum" || name == "extern" || name == "float"
            || name == "for" || name == "goto" || name == "if" || name == "inline" || name == "int"
            || name == "long" || name == "register" || name == "restrict" || name == "return"
            || name == "short" || name == "signed" || name == "sizeof" || name == "static"
            || name == "struct" || name == "switch" || name == "typedef" || name == "union"
            || name == "unsigned" || name == "void" || name == "volatile" || name == "while") {
            return true;
        }
        if (name == "_Alignas" || name == "_Alignof" || name == "_Atomic" || name == "_Bool"
            || name == "_Complex" || name == "_Generic" || name == "_Imaginary" || name == "_Noreturn"
            || name == "_Static_assert" || name == "_Thread_local") {
            return true;
        }
        if (name == "bool" || name == "true" || name == "false" || name == "NULL" || name == "alignas"
            || name == "alignof" || name == "static_assert" || name == "thread_local"
            || name == "complex" || name == "imaginary" || name == "noreturn") {
            return true;
        }
        // Object-like macros from the standard headers a hosted preamble includes
        if (name == "stdin" || name == "stdout" || name == "stderr" || name == "EOF"
            || name == "BUFSIZ" || name == "FILENAME_MAX" || name == "FOPEN_MAX" || name == "TMP_MAX"
            || name == "SEEK_SET" || name == "SEEK_CUR" || name == "SEEK_END" || name == "L_tmpnam"
            || name == "_IOFBF" || name == "_IOLBF" || name == "_IONBF" || name == "EXIT_SUCCESS"
            || name == "EXIT_FAILURE" || name == "RAND_MAX" || name == "MB_CUR_MAX" || name == "errno"
            || name == "CLOCKS_PER_SEC") {
            return true;
        }
        if (name == "CHAR_BIT" || name == "CHAR_MAX" || name == "CHAR_MIN" || name == "SCHAR_MAX"
            || name == "SCHAR_MIN" || name == "UCHAR_MAX" || name == "SHRT_MAX" || name == "SHRT_MIN"
            || name == "USHRT_MAX" || name == "INT_MAX" || name == "INT_MIN" || name == "UINT_MAX"
            || name == "LONG_MAX" || name == "LONG_MIN" || name == "ULONG_MAX" || name == "LLONG_MAX"
            || name == "LLONG_MIN" || name == "ULLONG_MAX") {
            return true;
        }
        if (name == "HUGE_VAL" || name == "HUGE_VALF" || name == "INFINITY" || name == "NAN"
            || name == "M_PI" || name == "M_E" || name == "DBL_MAX" || name == "DBL_MIN"
            || name == "DBL_EPSILON" || name == "FLT_MAX" || name == "FLT_MIN" || name == "FLT_EPSILON"
            || name == "SIZE_MAX" || name == "PTRDIFF_MAX" || name == "INTPTR_MAX"
            || name == "UINTPTR_MAX") {
            return true;
        }
        return false;
    }

    /*
     * Local - The C spelling of a local or parameter name. Names printed as written can collide
     * with C's vocabulary; those get a trailing underscore. Apply at every site that prints the
     * name.
     */
    public String func Local(String name) {
        return Mangle.IsCReserved(name) ? name + "_" : name;
    }

    /*
     * Member - The C spelling of a struct member: a class field, a union variant, or a variant's
     * payload field
     */
    public String func Member(String name) {
        return Mangle.IsCReserved(name) ? name + "_" : name;
    }

    /*
     * IsReservedLocal - True if a user-written local would collide with a compiler temporary
     */
    public bool func IsReservedLocal(String name) { return name.StartsWith("__"); }

    /*
     * Hash - A stable 8-hex C-identifier fragment derived from a string via 32-bit FNV-1a. Stable
     * across builds and machines, which matters because it ends up in emitted C.
     */
    public String func Hash(String s) { return FnvHash(s); }

    /*
     * FileToken - A stable fragment derived from the declaring file path, used to namespace
     * file-local function names
     */
    public String func FileToken(String file) { return Mangle.Hash(file); }

    /*
     * ThreadEntry - The C thread entry function name for a fully-qualified thread path
     */
    public String func ThreadEntry(String full) { return "gata_" + full + "_main"; }

    /*
     * OpSuffix - The stable C identifier suffix for a Gata operator token
     */
    public String func OpSuffix(String op) {
        if (op == "+")   { return "add"; }
        if (op == "-")   { return "sub"; }
        if (op == "*")   { return "mul"; }
        if (op == "/")   { return "div"; }
        if (op == "%")   { return "mod"; }
        if (op == "==")  { return "eq"; }
        if (op == "!=")  { return "neq"; }
        if (op == "<")   { return "lt"; }
        if (op == ">")   { return "gt"; }
        if (op == "<=")  { return "lte"; }
        if (op == ">=")  { return "gte"; }
        if (op == "&")   { return "band"; }
        if (op == "|")   { return "bor"; }
        if (op == "^")   { return "bxor"; }
        if (op == "<<")  { return "shl"; }
        if (op == ">>")  { return "shr"; }
        if (op == "[]")  { return "index_get"; }
        if (op == "[]=") { return "index_set"; }
        if (op == "!")   { return "not"; }
        if (op == "~")   { return "bnot"; }
        if (op == "++")  { return "inc"; }
        if (op == "--")  { return "dec"; }
        return "op";
    }

    /*
     * IsIdentChar - True for a character a C identifier may carry
     */
    public bool func IsIdentChar(char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
    }

    /*
     * MangleTypeName - Converts a Gata type name to a C-identifier fragment. Every non-identifier
     * character becomes a separating underscore (collapsed to prevent runs); pointer stars become
     * _p markers so distinct pointer types never collapse to the same suffix.
     */
    public String func MangleTypeName(String t) {
        let String s = t.Trim();
        if (s.Length() == 0) { return "x"; }

        let StringBuilder sb = new StringBuilder();
        let int i = 0;
        let bool lastWasSep = false;
        while (i < s.Length()) {
            let char c = s.CharAt(i);
            if (Mangle.IsIdentChar(c)) {
                sb.AppendChar(c);
                lastWasSep = false;
                i = i + 1;
            } else if (c == '*') {
                sb.Put("_p");
                lastWasSep = false;
                i = i + 1;
            } else {
                if (!lastWasSep) { sb.AppendChar('_'); lastWasSep = true; }
                i = i + 1;
            }
        }

        // Trim the separators off both ends
        let String out = sb.ToString();
        let int start = 0;
        let int end = out.Length();
        while (end > start && out.CharAt(end - 1) == '_') { end = end - 1; }
        while (start < end && out.CharAt(start) == '_') { start = start + 1; }
        if (end - start <= 0) { return "x"; }
        return out.Substring(start, end - start);
    }

    /*
     * OverloadSuffix - The suffix that distinguishes parameter-type combinations, encoding each
     * parameter's mangled type name joined by underscores
     */
    public String func OverloadSuffix(List[Param] ps) {
        if (ps.Length() == 0) { return "void"; }
        let StringBuilder sb = new StringBuilder();
        let int i = 0;
        while (i < ps.Length()) {
            if (i > 0) { sb.AppendChar('_'); }
            sb.Put(Mangle.MangleTypeName(Specs.ToSpecString(ps.Get(i).type)));
            i = i + 1;
        }
        return sb.ToString();
    }
}

/*
 * The stateful half: every naming rule that consults the NameTable.
 */
class Mangler {
    public NameTable names;

    func _init() { self.names = new NameTable(); }

    /*
     * Begin - Starts a compilation, discarding whatever the last one invented
     */
    public void func Begin() { self.names = new NameTable(); }

    /*
     * BeginRound - Starts a front-end round within the current compilation
     */
    public void func BeginRound() { self.names.BeginRound(); }

    /*
     * SetDense - Replaces the dense name map with the mapping the Densifier produced
     */
    public void func SetDense(StringMap[String] map) { self.names.SetDense(map); }

    /*
     * SetScopes - Adopts the scope tree of the round about to run
     */
    public void func SetScopes(ScopeTree tree) { self.names.scopes = Optional.Some(tree); }

    /*
     * MarkGenericFailed - Records that this instantiation was rejected with a diagnostic of its own
     */
    public void func MarkGenericFailed(String mangled) { self.names.failed.AddNew(mangled); }

    /*
     * GenericFailed - True if this instantiation was already rejected, so a missing-type report
     * would cascade
     */
    public bool func GenericFailed(String mangled) { return self.names.failed.Has(mangled); }

    /*
     * GenericInstance - Composes the internal name of a generic instantiation: ("List", ["int"]) is
     * "List_int". The single place this rule is spelled, so no caller's own concatenation can drift
     * from it - and the composed key is filed here, which is what later lets DisplayName spell a
     * flat name back as 'List[int]'.
     */
    public String func GenericInstance(String baseName, List[String] args) {
        let StringBuilder sb = new StringBuilder();
        sb.Put(baseName);
        let int i = 0;
        while (i < args.Length()) { sb.AppendChar('_'); sb.Put(args.Get(i)); i = i + 1; }
        let String mangled = sb.ToString();
        self.names.composed.Put(mangled, GenericKey.Key(baseName, args.Clone()));
        return mangled;
    }

    /*
     * RegisterGenericInstance - Records that this instantiation was stamped, so diagnostics can
     * tell an instance the build produced from a spelling that merely names one
     */
    public void func RegisterGenericInstance(String mangled) {
        match (self.names.composed.Find(mangled)) {
            case Some(key) { self.names.AddStamped(mangled, key); }
            case None { }
        }
    }

    /*
     * TryGetGenericInstance - The base name and type arguments of a STAMPED generic instance, such
     * as Map_int_String, which yields ("Map", ["int", "String"]). Structural consumers
     * (generic-function type inference) use this instead of re-splitting the mangled string.
     */
    public Optional[GenericKey] func TryGetGenericInstance(String mangled) {
        return self.names.stamped.Find(mangled);
    }

    /*
     * RegisterGenericTemplate - Records that a generic template with this base name was declared
     */
    public void func RegisterGenericTemplate(String baseName) { self.names.templates.AddNew(baseName); }

    /*
     * TrySplitInstance - Splits a mangled instance name back into the template it instantiates and
     * its arguments, for a name that reached a pass already flattened. The split is the key filed
     * when the name was composed, so a base or an argument containing an underscore costs nothing.
     */
    public Optional[GenericKey] func TrySplitInstance(String mangled) {
        match (self.names.composed.Find(mangled)) {
            case Some(key) {
                if (self.names.templates.Has(GK.Base(key))) { return Optional.Some(key); }
                return Optional[GenericKey].None();
            }
            case None { return Optional[GenericKey].None(); }
        }
    }

    /*
     * IsGenericTemplate - True if a generic template with this base name was declared
     */
    public bool func IsGenericTemplate(String baseName) { return self.names.templates.Has(baseName); }

    /*
     * InstancesOf - Every stamped instantiation of a generic base name, ordinally sorted - which
     * instance 'Maybe.Found(7)' means once the template is gone
     */
    public List[String] func InstancesOf(String baseName) {
        match (self.names.stampedByBase.Find(baseName)) {
            case Some(l) { return l; }
            case None { return new List[String](); }
        }
    }

    /*
     * ScopedKind - What a scope-qualified name was declared as, or None when nothing scoped
     * declares it
     */
    public Optional[String] func ScopedKind(String qualified) {
        match (self.names.scopes) {
            case Some(t) { return t.KindOf(qualified); }
            case None { return Optional[String].None(); }
        }
    }

    /*
     * ScopedCandidates - The readable paths of every scope declaring this bare name, ordinally
     * sorted. Empty when nothing scoped declares it, which is the ordinary case.
     */
    public List[String] func ScopedCandidates(String bare) {
        match (self.names.scopes) {
            case Some(t) { return t.Candidates(bare); }
            case None { return new List[String](); }
        }
    }

    /*
     * Unqualified - The readable, fully-qualified form of a scoped declaration name
     */
    String func Unqualified(String name) {
        match (self.names.scopes) {
            case Some(t) {
                match (t.TryUnqualify(name)) {
                    case Some(qn) { return t.Display(QN.Scope(qn), QN.Name(qn)); }
                    case None { return name; }
                }
            }
            case None { return name; }
        }
    }

    /*
     * IsScoped - True when a scope declares this exact qualified name, as opposed to it merely
     * containing one
     */
    bool func IsScoped(String name) {
        match (self.names.scopes) {
            case Some(t) {
                match (t.TryUnqualify(name)) { case Some(qn) { return true; } case None { return false; } }
            }
            case None { return false; }
        }
    }

    /*
     * TryStructure - The instantiation a flat name denotes: what the build stamped, or failing that
     * whatever composed the spelling, which is how an instantiation that was never stamped still
     * reads as 'Box[int]' rather than as its internal name.
     */
    Optional[GenericKey] func TryStructure(String name) {
        match (self.names.stamped.Find(name)) {
            case Some(k) { return Optional.Some(k); }
            case None { }
        }
        if (self.IsScoped(name)) { return Optional[GenericKey].None(); }
        return self.names.composed.Find(name);
    }

    /*
     * DisplayName - The user readable display name for a type, expanding generic instantiations
     * recursively, eg. List_int becomes List[int], and unqualifying scoped names
     */
    public String func DisplayName(String name) {
        match (self.TryStructure(name)) {
            case None { return self.Unqualified(name); }
            case Some(k) {
                let StringBuilder sb = new StringBuilder();
                self.AppendDisplayName(sb, name);
                return sb.ToString();
            }
        }
    }

    /*
     * AppendDisplayName - Recursively appends the user-readable display name for a type
     */
    void func AppendDisplayName(StringBuilder sb, String name) {
        match (self.TryStructure(name)) {
            case Some(key) {
                sb.Put(self.Unqualified(GK.Base(key)));
                sb.AppendChar('[');
                let List[String] args = GK.Args(key);
                let int i = 0;
                while (i < args.Length()) {
                    if (i > 0) { sb.Put(", "); }
                    self.AppendDisplayName(sb, args.Get(i));
                    i = i + 1;
                }
                sb.AppendChar(']');
            }
            case None { sb.Put(self.Unqualified(name)); }
        }
    }

    /*
     * Sanitize - Turns a scope-qualified Gata name into a C-safe fragment
     */
    public String func Sanitize(String name) {
        match (self.names.scopes) {
            case Some(tree) {
                match (tree.TryUnqualify(name)) {
                    case Some(qn) { return QN.Name(qn) + tree.Token(QN.Scope(qn)); }
                    case None { }
                }
            }
            case None { }
        }
        let int at = name.IndexOfChar('@');
        if (at < 0) { return name; }
        return name.Substring(0, at) + "_s"
             + Mangle.Hash(name.Substring(at, name.Length() - at));
    }

    /*
     * Class - The C struct typedef name for a Gata class, using the dense token if available
     */
    public String func Class(String name) {
        match (self.names.dense.Find(name)) {
            case Some(d) { return d; }
            case None { return "gata_" + self.Sanitize(name); }
        }
    }

    /*
     * Allocator - The C allocator function name for a class, using the dense token if available
     */
    public String func Allocator(String cls) {
        match (self.names.dense.Find(cls)) {
            case Some(d) { return d + "_n"; }
            case None { return "new_" + self.Sanitize(cls); }
        }
    }

    /*
     * Dtor - The C destructor function name for a class, using the dense token if available
     */
    public String func Dtor(String cls) {
        match (self.names.dense.Find(cls)) {
            case Some(d) { return d + "_d"; }
            case None { return "gata_" + self.Sanitize(cls) + "__dtor"; }
        }
    }

    /*
     * ProcessVar - The C name of the static holding a process variable
     */
    public String func ProcessVar(String procFull, String name) {
        return "gata_" + self.Sanitize(procFull) + "_state_" + self.Sanitize(name);
    }

    /*
     * ProcessStateInit - The C name of the generated function that assigns a process's variables
     * their initial values. External linkage: the launcher lives in its own translation unit.
     */
    public String func ProcessStateInit(String procFull) {
        return "gata_" + self.Sanitize(procFull) + "_state_init";
    }

    /*
     * EnumName - The C typedef name for a Gata enum type
     */
    public String func EnumName(String name) { return "gata_" + self.Sanitize(name); }

    /*
     * EnumMember - The C enumerator name for a member of a Gata enum type
     */
    public String func EnumMember(String enumName, String member) {
        return "gata_" + self.Sanitize(enumName) + "_" + member;
    }

    /*
     * UnionName - The C typedef name for a Gata union type
     */
    public String func UnionName(String name) { return "gata_" + self.Sanitize(name); }

    /*
     * UnionTag - The C tag enumerator name for a variant of a Gata union type
     */
    public String func UnionTag(String unionName, String variant) {
        return "gata_" + self.Sanitize(unionName) + "_" + variant;
    }

    /*
     * UnionRetain - The C name of a managed union's generated retain, which switches on the tag and
     * returns the union unchanged so it composes like the runtime intrinsic. Not densified, since
     * unions keep their readable typedef name and one type must be spelled one way.
     */
    public String func UnionRetain(String name) { return "gata_" + self.Sanitize(name) + "__retain"; }

    /*
     * UnionRelease - The C name of a managed union's generated release, which switches on the tag
     * and releases whatever the live variant holds
     */
    public String func UnionRelease(String name) { return "gata_" + self.Sanitize(name) + "__release"; }

    /*
     * UnionEq - The C name of a union's generated structural equality, which compares tags first
     * and then the live variant's fields
     */
    public String func UnionEq(String name) { return "gata_" + self.Sanitize(name) + "__eq"; }

    /*
     * Method - The C function name for a method, appending the overload suffix when overloaded
     */
    public String func Method(String owner, String name, List[Param] ps, bool overloaded) {
        let String bare = "gata_" + self.Sanitize(owner) + "_" + name;
        return overloaded ? bare + "_" + Mangle.OverloadSuffix(ps) : bare;
    }

    /*
     * FreeFunc - The C function name for a free function. Entry functions use the kernel entry
     * constant; extern functions use their bare C name; all others get the gata_ prefix.
     */
    public String func FreeFunc(String name, List[Param] ps, bool overloaded, bool isEntry, bool isExtern) {
        if (isEntry) { return Mangle.KernelEntry(); }
        if (isExtern) { return name; }
        let String b = name.StartsWith("gata_") ? name : "gata_" + self.Sanitize(name);
        return overloaded ? b + "_" + Mangle.OverloadSuffix(ps) : b;
    }

    /*
     * PrivateFreeFunc - The C function name for a file-local private free function, prefixed by a
     * stable per-file token so two files may reuse the same name without clashing
     */
    public String func PrivateFreeFunc(String fileToken, String name, List[Param] ps, bool overloaded) {
        let String bare = "gata_f" + fileToken + "_" + self.Sanitize(name);
        return overloaded ? bare + "_" + Mangle.OverloadSuffix(ps) : bare;
    }

    /*
     * Operator - The C name for an operator overload. 'overloaded' appends a disambiguating suffix
     * - only 'as' can have more than one per class today, distinguished by parameter type as every
     * other parameterized overload already is.
     */
    public String func Operator(String owner, String op, List[Param] ps, bool overloaded) {
        let String bare = "gata_" + self.Sanitize(owner) + "_" + Mangle.OpSuffix(op);
        if (!overloaded) { return bare; }
        let String suffix = ps.Length() > 0 ? Mangle.OverloadSuffix(ps) : "unary";
        return bare + "_" + suffix;
    }

    /*
     * CType - The C spelling of an IR type under the current naming, composed on first ask.
     * Replaces the ComposeCType that lived on IrType in C#; it has to live here because every
     * named case consults the dense map, and Ir.g must not depend on the NameTable.
     */
    public String func CType(IrType t) {
        let String key = Types.Key(t);
        match (self.names.cTypes.Find(key)) {
            case Some(c) { return c; }
            case None { }
        }
        let String composed = self.ComposeCType(t);
        self.names.cTypes.Put(key, composed);
        return composed;
    }

    /*
     * ComposeCType - Composes the C type spelling from scratch. Reached once per type per naming
     * round.
     */
    String func ComposeCType(IrType t) {
        match (t) {
            case IrVoidType(x)    { return "void"; }
            case IrErrorType(x)   { return "gata_ERROR_TYPE"; }
            case IrPrimType(x)    { return PrimTypes.ToC(x.cName); }
            case IrClassRef(x)    { return self.Class(x.className) + "*"; }
            case IrEnumType(x)    { return self.EnumName(x.name); }
            case IrUnionType(x)   { return self.UnionName(x.name); }
            case IrPtrType(x)     { return self.CType(x.inner) + "*"; }
            case IrArrayType(x)   { return self.Class(Types.MangledName(t)); }
            case IrResultType(x)  { return Types.ResultName(x); }
            case IrFuncPtrType(x) { return self.Class(Types.MangledName(t)); }
        }
    }
}
