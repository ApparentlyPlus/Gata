/*
 * Ir.g - the typed intermediate representation the resolver produces and the backend consumes
 *
 * Ports Appa/src/IR/Ir.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Int.g";
import "src/Diagnostics/TextSpan.g";
import "src/Syntax/Ast.g";
import "src/Semantics/SymbolTable.g";

/*
 * One source of truth for scalar types: each primitive's C spelling, family and promotion rank.
 * Every other predicate and list derives from it, so adding a primitive is one place that cannot
 * drift across passes.
 */
union PrimInfo { Info(String cType, bool isInt, bool isFloatTy, int rank, bool isUnsigned), Unknown }

module PrimTypes {

    /*
     * Lookup - The row for a primitive spelling, or Unknown
     */
    public PrimInfo func Lookup(String s) {
        if (s == "bool")    { return PrimInfo.Info("bool",      true,  false, 1, false); }
        if (s == "char")    { return PrimInfo.Info("char",      true,  false, 2, false); }
        if (s == "sbyte")   { return PrimInfo.Info("int8_t",    true,  false, 2, false); }
        if (s == "byte")    { return PrimInfo.Info("uint8_t",   true,  false, 2, true);  }
        if (s == "short")   { return PrimInfo.Info("int16_t",   true,  false, 3, false); }
        if (s == "ushort")  { return PrimInfo.Info("uint16_t",  true,  false, 3, true);  }
        if (s == "int")     { return PrimInfo.Info("int32_t",   true,  false, 4, false); }
        if (s == "uint")    { return PrimInfo.Info("uint32_t",  true,  false, 4, true);  }
        if (s == "int64")   { return PrimInfo.Info("int64_t",   true,  false, 5, false); }
        if (s == "uint64")  { return PrimInfo.Info("uint64_t",  true,  false, 5, true);  }
        if (s == "usize")   { return PrimInfo.Info("size_t",    true,  false, 5, true);  }
        if (s == "uintptr") { return PrimInfo.Info("uintptr_t", true,  false, 5, true);  }
        if (s == "float")   { return PrimInfo.Info("float",     false, true,  6, false); }
        if (s == "double")  { return PrimInfo.Info("double",    false, true,  7, false); }
        if (s == "void")    { return PrimInfo.Info("void",      false, false, 0, false); }
        return PrimInfo.Unknown();
    }

    /*
     * IsPrim - True if the string is a recognised Gata primitive spelling
     */
    public bool func IsPrim(String s) {
        match (PrimTypes.Lookup(s)) {
            case Info(c, i, f, r, u) { return true; }
            case Unknown { return false; }
        }
    }

    /*
     * ToC - The fixed-width C type for a primitive spelling; an unknown name is its own answer
     */
    public String func ToC(String s) {
        match (PrimTypes.Lookup(s)) {
            case Info(c, i, f, r, u) { return c; }
            case Unknown { return s; }
        }
    }

    /*
     * IsIntCanon - True if the canonical token belongs to the integer family (bool included,
     * matching C's integral treatment)
     */
    public bool func IsIntCanon(String canon) {
        match (PrimTypes.Lookup(canon)) {
            case Info(c, i, f, r, u) { return i; }
            case Unknown { return false; }
        }
    }

    /*
     * IsFloat - True if the canonical token is float or double
     */
    public bool func IsFloat(String canon) {
        match (PrimTypes.Lookup(canon)) {
            case Info(c, i, f, r, u) { return f; }
            case Unknown { return false; }
        }
    }

    /*
     * Rank - The numeric promotion rank used to pick the wider operand type. Unknown names take
     * int's rank, mirroring the resolver's historical default.
     */
    public int func Rank(String name) {
        match (PrimTypes.Lookup(name)) {
            case Info(c, i, f, r, u) { return r; }
            case Unknown { return 4; }
        }
    }

    /*
     * IsUnsignedCanon - True if the canonical token is an unsigned integer spelling. These need
     * their own formatting path: handing one to a signed printer reinterprets the high bit.
     */
    public bool func IsUnsignedCanon(String canon) {
        match (PrimTypes.Lookup(canon)) {
            case Info(c, i, f, r, u) { return u; }
            case Unknown { return false; }
        }
    }

    /*
     * IntBits - The width in bits of an integer primitive, or 0 for anything else
     */
    public int func IntBits(String canon) {
        if (canon == "bool") { return 1; }
        if (canon == "char" || canon == "sbyte" || canon == "byte") { return 8; }
        if (canon == "short" || canon == "ushort") { return 16; }
        if (canon == "int" || canon == "uint") { return 32; }
        if (canon == "int64" || canon == "uint64") { return 64; }
        return 0;
    }

    /*
     * Spellings - Every accepted spelling: the front end's set of primitive type names
     */
    public List[String] func Spellings() {
        let List[String] r = new List[String]();
        r.Add("bool"); r.Add("char"); r.Add("sbyte"); r.Add("byte");
        r.Add("short"); r.Add("ushort"); r.Add("int"); r.Add("uint");
        r.Add("int64"); r.Add("uint64"); r.Add("usize"); r.Add("uintptr");
        r.Add("float"); r.Add("double"); r.Add("void");
        return r;
    }
}

/*
 * Every IR type node.
 */
union IrType {
    IrVoidType(IrVoidType t),
    IrErrorType(IrErrorType t),
    IrPrimType(IrPrimType t),
    IrClassRef(IrClassRef t),
    IrEnumType(IrEnumType t),
    IrPtrType(IrPtrType t),
    IrArrayType(IrArrayType t),
    IrResultType(IrResultType t),
    IrFuncPtrType(IrFuncPtrType t),
    IrUnionType(IrUnionType t)
}

/*
 * The void type - used as a return type for functions that produce no value.
 */
class IrVoidType { func _init() { } }

/*
 * The type of an expression the resolver could not type because it already reported why. It never
 * reaches the backend: a build with errors stops before emission, so ComposeCType exists only to
 * keep the contract total and names itself loudly if that ever stops being true.
 */
class IrErrorType { func _init() { } }

/*
 * A primitive scalar type. cName is the canonical token; ComposeCType lowers it to the
 * corresponding fixed-width C type.
 */
class IrPrimType {
    public String cName;
    func _init(String cName) { self.cName = cName; }
}

/*
 * A reference to a named class type. Lowers to a mangled pointer in C output.
 */
class IrClassRef {
    public String className;
    func _init(String className) { self.className = className; }
}

/*
 * A named integer backed enum type. Distinct from int with no implicit conversion, but comparable,
 * assignable, and usable as a switch scrutinee. Lowers to a C enum.
 */
class IrEnumType {
    public String name;
    func _init(String name) { self.name = name; }
}

/*
 * A pointer type for unsafe Gata code. Lowers to a C pointer to the inner type.
 */
class IrPtrType {
    public IrType inner;
    func _init(IrType inner) { self.inner = inner; }
}

/*
 * A fixed-size array type [N]T - a value aggregate, not a heap reference. Monomorphized per
 * (element, size) pair into a named C struct. Copies, returns, and iterates by value with the
 * length carried in the type.
 */
class IrArrayType {
    public IrType elem;
    public int size;
    func _init(IrType elem, int size) { self.elem = elem; self.size = size; }
}

/*
 * A Result-of-T wrapper produced by throws functions. Lowers to a C struct with a bool tag and a
 * value or error payload.
 */
class IrResultType {
    public IrType inner;
    func _init(IrType inner) { self.inner = inner; }
}

/*
 * A function-pointer type func(T1, T2) -> R. Its C spelling is a stable typedef name rather than
 * an inline declarator, because inline declarators cannot be used with the type-then-name emission
 * pattern. The typedef is emitted once per distinct signature from IrModule.funcPtrTypes.
 */
class IrFuncPtrType {
    public IrType ret;
    public List[IrType] params;
    func _init(IrType ret, List[IrType] params) { self.ret = ret; self.params = params; }
}

/*
 * A named tagged-union type. Not generic, not ARC-managed. Lowers to a tag enum and a C struct
 * containing the tag and a union of per-variant payload structs.
 */
class IrUnionType {
    public String name;
    func _init(String name) { self.name = name; }
}

module Types {

    /*
     * MangledName - The stable C-identifier mangling of a type. This is also the structural
     * identity a type has, which is what IrTypeTable interns on.
     */
    public String func MangledName(IrType t) {
        match (t) {
            case IrVoidType(x)    { return "void"; }
            case IrErrorType(x)   { return "error"; }
            case IrPrimType(x)    { return x.cName; }
            case IrClassRef(x)    { return x.className; }
            case IrEnumType(x)    { return x.name; }
            case IrUnionType(x)   { return x.name; }
            case IrPtrType(x)     { return Types.MangledName(x.inner) + "_p"; }
            case IrArrayType(x)   { return "Arr_" + Types.MangledName(x.elem) + "_" + Int.ToString(x.size); }
            case IrResultType(x)  { return "Result_" + Types.MangledName(x.inner); }
            case IrFuncPtrType(x) {
                let StringBuilder sb = new StringBuilder();
                sb.Put("Fn_").Put(Types.MangledName(x.ret)).Put("__");
                let int i = 0;
                while (i < x.params.Length()) {
                    if (i > 0) { sb.AppendChar('_'); }
                    sb.Put(Types.MangledName(x.params.Get(i)));
                    i = i + 1;
                }
                return sb.ToString();
            }
        }
    }

    /*
     * Tag - A one-letter discriminator for the type's kind. MangledName alone is not a safe
     * identity key: a class, an enum and a union named 'Foo' all mangle to "Foo". C# never had to
     * care because it interned on the record's own type-aware equality; the tag restores that.
     */
    public String func Tag(IrType t) {
        match (t) {
            case IrVoidType(x)    { return "v"; }
            case IrErrorType(x)   { return "!"; }
            case IrPrimType(x)    { return "p"; }
            case IrClassRef(x)    { return "c"; }
            case IrEnumType(x)    { return "e"; }
            case IrUnionType(x)   { return "u"; }
            case IrPtrType(x)     { return "*"; }
            case IrArrayType(x)   { return "a"; }
            case IrResultType(x)  { return "r"; }
            case IrFuncPtrType(x) { return "f"; }
        }
    }

    /*
     * Key - The full structural identity of a type: its kind tag and its mangling
     */
    public String func Key(IrType t) { return Types.Tag(t) + ":" + Types.MangledName(t); }

    /*
     * TypeEq - Structural type equality. C# gets this from record equality plus interning, where
     * reference equality then answers it outright; here it is the key comparison, which is the
     * same question asked directly.
     */
    public bool func TypeEq(IrType a, IrType b) { return Types.Key(a) == Types.Key(b); }

    /*
     * Same - Reference identity, standing in for C#'s ReferenceEquals.
     */
    public bool func Same(IrType a, IrType b) { return a == b; }

    /*
     * ResultName - The C typedef name for a result type, e.g. Result_int or Result_MyClass. Void
     * folds to int, matching SymbolTable.ResultInnerName.
     */
    public String func ResultName(IrResultType r) {
        match (r.inner) {
            case IrVoidType(x) { return "Result_int"; }
            default { return "Result_" + Types.MangledName(r.inner); }
        }
    }

    /*
     * IsNumeric - INTEGER-valued, which is narrower than the name suggests and deliberately so:
     * C#'s IrPrimType.IsNumeric is PrimTypes.IsIntCanon(CName) and nothing more. Every site that
     * means "integer or float" writes 'IsNumeric(t) || IsFloat(t)' explicitly, on both sides.
     *
     * Folding floats in here looks harmless and is not: the emitter narrows a binary operator to
     * its result type when IsNumeric says so, and doing that for a double emits a redundant
     * '((double)(a * b))' the C# compiler does not.
     */
    public bool func IsNumeric(IrType t) {
        match (t) {
            case IrPrimType(x) { return PrimTypes.IsIntCanon(x.cName); }
            default { return false; }
        }
    }

    public bool func IsFloat(IrType t) {
        match (t) {
            case IrPrimType(x) { return PrimTypes.IsFloat(x.cName); }
            default { return false; }
        }
    }

    public bool func IsChar(IrType t) {
        match (t) {
            case IrPrimType(x) { return x.cName == "char"; }
            default { return false; }
        }
    }

    public bool func IsUnsigned(IrType t) {
        match (t) {
            case IrPrimType(x) { return PrimTypes.IsUnsignedCanon(x.cName); }
            default { return false; }
        }
    }

    public bool func IsString(IrType t) {
        match (t) {
            case IrClassRef(x) { return x.className == "String" || x.className == "gata_String"; }
            default { return false; }
        }
    }

    public bool func IsVoid(IrType t) {
        match (t) { case IrVoidType(x) { return true; } default { return false; } }
    }

    public bool func IsError(IrType t) {
        match (t) { case IrErrorType(x) { return true; } default { return false; } }
    }
}

/*
 * The hash-consing table for IR types. A type is a value, so one instance per distinct shape is
 * enough, and identity then answers type equality outright.
 */
class IrTypeTable {
    StringMap[IrType] table;

    func _init() { self.table = new StringMap[IrType](); }

    /*
     * Intern - The canonical instance for a type's shape, which is the given one the first time
     * that shape is seen
     */
    public IrType func Intern(IrType t) {
        let String k = Types.Key(t);
        match (self.table.Find(k)) {
            case Some(existing) { return existing; }
            case None { self.table.Put(k, t); return t; }
        }
    }

    public IrType func Void()  { return self.Intern(IrType.IrVoidType(new IrVoidType())); }
    public IrType func Error() { return self.Intern(IrType.IrErrorType(new IrErrorType())); }

    public IrType func Prim(String canon) { return self.Intern(IrType.IrPrimType(new IrPrimType(canon))); }

    public IrType func ClassRef(String className) {
        return self.Intern(IrType.IrClassRef(new IrClassRef(className)));
    }

    public IrType func EnumType(String name) { return self.Intern(IrType.IrEnumType(new IrEnumType(name))); }

    public IrType func UnionType(String name) { return self.Intern(IrType.IrUnionType(new IrUnionType(name))); }

    public IrType func Ptr(IrType inner) { return self.Intern(IrType.IrPtrType(new IrPtrType(inner))); }

    public IrType func Array(IrType elem, int size) {
        return self.Intern(IrType.IrArrayType(new IrArrayType(elem, size)));
    }

    public IrType func Result(IrType inner) {
        return self.Intern(IrType.IrResultType(new IrResultType(inner)));
    }

    public IrType func FuncPtr(IrType ret, List[IrType] ps) {
        return self.Intern(IrType.IrFuncPtrType(new IrFuncPtrType(ret, ps)));
    }

    // The singletons C# exposes as static readonly fields on IrType.
    public IrType func Bool()   { return self.Prim("bool"); }
    public IrType func Int()    { return self.Prim("int"); }
    public IrType func Char()   { return self.Prim("char"); }
    public IrType func Short()  { return self.Prim("short"); }
    public IrType func Long()   { return self.Prim("int64"); }
    public IrType func Float()  { return self.Prim("float"); }
    public IrType func Double() { return self.Prim("double"); }
    public IrType func SizeT()  { return self.Prim("usize"); }
    public IrType func Str()    { return self.ClassRef("String"); }
}

/*
 * Every IR expression node. Each carries its result type and an optional source span.
 */
union IrExpr {
    IrLitInt(IrLitInt e),
    IrLitChar(IrLitChar e),
    IrLitFloat(IrLitFloat e),
    IrLitBool(IrLitBool e),
    IrLitString(IrLitString e),
    IrLitNull(IrLitNull e),
    IrEnumConst(IrEnumConst e),
    IrVar(IrVar e),
    IrGlobal(IrGlobal e),
    IrSelfExpr(IrSelfExpr e),
    IrFieldLoad(IrFieldLoad e),
    IrIndex(IrIndex e),
    IrStaticCall(IrStaticCall e),
    IrInstanceCall(IrInstanceCall e),
    IrThrowsCall(IrThrowsCall e),
    IrThrowsInstanceCall(IrThrowsInstanceCall e),
    IrCatchCall(IrCatchCall e),
    IrFuncRef(IrFuncRef e),
    IrIndirectCall(IrIndirectCall e),
    IrUnionConstruct(IrUnionConstruct e),
    IrUnionField(IrUnionField e),
    IrBinOp(IrBinOp e),
    IrTernary(IrTernary e),
    IrUnaryOp(IrUnaryOp e),
    IrPostfix(IrPostfix e),
    IrCast(IrCast e),
    IrNew(IrNew e),
    IrNewInit(IrNewInit e),
    IrArrayLit(IrArrayLit e),
    IrInterp(IrInterp e),
    IrAddrOf(IrAddrOf e),
    IrDeref(IrDeref e),
    IrSizeof(IrSizeof e),
    IrDefault(IrDefault e),
    IrStructLit(IrStructLit e)
}

/*
 * An integer literal. value is the 64-bit bit pattern; cText overrides the emitted text when set.
 */
class IrLitInt {
    public int64 value;
    public IrType type;
    public Optional[String] cText;
    public TextSpan span;
    func _init(int64 value, IrType type, Optional[String] cText) {
        self.value = value;
        self.type = type;
        self.cText = cText;
        self.span = TS.NoneSpan();
    }
}

/*
 * A character literal. codepoint is the code point of the character.
 */
class IrLitChar {
    public int codepoint;
    public IrType type;
    public TextSpan span;
    func _init(int codepoint, IrType type) { self.codepoint = codepoint; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A floating-point literal. raw is emitted verbatim as valid C text.
 */
class IrLitFloat {
    public String raw;
    public IrType type;
    public TextSpan span;
    func _init(String raw, IrType type) { self.raw = raw; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A boolean literal.
 */
class IrLitBool {
    public bool value;
    public IrType type;
    public TextSpan span;
    func _init(bool value, IrType type) { self.value = value; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A string literal. raw includes the surrounding quotes.
 */
class IrLitString {
    public String raw;
    public IrType type;
    public TextSpan span;
    func _init(String raw, IrType type) { self.raw = raw; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A null literal of a specific type.
 */
class IrLitNull {
    public IrType type;
    public TextSpan span;
    func _init(IrType type) { self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A reference to a named enum member.
 */
class IrEnumConst {
    public String enumName;
    public String member;
    public IrType type;
    public TextSpan span;
    func _init(String enumName, String member, IrType type) {
        self.enumName = enumName;
        self.member = member;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A local variable or parameter reference.
 */
class IrVar {
    public String name;
    public IrType type;
    public bool isRef;
    public TextSpan span;
    func _init(String name, IrType type, bool isRef) {
        self.name = name;
        self.type = type;
        self.isRef = isRef;
        self.span = TS.NoneSpan();
    }
}

/*
 * A reference to a process variable: a translation-unit static, addressed by the C name it was
 * given rather than by a local's mangling.
 */
class IrGlobal {
    public String cName;
    public IrType type;
    public TextSpan span;
    func _init(String cName, IrType type) { self.cName = cName; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A reference to the implicit self object inside a method body.
 */
class IrSelfExpr {
    public String className;
    public IrType type;
    public TextSpan span;
    func _init(String className, IrType type) { self.className = className; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A field load from an object expression.
 */
class IrFieldLoad {
    public IrExpr obj;
    public String field;
    public IrType type;
    public TextSpan span;
    func _init(IrExpr obj, String field, IrType type) {
        self.obj = obj;
        self.field = field;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * An index expression into a collection or fixed array.
 */
class IrIndex {
    public IrExpr obj;
    public IrExpr idx;
    public IrType type;
    public TextSpan span;
    func _init(IrExpr obj, IrExpr idx, IrType type) {
        self.obj = obj;
        self.idx = idx;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A call to a static (free) C function. cName is the fully-qualified C function name.
 */
class IrStaticCall {
    public String cName;
    public IrType type;
    public List[IrExpr] args;
    public TextSpan span;
    func _init(String cName, IrType type, List[IrExpr] args) {
        self.cName = cName;
        self.type = type;
        self.args = args;
        self.span = TS.NoneSpan();
    }
}

/*
 * A call to an instance method, passing the receiver as the first argument.
 */
class IrInstanceCall {
    public IrExpr recv;
    public String cName;
    public IrType type;
    public List[IrExpr] args;
    public TextSpan span;
    func _init(IrExpr recv, String cName, IrType type, List[IrExpr] args) {
        self.recv = recv;
        self.cName = cName;
        self.type = type;
        self.args = args;
        self.span = TS.NoneSpan();
    }
}

/*
 * A call to a throws-annotated static function. Its type wraps innerType in Result.
 */
class IrThrowsCall {
    public String cName;
    public IrType innerType;
    public IrType type;
    public List[IrExpr] args;
    public TextSpan span;
    func _init(String cName, IrType innerType, IrType type, List[IrExpr] args) {
        self.cName = cName;
        self.innerType = innerType;
        self.type = type;
        self.args = args;
        self.span = TS.NoneSpan();
    }
}

/*
 * A call to a throws-annotated instance method. Its type wraps innerType in Result.
 */
class IrThrowsInstanceCall {
    public IrExpr recv;
    public String cName;
    public IrType innerType;
    public IrType type;
    public List[IrExpr] args;
    public TextSpan span;
    func _init(IrExpr recv, String cName, IrType innerType, IrType type, List[IrExpr] args) {
        self.recv = recv;
        self.cName = cName;
        self.innerType = innerType;
        self.type = type;
        self.args = args;
        self.span = TS.NoneSpan();
    }
}

/*
 * A throwing call carrying its own inline failure handler (`f() catch { ... }`). Its type is the
 * inner type, not IrThrowsCall's Result wrapper, since the handler always supplies a value. The
 * ARC pass splits it into a declaration plus an if/else before the emitter.
 */
class IrCatchCall {
    public IrExpr call;
    public IrBlock handler;
    public IrType type;
    public TextSpan span;
    func _init(IrExpr call, IrBlock handler, IrType type) {
        self.call = call;
        self.handler = handler;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A bare reference to a free function by name, decaying to a function-pointer value. cName is a
 * valid C function-pointer value with no cast needed.
 */
class IrFuncRef {
    public String cName;
    public IrType type;
    public TextSpan span;
    func _init(String cName, IrType type) { self.cName = cName; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A call through a function-pointer-typed expression.
 */
class IrIndirectCall {
    public IrExpr target;
    public IrType type;
    public List[IrExpr] args;
    public TextSpan span;
    func _init(IrExpr target, IrType type, List[IrExpr] args) {
        self.target = target;
        self.type = type;
        self.args = args;
        self.span = TS.NoneSpan();
    }
}

/*
 * Constructs a union variant value. variantIndex selects the tag.
 */
class IrUnionConstruct {
    public IrType type;
    public int variantIndex;
    public List[IrExpr] args;
    public TextSpan span;
    func _init(IrType type, int variantIndex, List[IrExpr] args) {
        self.type = type;
        self.variantIndex = variantIndex;
        self.args = args;
        self.span = TS.NoneSpan();
    }
}

/*
 * Reads one payload field of a union's active variant. Only emitted after the tag has already
 * been tested.
 */
class IrUnionField {
    // Named target, not union: 'union' is a reserved keyword.
    public IrExpr target;
    public int variantIndex;
    public String field;
    public IrType type;
    public TextSpan span;
    func _init(IrExpr target, int variantIndex, String field, IrType type) {
        self.target = target;
        self.variantIndex = variantIndex;
        self.field = field;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A binary operator expression.
 */
class IrBinOp {
    public BinOp op;
    public IrExpr left;
    public IrExpr right;
    public IrType type;
    public TextSpan span;
    func _init(BinOp op, IrExpr left, IrExpr right, IrType type) {
        self.op = op;
        self.left = left;
        self.right = right;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A ternary conditional expression.
 */
class IrTernary {
    public IrExpr cond;
    public IrExpr then;
    public IrExpr otherwise;
    public IrType type;
    public TextSpan span;
    func _init(IrExpr cond, IrExpr then, IrExpr otherwise, IrType type) {
        self.cond = cond;
        self.then = then;
        self.otherwise = otherwise;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A prefix unary operator expression.
 */
class IrUnaryOp {
    public UnOp op;
    public IrExpr operand;
    public IrType type;
    public TextSpan span;
    func _init(UnOp op, IrExpr operand, IrType type) {
        self.op = op;
        self.operand = operand;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A postfix operator expression such as i++ or i--. Its type is the operand's.
 */
class IrPostfix {
    public PostfixOp op;
    public IrExpr operand;
    public IrType type;
    public TextSpan span;
    func _init(PostfixOp op, IrExpr operand, IrType type) {
        self.op = op;
        self.operand = operand;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * An explicit cast to a target type.
 */
class IrCast {
    public IrType to;
    public IrExpr value;
    public TextSpan span;
    func _init(IrType to, IrExpr value) { self.to = to; self.value = value; self.span = TS.NoneSpan(); }
}

/*
 * A heap allocation of a named class with constructor arguments.
 */
class IrNew {
    public String className;
    public List[IrExpr] args;
    public IrType type;
    public TextSpan span;
    func _init(String className, List[IrExpr] args, IrType type) {
        self.className = className;
        self.args = args;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A heap allocation followed by repeated Add calls to populate a collection. Lowered to a GNU
 * statement expression by the emitter.
 */
class IrNewInit {
    public String className;
    public List[IrExpr] args;
    public String addCName;
    public List[IrExpr] inits;
    public IrType type;
    public TextSpan span;
    func _init(String className, List[IrExpr] args, String addCName, List[IrExpr] inits, IrType type) {
        self.className = className;
        self.args = args;
        self.addCName = addCName;
        self.inits = inits;
        self.type = type;
        self.span = TS.NoneSpan();
    }
}

/*
 * A fixed-array literal [e1, e2, ...] lowered to a C compound literal.
 */
class IrArrayLit {
    public IrType arrType;
    public List[IrExpr] elems;
    public TextSpan span;
    func _init(IrType arrType, List[IrExpr] elems) {
        self.arrType = arrType;
        self.elems = elems;
        self.span = TS.NoneSpan();
    }
}

/*
 * An interpolated string whose parts are all typed String.
 */
class IrInterp {
    public List[IrExpr] parts;
    public IrType type;
    public TextSpan span;
    func _init(List[IrExpr] parts, IrType type) { self.parts = parts; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * Takes the address of a target expression, producing a pointer.
 */
class IrAddrOf {
    public IrExpr target;
    public IrType type;
    public TextSpan span;
    func _init(IrExpr target, IrType type) { self.target = target; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * Dereferences a pointer expression to yield the pointed-to value.
 */
class IrDeref {
    public IrExpr ptr;
    public IrType type;
    public TextSpan span;
    func _init(IrExpr ptr, IrType type) { self.ptr = ptr; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A sizeof expression. Emits as C sizeof(ctype).
 */
class IrSizeof {
    public IrType of;
    public IrType type;
    public TextSpan span;
    func _init(IrType of, IrType type) { self.of = of; self.type = type; self.span = TS.NoneSpan(); }
}

/*
 * A default value expression. Emits as a C zero-cast: (ctype)0.
 */
class IrDefault {
    public IrType of;
    public TextSpan span;
    func _init(IrType of) { self.of = of; self.span = TS.NoneSpan(); }
}

/*
 * One field of a designated struct literal.
 */
class IrFieldInit {
    public String field;
    public IrExpr value;
    func _init(String field, IrExpr value) { self.field = field; self.value = value; }
}

/*
 * A designated struct literal: `(T){ .field = value, ... }`. Fields left out of the list are
 * zero-initialized by C's own rules, which is how a Result carrying only an error is built. The
 * ARC pass uses this to construct the Result values a throws function returns.
 */
class IrStructLit {
    public IrType structType;
    public List[IrFieldInit] structFields;
    public TextSpan span;
    func _init(IrType structType, List[IrFieldInit] structFields) {
        self.structType = structType;
        self.structFields = structFields;
        self.span = TS.NoneSpan();
    }
}

module Exprs2 {

    /*
     * TypeOf - The result type of any IR expression (C#'s IrExpr.Type base property)
     */
    public IrType func TypeOf(IrExpr e) {
        match (e) {
            case IrLitInt(x)              { return x.type; }
            case IrLitChar(x)             { return x.type; }
            case IrLitFloat(x)            { return x.type; }
            case IrLitBool(x)             { return x.type; }
            case IrLitString(x)           { return x.type; }
            case IrLitNull(x)             { return x.type; }
            case IrEnumConst(x)           { return x.type; }
            case IrVar(x)                 { return x.type; }
            case IrGlobal(x)              { return x.type; }
            case IrSelfExpr(x)            { return x.type; }
            case IrFieldLoad(x)           { return x.type; }
            case IrIndex(x)               { return x.type; }
            case IrStaticCall(x)          { return x.type; }
            case IrInstanceCall(x)        { return x.type; }
            case IrThrowsCall(x)          { return x.type; }
            case IrThrowsInstanceCall(x)  { return x.type; }
            case IrCatchCall(x)           { return x.type; }
            case IrFuncRef(x)             { return x.type; }
            case IrIndirectCall(x)        { return x.type; }
            case IrUnionConstruct(x)      { return x.type; }
            case IrUnionField(x)          { return x.type; }
            case IrBinOp(x)               { return x.type; }
            case IrTernary(x)             { return x.type; }
            case IrUnaryOp(x)             { return x.type; }
            case IrPostfix(x)             { return x.type; }
            case IrCast(x)                { return x.to; }
            case IrNew(x)                 { return x.type; }
            case IrNewInit(x)             { return x.type; }
            case IrArrayLit(x)            { return x.arrType; }
            case IrInterp(x)              { return x.type; }
            case IrAddrOf(x)              { return x.type; }
            case IrDeref(x)               { return x.type; }
            case IrSizeof(x)              { return x.type; }
            case IrDefault(x)             { return x.of; }
            case IrStructLit(x)           { return x.structType; }
        }
    }

    /*
     * SetSpan - Stamps a source span onto an IR expression that has none yet.
     *
     * C# gets this from a record 'with' expression; here every node owns a mutable span field, so
     * the assignment is written out per variant. Mirrors SpanOf arm for arm, and the two are meant
     * to be edited together.
     */
    public void func SetSpan(IrExpr e, TextSpan span) {
        match (e) {
            case IrLitInt(x) { x.span = span; }
            case IrLitChar(x) { x.span = span; }
            case IrLitFloat(x) { x.span = span; }
            case IrLitBool(x) { x.span = span; }
            case IrLitString(x) { x.span = span; }
            case IrLitNull(x) { x.span = span; }
            case IrEnumConst(x) { x.span = span; }
            case IrVar(x) { x.span = span; }
            case IrGlobal(x) { x.span = span; }
            case IrSelfExpr(x) { x.span = span; }
            case IrFieldLoad(x) { x.span = span; }
            case IrIndex(x) { x.span = span; }
            case IrStaticCall(x) { x.span = span; }
            case IrInstanceCall(x) { x.span = span; }
            case IrThrowsCall(x) { x.span = span; }
            case IrThrowsInstanceCall(x) { x.span = span; }
            case IrCatchCall(x) { x.span = span; }
            case IrFuncRef(x) { x.span = span; }
            case IrIndirectCall(x) { x.span = span; }
            case IrUnionConstruct(x) { x.span = span; }
            case IrUnionField(x) { x.span = span; }
            case IrBinOp(x) { x.span = span; }
            case IrTernary(x) { x.span = span; }
            case IrUnaryOp(x) { x.span = span; }
            case IrPostfix(x) { x.span = span; }
            case IrCast(x) { x.span = span; }
            case IrNew(x) { x.span = span; }
            case IrNewInit(x) { x.span = span; }
            case IrArrayLit(x) { x.span = span; }
            case IrInterp(x) { x.span = span; }
            case IrAddrOf(x) { x.span = span; }
            case IrDeref(x) { x.span = span; }
            case IrSizeof(x) { x.span = span; }
            case IrDefault(x) { x.span = span; }
            case IrStructLit(x) { x.span = span; }
        }
    }

    /*
     * SpanOf - The source span of any IR expression
     */
    public TextSpan func SpanOf(IrExpr e) {
        match (e) {
            case IrLitInt(x)              { return x.span; }
            case IrLitChar(x)             { return x.span; }
            case IrLitFloat(x)            { return x.span; }
            case IrLitBool(x)             { return x.span; }
            case IrLitString(x)           { return x.span; }
            case IrLitNull(x)             { return x.span; }
            case IrEnumConst(x)           { return x.span; }
            case IrVar(x)                 { return x.span; }
            case IrGlobal(x)              { return x.span; }
            case IrSelfExpr(x)            { return x.span; }
            case IrFieldLoad(x)           { return x.span; }
            case IrIndex(x)               { return x.span; }
            case IrStaticCall(x)          { return x.span; }
            case IrInstanceCall(x)        { return x.span; }
            case IrThrowsCall(x)          { return x.span; }
            case IrThrowsInstanceCall(x)  { return x.span; }
            case IrCatchCall(x)           { return x.span; }
            case IrFuncRef(x)             { return x.span; }
            case IrIndirectCall(x)        { return x.span; }
            case IrUnionConstruct(x)      { return x.span; }
            case IrUnionField(x)          { return x.span; }
            case IrBinOp(x)               { return x.span; }
            case IrTernary(x)             { return x.span; }
            case IrUnaryOp(x)             { return x.span; }
            case IrPostfix(x)             { return x.span; }
            case IrCast(x)                { return x.span; }
            case IrNew(x)                 { return x.span; }
            case IrNewInit(x)             { return x.span; }
            case IrArrayLit(x)            { return x.span; }
            case IrInterp(x)              { return x.span; }
            case IrAddrOf(x)              { return x.span; }
            case IrDeref(x)               { return x.span; }
            case IrSizeof(x)              { return x.span; }
            case IrDefault(x)             { return x.span; }
            case IrStructLit(x)           { return x.span; }
        }
    }
}

/*
 * Every IR statement node. Each carries an optional source span.
 */
union IrStmt {
    IrBlock(IrBlock s),
    IrNativeStmt(IrNativeStmt s),
    IrAssignValue(IrAssignValue s),
    IrGoto(IrGoto s),
    IrLabel(IrLabel s),
    IrDeclVar(IrDeclVar s),
    IrAssign(IrAssign s),
    IrExprStmt(IrExprStmt s),
    IrReturn(IrReturn s),
    IrBreak(IrBreak s),
    IrContinue(IrContinue s),
    IrIf(IrIf s),
    IrWhile(IrWhile s),
    IrFor(IrFor s),
    IrForIn(IrForIn s),
    IrTryCatch(IrTryCatch s),
    IrSwitch(IrSwitch s),
    IrMatch(IrMatch s),
    IrUnsafeBlock(IrUnsafeBlock s),
    IrDefer(IrDefer s),
    IrThrow(IrThrow s),
    IrDebug(IrDebug s),
    IrPanic(IrPanic s)
}

/*
 * A sequential list of statements forming a scope.
 */
class IrBlock {
    public List[IrStmt] stmts;
    public TextSpan span;
    func _init(List[IrStmt] stmts) { self.stmts = stmts; self.span = TS.NoneSpan(); }
}

/*
 * A native C statement, spliced verbatim.
 */
class IrNativeStmt {
    public String c;
    public TextSpan span;
    func _init(String c) { self.c = c; self.span = TS.NoneSpan(); }
}

/*
 * `assign v;` inside a catch handler: stores the replacement value into the declaration the
 * handler is attached to. The ARC pass rewrites it into a plain store, since only that pass knows
 * the target's name - the handler is lowered as part of the declaration it belongs to.
 */
class IrAssignValue {
    public IrExpr value;
    public TextSpan span;
    func _init(IrExpr value) { self.value = value; self.span = TS.NoneSpan(); }
}

/*
 * A goto targeting an IrLabel. Only the ARC pass emits these, to route a failed throwing call or
 * an explicit throw to its enclosing try's handler.
 */
class IrGoto {
    public String label;
    public TextSpan span;
    func _init(String label) { self.label = label; self.span = TS.NoneSpan(); }
}

/*
 * A label an IrGoto can target. Emitted as `name:;` - the trailing empty statement keeps a label
 * legal immediately before a closing brace, which C forbids otherwise.
 */
class IrLabel {
    public String name;
    public TextSpan span;
    func _init(String name) { self.name = name; self.span = TS.NoneSpan(); }
}

/*
 * A local variable declaration with an optional initializer.
 */
class IrDeclVar {
    public String name;
    public IrType type;
    public Optional[IrExpr] init;
    public TextSpan span;
    func _init(String name, IrType type, Optional[IrExpr] init) {
        self.name = name;
        self.type = type;
        self.init = init;
        self.span = TS.NoneSpan();
    }
}

/*
 * An assignment expression statement. op is the assignment operator kind, e.g. Assign, AddAssign.
 */
class IrAssign {
    public IrExpr target;
    public AssignOp op;
    public IrExpr value;
    public TextSpan span;
    func _init(IrExpr target, AssignOp op, IrExpr value) {
        self.target = target;
        self.op = op;
        self.value = value;
        self.span = TS.NoneSpan();
    }
}

/*
 * An expression evaluated for its side effects, result discarded.
 */
class IrExprStmt {
    public IrExpr expr;
    public TextSpan span;
    func _init(IrExpr expr) { self.expr = expr; self.span = TS.NoneSpan(); }
}

/*
 * A return statement with an optional value.
 */
class IrReturn {
    public Optional[IrExpr] value;
    public TextSpan span;
    func _init(Optional[IrExpr] value) { self.value = value; self.span = TS.NoneSpan(); }
}

/*
 * A break statement exiting the nearest enclosing loop or switch.
 */
class IrBreak {
    public TextSpan span;
    func _init() { self.span = TS.NoneSpan(); }
}

/*
 * A continue statement jumping to the next iteration of the nearest enclosing loop.
 */
class IrContinue {
    public TextSpan span;
    func _init() { self.span = TS.NoneSpan(); }
}

/*
 * An if/else statement. otherwise is None when there is no else branch.
 */
class IrIf {
    public IrExpr cond;
    public IrBlock then;
    public Optional[IrBlock] otherwise;
    public TextSpan span;
    func _init(IrExpr cond, IrBlock then, Optional[IrBlock] otherwise) {
        self.cond = cond;
        self.then = then;
        self.otherwise = otherwise;
        self.span = TS.NoneSpan();
    }
}

/*
 * A while loop.
 */
class IrWhile {
    public IrExpr cond;
    public IrBlock body;
    public TextSpan span;
    func _init(IrExpr cond, IrBlock body) { self.cond = cond; self.body = body; self.span = TS.NoneSpan(); }
}

/*
 * A C-style for loop with optional init, condition, and step.
 */
class IrFor {
    public Optional[IrStmt] init;
    public Optional[IrExpr] cond;
    public Optional[IrStmt] step;
    public IrBlock body;
    public TextSpan span;
    func _init(Optional[IrStmt] init, Optional[IrExpr] cond, Optional[IrStmt] step, IrBlock body) {
        self.init = init;
        self.cond = cond;
        self.step = step;
        self.body = body;
        self.span = TS.NoneSpan();
    }
}

/*
 * A for-in loop over a collection or fixed array. arraySize is -1 for a class collection.
 */
class IrForIn {
    public String varName;
    public IrType elemType;
    public String lenCName;
    public String getCName;
    public IrExpr collection;
    public IrBlock body;
    public int arraySize;
    public TextSpan span;
    func _init(String varName, IrType elemType, String lenCName, String getCName,
               IrExpr collection, IrBlock body, int arraySize) {
        self.varName = varName;
        self.elemType = elemType;
        self.lenCName = lenCName;
        self.getCName = getCName;
        self.collection = collection;
        self.body = body;
        self.arraySize = arraySize;
        self.span = TS.NoneSpan();
    }
}

/*
 * A try/catch block. seq is a unique sequence number used to name generated labels.
 */
class IrTryCatch {
    public IrBlock tryBlock;
    public IrBlock catchBlock;
    public int seq;
    public TextSpan span;
    func _init(IrBlock tryBlock, IrBlock catchBlock, int seq) {
        self.tryBlock = tryBlock;
        self.catchBlock = catchBlock;
        self.seq = seq;
        self.span = TS.NoneSpan();
    }
}

/*
 * One case arm of an IrSwitch, with one or more labels and a body block.
 */
class IrSwitchCase {
    public List[IrExpr] labels;
    public IrBlock body;
    func _init(List[IrExpr] labels, IrBlock body) { self.labels = labels; self.body = body; }
}

/*
 * A switch statement. Lowered to an if/else-if chain by Desugar; never reaches the backend.
 */
class IrSwitch {
    public IrExpr scrutinee;
    public List[IrSwitchCase] cases;
    public Optional[IrBlock] otherwise;
    public TextSpan span;
    func _init(IrExpr scrutinee, List[IrSwitchCase] cases, Optional[IrBlock] otherwise) {
        self.scrutinee = scrutinee;
        self.cases = cases;
        self.otherwise = otherwise;
        self.span = TS.NoneSpan();
    }
}

/*
 * A single binding introduced by a match pattern - maps a variant field to a local name.
 */
class IrMatchBind {
    public String fieldName;
    public String bindName;
    public IrType type;
    func _init(String fieldName, String bindName, IrType type) {
        self.fieldName = fieldName;
        self.bindName = bindName;
        self.type = type;
    }
}

/*
 * One case arm of an IrMatch, identified by variant index with its pattern bindings.
 */
class IrMatchCase {
    public int variantIndex;
    public List[IrMatchBind] binds;
    public IrBlock body;
    func _init(int variantIndex, List[IrMatchBind] binds, IrBlock body) {
        self.variantIndex = variantIndex;
        self.binds = binds;
        self.body = body;
    }
}

/*
 * A match statement over a union type. Lowered to an if/else-if chain by Desugar; never reaches
 * the backend.
 */
class IrMatch {
    public IrExpr scrutinee;
    public IrType unionT;
    public List[IrMatchCase] cases;
    public Optional[IrBlock] otherwise;
    public TextSpan span;
    func _init(IrExpr scrutinee, IrType unionT, List[IrMatchCase] cases, Optional[IrBlock] otherwise) {
        self.scrutinee = scrutinee;
        self.unionT = unionT;
        self.cases = cases;
        self.otherwise = otherwise;
        self.span = TS.NoneSpan();
    }
}

/*
 * An unsafe block containing statements that may use pointer operations.
 */
class IrUnsafeBlock {
    public IrBlock body;
    public TextSpan span;
    func _init(IrBlock body) { self.body = body; self.span = TS.NoneSpan(); }
}

/*
 * A defer statement. Lowered by the Ownership pass; never reaches the backend.
 */
class IrDefer {
    public IrStmt action;
    public TextSpan span;
    func _init(IrStmt action) { self.action = action; self.span = TS.NoneSpan(); }
}

/*
 * A throw statement. Lowered by the Ownership pass; never reaches the backend.
 */
class IrThrow {
    public TextSpan span;
    func _init() { self.span = TS.NoneSpan(); }
}

/*
 * A debug assertion. Emitted as a direct call to the env debug binding with a raw C string
 * literal.
 */
class IrDebug {
    public String raw;
    public TextSpan span;
    func _init(String raw) { self.raw = raw; self.span = TS.NoneSpan(); }
}

/*
 * A panic statement. Emitted as a direct call to the env panic binding with a raw C string
 * literal.
 */
class IrPanic {
    public String raw;
    public TextSpan span;
    func _init(String raw) { self.raw = raw; self.span = TS.NoneSpan(); }
}

module Stmts2 {


    /*
     * SetSpan - Stamps a source span onto an IR statement that has none yet. The statement-side
     * companion to Exprs2.SetSpan, and mirrors SpanOf arm for arm.
     */
    public void func SetSpan(IrStmt s, TextSpan span) {
        match (s) {
            case IrBlock(x) { x.span = span; }
            case IrNativeStmt(x) { x.span = span; }
            case IrAssignValue(x) { x.span = span; }
            case IrGoto(x) { x.span = span; }
            case IrLabel(x) { x.span = span; }
            case IrDeclVar(x) { x.span = span; }
            case IrAssign(x) { x.span = span; }
            case IrExprStmt(x) { x.span = span; }
            case IrReturn(x) { x.span = span; }
            case IrBreak(x) { x.span = span; }
            case IrContinue(x) { x.span = span; }
            case IrIf(x) { x.span = span; }
            case IrWhile(x) { x.span = span; }
            case IrFor(x) { x.span = span; }
            case IrForIn(x) { x.span = span; }
            case IrTryCatch(x) { x.span = span; }
            case IrSwitch(x) { x.span = span; }
            case IrMatch(x) { x.span = span; }
            case IrUnsafeBlock(x) { x.span = span; }
            case IrDefer(x) { x.span = span; }
            case IrThrow(x) { x.span = span; }
            case IrDebug(x) { x.span = span; }
            case IrPanic(x) { x.span = span; }
        }
    }

    /*
     * SpanOf - The source span of any IR statement
     */
    public TextSpan func SpanOf(IrStmt s) {
        match (s) {
            case IrBlock(x)       { return x.span; }
            case IrNativeStmt(x)  { return x.span; }
            case IrAssignValue(x) { return x.span; }
            case IrGoto(x)        { return x.span; }
            case IrLabel(x)       { return x.span; }
            case IrDeclVar(x)     { return x.span; }
            case IrAssign(x)      { return x.span; }
            case IrExprStmt(x)    { return x.span; }
            case IrReturn(x)      { return x.span; }
            case IrBreak(x)       { return x.span; }
            case IrContinue(x)    { return x.span; }
            case IrIf(x)          { return x.span; }
            case IrWhile(x)       { return x.span; }
            case IrFor(x)         { return x.span; }
            case IrForIn(x)       { return x.span; }
            case IrTryCatch(x)    { return x.span; }
            case IrSwitch(x)      { return x.span; }
            case IrMatch(x)       { return x.span; }
            case IrUnsafeBlock(x) { return x.span; }
            case IrDefer(x)       { return x.span; }
            case IrThrow(x)       { return x.span; }
            case IrDebug(x)       { return x.span; }
            case IrPanic(x)       { return x.span; }
        }
    }
}

/*
 * Which translation unit a declaration is emitted into. The visibility axis; the name axis is
 * ScopeId's, kept separate so a process can contribute to a name's scope while inheriting its
 * realm's visibility.
 */
enum Visibility { Shared, Kernel, User }

/*
 * A single parameter in an IR function signature.
 */
class IrParam {
    public String name;
    public IrType type;
    public bool isRef;
    func _init(String name, IrType type, bool isRef) {
        self.name = name;
        self.type = type;
        self.isRef = isRef;
    }
}

/*
 * An IR function - either a free function or a class method. body is None for native functions;
 * native carries the C text instead.
 */
class IrFunction {
    public String name;
    public String cName;
    public IrType returnType;
    public List[IrParam] params;
    public bool isStatic;
    public bool isEntry;
    public bool isThrows;
    public bool isLib;
    public Visibility vis;
    public Optional[String] ownerClass;
    public Optional[IrBlock] body;
    public Optional[String] native;
    public List[Annotation] annotations;
    func _init(String name, String cName, IrType returnType, List[IrParam] params, bool isStatic,
               bool isEntry, bool isThrows, bool isLib, Visibility vis, Optional[String] ownerClass,
               Optional[IrBlock] body, Optional[String] native, List[Annotation] annotations) {
        self.name = name;
        self.cName = cName;
        self.returnType = returnType;
        self.params = params;
        self.isStatic = isStatic;
        self.isEntry = isEntry;
        self.isThrows = isThrows;
        self.isLib = isLib;
        self.vis = vis;
        self.ownerClass = ownerClass;
        self.body = body;
        self.native = native;
        self.annotations = annotations;
    }
}

/*
 * A field declaration on a class, with an optional default initializer.
 */
class IrField {
    public String name;
    public IrType type;
    public Optional[IrExpr] init;
    func _init(String name, IrType type, Optional[IrExpr] init) {
        self.name = name;
        self.type = type;
        self.init = init;
    }
}

/*
 * A raw native struct-field block.
 */
class RawFieldBlock {
    public String c;
    func _init(String c) { self.c = c; }
}

/*
 * An operator overload on a class; body is None for native ones, which carry C text. isStatic is
 * true only for one-parameter 'as', a factory converting its parameter to self - every other
 * operator, zero-parameter 'as' included, is an instance operator.
 */
class IrOperator {
    public String op;
    public String cName;
    public IrType returnType;
    public List[IrParam] params;
    public String ownerClass;
    public bool isLib;
    public Visibility vis;
    public Optional[IrBlock] body;
    public Optional[String] native;
    public bool isStatic;
    func _init(String op, String cName, IrType returnType, List[IrParam] params, String ownerClass,
               bool isLib, Visibility vis, Optional[IrBlock] body, Optional[String] native, bool isStatic) {
        self.op = op;
        self.cName = cName;
        self.returnType = returnType;
        self.params = params;
        self.ownerClass = ownerClass;
        self.isLib = isLib;
        self.vis = vis;
        self.body = body;
        self.native = native;
        self.isStatic = isStatic;
    }
}

/*
 * An IR class declaration with its fields, methods, and operator overloads. keep marks a class as
 * exempt from Dce reachability and Densifier renaming.
 */
class IrClass {
    public String name;
    public String cName;
    public bool isLib;
    public Visibility vis;
    public List[RawFieldBlock] rawFields;
    public List[IrField] classFields;
    public List[IrFunction] methods;
    public List[IrOperator] operators;
    public bool hasInit;
    public StringMap[IrExpr] fieldInits;
    public bool isModule;
    public bool keep;
    func _init(String name, String cName, bool isLib, Visibility vis, List[RawFieldBlock] rawFields,
               List[IrField] classFields, List[IrFunction] methods, List[IrOperator] operators,
               bool hasInit, StringMap[IrExpr] fieldInits, bool isModule, bool keep) {
        self.name = name;
        self.cName = cName;
        self.isLib = isLib;
        self.vis = vis;
        self.rawFields = rawFields;
        self.classFields = classFields;
        self.methods = methods;
        self.operators = operators;
        self.hasInit = hasInit;
        self.fieldInits = fieldInits;
        self.isModule = isModule;
        self.keep = keep;
    }
}

/*
 * One process variable: its written name, the C name of the static holding it, and its type.
 */
class IrProcessVar {
    public String name;
    public String cName;
    public IrType type;
    func _init(String name, String cName, IrType type) {
        self.name = name;
        self.cName = cName;
        self.type = type;
    }
}

/*
 * A single thread within a process, with a fully-qualified name and optional entry function.
 * Deployment mode lives on the owning process; threads have none of their own.
 */
class IrThread {
    public String name;
    public String fullName;
    public Optional[IrFunction] entryFunc;
    func _init(String name, String fullName, Optional[IrFunction] entryFunc) {
        self.name = name;
        self.fullName = fullName;
        self.entryFunc = entryFunc;
    }
}

/*
 * A process declaration grouping one or more threads.
 */
class IrProcess {
    public String name;
    public String mode;
    public List[IrThread] threads;

    /*
     * The process's own variables, emitted as statics in its realm's translation unit.
     */
    public List[IrProcessVar] state;

    /*
     * Generated function assigning every variable its initial value, or None when the process has
     * none. The launcher calls it after creating the process and before spawning any thread, which
     * is what makes "initialised before first read" true rather than hoped for.
     */
    public Optional[IrFunction] stateInit;

    func _init(String name, String mode, List[IrThread] threads) {
        self.name = name;
        self.mode = mode;
        self.threads = threads;
        self.state = new List[IrProcessVar]();
        self.stateInit = Optional[IrFunction].None();
    }
}

/*
 * Where a native block lands in the output. Types (default) -> the type section, alongside
 * structs. Preamble -> before #include "shared.h". Boot -> after all functions.
 */
enum NativeSection { Types, Preamble, Boot }

/*
 * A native C block with a target output section.
 */
class IrNativeBlock {
    public String c;
    public Visibility vis;
    public NativeSection section;
    func _init(String c, Visibility vis, NativeSection section) {
        self.c = c;
        self.vis = vis;
        self.section = section;
    }
}

/*
 * A native type declaration - a C struct declared inside Gata source.
 */
class IrNativeType {
    public String name;
    public String cName;
    public String c;
    public Visibility vis;
    func _init(String name, String cName, String c, Visibility vis) {
        self.name = name;
        self.cName = cName;
        self.c = c;
        self.vis = vis;
    }
}

/*
 * One member of an enum, with its optional explicit C value.
 */
class IrEnumMember {
    public String name;
    public Optional[String] cValue;
    func _init(String name, Optional[String] cValue) { self.name = name; self.cValue = cValue; }
}

/*
 * An enum declaration.
 */
class IrEnum {
    public String name;
    public String cName;
    public List[IrEnumMember] members;
    func _init(String name, String cName, List[IrEnumMember] members) {
        self.name = name;
        self.cName = cName;
        self.members = members;
    }
}

/*
 * One variant of a union type, with a tag name and its payload fields.
 */
class IrUnionVariant {
    public String name;
    public String tagCName;
    public List[IrParam] variantFields;
    func _init(String name, String tagCName, List[IrParam] variantFields) {
        self.name = name;
        self.tagCName = tagCName;
        self.variantFields = variantFields;
    }
}

/*
 * A union type declaration with all its variants.
 */
class IrUnion {
    public String name;
    public String cName;
    public List[IrUnionVariant] variants;
    func _init(String name, String cName, List[IrUnionVariant] variants) {
        self.name = name;
        self.cName = cName;
        self.variants = variants;
    }
}

/*
 * The top-level IR module produced by the type resolver. Carries all classes, functions, native
 * blocks, and supporting type lists.
 */
class IrModule {
    public List[IrNativeBlock] nativeBlocks;
    public List[IrNativeType] nativeTypes;
    public List[IrClass] classes;
    public List[IrFunction] freeFunctions;
    public List[IrProcess] processes;
    public List[IrType] arrayTypes;
    public List[IrEnum] enums;
    public SymbolTable symbols;
    public List[IrType] funcPtrTypes;
    public List[IrUnion] unions;

    // Unions by name, built on first ask.
    StringMap[IrUnion] unionsByName;
    bool unionsIndexed;

    func _init(List[IrNativeBlock] nativeBlocks, List[IrNativeType] nativeTypes, List[IrClass] classes,
               List[IrFunction] freeFunctions, List[IrProcess] processes, List[IrType] arrayTypes,
               List[IrEnum] enums, SymbolTable symbols, List[IrType] funcPtrTypes,
               List[IrUnion] unions) {
        self.nativeBlocks = nativeBlocks;
        self.nativeTypes = nativeTypes;
        self.classes = classes;
        self.freeFunctions = freeFunctions;
        self.processes = processes;
        self.arrayTypes = arrayTypes;
        self.enums = enums;
        self.symbols = symbols;
        self.funcPtrTypes = funcPtrTypes;
        self.unions = unions;
        self.unionsByName = new StringMap[IrUnion]();
        self.unionsIndexed = false;
    }

    /*
     * HasKernelRealm - True if the module emits a kernel realm, from its preamble or boot blocks
     */
    public bool func HasKernelRealm() {
        let int i = 0;
        while (i < self.nativeBlocks.Length()) {
            let IrNativeBlock nb = self.nativeBlocks.Get(i);
            if (nb.vis == Visibility.Kernel &&
                (nb.section == NativeSection.Preamble || nb.section == NativeSection.Boot)) {
                return true;
            }
            i = i + 1;
        }
        return false;
    }

    /*
     * HasUserRealm - True if the module emits a user realm, determined by the presence of user
     * preamble blocks
     */
    public bool func HasUserRealm() {
        let int i = 0;
        while (i < self.nativeBlocks.Length()) {
            let IrNativeBlock nb = self.nativeBlocks.Get(i);
            if (nb.vis == Visibility.User && nb.section == NativeSection.Preamble) { return true; }
            i = i + 1;
        }
        return false;
    }

    /*
     * UnionNamed - The union declared under a name. First declaration wins, as the linear scan it
     * replaces did.
     */
    public Optional[IrUnion] func UnionNamed(String name) {
        if (!self.unionsIndexed) {
            let int i = 0;
            while (i < self.unions.Length()) {
                let IrUnion u = self.unions.Get(i);
                if (!self.unionsByName.Has(u.name)) { self.unionsByName.Put(u.name, u); }
                i = i + 1;
            }
            self.unionsIndexed = true;
        }
        return self.unionsByName.Find(name);
    }
}
