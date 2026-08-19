/*
 * Ast.g - the untyped AST node definitions the parser produces
 *
 * Ports Appa/src/Syntax/Ast.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Optional.g";
import "src/Diagnostics/TextSpan.g";

/*
 * Which execution environment a declaration belongs to. Lives in Ir.cs on the C# side; it is
 * declared here because ContextDecl needs it and a Gata type name is global to the build, so
 * Ir.g must import this rather than redeclare it (ERROR G003).
 */
enum Realm { None, Kernel, User }

/*
 * The access/storage modifiers accepted before a function, method, or field declaration.
 * Combinable, eg. 'public static'. C#'s [Flags] enum; Gata enums carry no bitwise operators of
 * their own, so the set operations live in Mods below and go through `as int`.
 */
enum Modifiers { None = 0, Static = 1, Public = 2, Private = 4 }

module Mods {
    public Modifiers func Empty() { return Modifiers.None; }

    /*
     * Has - True when set contains flag (C#'s `(mods & Modifiers.Public) != 0`)
     */
    public bool func Has(Modifiers set, Modifiers flag) {
        return ((set as int) & (flag as int)) != 0;
    }

    /*
     * With - set plus flag (C#'s `mods |= Modifiers.Static`)
     */
    public Modifiers func With(Modifiers set, Modifiers flag) {
        return ((set as int) | (flag as int)) as Modifiers;
    }

    /*
     * Without - set minus flag
     */
    public Modifiers func Without(Modifiers set, Modifiers flag) {
        return ((set as int) & ~(flag as int)) as Modifiers;
    }
}



/*
 * The kind of a binary operator, shared by BinExpr and its lowered IrBinOp form.
 */
enum BinOp { Or, And, BitOr, BitXor, BitAnd, Eq, Ne, Lt, Gt, Le, Ge, Shl, Shr, Add, Sub, Mul, Div, Mod }

/*
 * The kind of a prefix unary operator, shared by UnaryExpr and its lowered IrUnaryOp form.
 */
enum UnOp { Not, BitNot, Neg }

/*
 * The kind of a postfix operator, shared by PostfixExpr and its lowered IrPostfix form.
 */
enum PostfixOp { Inc, Dec }

/*
 * The kind of an assignment operator. Assign is plain '='; the rest are compound forms that
 * combine a BinOp with the store, eg. AddAssign for '+='.
 */
enum AssignOp { Assign, AddAssign, SubAssign, MulAssign, DivAssign, ModAssign, AndAssign, OrAssign, XorAssign, ShlAssign, ShrAssign }

/*
 * The one table of user-overloadable operator shape rules: required arity, default return type,
 * and the bool/void return constraints. SymbolCollector (declaration keys and tentative
 * signatures) and TypeResolver (validation) both read it, so they cannot drift.
 */
module OperatorRules {

    /*
     * RequiredArity - The parameter count the operator's declaration must have. '-' alone is
     * dual-arity: zero parameters declares unary negation, one declares binary subtraction.
     */
    public int func RequiredArity(String op, int declaredParams) {
        if (op == "[]=") { return 2; }
        if (op == "!" || op == "~" || op == "++" || op == "--") { return 0; }
        if (op == "-") { return declaredParams == 0 ? 0 : 1; }
        return 1;
    }

    /*
     * IsComparison - True for the comparison operators, which must return bool (and whose
     * '=='/'!=' pair is derived by negation when only one is declared)
     */
    public bool func IsComparison(String op) {
        return op == "==" || op == "!=" || op == "<" || op == ">" || op == "<=" || op == ">=";
    }

    /*
     * IsMutator - True for the in-place mutators, which must return void
     */
    public bool func IsMutator(String op) { return op == "++" || op == "--"; }

    /*
     * DefaultReturn - The return type an operator defaults to when the declaration omits one
     */
    public String func DefaultReturn(String op, String ownerClass) {
        if (op == "[]=" || OperatorRules.IsMutator(op)) { return "void"; }
        if (OperatorRules.IsComparison(op) || op == "!") { return "bool"; }
        return ownerClass;
    }
}

/*
 * Conversions between operator enums and their canonical Gata/C token spelling, plus the
 * compound-assignment-to-binary-operator mapping used when desugaring '+=' and friends.
 */
module Ops {

    /*
     * BinSym - The canonical source and C token spelling for a binary operator
     */
    public String func BinSym(BinOp op) {
        switch (op as int) {
            case 0  { return "||"; }
            case 1  { return "&&"; }
            case 2  { return "|"; }
            case 3  { return "^"; }
            case 4  { return "&"; }
            case 5  { return "=="; }
            case 6  { return "!="; }
            case 7  { return "<"; }
            case 8  { return ">"; }
            case 9  { return "<="; }
            case 10 { return ">="; }
            case 11 { return "<<"; }
            case 12 { return ">>"; }
            case 13 { return "+"; }
            case 14 { return "-"; }
            case 15 { return "*"; }
            case 16 { return "/"; }
            case 17 { return "%"; }
        }
        return "";
    }

    /*
     * UnSym - The canonical source and C token spelling for a prefix unary operator
     */
    public String func UnSym(UnOp op) {
        switch (op as int) {
            case 0 { return "!"; }
            case 1 { return "~"; }
            case 2 { return "-"; }
        }
        return "";
    }

    /*
     * PostSym - The canonical source and C token spelling for a postfix operator
     */
    public String func PostSym(PostfixOp op) {
        switch (op as int) {
            case 0 { return "++"; }
            case 1 { return "--"; }
        }
        return "";
    }

    /*
     * AssignSym - The canonical source spelling for an assignment operator
     */
    public String func AssignSym(AssignOp op) {
        switch (op as int) {
            case 0  { return "="; }
            case 1  { return "+="; }
            case 2  { return "-="; }
            case 3  { return "*="; }
            case 4  { return "/="; }
            case 5  { return "%="; }
            case 6  { return "&="; }
            case 7  { return "|="; }
            case 8  { return "^="; }
            case 9  { return "<<="; }
            case 10 { return ">>="; }
        }
        return "";
    }

    /*
     * BaseOp - The underlying binary operator a compound assignment combines with the store, or
     * None for plain '='
     */
    public Optional[BinOp] func BaseOp(AssignOp op) {
        switch (op as int) {
            case 1  { return Optional.Some(BinOp.Add); }
            case 2  { return Optional.Some(BinOp.Sub); }
            case 3  { return Optional.Some(BinOp.Mul); }
            case 4  { return Optional.Some(BinOp.Div); }
            case 5  { return Optional.Some(BinOp.Mod); }
            case 6  { return Optional.Some(BinOp.BitAnd); }
            case 7  { return Optional.Some(BinOp.BitOr); }
            case 8  { return Optional.Some(BinOp.BitXor); }
            case 9  { return Optional.Some(BinOp.Shl); }
            case 10 { return Optional.Some(BinOp.Shr); }
        }
        return Optional[BinOp].None();
    }

    /*
     * IsBitwise - True for the compound assignment operators that require integer operands
     */
    public bool func IsBitwise(AssignOp op) {
        return op == AssignOp.AndAssign || op == AssignOp.OrAssign || op == AssignOp.XorAssign ||
               op == AssignOp.ShlAssign || op == AssignOp.ShrAssign;
    }
}



/*
 * Structured type specifier. The parser builds it once; every later pass walks it structurally.
 * Specs.ToSpecString() reproduces the legacy flat spelling used for mangling and
 * duplicate-signature keys, so emitted C names stay byte identical.
 */
union TypeSpec {
    NamedSpec(NamedSpec s),
    PtrSpec(PtrSpec s),
    ArraySpec(ArraySpec s),
    FuncSpec(FuncSpec s)
}

/*
 * A named type: primitive, class, enum, union or generic instantiation. args holds the type
 * arguments structurally, each itself a named type. Specs.Mangled flattens the name the way the
 * rest of the compiler identifies it: Base or Base_Arg1_Arg2.
 */
class NamedSpec {
    public String name;
    public List[NamedSpec] args;
    public TextSpan span;

    /*
     * The scope this name was written under: ["kernel", "P"] for 'kernel.P.Config', an EMPTY
     * list for the root scope written '::Config', None when the name was written bare. The
     * ScopeBinder resolves it into name and clears it, so every later pass sees an ordinary
     * flat name.
     */
    public Optional[List[String]] scope;

    // Read at least thirteen times per spec in the resolver alone, plus the parser, the binder,
    // the monomorphizer and the symbol table - so the flattened spelling is memoized. Gata has
    // no `??=`, so the "computed yet" bit is explicit.
    String mangled;
    bool mangledSet;

    func _init(String name, List[NamedSpec] args, TextSpan span) {
        self.name = name;
        self.args = args;
        self.span = span;
        self.scope = Optional[List[String]].None();
        self.mangled = "";
        self.mangledSet = false;
    }

    /*
     * Mangled - The flat spelling of this named spec, computed once and remembered. C#'s
     * `Mangled` property; a method rather than a module function so the memo stays private.
     */
    public String func Mangled() {
        if (!self.mangledSet) {
            self.mangled = Specs.Flatten(self.name, self.args);
            self.mangledSet = true;
        }
        return self.mangled;
    }
}

/*
 * A pointer type T*. Only legal to dereference inside unsafe code.
 */
class PtrSpec {
    public TypeSpec inner;
    public TextSpan span;
    func _init(TypeSpec inner, TextSpan span) { self.inner = inner; self.span = span; }
}

/*
 * A fixed-size array type [N]T. sizeText is the literal size token as written (validated and
 * parsed by the type resolver, like every other literal).
 */
class ArraySpec {
    public String sizeText;
    public TypeSpec elem;
    public TextSpan span;
    func _init(String sizeText, TypeSpec elem, TextSpan span) {
        self.sizeText = sizeText;
        self.elem = elem;
        self.span = span;
    }
}

/*
 * A function-pointer type func(T1, T2) -> R.
 */
class FuncSpec {
    public List[TypeSpec] params;
    public TypeSpec ret;
    public TextSpan span;
    func _init(List[TypeSpec] params, TypeSpec ret, TextSpan span) {
        self.params = params;
        self.ret = ret;
        self.span = span;
    }
}

module Specs {

    /*
     * The name a type spec takes once the reason it could not be resolved has been reported. No
     * source can spell it, so reaching it means exactly one error was already issued.
     */
    public String func Poison() { return "<error>"; }

    /*
     * Named - A NamedSpec with no type arguments and no span (C#'s NamedSpec(string name))
     */
    public TypeSpec func Named(String name) {
        return TypeSpec.NamedSpec(new NamedSpec(name, new List[NamedSpec](), TS.NoneSpan()));
    }

    /*
     * NamedAt - A NamedSpec with no type arguments at a span (C#'s NamedSpec(name, span))
     */
    public TypeSpec func NamedAt(String name, TextSpan span) {
        return TypeSpec.NamedSpec(new NamedSpec(name, new List[NamedSpec](), span));
    }

    /*
     * Span - The source span of any type spec (C#'s TypeSpec.Span base property)
     */
    public TextSpan func Span(TypeSpec t) {
        match (t) {
            case NamedSpec(s) { return s.span; }
            case PtrSpec(s)   { return s.span; }
            case ArraySpec(s) { return s.span; }
            case FuncSpec(s)  { return s.span; }
        }
    }

    /*
     * Flatten - Flattens a name and its type arguments the way the rest of the compiler
     * identifies the type: Base, or Base_Arg1_Arg2.
     *
     * TODO(Mangler.g): C#'s Mangler.GenericInstance ALSO files the composed name in the
     * NameTable's Composed map, which is what later lets Mangler.DisplayName spell a flat name
     * back as 'Box[int]'. That side effect has nowhere to live until Backend/Mangler.g and
     * Backend/NameTable.g are ported; this routes through the string composition only. Wire it
     * through Mangler.GenericInstance when they land.
     */
    public String func Flatten(String name, List[NamedSpec] args) {
        if (args.Length() == 0) { return name; }
        let StringBuilder sb = new StringBuilder();
        sb.Put(name);
        let int i = 0;
        while (i < args.Length()) {
            sb.AppendChar('_');
            sb.Put(args.Get(i).Mangled());
            i = i + 1;
        }
        return sb.ToString();
    }

    /*
     * ToSpecString - The legacy flat spelling used for mangling and duplicate-signature keys
     */
    public String func ToSpecString(TypeSpec t) {
        match (t) {
            case NamedSpec(s) { return s.Mangled(); }
            case PtrSpec(s)   { return Specs.ToSpecString(s.inner) + "*"; }
            case ArraySpec(s) { return "[" + s.sizeText + "]" + Specs.ToSpecString(s.elem); }
            case FuncSpec(s)  {
                let StringBuilder sb = new StringBuilder();
                sb.Put("func(");
                let int i = 0;
                while (i < s.params.Length()) {
                    if (i > 0) { sb.AppendChar(','); }
                    sb.Put(Specs.ToSpecString(s.params.Get(i)));
                    i = i + 1;
                }
                sb.Put(")->");
                sb.Put(Specs.ToSpecString(s.ret));
                return sb.ToString();
            }
        }
    }
}



/*
 * A function or method parameter. isRef = true means the argument is passed by reference; the
 * call site must supply an lvalue prefixed with ref.
 */
class Param {
    public TypeSpec type;
    public String name;
    public TextSpan span;
    public bool isRef;
    func _init(TypeSpec type, String name, TextSpan span, bool isRef) {
        self.type = type;
        self.name = name;
        self.span = span;
        self.isRef = isRef;
    }
}



/*
 * The captured raw C source of a native block.
 */
class NativeBody {
    public String c;
    func _init(String c) { self.c = c; }
}

/*
 * Every annotation (@intrinsic, @preamble, @keep, @shadows, @builtin).
 */
union Annotation {
    IntrinsicAnnotation(IntrinsicAnnotation a),
    PreambleAnnotation(PreambleAnnotation a),
    KeepAnnotation(KeepAnnotation a),
    ShadowsAnnotation(ShadowsAnnotation a),
    BuiltinAnnotation(BuiltinAnnotation a)
}

/*
 * @intrinsic(role): binds a function or method to a named compiler intrinsic. role identifies
 * which intrinsic slot this declaration fills, eg. "arc_retain".
 */
class IntrinsicAnnotation {
    public String role;
    public TextSpan span;
    func _init(String role, TextSpan span) { self.role = role; self.span = span; }
}

/*
 * @preamble(target): marks a native block as a preamble to be emitted before all other generated
 * output for the given target translation unit ("kernel" or "user").
 */
class PreambleAnnotation {
    public String target;
    public TextSpan span;
    func _init(String target, TextSpan span) { self.target = target; self.span = span; }
}

/*
 * @keep: exempts a class or free function from dead-code elimination and dense renaming. Use when
 * native code references the Gata-mangled name directly and the compiler cannot see that
 * reference through static analysis.
 */
class KeepAnnotation {
    public TextSpan span;
    func _init(TextSpan span) { self.span = span; }
}

/*
 * @shadows: declares that this scoped declaration deliberately displaces one of the same name
 * from an enclosing scope. Shadowing is legal but never silent - unmarked, it is a hard error, so
 * a name changing meaning is always something the author wrote down.
 */
class ShadowsAnnotation {
    public TextSpan span;
    func _init(TextSpan span) { self.span = span; }
}

/*
 * @builtin(name): binds a class or native type declaration to a named compiler builtin type slot
 * (eg. "String", "Process", "Thread"), the same way @intrinsic binds a role - the compiler never
 * hardcodes these names, it resolves them from this declaration.
 */
class BuiltinAnnotation {
    public String name;
    public TextSpan span;
    func _init(String name, TextSpan span) { self.name = name; self.span = span; }
}

module Anns {
    /*
     * Span - The source span of any annotation
     */
    public TextSpan func Span(Annotation a) {
        match (a) {
            case IntrinsicAnnotation(x) { return x.span; }
            case PreambleAnnotation(x)  { return x.span; }
            case KeepAnnotation(x)      { return x.span; }
            case ShadowsAnnotation(x)   { return x.span; }
            case BuiltinAnnotation(x)   { return x.span; }
        }
    }

    /*
     * Empty - The empty annotation list, standing in for C#'s `Annotation[]? = null` default
     * (every consumer reads a null annotation array as no annotations)
     */
    public List[Annotation] func Empty() { return new List[Annotation](); }
}



/*
 * Every expression node.
 */
union Expr {
    IntLitExpr(IntLitExpr e),
    CharLitExpr(CharLitExpr e),
    FloatLitExpr(FloatLitExpr e),
    BoolLitExpr(BoolLitExpr e),
    StrLitExpr(StrLitExpr e),
    NullExpr(NullExpr e),
    InterpStrExpr(InterpStrExpr e),
    IdentExpr(IdentExpr e),
    ScopedNameExpr(ScopedNameExpr e),
    PoisonExpr(PoisonExpr e),
    CastExpr(CastExpr e),
    CallExpr(CallExpr e),
    CatchCallExpr(CatchCallExpr e),
    MemberAccessExpr(MemberAccessExpr e),
    IndexExpr(IndexExpr e),
    GenericTypeRefExpr(GenericTypeRefExpr e),
    BinExpr(BinExpr e),
    TernaryExpr(TernaryExpr e),
    UnaryExpr(UnaryExpr e),
    PostfixExpr(PostfixExpr e),
    NewExpr(NewExpr e),
    ArrayLitExpr(ArrayLitExpr e),
    AddrOfExpr(AddrOfExpr e),
    RefArgExpr(RefArgExpr e),
    DerefExpr(DerefExpr e),
    SizeofExpr(SizeofExpr e),
    DefaultExpr(DefaultExpr e)
}

/*
 * An integer literal, eg. 42 or 0xFF. value holds the raw source spelling including any suffix
 * (u, L) so the backend can emit the right C constant.
 */
class IntLitExpr {
    public String value;
    public TextSpan span;
    func _init(String value, TextSpan span) { self.value = value; self.span = span; }
}

/*
 * A character literal, eg. 'a' or '\n'. value is the decoded codepoint.
 */
class CharLitExpr {
    public int value;
    public TextSpan span;
    func _init(int value, TextSpan span) { self.value = value; self.span = span; }
}

/*
 * A floating-point literal, eg. 3.14 or 1e9f. value holds the raw source spelling including any
 * suffix so the backend can choose float vs double.
 */
class FloatLitExpr {
    public String value;
    public TextSpan span;
    func _init(String value, TextSpan span) { self.value = value; self.span = span; }
}

/*
 * A boolean literal. value is "true" or "false".
 */
class BoolLitExpr {
    public String value;
    public TextSpan span;
    func _init(String value, TextSpan span) { self.value = value; self.span = span; }
}

/*
 * A plain string literal. value holds the decoded string content without surrounding quotes.
 */
class StrLitExpr {
    public String value;
    public TextSpan span;
    func _init(String value, TextSpan span) { self.value = value; self.span = span; }
}

/*
 * The null literal. Represents a null pointer or absent reference.
 */
class NullExpr {
    public TextSpan span;
    func _init(TextSpan span) { self.span = span; }
}

/*
 * An interpolated string. parts alternates between StrLitExpr (literal segments) and arbitrary
 * Expr (embedded expressions). Built by the parser from the InterpStrStart, StrLit,
 * brace-delimited expr, and InterpStrEnd token stream the lexer emits.
 */
class InterpStrExpr {
    public List[Expr] parts;
    public TextSpan span;
    func _init(List[Expr] parts, TextSpan span) { self.parts = parts; self.span = span; }
}

/*
 * A bare identifier used as an expression, eg. a variable or function name.
 */
class IdentExpr {
    public String name;
    public TextSpan span;
    func _init(String name, TextSpan span) { self.name = name; self.span = span; }
}

/*
 * A name reached through an explicit scope qualifier: 'kernel.Step', 'kernel.P.Config',
 * '::Helper'. path holds every dotted segment after it, because only the scope tree can tell a
 * process segment from the name or from a trailing member access. The ScopeBinder splits it and
 * rewrites the node.
 */
class ScopedNameExpr {
    public List[String] scope;
    public List[String] path;
    public TextSpan span;
    public Optional[NamedSpec] generic;
    func _init(List[String] scope, List[String] path, TextSpan span) {
        self.scope = scope;
        self.path = path;
        self.span = span;
        self.generic = Optional[NamedSpec].None();
    }
}

/*
 * Stands in for an expression whose meaning was already reported as an error, so nothing
 * downstream invents a type for it and complains again. The AST-level twin of IrType.Error.
 */
class PoisonExpr {
    public TextSpan span;
    func _init(TextSpan span) { self.span = span; }
}

/*
 * An explicit type cast, eg. (int) x. targetType is the destination type.
 */
class CastExpr {
    public TypeSpec targetType;
    public Expr value;
    public TextSpan span;
    func _init(TypeSpec targetType, Expr value, TextSpan span) {
        self.targetType = targetType;
        self.value = value;
        self.span = span;
    }
}

/*
 * A function or method call. callee may be any expression that resolves to a callable.
 */
class CallExpr {
    public Expr callee;
    public List[Expr] args;
    public TextSpan span;
    func _init(Expr callee, List[Expr] args, TextSpan span) {
        self.callee = callee;
        self.args = args;
        self.span = span;
    }
}

/*
 * A throwing call with an inline handler: `f() catch { ... assign v; }`.
 */
class CatchCallExpr {
    public Expr call;
    public Block handler;
    public TextSpan span;
    func _init(Expr call, Block handler, TextSpan span) {
        self.call = call;
        self.handler = handler;
        self.span = span;
    }
}

/*
 * Member access via dot, eg. obj.field or obj.method. member is the field or method name.
 */
class MemberAccessExpr {
    public Expr object;
    public String member;
    public TextSpan span;
    func _init(Expr object, String member, TextSpan span) {
        self.object = object;
        self.member = member;
        self.span = span;
    }
}

/*
 * Index access, eg. arr[i]. object is the collection expression, index is the subscript.
 */
class IndexExpr {
    public Expr object;
    public Expr index;
    public TextSpan span;
    func _init(Expr object, Expr index, TextSpan span) {
        self.object = object;
        self.index = index;
        self.span = span;
    }
}

/*
 * 'Name[Args]' where a value is expected, as in 'Maybe[int].Found(7)'. With one identifier in the
 * brackets this is the same tokens as an index, so the parser keeps both readings - args and
 * indexForm - and the resolver picks, knowing what is in scope.
 */
class GenericTypeRefExpr {
    public String name;
    public List[NamedSpec] args;
    public Optional[Expr] indexForm;
    public TextSpan span;
    func _init(String name, List[NamedSpec] args, Optional[Expr] indexForm, TextSpan span) {
        self.name = name;
        self.args = args;
        self.indexForm = indexForm;
        self.span = span;
    }
}

/*
 * A binary expression. op is the operator kind.
 */
class BinExpr {
    public BinOp op;
    public Expr left;
    public Expr right;
    public TextSpan span;
    func _init(BinOp op, Expr left, Expr right, TextSpan span) {
        self.op = op;
        self.left = left;
        self.right = right;
        self.span = span;
    }
}

/*
 * A ternary conditional: cond ? then : else.
 */
class TernaryExpr {
    public Expr cond;
    public Expr then;
    public Expr otherwise;
    public TextSpan span;
    func _init(Expr cond, Expr then, Expr otherwise, TextSpan span) {
        self.cond = cond;
        self.then = then;
        self.otherwise = otherwise;
        self.span = span;
    }
}

/*
 * A prefix unary expression. op is the operator kind.
 */
class UnaryExpr {
    public UnOp op;
    public Expr operand;
    public TextSpan span;
    func _init(UnOp op, Expr operand, TextSpan span) {
        self.op = op;
        self.operand = operand;
        self.span = span;
    }
}

/*
 * A postfix unary expression, eg. x++ or x--. op comes after the operand, unlike UnaryExpr.
 */
class PostfixExpr {
    public PostfixOp op;
    public Expr operand;
    public TextSpan span;
    func _init(PostfixOp op, Expr operand, TextSpan span) {
        self.op = op;
        self.operand = operand;
        self.span = span;
    }
}

/*
 * Object construction. args holds constructor arguments for class instantiation; collectionInit
 * holds the bracketed element list for collection construction.
 */
class NewExpr {
    public TypeSpec type;
    public List[Expr] args;
    public List[Expr] collectionInit;
    public TextSpan span;
    func _init(TypeSpec type, List[Expr] args, List[Expr] collectionInit, TextSpan span) {
        self.type = type;
        self.args = args;
        self.collectionInit = collectionInit;
        self.span = span;
    }
}

/*
 * A fixed-size array literal, eg. [e1, e2, e3].
 */
class ArrayLitExpr {
    public List[Expr] elems;
    public TextSpan span;
    func _init(List[Expr] elems, TextSpan span) { self.elems = elems; self.span = span; }
}

/*
 * Address-of expression. Takes the address of an lvalue. Only legal inside unsafe blocks.
 */
class AddrOfExpr {
    public Expr target;
    public TextSpan span;
    func _init(Expr target, TextSpan span) { self.target = target; self.span = span; }
}

/*
 * A ref argument at a call site, eg. ref x. Passes an lvalue by reference. Only legal as a direct
 * call argument, not in any other expression position.
 */
class RefArgExpr {
    public Expr target;
    public TextSpan span;
    func _init(Expr target, TextSpan span) { self.target = target; self.span = span; }
}

/*
 * Pointer dereference, eg. *ptr. Only legal inside unsafe blocks.
 */
class DerefExpr {
    public Expr ptr;
    public TextSpan span;
    func _init(Expr ptr, TextSpan span) { self.ptr = ptr; self.span = span; }
}

/*
 * sizeof(T) expression. Evaluates to the usize byte count of the named type.
 */
class SizeofExpr {
    public TypeSpec typeName;
    public TextSpan span;
    func _init(TypeSpec typeName, TextSpan span) { self.typeName = typeName; self.span = span; }
}

/*
 * default(T) expression. Evaluates to the zero value of the named type.
 */
class DefaultExpr {
    public TypeSpec typeName;
    public TextSpan span;
    func _init(TypeSpec typeName, TextSpan span) { self.typeName = typeName; self.span = span; }
}

module Exprs {

    /*
     * Span - The source span of any expression (C#'s Expr.Span base property)
     */
    public TextSpan func Span(Expr e) {
        match (e) {
            case IntLitExpr(x)         { return x.span; }
            case CharLitExpr(x)        { return x.span; }
            case FloatLitExpr(x)       { return x.span; }
            case BoolLitExpr(x)        { return x.span; }
            case StrLitExpr(x)         { return x.span; }
            case NullExpr(x)           { return x.span; }
            case InterpStrExpr(x)      { return x.span; }
            case IdentExpr(x)          { return x.span; }
            case ScopedNameExpr(x)     { return x.span; }
            case PoisonExpr(x)         { return x.span; }
            case CastExpr(x)           { return x.span; }
            case CallExpr(x)           { return x.span; }
            case CatchCallExpr(x)      { return x.span; }
            case MemberAccessExpr(x)   { return x.span; }
            case IndexExpr(x)          { return x.span; }
            case GenericTypeRefExpr(x) { return x.span; }
            case BinExpr(x)            { return x.span; }
            case TernaryExpr(x)        { return x.span; }
            case UnaryExpr(x)          { return x.span; }
            case PostfixExpr(x)        { return x.span; }
            case NewExpr(x)            { return x.span; }
            case ArrayLitExpr(x)       { return x.span; }
            case AddrOfExpr(x)         { return x.span; }
            case RefArgExpr(x)         { return x.span; }
            case DerefExpr(x)          { return x.span; }
            case SizeofExpr(x)         { return x.span; }
            case DefaultExpr(x)        { return x.span; }
        }
    }

    /*
     * Mangled - The mangled instance name a generic type reference denotes, e.g. Maybe_int
     */
    public String func Mangled(GenericTypeRefExpr g) { return Specs.Flatten(g.name, g.args); }

    /*
     * Written - The reference as written, e.g. Maybe[int] - for diagnostics, which must never
     * show a mangled name for a type the author never spelled that way.
     *
     * TODO(Mangler.g): C# runs each argument through Mangler.DisplayName, which unflattens a
     * nested instance argument back to bracket form. Until Backend/Mangler.g lands this prints
     * the argument's own mangled spelling, which differs only for a nested instantiation.
     */
    public String func Written(GenericTypeRefExpr g) {
        let StringBuilder sb = new StringBuilder();
        sb.Put(g.name);
        sb.AppendChar('[');
        let int i = 0;
        while (i < g.args.Length()) {
            if (i > 0) { sb.Put(", "); }
            sb.Put(g.args.Get(i).Mangled());
            i = i + 1;
        }
        sb.AppendChar(']');
        return sb.ToString();
    }
}



/*
 * Every statement node.
 */
union Stmt {
    Block(Block s),
    NativeStmt(NativeStmt s),
    LetStmt(LetStmt s),
    AssignStmt(AssignStmt s),
    ExprStmt(ExprStmt s),
    IfStmt(IfStmt s),
    WhileStmt(WhileStmt s),
    ForStmt(ForStmt s),
    ForInStmt(ForInStmt s),
    ReturnStmt(ReturnStmt s),
    BreakStmt(BreakStmt s),
    ContinueStmt(ContinueStmt s),
    TryCatchStmt(TryCatchStmt s),
    SwitchStmt(SwitchStmt s),
    MatchStmt(MatchStmt s),
    UnsafeBlock(UnsafeBlock s),
    DeferStmt(DeferStmt s),
    ThrowStmt(ThrowStmt s),
    AssignValueStmt(AssignValueStmt s),
    DebugStmt(DebugStmt s),
    PanicStmt(PanicStmt s)
}

/*
 * A brace-delimited sequence of statements forming a lexical scope.
 */
class Block {
    public List[Stmt] stmts;
    public TextSpan span;
    func _init(List[Stmt] stmts, TextSpan span) { self.stmts = stmts; self.span = span; }
}

/*
 * A verbatim native C statement embedded inside a Gata method body.
 */
class NativeStmt {
    public NativeBody body;
    public TextSpan span;
    func _init(NativeBody body, TextSpan span) { self.body = body; self.span = span; }
}

/*
 * A local variable declaration. type is None when the type is inferred from the initializer.
 * init is None for declarations without an initializer.
 */
class LetStmt {
    public Optional[TypeSpec] type;
    public String name;
    public Optional[Expr] init;
    public TextSpan span;
    func _init(Optional[TypeSpec] type, String name, Optional[Expr] init, TextSpan span) {
        self.type = type;
        self.name = name;
        self.init = init;
        self.span = span;
    }
}

/*
 * An assignment statement. op is the assignment operator kind (plain '=' or a compound form).
 * target must be an lvalue expression.
 */
class AssignStmt {
    public Expr target;
    public AssignOp op;
    public Expr value;
    public TextSpan span;
    func _init(Expr target, AssignOp op, Expr value, TextSpan span) {
        self.target = target;
        self.op = op;
        self.value = value;
        self.span = span;
    }
}

/*
 * An expression used as a statement, typically a call expression whose return value is discarded.
 */
class ExprStmt {
    public Expr e;
    public TextSpan span;
    func _init(Expr e, TextSpan span) { self.e = e; self.span = span; }
}

/*
 * An if/else statement. otherwise is None when there is no else branch.
 */
class IfStmt {
    public Expr cond;
    public Stmt then;
    public Optional[Stmt] otherwise;
    public TextSpan span;
    func _init(Expr cond, Stmt then, Optional[Stmt] otherwise, TextSpan span) {
        self.cond = cond;
        self.then = then;
        self.otherwise = otherwise;
        self.span = span;
    }
}

/*
 * A while loop.
 */
class WhileStmt {
    public Expr cond;
    public Stmt body;
    public TextSpan span;
    func _init(Expr cond, Stmt body, TextSpan span) {
        self.cond = cond;
        self.body = body;
        self.span = span;
    }
}

/*
 * A C-style for loop. init, cond, and step are all optional. init and step are statements so both
 * clauses accept a plain or compound assignment as well as an expression.
 */
class ForStmt {
    public Optional[Stmt] init;
    public Optional[Expr] cond;
    public Optional[Stmt] step;
    public Block body;
    public TextSpan span;
    func _init(Optional[Stmt] init, Optional[Expr] cond, Optional[Stmt] step, Block body, TextSpan span) {
        self.init = init;
        self.cond = cond;
        self.step = step;
        self.body = body;
        self.span = span;
    }
}

/*
 * A for-in loop that iterates over a collection. varName is the loop variable name.
 */
class ForInStmt {
    public String varName;
    public Expr collection;
    public Block body;
    public TextSpan span;
    func _init(String varName, Expr collection, Block body, TextSpan span) {
        self.varName = varName;
        self.collection = collection;
        self.body = body;
        self.span = span;
    }
}

/*
 * A return statement. value is None for void returns.
 */
class ReturnStmt {
    public Optional[Expr] value;
    public TextSpan span;
    func _init(Optional[Expr] value, TextSpan span) { self.value = value; self.span = span; }
}

/*
 * A break statement that exits the nearest enclosing loop or switch.
 */
class BreakStmt {
    public TextSpan span;
    func _init(TextSpan span) { self.span = span; }
}

/*
 * A continue statement that skips to the next iteration of the nearest enclosing loop.
 */
class ContinueStmt {
    public TextSpan span;
    func _init(TextSpan span) { self.span = span; }
}

/*
 * A try/catch statement for Result-based error propagation. The catch block receives control when
 * the try block throws.
 */
class TryCatchStmt {
    public Block tryBlock;
    public Block catchBlock;
    public TextSpan span;
    func _init(Block tryBlock, Block catchBlock, TextSpan span) {
        self.tryBlock = tryBlock;
        self.catchBlock = catchBlock;
        self.span = span;
    }
}

/*
 * A switch statement. cases is the list of arms; otherwise is the optional fallback block. There
 * is no fallthrough: break and continue inside a case target the enclosing loop.
 */
class SwitchStmt {
    public Expr scrutinee;
    public List[SwitchCase] cases;
    public Optional[Block] otherwise;
    public TextSpan span;
    func _init(Expr scrutinee, List[SwitchCase] cases, Optional[Block] otherwise, TextSpan span) {
        self.scrutinee = scrutinee;
        self.cases = cases;
        self.otherwise = otherwise;
        self.span = span;
    }
}

/*
 * One arm of a switch statement. labels is the list of values that route to this arm.
 */
class SwitchCase {
    public List[Expr] labels;
    public Block body;
    public TextSpan span;
    func _init(List[Expr] labels, Block body, TextSpan span) {
        self.labels = labels;
        self.body = body;
        self.span = span;
    }
}

/*
 * A match statement that scrutinizes a union value by variant. Each case binds the variant's
 * fields as locals in its body. otherwise is the optional fallback block.
 */
class MatchStmt {
    public Expr scrutinee;
    public List[MatchCase] cases;
    public Optional[Block] otherwise;
    public TextSpan span;
    func _init(Expr scrutinee, List[MatchCase] cases, Optional[Block] otherwise, TextSpan span) {
        self.scrutinee = scrutinee;
        self.cases = cases;
        self.otherwise = otherwise;
        self.span = span;
    }
}

/*
 * One arm of a match statement. variant is the union variant name; bindings are the local names
 * bound to the variant's fields in source order.
 */
class MatchCase {
    public String variant;
    public List[String] bindings;
    public Block body;
    public TextSpan span;
    func _init(String variant, List[String] bindings, Block body, TextSpan span) {
        self.variant = variant;
        self.bindings = bindings;
        self.body = body;
        self.span = span;
    }
}

/*
 * An unsafe block. Pointer operations (address-of, dereference) are only legal inside one.
 */
class UnsafeBlock {
    public List[Stmt] stmts;
    public TextSpan span;
    func _init(List[Stmt] stmts, TextSpan span) { self.stmts = stmts; self.span = span; }
}

/*
 * A defer statement. action runs on every exit from the enclosing block, in LIFO order with other
 * defers. action may not itself transfer control.
 */
class DeferStmt {
    public Stmt action;
    public TextSpan span;
    func _init(Stmt action, TextSpan span) { self.action = action; self.span = span; }
}

/*
 * A throw statement that aborts the enclosing throws function or try block with an error Result.
 */
class ThrowStmt {
    public TextSpan span;
    func _init(TextSpan span) { self.span = span; }
}

/*
 * `assign expr;` supplies the replacement value for the declaration a `catch` handler is attached
 * to, then resumes after it. Its own keyword rather than `return`, so it can never be misread as
 * returning out of the enclosing function.
 */
class AssignValueStmt {
    public Expr value;
    public TextSpan span;
    func _init(Expr value, TextSpan span) { self.value = value; self.span = span; }
}

/*
 * A debug statement. raw is the raw string literal including quotes. Lowered to the environment's
 * debug binding. Hard error in a release build.
 */
class DebugStmt {
    public String raw;
    public TextSpan span;
    func _init(String raw, TextSpan span) { self.raw = raw; self.span = span; }
}

/*
 * A panic statement. raw is the raw string literal including quotes. Lowered to the environment's
 * panic binding. Only legal in kernel context. Hard error in a release build.
 */
class PanicStmt {
    public String raw;
    public TextSpan span;
    func _init(String raw, TextSpan span) { self.raw = raw; self.span = span; }
}

module Stmts {

    /*
     * Span - The source span of any statement (C#'s Stmt.Span base property)
     */
    public TextSpan func Span(Stmt s) {
        match (s) {
            case Block(x)           { return x.span; }
            case NativeStmt(x)      { return x.span; }
            case LetStmt(x)         { return x.span; }
            case AssignStmt(x)      { return x.span; }
            case ExprStmt(x)        { return x.span; }
            case IfStmt(x)          { return x.span; }
            case WhileStmt(x)       { return x.span; }
            case ForStmt(x)         { return x.span; }
            case ForInStmt(x)       { return x.span; }
            case ReturnStmt(x)      { return x.span; }
            case BreakStmt(x)       { return x.span; }
            case ContinueStmt(x)    { return x.span; }
            case TryCatchStmt(x)    { return x.span; }
            case SwitchStmt(x)      { return x.span; }
            case MatchStmt(x)       { return x.span; }
            case UnsafeBlock(x)     { return x.span; }
            case DeferStmt(x)       { return x.span; }
            case ThrowStmt(x)       { return x.span; }
            case AssignValueStmt(x) { return x.span; }
            case DebugStmt(x)       { return x.span; }
            case PanicStmt(x)       { return x.span; }
        }
    }

    /*
     * AsBlock - Some(block) when the statement IS a block, None otherwise (C#'s `s is Block b`)
     */
    public Optional[Block] func AsBlock(Stmt s) {
        match (s) {
            case Block(x) { return Optional.Some(x); }
            default { return Optional[Block].None(); }
        }
    }
}



/*
 * Discriminates between a Gata block body and a verbatim native C body for methods and functions.
 */
union MethodBody {
    BlockBody(BlockBody b),
    NativeMethodBody(NativeMethodBody b)
}

/*
 * A method whose implementation is a Gata statement block.
 */
class BlockBody {
    public Block block;
    func _init(Block block) { self.block = block; }
}

/*
 * A method whose implementation is raw C source captured verbatim.
 */
class NativeMethodBody {
    public NativeBody native;
    func _init(NativeBody native) { self.native = native; }
}



/*
 * Every member that can appear inside a class or module body.
 */
union ClassMember {
    FieldsBlock(FieldsBlock m),
    FieldDecl(FieldDecl m),
    MethodDecl(MethodDecl m),
    OperatorDecl(OperatorDecl m)
}

/*
 * The fields { ... } block is raw C struct fields injected into the emitted struct typedef.
 */
class FieldsBlock {
    public NativeBody body;
    public TextSpan span;
    func _init(NativeBody body, TextSpan span) { self.body = body; self.span = span; }
}

/*
 * A Gata field declaration. init is the optional initializer expression; type is None when
 * inferred.
 */
class FieldDecl {
    public Modifiers modifiers;
    public Optional[TypeSpec] type;
    public String name;
    public TextSpan span;
    public Optional[Expr] init;
    func _init(Modifiers modifiers, Optional[TypeSpec] type, String name, TextSpan span, Optional[Expr] init) {
        self.modifiers = modifiers;
        self.type = type;
        self.name = name;
        self.span = span;
        self.init = init;
    }
}

/*
 * A method declaration inside a class or module. isEntry marks it as a thread entry point; throws
 * means it participates in the Result error-propagation protocol. genericParams empty = ordinary
 * method; non-empty = generic, monomorphized per call site like a generic free function.
 */
class MethodDecl {
    public Modifiers modifiers;
    public List[Annotation] annotations;
    public Optional[TypeSpec] returnType;
    public String name;
    public List[String] genericParams;
    public List[Param] params;
    public bool isEntry;
    public bool isThrows;
    public MethodBody body;
    public TextSpan span;
    func _init(Modifiers modifiers, List[Annotation] annotations, Optional[TypeSpec] returnType,
               String name, List[String] genericParams, List[Param] params, bool isEntry,
               bool isThrows, MethodBody body, TextSpan span) {
        self.modifiers = modifiers;
        self.annotations = annotations;
        self.returnType = returnType;
        self.name = name;
        self.genericParams = genericParams;
        self.params = params;
        self.isEntry = isEntry;
        self.isThrows = isThrows;
        self.body = body;
        self.span = span;
    }
}

/*
 * An operator overload inside a class. op is the operator symbol string ("+", "==").
 */
class OperatorDecl {
    public Modifiers modifiers;
    public String op;
    public List[Param] params;
    public Optional[TypeSpec] returnType;
    public MethodBody body;
    public TextSpan span;
    func _init(Modifiers modifiers, String op, List[Param] params, Optional[TypeSpec] returnType,
               MethodBody body, TextSpan span) {
        self.modifiers = modifiers;
        self.op = op;
        self.params = params;
        self.returnType = returnType;
        self.body = body;
        self.span = span;
    }
}

module Members {
    /*
     * Span - The source span of any class member
     */
    public TextSpan func Span(ClassMember m) {
        match (m) {
            case FieldsBlock(x)  { return x.span; }
            case FieldDecl(x)    { return x.span; }
            case MethodDecl(x)   { return x.span; }
            case OperatorDecl(x) { return x.span; }
        }
    }
}



/*
 * A thread inside a process, pointing at exactly one entry function. Deployment mode belongs to
 * the process, so mode is Some only when the source invalidly wrote one before 'thread' - which
 * the resolver rejects as G043.
 */
class ThreadDecl {
    public String name;
    public Optional[String] mode;
    // Named entryFunc, not entry: 'entry' is a reserved keyword.
    public EntryFuncDecl entryFunc;
    public TextSpan span;
    func _init(String name, Optional[String] mode, EntryFuncDecl entryFunc, TextSpan span) {
        self.name = name;
        self.mode = mode;
        self.entryFunc = entryFunc;
        self.span = span;
    }
}

/*
 * The entry function of a thread. It consists of parameters and a single block body. Not a
 * FuncDecl because it cannot be called from Gata code, only dispatched by the runtime.
 */
class EntryFuncDecl {
    public Modifiers modifiers;
    public Optional[TypeSpec] returnType;
    public List[Param] params;
    public Block body;
    public TextSpan span;
    func _init(Modifiers modifiers, Optional[TypeSpec] returnType, List[Param] params, Block body, TextSpan span) {
        self.modifiers = modifiers;
        self.returnType = returnType;
        self.params = params;
        self.body = body;
        self.span = span;
    }
}



/*
 * Every top-level declaration.
 */
union TopLevel {
    ImportDecl(ImportDecl d),
    EnvironmentDecl(EnvironmentDecl d),
    NativeBlock(NativeBlock d),
    ClassDecl(ClassDecl d),
    ContextDecl(ContextDecl d),
    FuncDecl(FuncDecl d),
    ProcessDecl(ProcessDecl d),
    ProcessVarDecl(ProcessVarDecl d),
    ExternFuncDecl(ExternFuncDecl d),
    NativeTypeDecl(NativeTypeDecl d),
    EnumDecl(EnumDecl d),
    UnionDecl(UnionDecl d)
}

/*
 * import "path" or import name. Pulls another Gata source file into the build. isPath
 * distinguishes a filesystem path (true) from a bare module name (false).
 */
class ImportDecl {
    public String name;
    public bool isPath;
    public TextSpan span;
    func _init(String name, bool isPath, TextSpan span) {
        self.name = name;
        self.isPath = isPath;
        self.span = span;
    }
}

/*
 * Marks exactly one file in the build as the environment definition. The environment file
 * provides the intrinsic bindings (I/O, ARC, panic) for the target.
 */
class EnvironmentDecl {
    public TextSpan span;
    func _init(TextSpan span) { self.span = span; }
}

/*
 * A native { ... } block containing raw C source captured verbatim. Routed to the kernel and/or
 * user translation unit(s) by its enclosing context.
 */
class NativeBlock {
    public NativeBody body;
    public TextSpan span;
    public List[Annotation] annotations;
    func _init(NativeBody body, TextSpan span, List[Annotation] annotations) {
        self.body = body;
        self.span = span;
        self.annotations = annotations;
    }
}

/*
 * class or module declaration. isModule = true means all members are implicitly static, meaning
 * no self parameter, no instances. genericParams non-empty makes it a generic class monomorphized
 * per concrete type argument set.
 */
class ClassDecl {
    public String name;
    public List[String] genericParams;
    public List[Annotation] annotations;
    public List[ClassMember] members;
    public TextSpan span;
    public bool isModule;

    // The template this declaration was stamped from; equal to name for a non-generic class.
    public String baseName;

    func _init(String name, List[String] genericParams, List[Annotation] annotations,
               List[ClassMember] members, TextSpan span, bool isModule) {
        self.name = name;
        self.genericParams = genericParams;
        self.annotations = annotations;
        self.members = members;
        self.span = span;
        self.isModule = isModule;
        self.baseName = name;
    }
}

/*
 * realm kernel { ... } or realm userspace { ... } block. Groups top-level declarations that belong
 * to one execution environment, which decides the translation unit they are emitted into.
 */
class ContextDecl {
    public Realm kind;
    public List[TopLevel] items;
    public TextSpan span;
    func _init(Realm kind, List[TopLevel] items, TextSpan span) {
        self.kind = kind;
        self.items = items;
        self.span = span;
    }
}

/*
 * A free function declaration. genericParams empty = ordinary function; non-empty = generic
 * template monomorphized per call site with type arguments inferred from the argument types.
 * isEntry marks it as a thread entry point; isThrows means it may propagate a Result error.
 */
class FuncDecl {
    public Modifiers modifiers;
    public List[Annotation] annotations;
    public Optional[TypeSpec] returnType;
    public String name;
    public List[String] genericParams;
    public List[Param] params;
    public bool isEntry;
    public bool isThrows;
    public MethodBody body;
    public TextSpan span;
    func _init(Modifiers modifiers, List[Annotation] annotations, Optional[TypeSpec] returnType,
               String name, List[String] genericParams, List[Param] params, bool isEntry,
               bool isThrows, MethodBody body, TextSpan span) {
        self.modifiers = modifiers;
        self.annotations = annotations;
        self.returnType = returnType;
        self.name = name;
        self.genericParams = genericParams;
        self.params = params;
        self.isEntry = isEntry;
        self.isThrows = isThrows;
        self.body = body;
        self.span = span;
    }
}

/*
 * A process declaration is pure deployment topology. A process is a named bag of threads; it holds
 * no logic of its own. mode is the deployment mode ("foreground" or "background").
 */
class ProcessDecl {
    public String name;
    public String mode;
    public List[ThreadDecl] threads;
    public TextSpan span;

    // The process's own declarations (classes, functions, process variables), empty by default.
    public List[TopLevel] items;

    func _init(String name, String mode, List[ThreadDecl] threads, TextSpan span) {
        self.name = name;
        self.mode = mode;
        self.threads = threads;
        self.span = span;
        self.items = new List[TopLevel]();
    }
}

/*
 * A variable belonging to a process rather than to a scope inside it: one instance, shared by
 * every thread of that process, initialised once before any of them is spawned and living as long
 * as the process does.
 */
class ProcessVarDecl {
    public String name;
    public TypeSpec type;
    public Optional[Expr] init;
    public TextSpan span;
    func _init(String name, TypeSpec type, Optional[Expr] init, TextSpan span) {
        self.name = name;
        self.type = type;
        self.init = init;
        self.span = span;
    }
}

/*
 * An extern function pre-declaration that tells the compiler a C function exists so it can be
 * called from Gata without a Gata body. Translated to a forward prototype in the backend.
 */
class ExternFuncDecl {
    public Optional[TypeSpec] returnType;
    public String name;
    public List[Param] params;
    public TextSpan span;
    public List[Annotation] annotations;
    func _init(Optional[TypeSpec] returnType, String name, List[Param] params, TextSpan span,
               List[Annotation] annotations) {
        self.returnType = returnType;
        self.name = name;
        self.params = params;
        self.span = span;
        self.annotations = annotations;
    }
}

/*
 * native type Name { C body }. It registers a C struct as a named Gata type. The cBody is emitted
 * verbatim as a typedef; the name becomes resolvable in type positions.
 */
class NativeTypeDecl {
    public String name;
    public String cBody;
    public TextSpan span;
    public List[Annotation] annotations;
    func _init(String name, String cBody, TextSpan span, List[Annotation] annotations) {
        self.name = name;
        self.cBody = cBody;
        self.span = span;
        self.annotations = annotations;
    }
}

/*
 * enum Name { A, B = 2, C } is a distinct integer-backed type with named members. Members may
 * carry explicit integer values; unspecified members follow C's increment rule.
 */
class EnumDecl {
    public String name;
    public List[EnumMember] members;
    public TextSpan span;
    public List[Annotation] annotations;
    func _init(String name, List[EnumMember] members, TextSpan span, List[Annotation] annotations) {
        self.name = name;
        self.members = members;
        self.span = span;
        self.annotations = annotations;
    }
}

/*
 * One member of an enum. value is None when the member takes the implicit next integer.
 */
class EnumMember {
    public String name;
    public Optional[Expr] value;
    public TextSpan span;
    func _init(String name, Optional[Expr] value, TextSpan span) {
        self.name = name;
        self.value = value;
        self.span = span;
    }
}

/*
 * A tagged union; each variant carries named fields or no payload, lowered to a tag enum plus a C
 * union. genericParams is non-empty for a template, which the Monomorphizer replaces with one
 * stamped UnionDecl per instantiation.
 */
class UnionDecl {
    public String name;
    public List[String] genericParams;
    public List[UnionVariant] variants;
    public TextSpan span;
    public List[Annotation] annotations;

    // The template this declaration was stamped from; equal to name for a non-generic union.
    public String baseName;

    func _init(String name, List[String] genericParams, List[UnionVariant] variants,
               TextSpan span, List[Annotation] annotations) {
        self.name = name;
        self.genericParams = genericParams;
        self.variants = variants;
        self.span = span;
        self.annotations = annotations;
        self.baseName = name;
    }
}

/*
 * One variant of a union. fields is empty for a payload-free variant like Point.
 */
class UnionVariant {
    public String name;
    public List[Param] variantFields;
    public TextSpan span;
    func _init(String name, List[Param] variantFields, TextSpan span) {
        self.name = name;
        self.variantFields = variantFields;
        self.span = span;
    }
}

module Tops {
    /*
     * Span - The source span of any top-level declaration
     */
    public TextSpan func Span(TopLevel t) {
        match (t) {
            case ImportDecl(x)      { return x.span; }
            case EnvironmentDecl(x) { return x.span; }
            case NativeBlock(x)     { return x.span; }
            case ClassDecl(x)       { return x.span; }
            case ContextDecl(x)     { return x.span; }
            case FuncDecl(x)        { return x.span; }
            case ProcessDecl(x)     { return x.span; }
            case ProcessVarDecl(x)  { return x.span; }
            case ExternFuncDecl(x)  { return x.span; }
            case NativeTypeDecl(x)  { return x.span; }
            case EnumDecl(x)        { return x.span; }
            case UnionDecl(x)       { return x.span; }
        }
    }
}



/*
 * A generic instantiation site found during parsing, telling the Monomorphizer which concrete
 * copies to stamp. args is mangled ("int"); argSpecs keeps the same arguments unflattened, so
 * substituting inside them is structural rather than string surgery.
 */
class GenericUse {
    public String base;
    public List[String] args;
    public TextSpan span;
    public Optional[List[NamedSpec]] argSpecs;
    public Optional[List[String]] scope;
    func _init(String base, List[String] args, TextSpan span, Optional[List[NamedSpec]] argSpecs) {
        self.base = base;
        self.args = args;
        self.span = span;
        self.argSpecs = argSpecs;
        self.scope = Optional[List[String]].None();
    }
}

/*
 * Root of the AST. Holds all top-level declarations in source order, plus generic instantiation
 * requests collected during parsing and consumed by the Monomorphizer.
 */
class Program {
    public List[TopLevel] items;
    public List[GenericUse] genericUses;

    /*
     * True when the file writes a scope qualifier anywhere. Lets the ScopeBinder keep its
     * do-nothing path for a program that declares nothing scoped and names nothing scoped.
     */
    public bool hasScopedRefs;

    func _init(List[TopLevel] items) {
        self.items = items;
        self.genericUses = new List[GenericUse]();
        self.hasScopedRefs = false;
    }
}
