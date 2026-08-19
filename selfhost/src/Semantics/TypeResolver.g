/*
 * TypeResolver.g - the main pass: untyped AST to typed IR, all type checking happens here
 *
 * Ports Appa/src/Semantics/TypeResolver.cs.
 *
 * This is the largest pass in the compiler and the only one that both CHECKS and BUILDS: every
 * semantic diagnostic the language has is raised somewhere in here, and what comes out the far
 * side is the typed IR the whole backend consumes. Nothing downstream re-derives a type.
 *
 * Shape of the port. C# leans on four things Gata does not have, and each is answered the same way
 * throughout, so the translation stays mechanical rather than inventive:
 *
 *   nullable T?          -> Optional[T], or a sentinel where the absent case has a natural one
 *   (A, B) tuples        -> a small named class
 *   out parameters       -> a union carrying every result, or a ref parameter
 *   nested visitors      -> IrWalk[S] from IrWalker.g: state class + function-pointer hook
 *
 * The one thing that could not be carried over literally is C#'s static Mangler. Here it is an
 * instance threaded from the pipeline, because DisplayName reads the generic instances the
 * Monomorphizer stamped - a fresh mangler would silently print flat names in diagnostics.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Char.g";
import "selfhostlib/Int.g";
import "selfhostlib/Long.g";
import "selfhostlib/Algorithms.g";
import "src/Diagnostics/TextSpan.g";
import "src/Diagnostics/Diagnostic.g";
import "src/Syntax/Ast.g";
import "src/IR/Ir.g";
import "src/Semantics/ScopeBinder.g";
import "src/Semantics/ScopeTree.g";
import "src/Semantics/SignatureKey.g";
import "src/Semantics/SymbolTable.g";
import "src/Semantics/Monomorphizer.g";
import "src/Lowering/IrWalker.g";
import "src/Backend/Mangler.g";

/*
 * The reading of an integer literal. C# hands back four values through three `out` parameters;
 * Gata says the same thing as one union, which also makes the failure case unmissable.
 *
 *   value   the bits, reinterpreted as int64 - a uint64 literal above int64.MaxValue is stored
 *           wrapped, exactly as C# does with `unchecked((long)mag)`, because the emitted C text
 *           is what carries the real value
 *   type    the CANONICAL GATA SPELLING of the inferred type ("int", "int64", "uint", "uint64"),
 *           not the C one. The caller interns it into an IrType if it needs one, which keeps
 *           this answerable without an IrTypeTable
 *   cText   the text to emit into C when the source spelling cannot be used verbatim, None when
 *           it can
 */
union IntLit { Parsed(int64 value, String type, Optional[String] cText), Bad }

module Literals {

    /*
     * ParseInt - Reads an integer literal the way section 2.5 of the language spec describes:
     * decimal or hex, with u/U and l/L suffix characters in any run, and the inferred type read
     * off the suffixes and the magnitude.
     *
     *   u + l      -> uint64
     *   l          -> int64
     *   u          -> uint if it fits, else uint64
     *   no suffix  -> int if it fits, else int64, else uint64
     *
     * Bad when the digits do not parse or the magnitude does not fit in 64 bits - which is what
     * the resolver turns into ERROR G004, and what the array-size check turns into G007.
     */
    public IntLit func ParseInt(String raw) {
        let int end = raw.Length();
        let bool hasU = false;
        let int lCount = 0;

        // The suffix is a RUN in any order: 3ul, 3lu and 3ull are all legal
        while (end > 0) {
            let char c = raw.CharAt(end - 1);
            if (c == 'u' || c == 'U') { hasU = true; }
            else if (c == 'l' || c == 'L') { lCount = lCount + 1; }
            else { break; }
            end = end - 1;
        }

        let bool hasSuffix = end < raw.Length();
        let String core = raw.Substring(0, end);
        let bool isHex = core.Length() > 2 && core.CharAt(0) == '0' &&
                         (core.CharAt(1) == 'x' || core.CharAt(1) == 'X');

        let uint64 mag = 0 as uint64;
        let bool ok = false;
        if (isHex) { ok = Literals.ParseHex(core.Substring(2, core.Length() - 2), ref mag); }
        else       { ok = Literals.ParseDec(core, ref mag); }
        if (!ok) { return IntLit.Bad(); }

        let String type = Literals.IntLitType(mag, hasU, lCount >= 1);

        // A hex or suffixed spelling is emitted VERBATIM, so 0xFF stays 0xFF in the C rather than
        // becoming 255 - the author pinned the width or wrote the bit pattern for a reason, and the
        // emitted C should still read like what they wrote. A bare decimal that landed in uint64
        // has to be spelled with the C suffix instead, or the C compiler reads it as a signed
        // literal that does not fit.
        let Optional[String] cText = isHex || hasSuffix
            ? Optional.Some(raw)
            : (type == "uint64" ? Optional.Some(Int.ToUnsignedString(mag) + "ULL")
                                : Optional[String].None());

        return IntLit.Parsed(Literals.Reinterpret(mag), type, cText);
    }

    /*
     * IntValue - The value of an integer literal, or fallback when it does not parse
     */
    public int64 func IntValue(String raw, int64 fallback) {
        match (Literals.ParseInt(raw)) {
            case Parsed(v, ty, ct) { return v; }
            case Bad { return fallback; }
        }
    }

    /*
     * IntLitType - The canonical Gata spelling an integer literal's magnitude and suffixes infer
     */
    private String func IntLitType(uint64 mag, bool hasU, bool isLong) {
        if (hasU && isLong) { return "uint64"; }
        if (isLong)         { return "int64"; }
        if (hasU)           { return mag <= 4294967295u ? "uint" : "uint64"; }
        if (mag <= 2147483647u)          { return "int"; }
        if (mag <= 9223372036854775807u) { return "int64"; }
        return "uint64";
    }

    /*
     * Reinterpret - The bits of a uint64 read back as int64, C#'s `unchecked((long)mag)`. Values
     * above int64.MaxValue wrap; the C text is what carries them truthfully, which is exactly why
     * ParseInt also hands back a cText for that case.
     */
    private int64 func Reinterpret(uint64 mag) {
        if (mag <= 9223372036854775807u) { return mag as int64; }
        return (mag - 9223372036854775808u) as int64 - 9223372036854775807L - 1L;
    }

    /*
     * ParseDec - Decimal digits into mag. False on a non-digit, on emptiness, or on a magnitude
     * past 64 bits. C# gets the range check from ulong.TryParse; here the multiply is checked
     * before it happens, since Gata arithmetic wraps rather than throwing.
     */
    private bool func ParseDec(String s, ref uint64 mag) {
        if (s.Length() == 0) { return false; }
        let uint64 max = 18446744073709551615u;
        let uint64 acc = 0 as uint64;
        let int i = 0;
        while (i < s.Length()) {
            let char c = s.CharAt(i);
            if (!Char.IsDigit(c)) { return false; }
            let uint64 d = (Char.DigitValue(c)) as uint64;
            if (acc > (max - d) / (10 as uint64)) { return false; }
            acc = acc * (10 as uint64) + d;
            i = i + 1;
        }
        mag = acc;
        return true;
    }

    /*
     * ParseHex - Hex digits into mag, the same way, without the '0x' prefix
     */
    private bool func ParseHex(String s, ref uint64 mag) {
        if (s.Length() == 0) { return false; }
        let uint64 max = 18446744073709551615u;
        let uint64 acc = 0 as uint64;
        let int i = 0;
        while (i < s.Length()) {
            let char c = s.CharAt(i);
            if (!Char.IsHexDigit(c)) { return false; }
            let uint64 d = (Char.HexValue(c)) as uint64;
            if (acc > (max - d) / (16 as uint64)) { return false; }
            acc = acc * (16 as uint64) + d;
            i = i + 1;
        }
        mag = acc;
        return true;
    }

    /*
     * FloatType - The canonical Gata spelling of a floating-point literal: float for an f/F
     * suffix, double otherwise
     */
    public String func FloatType(String raw) {
        if (raw.Length() > 0) {
            let char last = raw.CharAt(raw.Length() - 1);
            if (last == 'f' || last == 'F') { return "float"; }
        }
        return "double";
    }

    /*
     * InferFieldTypeSpec - The type a field's initializer infers, or None.
     *
     * Fields register their type before any body is resolved, so this is limited to literals,
     * optionally under a unary minus - the only initializers knowable without resolving
     * expressions. Anything else is ERROR G054 at the caller, which is what makes
     * `e = Compute();` a diagnostic that names the fix rather than a silent guess.
     */
    public Optional[TypeSpec] func InferFieldTypeSpec(Optional[Expr] init) {
        match (init) {
            case None { return Optional[TypeSpec].None(); }
            case Some(e) { return Literals.InferFrom(e); }
        }
    }

    /*
     * InferFrom - InferFieldTypeSpec over an expression that is known to be present
     */
    private Optional[TypeSpec] func InferFrom(Expr e) {
        match (e) {
            case IntLitExpr(x) {
                match (Literals.ParseInt(x.value)) {
                    case Parsed(v, ty, ct) { return Optional.Some(Specs.NamedAt(ty, x.span)); }
                    case Bad { return Optional[TypeSpec].None(); }
                }
            }
            case FloatLitExpr(x) {
                return Optional.Some(Specs.NamedAt(Literals.FloatType(x.value), x.span));
            }
            case BoolLitExpr(x) { return Optional.Some(Specs.NamedAt("bool", x.span)); }
            case CharLitExpr(x) { return Optional.Some(Specs.NamedAt("char", x.span)); }
            case StrLitExpr(x)  { return Optional.Some(Specs.NamedAt(BuiltinTypes.Str(), x.span)); }
            case UnaryExpr(x) {
                // Only a negated NUMERIC literal. '-flag' or '-"s"' infers nothing, the same way
                // C#'s pattern requires an IntLitExpr or FloatLitExpr operand.
                if (x.op != UnOp.Neg) { return Optional[TypeSpec].None(); }
                match (x.operand) {
                    case IntLitExpr(y)   { return Literals.InferFrom(x.operand); }
                    case FloatLitExpr(y) { return Literals.InferFrom(x.operand); }
                    default { return Optional[TypeSpec].None(); }
                }
            }
            default { return Optional[TypeSpec].None(); }
        }
    }
}



/*
 * A lexical scope chain for locals: what is declared, at what type, and whether by reference.
 *
 * Two levels matter beyond plain nesting. A PARAMETER scope is marked, because a top-level local
 * sharing a parameter's name is an error rather than a shadow - they land in one C scope, so no
 * renaming can separate them. And ShadowsOuter is asked separately from DeclaredHere, because
 * displacing an outer local is a warning while redeclaring in the same scope is an error.
 */
class ScopeStack {
    public Optional[ScopeStack] parent;
    public bool isParams;
    StringMap[IrType] vars;
    StringSet refs;

    func _init(Optional[ScopeStack] parent, bool isParams) {
        self.parent = parent;
        self.isParams = isParams;
        self.vars = new StringMap[IrType]();
        self.refs = new StringSet();
    }

    /*
     * Push - A nested scope. isParams marks the one holding a function's parameters.
     */
    public ScopeStack func Push(bool isParams) {
        return new ScopeStack(Optional.Some(self), isParams);
    }

    /*
     * Declare - Binds a name in this scope
     */
    public void func Declare(String name, IrType type, bool isRef) {
        self.vars.Put(name, type);
        if (isRef) { self.refs.AddNew(name); }
    }

    /*
     * DeclaredHere - True when this exact scope already binds the name
     */
    public bool func DeclaredHere(String name) { return self.vars.Has(name); }

    /*
     * CollidesWithParam - True when a parameter scope directly enclosing this one binds the name.
     * The walk stops at the first parameter scope, since anything beyond it belongs to another
     * function.
     */
    public bool func CollidesWithParam(String name) {
        let ScopeStack s = self;
        while (true) {
            if (s.isParams) { return s.DeclaredHere(name); }
            match (s.parent) {
                case Some(p) { s = p; }
                case None { return false; }
            }
        }
    }

    /*
     * ShadowsOuter - True when some ENCLOSING scope binds the name
     */
    public bool func ShadowsOuter(String name) {
        match (self.parent) {
            case None { return false; }
            case Some(p) {
                let ScopeStack s = p;
                while (true) {
                    if (s.DeclaredHere(name)) { return true; }
                    match (s.parent) {
                        case Some(q) { s = q; }
                        case None { return false; }
                    }
                }
            }
        }
    }

    /*
     * Lookup - The type bound to a name, searching outward
     */
    public Optional[IrType] func Lookup(String name) {
        let ScopeStack s = self;
        while (true) {
            match (s.vars.Find(name)) {
                case Some(t) { return Optional.Some(t); }
                case None { }
            }
            match (s.parent) {
                case Some(p) { s = p; }
                case None { return Optional[IrType].None(); }
            }
        }
    }

    /*
     * IsRef - True when the name was declared as a by-reference parameter
     */
    public bool func IsRef(String name) {
        let ScopeStack s = self;
        while (true) {
            if (s.DeclaredHere(name)) { return s.refs.Has(name); }
            match (s.parent) {
                case Some(p) { s = p; }
                case None { return false; }
            }
        }
    }
}



/*
 * Everything the resolver needs to know about WHERE it is: which file and function, which class if
 * any, whether the surrounding code is static or unsafe, and how a failure would be handled.
 *
 * C# makes this a readonly record struct with `with`-style WithX methods, copied at every nesting
 * step so an inner context can never leak back out. Gata has no record copy, so Clone is explicit
 * and each WithX returns a fresh one - the important property being the same: passing a modified
 * context down never mutates the caller's.
 */
class ResolveCtx {
    public String file;
    public String curClass;
    public String curFunc;
    public bool isStatic;
    public bool inUnsafe;
    public bool inTry;
    public String tryLabel;
    public bool inThrowsFunc;
    public bool catchWrapped;
    public bool inDefer;
    // Named 'realmKind' because 'realm' is a hard keyword and can never be an identifier
    public Realm realmKind;
    public ScopeStack locals;

    // Set inside an inline catch handler, and the type an 'assign' there must produce. None
    // outside one, which is what makes a stray 'assign' reportable.
    public Optional[IrType] assignType;

    // The type this expression is being resolved INTO, when there is one. Carried only through a
    // call and a ternary, and cleared everywhere else, because it exists for exactly two jobs:
    // picking a union instantiation from the expected type, and typing a bare variant name.
    public Optional[IrType] expected;

    // The enclosing function's return type, for a 'return' to check against
    public Optional[IrType] retType;

    // How many loops enclose this point, so 'break' outside one is reportable
    public int loopDepth;

    // Inside a process variable's initialiser, where a catch handler may not 'return'
    public bool inProcessInit;

    func _init(String file) {
        self.file = file;
        self.curClass = "";
        self.curFunc = "";
        self.isStatic = false;
        self.inUnsafe = false;
        self.inTry = false;
        self.tryLabel = "";
        self.inThrowsFunc = false;
        self.catchWrapped = false;
        self.inDefer = false;
        self.realmKind = Realm.None;
        self.locals = new ScopeStack(Optional[ScopeStack].None(), false);
        self.assignType = Optional[IrType].None();
        self.expected = Optional[IrType].None();
        self.retType = Optional[IrType].None();
        self.loopDepth = 0;
        self.inProcessInit = false;
    }

    /*
     * Clone - A copy sharing the same locals chain. Every WithX starts here, so adding a field to
     * the context is one edit rather than fourteen.
     */
    public ResolveCtx func Clone() {
        let ResolveCtx c = new ResolveCtx(self.file);
        c.curClass = self.curClass;
        c.curFunc = self.curFunc;
        c.isStatic = self.isStatic;
        c.inUnsafe = self.inUnsafe;
        c.inTry = self.inTry;
        c.tryLabel = self.tryLabel;
        c.inThrowsFunc = self.inThrowsFunc;
        c.catchWrapped = self.catchWrapped;
        c.inDefer = self.inDefer;
        c.realmKind = self.realmKind;
        c.locals = self.locals;
        c.assignType = self.assignType;
        c.expected = self.expected;
        c.retType = self.retType;
        c.loopDepth = self.loopDepth;
        c.inProcessInit = self.inProcessInit;
        return c;
    }

    public ResolveCtx func WithClass(String c)      { let ResolveCtx x = self.Clone(); x.curClass = c; return x; }
    public ResolveCtx func WithFunc(String f)       { let ResolveCtx x = self.Clone(); x.curFunc = f; return x; }
    public ResolveCtx func WithStatic(bool s)       { let ResolveCtx x = self.Clone(); x.isStatic = s; return x; }
    public ResolveCtx func WithUnsafe(bool u)       { let ResolveCtx x = self.Clone(); x.inUnsafe = u; return x; }
    public ResolveCtx func WithThrowsFunc(bool t)   { let ResolveCtx x = self.Clone(); x.inThrowsFunc = t; return x; }
    public ResolveCtx func WithRealm(Realm r)       { let ResolveCtx x = self.Clone(); x.realmKind = r; return x; }
    public ResolveCtx func WithCatchWrapped()       { let ResolveCtx x = self.Clone(); x.catchWrapped = true; return x; }
    public ResolveCtx func WithDefer()              { let ResolveCtx x = self.Clone(); x.inDefer = true; return x; }
    public ResolveCtx func WithLoop()               { let ResolveCtx x = self.Clone(); x.loopDepth = self.loopDepth + 1; return x; }
    public ResolveCtx func WithRetType(IrType r)    { let ResolveCtx x = self.Clone(); x.retType = Optional.Some(r); return x; }
    public ResolveCtx func WithProcessInit()        { let ResolveCtx x = self.Clone(); x.inProcessInit = true; return x; }
    public ResolveCtx func WithExpected(IrType e)   { let ResolveCtx x = self.Clone(); x.expected = Optional.Some(e); return x; }
    public ResolveCtx func NoExpected()             { let ResolveCtx x = self.Clone(); x.expected = Optional[IrType].None(); return x; }
    public ResolveCtx func NoCatchWrap()            { let ResolveCtx x = self.Clone(); x.catchWrapped = false; x.expected = Optional[IrType].None(); return x; }

    /*
     * WithTry - Inside a try block, whose label a throw jumps to
     */
    public ResolveCtx func WithTry(String label) {
        let ResolveCtx x = self.Clone();
        x.inTry = true;
        x.tryLabel = label;
        return x;
    }

    /*
     * WithCatchHandler - Inside an inline catch handler, which is where 'assign' is legal and the
     * type it must supply
     */
    public ResolveCtx func WithCatchHandler(IrType assignType) {
        let ResolveCtx x = self.Clone();
        x.assignType = Optional.Some(assignType);
        return x;
    }

    /*
     * PushScope - A nested local scope
     */
    public ResolveCtx func PushScope(bool isParams) {
        let ResolveCtx x = self.Clone();
        x.locals = self.locals.Push(isParams);
        return x;
    }
}



/*
 * The four carriers standing in for C#'s tuple types. Gata has no tuples, and naming each shape
 * once is cheaper than threading four positional values through every call that touches them.
 */

/*
 * A generic free-function template, kept whole until a call site says what to stamp it as.
 * Bucketed by name, because several files may each declare their own private generic under one
 * name without clobbering each other - which is why File and IsPrivate travel with the decl.
 */
class FuncTemplate {
    public FuncDecl decl;
    public String file;
    public Realm realmKind;
    public bool isPrivate;
    func _init(FuncDecl decl, String file, Realm realmKind, bool isPrivate) {
        self.decl = decl;
        self.file = file;
        self.realmKind = realmKind;
        self.isPrivate = isPrivate;
    }
}

/*
 * A generic method template on a class or module, keyed by owner and name
 */
class MethodTemplate {
    public MethodDecl decl;
    public String file;
    public Realm realmKind;
    func _init(MethodDecl decl, String file, Realm realmKind) {
        self.decl = decl;
        self.file = file;
        self.realmKind = realmKind;
    }
}

/*
 * One queued stamping of a generic free function. requestScope is the module scope in force where
 * the type arguments were NAMED, not where the template lives - the stamped body is resolved
 * under it, because a type argument can come from a file the template never imported.
 */
class GenericJob {
    public FuncDecl decl;
    public String file;
    public Realm realmKind;
    public StringMap[TypeSpec] binds;
    public String mangled;
    public StringSet requestScope;
    func _init(FuncDecl decl, String file, Realm realmKind, StringMap[TypeSpec] binds,
               String mangled, StringSet requestScope) {
        self.decl = decl;
        self.file = file;
        self.realmKind = realmKind;
        self.binds = binds;
        self.mangled = mangled;
        self.requestScope = requestScope;
    }
}

/*
 * One queued stamping of a generic method, which additionally remembers what it hangs off
 */
class GenericMethodJob {
    public MethodDecl decl;
    public String owner;
    public String file;
    public Realm realmKind;
    public StringMap[TypeSpec] binds;
    public String mangled;
    public StringSet requestScope;
    func _init(MethodDecl decl, String owner, String file, Realm realmKind,
               StringMap[TypeSpec] binds, String mangled, StringSet requestScope) {
        self.decl = decl;
        self.owner = owner;
        self.file = file;
        self.realmKind = realmKind;
        self.binds = binds;
        self.mangled = mangled;
        self.requestScope = requestScope;
    }
}

/*
 * The pass itself. One instance per build; call Resolve once.
 *
 * Constructed from what SymbolCollector produced (the table, plus the three sets it recorded),
 * the import-visibility map the pipeline built, and the two maps the Monomorphizer left behind
 * saying where each stamped instance was asked for. releaseMode is carried because 'debug' and
 * 'panic' are rejected in a Release build and nowhere else.
 */
class TypeResolver {
    SymbolTable sym;
    StringSet hasInit;
    StringSet nativeStructs;
    StringSet opaqueFieldClasses;
    StringMap[StringSet] visible;
    StringMap[String] genericRequestFile;
    StringMap[StringSet] seedScopes;
    bool releaseMode;
    // Public because the analysis walkers below, which cannot be nested inside this class,
    // report and mangle through them
    public DiagnosticBag diag;
    public Mangler mangler;

    // The interning table every type in the emitted IR comes from. The resolver owns it, and the
    // module it produces carries the same one, so structural identity holds across the backend.
    public IrTypeTable t;

    // Modules visible to the file being resolved, and the same before any per-item widening
    StringSet scope;
    StringSet fileScope;

    // The stamped instance whose body is being resolved, "" at top level. C# tracks this with an
    // IDisposable scope guard; Gata has no using, so callers save and restore it by hand.
    String curInstance;

    // Every distinct fixed-array and function-pointer type this module names. The emitter stamps
    // one typedef per entry, so the list is what it walks and the set is what keeps it unique.
    List[IrType] arrays;
    StringSet arraysSeen;
    List[IrType] funcPtrTypes;
    StringSet funcPtrSeen;

    int tmpSeq;
    int labelSeq;

    // Generic templates, kept whole until a call site says what to stamp them as
    StringMap[List[FuncTemplate]] funcTemplates;
    StringMap[MethodTemplate] methodTemplates;

    // Instantiations this pass needed but could not find, because they only became concrete while
    // stamping a generic function or method
    public List[GenericSeed] pendingInstances;

    // The stamping worklists, and what has already been stamped
    List[GenericJob] genericQueue;
    List[GenericMethodJob] genericMethodQueue;
    StringSet genericSeen;

    // Templates some call site actually instantiated, so a never-used one can be told apart
    StringSet usedFuncTemplates;
    StringSet usedMethodTemplates;

    // Names already reported as wrong-kind or not-visible, keyed file|name. Both diagnostics
    // explain a name's whole meaning rather than one use of it, so they are worth saying once.
    StringSet wrongKind;
    StringSet notVisible;

    // Process variables, keyed by the qualified name the ScopeBinder rewrote every use to, plus
    // the ones whose initialiser has not run yet and the one currently being initialised
    StringMap[IrExpr] processState;
    StringSet processStateNames;
    StringMap[String] processStatePending;
    String processStateCurrent;

    // Whether a union stores a managed value, and whether the walk that decided stood on a cycle
    StringMap[bool] managedUnionCache;
    bool cycleCut;

    func _init(SymbolTable sym, StringSet hasInit, StringSet nativeStructs,
               StringSet opaqueFieldClasses, StringMap[StringSet] visible,
               StringMap[String] genericRequestFile, StringMap[StringSet] seedScopes,
               bool releaseMode, DiagnosticBag diag, Mangler mangler) {
        self.sym = sym;
        self.hasInit = hasInit;
        self.nativeStructs = nativeStructs;
        self.opaqueFieldClasses = opaqueFieldClasses;
        self.visible = visible;
        self.genericRequestFile = genericRequestFile;
        self.seedScopes = seedScopes;
        self.releaseMode = releaseMode;
        self.diag = diag;
        self.mangler = mangler;
        self.t = new IrTypeTable();
        self.scope = new StringSet();
        self.fileScope = new StringSet();
        self.curInstance = "";
        self.arrays = new List[IrType]();
        self.arraysSeen = new StringSet();
        self.funcPtrTypes = new List[IrType]();
        self.funcPtrSeen = new StringSet();
        self.tmpSeq = 0;
        self.labelSeq = 0;
        self.funcTemplates = new StringMap[List[FuncTemplate]]();
        self.methodTemplates = new StringMap[MethodTemplate]();
        self.pendingInstances = new List[GenericSeed]();
        self.genericQueue = new List[GenericJob]();
        self.genericMethodQueue = new List[GenericMethodJob]();
        self.genericSeen = new StringSet();
        self.usedFuncTemplates = new StringSet();
        self.usedMethodTemplates = new StringSet();
        self.wrongKind = new StringSet();
        self.notVisible = new StringSet();
        self.processState = new StringMap[IrExpr]();
        self.processStateNames = new StringSet();
        self.processStatePending = new StringMap[String]();
        self.processStateCurrent = "";
        self.managedUnionCache = new StringMap[bool]();
        self.cycleCut = false;
    }

    /* ---------------------------------------------------------------------------------------
     * Scope: what the file being resolved can see
     * ------------------------------------------------------------------------------------ */

    /*
     * ClassInScope - True when a class name is declared in a module the current file imports
     */
    bool func ClassInScope(String name) {
        match (self.sym.ClassModule(name)) {
            case Some(m) { return self.scope.Has(m); }
            case None { return false; }
        }
    }

    /*
     * FuncInScope - True when a free-function symbol is in scope for the current file
     */
    bool func FuncInScope(Optional[Symbol] f) {
        match (f) {
            case Some(s) { return self.scope.Has(s.declFile); }
            case None { return false; }
        }
    }

    /*
     * LookupFreeFuncVisible - A free function, preferring a registration this file can see. The
     * last registration wins by default, which may belong to a file this one never imported; an
     * in-scope declaration of the same name is the better answer whenever there is one.
     */
    Optional[Symbol] func LookupFreeFuncVisible(String name) {
        let Optional[Symbol] f = self.sym.LookupFreeFunc(name);
        match (f) {
            case None { return f; }
            case Some(s) {
                if (self.scope.Has(s.declFile)) { return f; }
                let List[Symbol] cands = self.sym.FuncDeclarations(name);
                let int i = 0;
                while (i < cands.Length()) {
                    let Symbol c = cands.Get(i);
                    if (!self.SigIsEntry(c) && self.scope.Has(c.declFile)) {
                        return Optional.Some(c);
                    }
                    i = i + 1;
                }
                return f;
            }
        }
    }

    /*
     * SigIsEntry - True when a symbol carries an entry-point signature
     */
    bool func SigIsEntry(Symbol s) {
        match (s.sig) { case Some(g) { return g.isEntry; } case None { return false; } }
    }

    /*
     * SigOf - A symbol's signature, or None
     */
    Optional[MethodSig] func SigOf(Optional[Symbol] s) {
        match (s) { case Some(x) { return x.sig; } case None { return Optional[MethodSig].None(); } }
    }

    /* ---------------------------------------------------------------------------------------
     * Small allocators: temporaries, and the type lists the emitter stamps typedefs from
     * ------------------------------------------------------------------------------------ */

    /*
     * Tmp - A unique temporary name. The '__' prefix is reserved against author-written locals
     * precisely so these can never collide with one.
     */
    String func Tmp(String prefix) {
        let String n = prefix + Int.ToString(self.tmpSeq);
        self.tmpSeq = self.tmpSeq + 1;
        return n;
    }

    /*
     * Label - A unique label name, for the goto a try block lowers to
     */
    String func Label(String prefix) {
        let String n = prefix + Int.ToString(self.labelSeq);
        self.labelSeq = self.labelSeq + 1;
        return n;
    }

    /*
     * Arr - The fixed-array type for an element type and size, recording it the first time this
     * module names it
     */
    IrType func Arr(IrType elem, int size) {
        let IrType a = self.t.Array(elem, size);
        if (self.arraysSeen.AddNew(Types.Key(a))) { self.arrays.Add(a); }
        return a;
    }

    /*
     * FnPtr - The function-pointer type for a signature, recording it the first time this module
     * names it. Interning is table-wide and outlives one module, so the seen set has to be the
     * resolver's: a signature an earlier module canonicalised still needs stamping into this one.
     */
    IrType func FnPtr(IrType ret, List[IrType] ps) {
        let IrType f = self.t.FuncPtr(ret, ps);
        if (self.funcPtrSeen.AddNew(Types.Key(f))) { self.funcPtrTypes.Add(f); }
        return f;
    }

    /*
     * Poison - The value an expression takes once the reason it could not be resolved has been
     * reported. Typed as the error type, which every check treats as "already complained about",
     * so one mistake yields one diagnostic rather than a cascade.
     */
    IrExpr func Poison(TextSpan span) {
        let IrDefault d = new IrDefault(self.t.Error());
        d.span = span;
        return IrExpr.IrDefault(d);
    }

    /* ---------------------------------------------------------------------------------------
     * Type predicates
     * ------------------------------------------------------------------------------------ */

    /*
     * IsNum - True for any numeric primitive, bool included (it is integral, rank 1)
     */
    bool func IsNum(IrType ty) { return Types.IsNumeric(ty) || Types.IsFloat(ty); }

    /*
     * IsArith - Numeric, but not bool: what '+' and friends accept
     */
    bool func IsArith(IrType ty) {
        if (!self.IsNum(ty)) { return false; }
        match (ty) { case IrPrimType(p) { return p.cName != "bool"; } default { return true; } }
    }

    /*
     * IsInteger - True for an integer primitive, which is what the bitwise operators require
     */
    bool func IsInteger(IrType ty) {
        match (ty) {
            case IrPrimType(p) { return PrimTypes.IsIntCanon(p.cName); }
            default { return false; }
        }
    }

    /*
     * NumRank - The promotion rank of a type. Ranks live in PrimTypes with each primitive's other
     * facts, so widening cannot disagree with the table.
     */
    int func NumRank(IrType ty) {
        match (ty) { case IrPrimType(p) { return PrimTypes.Rank(p.cName); } default { return 4; } }
    }

    /*
     * IsOpaqueStruct - True when the class was declared as a native type with no Gata-visible
     * fields
     */
    bool func IsOpaqueStruct(String cls) { return self.nativeStructs.Has(cls); }

    /*
     * HasOpaqueFields - True when the class has either a native struct body or a raw C 'fields'
     * block. The compiler cannot see inside either, so an unknown member on one is not an error.
     */
    bool func HasOpaqueFields(String cls) {
        return self.nativeStructs.Has(cls) || self.opaqueFieldClasses.Has(cls);
    }

    /*
     * Describe - A type as a human reads it, for diagnostics. Never a mangled spelling: an
     * instantiation reads the way the author wrote it.
     */
    String func Describe(IrType ty) {
        match (ty) {
            case IrVoidType(v)   { return "void"; }
            case IrPrimType(p)   { return p.cName; }
            case IrClassRef(c)   { return self.mangler.DisplayName(c.className); }
            case IrPtrType(p)    { return self.Describe(p.inner) + "*"; }
            case IrArrayType(a)  { return "[" + Int.ToString(a.size) + "]" + self.Describe(a.elem); }
            case IrResultType(r) { return "throws " + self.Describe(r.inner); }
            case IrFuncPtrType(f) { return self.DescribeFuncPtr(f); }
            case IrUnionType(u)  { return self.mangler.DisplayName(u.name); }
            case IrEnumType(e)   { return self.mangler.DisplayName(e.name); }
            default { return self.mangler.CType(ty); }
        }
    }

    /*
     * DescribeFuncPtr - A function-pointer type spelled the way it is written in source
     */
    String func DescribeFuncPtr(IrFuncPtrType f) {
        let StringBuilder sb = new StringBuilder();
        sb.Put("func(");
        let int i = 0;
        while (i < f.params.Length()) {
            if (i > 0) { sb.Put(", "); }
            sb.Put(self.Describe(f.params.Get(i)));
            i = i + 1;
        }
        sb.Put(") -> ");
        sb.Put(self.Describe(f.ret));
        return sb.ToString();
    }

    /*
     * DescribeArgs - An argument list's types, for an overload diagnostic
     */
    String func DescribeArgs(List[IrExpr] args) {
        let StringBuilder sb = new StringBuilder();
        let int i = 0;
        while (i < args.Length()) {
            if (i > 0) { sb.Put(", "); }
            sb.Put(self.Describe(Exprs2.TypeOf(args.Get(i))));
            i = i + 1;
        }
        return sb.ToString();
    }

    /* ---------------------------------------------------------------------------------------
     * Type specs: checking one, and turning one into an IrType
     * ------------------------------------------------------------------------------------ */

    /*
     * MaxSeedDepth - How deeply a type argument may nest before an instantiation stops being
     * created on demand. Hand-written code nests two or three deep; deeper than this is the
     * signature of a family that generates a new level every time the previous one is created.
     */
    int func MaxSeedDepth() { return 6; }

    /*
     * SeedDepth - Nesting depth of an already-mangled instance name, walked the same way
     * TrySplitInstance walks it
     */
    int func SeedDepth(String mangled) {
        let int depth = 1;
        let String cur = mangled;
        while (true) {
            match (self.mangler.TrySplitInstance(cur)) {
                case None { return depth; }
                case Some(k) {
                    if (GK.Args(k).Length() == 0) { return depth; }
                    depth = depth + 1;
                    if (depth > self.MaxSeedDepth() + 1) { return depth; }
                    cur = GK.Args(k).Get(0);
                }
            }
        }
    }

    /*
     * SpecDepth - Nesting depth of a written type spec
     */
    int func SpecDepth(NamedSpec s) {
        let int deepest = 0;
        let int i = 0;
        while (i < s.args.Length()) {
            let int d = self.SpecDepth(s.args.Get(i));
            if (d > deepest) { deepest = d; }
            i = i + 1;
        }
        return deepest + 1;
    }

    /*
     * Sp - A spec node's own span, falling back to the declaration's when the node was
     * synthesized without one. Each node carries its own, so the caret lands on the offending
     * part of a compound type rather than on the whole declaration.
     */
    TextSpan func Sp(TypeSpec ty, TextSpan fallback) {
        let TextSpan s = Specs.Span(ty);
        return TS.IsNone(s) ? fallback : s;
    }

    /*
     * CheckType - Validates that a type spec names real, in-scope types, node by node
     */
    void func CheckType(Optional[TypeSpec] ty, ResolveCtx ctx, TextSpan span, bool allowVoid) {
        match (ty) {
            case None { }
            case Some(x) { self.CheckTypeSpec(x, ctx, span, allowVoid); }
        }
    }

    /*
     * CheckTypeSpec - CheckType over a spec known to be present
     */
    void func CheckTypeSpec(TypeSpec ty, ResolveCtx ctx, TextSpan span, bool allowVoid) {
        match (ty) {
            case FuncSpec(f) {
                let int i = 0;
                while (i < f.params.Length()) {
                    self.CheckTypeSpec(f.params.Get(i), ctx, self.Sp(f.params.Get(i), span), false);
                    i = i + 1;
                }
                // A function pointer may return void, unlike anything else that names a type
                self.CheckTypeSpec(f.ret, ctx, self.Sp(f.ret, span), true);
            }
            case ArraySpec(a) {
                let int64 n = Literals.IntValue(a.sizeText, 0L);
                if (n <= 0L) {
                    self.diag.Error(Codes.UndefinedType(), ctx.file, self.Sp(ty, span),
                        "invalid fixed-array size in '" + Specs.ToSpecString(ty) + "'");
                } else {
                    self.CheckTypeSpec(a.elem, ctx, self.Sp(a.elem, span), false);
                }
            }
            case PtrSpec(ptr) {
                // Any depth of void* is a legal type with nothing further to check
                let TypeSpec inner = ptr.inner;
                while (true) {
                    match (inner) { case PtrSpec(ip) { inner = ip.inner; } default { break; } }
                }
                match (inner) {
                    case NamedSpec(nm) {
                        if (nm.name == "void" && nm.args.Length() == 0) { return; }
                    }
                    default { }
                }
                self.CheckTypeSpec(inner, ctx, self.Sp(inner, span), false);
            }
            case NamedSpec(nm) { self.CheckNamedSpec(nm, ty, ctx, span, allowVoid); }
        }
    }

    /*
     * CheckNamedSpec - The named-type half of CheckType, which is where every "unknown type"
     * diagnostic and every deferred-instantiation seed comes from
     */
    void func CheckNamedSpec(NamedSpec nm, TypeSpec ty, ResolveCtx ctx, TextSpan span, bool allowVoid) {
        if (nm.name == Specs.Poison()) { return; }

        let String name = nm.Mangled();
        let TextSpan at = self.Sp(ty, span);

        if (name == "void") {
            if (!allowVoid) {
                self.diag.Error(Codes.UndefinedType(), ctx.file, at, "'void' is not a value type");
            }
            return;
        }
        if (PrimTypes.IsPrim(name))         { return; }
        if (BuiltinTypes.IsBuiltin(name))   { return; }
        if (self.sym.IsEnum(name))          { return; }
        if (self.sym.IsUnion(name))         { return; }
        if (self.ClassInScope(name))        { return; }

        // The type exists, but this file never imported the module declaring it
        if (self.sym.IsClass(name)) {
            let List[String] hints = new List[String]();
            self.AddInstantiationHint(hints, self.InstanceOrClass(ctx));
            self.diag.Error(Codes.UndefinedType(), ctx.file, at,
                "type '" + self.mangler.DisplayName(name) + "' is not in scope; import its module", hints);
            return;
        }

        if (self.ReportNotVisible("type", nm.name, ctx.file, at)) { return; }
        if (self.ReportWrongKind(Codes.UndefinedType(),
                nm.args.Length() > 0 ? "a generic type" : "a type", nm.name, ctx.file, at)) { return; }

        // A generic whose creation already failed reports once, not once per use
        if (self.mangler.GenericFailed(name)) { return; }
        if (name.Contains(Types.MangledName(self.t.Error()))) {
            self.mangler.MarkGenericFailed(name);
            return;
        }

        // An instance name that was composed but never stamped. Seeding it lets a later round
        // create it; the diagnostic is what the author sees if no round can.
        if (nm.args.Length() == 0) {
            match (self.mangler.TrySplitInstance(name)) {
                case Some(k) {
                    if (self.SeedDepth(name) <= self.MaxSeedDepth()) {
                        self.SeedInstance(GK.Base(k), GK.Args(k), at, ctx.file);
                    }
                    let List[String] hints = new List[String]();
                    hints.Add("this instantiation is named over a generic function's own type " +
                              "parameter, and could not be created");
                    hints.Add("name it once outside any generic function, or give the enclosing " +
                              "function a concrete parameter type instead of a generic one");
                    self.diag.Error(Codes.UndefinedType(), ctx.file, at,
                        "'" + self.mangler.DisplayName(GK.Base(k)) + "[" +
                        self.DisplayList(GK.Args(k)) + "]' is never instantiated, so it cannot be used here",
                        hints);
                    self.mangler.MarkGenericFailed(name);
                    return;
                }
                case None { }
            }
        }

        // Written as Base[Args] against a template that was never stamped for these arguments
        if (nm.args.Length() > 0 && self.mangler.IsGenericTemplate(nm.name)) {
            let List[String] argNames = new List[String]();
            let int i = 0;
            while (i < nm.args.Length()) { argNames.Add(nm.args.Get(i).Mangled()); i = i + 1; }
            if (self.SpecDepth(nm) <= self.MaxSeedDepth()) {
                self.SeedInstance(nm.name, argNames, at, ctx.file);
            }
            let String written = self.Written(nm);
            let List[String] hints = new List[String]();
            hints.Add("'" + self.mangler.DisplayName(nm.name) + "' is a generic type used over a " +
                      "generic function's own type parameter, and this instantiation could not be created");
            hints.Add("name it once outside any generic function - 'let " + written +
                      " _seed = ...;' - or give the enclosing function a concrete parameter type " +
                      "instead of a generic one");
            self.diag.Error(Codes.UndefinedType(), ctx.file, at,
                "'" + written + "' is never instantiated, so it cannot be used here", hints);
            self.mangler.MarkGenericFailed(name);
            return;
        }

        let List[String] unknownHints = new List[String]();
        self.AddInstantiationHint(unknownHints, self.InstanceOrClass(ctx));
        self.diag.Error(Codes.UndefinedType(), ctx.file, at,
            "unknown type '" + self.Written(nm) + "'", unknownHints);
    }

    /*
     * SeedInstance - Records an instantiation a later round should create, carrying the scope in
     * force where it was named
     */
    void func SeedInstance(String base, List[String] args, TextSpan span, String file) {
        let GenericSeed g = new GenericSeed(base, args, span, file);
        g.scope = self.scope.ToList();
        self.pendingInstances.Add(g);
    }

    /*
     * DisplayList - Type arguments spelled the way the author wrote them, comma separated
     */
    String func DisplayList(List[String] args) {
        let List[String] out = new List[String]();
        let int i = 0;
        while (i < args.Length()) { out.Add(self.mangler.DisplayName(args.Get(i))); i = i + 1; }
        return String.Join(out, ", ");
    }

    /*
     * Written - A named spec as the author spelled it, never mangled
     */
    String func Written(NamedSpec nm) {
        if (nm.args.Length() == 0) { return self.mangler.DisplayName(nm.name); }
        let List[String] args = new List[String]();
        let int i = 0;
        while (i < nm.args.Length()) { args.Add(nm.args.Get(i).Mangled()); i = i + 1; }
        return self.mangler.DisplayName(nm.name) + "[" + self.DisplayList(args) + "]";
    }

    /*
     * InstanceOrClass - The stamped instance being resolved, else the enclosing class
     */
    String func InstanceOrClass(ResolveCtx ctx) {
        return self.curInstance.Length() > 0 ? self.curInstance : ctx.curClass;
    }

    /*
     * ResolveType - A written type spec as an IrType. Every type in the emitted IR comes from
     * here, so it is also where an unresolvable name becomes the error type rather than a crash.
     */
    public IrType func ResolveType(Optional[TypeSpec] ty) {
        match (ty) {
            case None { return self.t.Void(); }
            case Some(x) { return self.ResolveTypeSpec(x); }
        }
    }

    /*
     * ResolveTypeSpec - ResolveType over a spec known to be present
     */
    public IrType func ResolveTypeSpec(TypeSpec ty) {
        match (ty) {
            case FuncSpec(f) {
                let List[IrType] ps = new List[IrType]();
                let int i = 0;
                while (i < f.params.Length()) { ps.Add(self.ResolveTypeSpec(f.params.Get(i))); i = i + 1; }
                return self.FnPtr(self.ResolveTypeSpec(f.ret), ps);
            }
            case ArraySpec(a) {
                return self.Arr(self.ResolveTypeSpec(a.elem),
                                Literals.IntValue(a.sizeText, 0L) as int);
            }
            case PtrSpec(p) { return self.t.Ptr(self.ResolveTypeSpec(p.inner)); }
            case NamedSpec(nm) { return self.ResolveNamed(nm); }
        }
    }

    /*
     * ResolveNamed - The named-type half of ResolveType
     */
    IrType func ResolveNamed(NamedSpec nm) {
        if (nm.name == Specs.Poison()) { return self.t.Error(); }
        let String name = nm.Mangled();
        if (name == "void") { return self.t.Void(); }

        if (BuiltinTypes.IsBuiltin(name)) {
            match (self.sym.ResolveBuiltinType(name, self.t)) {
                case Some(bt) { return bt; }
                case None {
                    if (name == BuiltinTypes.Str()) { return self.t.Str(); }
                    return self.t.ClassRef(name);
                }
            }
        }
        if (PrimTypes.IsPrim(name))  { return self.t.Prim(name); }
        if (self.sym.IsEnum(name))   { return self.t.EnumType(name); }
        if (self.sym.IsUnion(name))  { return self.t.UnionType(name); }
        if (self.sym.IsClass(name))  { return self.t.ClassRef(name); }
        return self.t.Error();
    }

    /* ---------------------------------------------------------------------------------------
     * Declaration-shaped checks
     * ------------------------------------------------------------------------------------ */

    /*
     * CheckParams - Rejects two parameters of one name, and any name the compiler reserves
     */
    void func CheckParams(List[Param] ps, ResolveCtx ctx) {
        let StringSet seen = new StringSet();
        let int i = 0;
        while (i < ps.Length()) {
            let Param p = ps.Get(i);
            if (!seen.AddNew(p.name)) {
                self.diag.Error(Codes.DuplicateName(), ctx.file, p.span,
                    "duplicate parameter '" + p.name + "'");
            }
            self.CheckNotReservedLocal(p.name, p.span, "parameter", ctx);
            i = i + 1;
        }
    }

    /*
     * CheckNotReservedLocal - Rejects a local or parameter whose name the compiler also generates
     * for its own temporaries. Both are emitted verbatim into one C scope, so the declarations
     * would collide and no renaming rule can separate them afterwards.
     */
    void func CheckNotReservedLocal(String name, TextSpan span, String what, ResolveCtx ctx) {
        if (!Mangle.IsReservedLocal(name)) { return; }
        let List[String] hints = new List[String]();
        hints.Add("that prefix belongs to the temporaries lowering introduces, which land in this " +
                  "same C scope");
        let String trimmed = name;
        while (trimmed.Length() > 0 && trimmed.CharAt(0) == '_') {
            trimmed = trimmed.Substring(1, trimmed.Length() - 1);
        }
        hints.Add("one underscore is yours: '_" + trimmed + "'");
        self.diag.Error(Codes.DuplicateName(), ctx.file, span,
            "a " + what + " name cannot begin with '__'", hints);
    }

    /*
     * CheckArgCount - Reports an argument count that does not match the signature
     */
    void func CheckArgCount(Optional[MethodSig] sig, int argCount, String display,
                            ResolveCtx ctx, TextSpan span) {
        match (sig) {
            case None { }
            case Some(g) {
                if (g.params.Length() != argCount) {
                    self.diag.Error(Codes.WrongArgCount(), ctx.file, span,
                        "'" + display + "' expects " + Int.ToString(g.params.Length()) +
                        " argument(s), got " + Int.ToString(argCount));
                }
            }
        }
    }

    /* ---------------------------------------------------------------------------------------
     * Overload resolution
     * ------------------------------------------------------------------------------------ */

    /*
     * ArgConvCost - What it costs to pass an argument where a parameter of type 'to' is wanted:
     * 0 exact, 1 widening or pointer covariance, 2 narrowing. -1 means no conversion exists.
     */
    int func ArgConvCost(IrExpr arg, IrType to) {
        let IrType from = Exprs2.TypeOf(arg);
        if (Types.IsError(from) || Types.IsError(to)) { return 0; }
        match (arg) {
            case IrLitNull(n) { return self.IsRefLike(to) ? 0 : -1; }
            default { }
        }
        if (Types.Same(from, to)) { return 0; }
        if (self.IsNum(from) && self.IsNum(to)) {
            return self.NumRank(from) <= self.NumRank(to) ? 1 : 2;
        }
        if (Types.IsString(from) && Types.IsString(to)) { return 0; }
        if (self.PtrCompatible(from, to)) { return 1; }
        return -1;
    }

    /*
     * IsRefLike - True for the types 'null' may be stored in
     */
    bool func IsRefLike(IrType ty) {
        match (ty) {
            case IrClassRef(c)    { return true; }
            case IrPtrType(p)     { return true; }
            case IrFuncPtrType(f) { return true; }
            default { return false; }
        }
    }

    /*
     * PtrCompatible - Pointer covariance: same pointee, or either side void*
     */
    bool func PtrCompatible(IrType from, IrType to) {
        match (from) {
            case IrPtrType(fp) {
                match (to) {
                    case IrPtrType(tp) {
                        return Types.Same(fp.inner, tp.inner) ||
                               Types.IsVoid(fp.inner) || Types.IsVoid(tp.inner);
                    }
                    default { return false; }
                }
            }
            default { return false; }
        }
    }

    /*
     * MatchCost - The total conversion cost of an argument list against a signature, or -1 when
     * the count differs or any one argument cannot convert
     */
    int func MatchCost(MethodSig sig, List[IrExpr] args) {
        if (sig.params.Length() != args.Length()) { return -1; }
        let int total = 0;
        let int i = 0;
        while (i < args.Length()) {
            let int c = self.ArgConvCost(args.Get(i),
                            self.ResolveTypeSpec(sig.params.Get(i).type));
            if (c < 0) { return -1; }
            total = total + c;
            i = i + 1;
        }
        return total;
    }

    /*
     * ChooseOverload - The best-matching candidate for an argument list. Lowest total cost wins;
     * a tie between two different C names is ambiguous, and no match at all is its own error.
     */
    Optional[Symbol] func ChooseOverload(List[Symbol] cands, Optional[Symbol] primary,
                                         List[IrExpr] args, String display, ResolveCtx ctx,
                                         TextSpan span) {
        if (cands.Length() <= 1) {
            match (primary) {
                case Some(p) { self.CheckArgCount(p.sig, args.Length(), display, ctx, span); }
                case None { }
            }
            return primary;
        }

        let Optional[Symbol] best = Optional[Symbol].None();
        let int bestCost = 2147483647;
        let bool tie = false;
        let int i = 0;
        while (i < cands.Length()) {
            let Symbol c = cands.Get(i);
            match (c.sig) {
                case None { }
                case Some(g) {
                    let int cost = self.MatchCost(g, args);
                    if (cost >= 0) {
                        let bool first = IsNone(best);
                        if (first || cost < bestCost) {
                            bestCost = cost;
                            best = Optional.Some(c);
                            tie = false;
                        } else if (cost == bestCost) {
                            match (best) {
                                case Some(b) { if (c.cName != b.cName) { tie = true; } }
                                case None { }
                            }
                        }
                    }
                }
            }
            i = i + 1;
        }

        if (IsNone(best)) {
            self.diag.Error(Codes.NoMatchingOverload(), ctx.file, span,
                "no overload of '" + display + "' matches (" + self.DescribeArgs(args) + ")");
            return Optional[Symbol].None();
        }
        if (tie) {
            self.diag.Error(Codes.AmbiguousOverload(), ctx.file, span,
                "call to '" + display + "' is ambiguous for (" + self.DescribeArgs(args) + ")");
        }
        return best;
    }

    /* ---------------------------------------------------------------------------------------
     * Assignment compatibility
     * ------------------------------------------------------------------------------------ */

    /*
     * Assignable - True when a value may be stored in a target of the given type, allowing
     * implicit widening, a literal into anything it fits, null into a reference, and pointer
     * covariance. Narrowing is never implicit.
     */
    bool func Assignable(IrExpr value, IrType to) {
        let IrType from = Exprs2.TypeOf(value);
        if (Types.IsError(from) || Types.IsError(to)) { return true; }
        match (value) {
            case IrLitNull(n) { return self.IsRefLike(to); }
            default { }
        }
        if (Types.Same(from, to)) { return true; }
        if (Types.IsVoid(to)) { return false; }

        // A literal goes into any numeric type; CheckLiteralFits is what then rejects one whose
        // value would not survive the store.
        let bool isCharLit = false;
        match (value) { case IrLitChar(c) { isCharLit = true; } default { } }
        if ((isCharLit || IsSome(self.LiteralValue(value))) && self.IsNum(to)) { return true; }
        match (value) {
            case IrLitFloat(f) { if (Types.IsFloat(to)) { return true; } }
            default { }
        }

        if (self.IsNum(from) && self.IsNum(to)) { return self.NumRank(from) <= self.NumRank(to); }
        if (Types.IsString(from) && Types.IsString(to)) { return true; }
        return self.PtrCompatible(from, to);
    }

    /*
     * LiteralValue - The constant an expression denotes when it is an integer literal, optionally
     * negated. Only those two shapes: anything else may depend on values this pass cannot see.
     */
    Optional[int64] func LiteralValue(IrExpr e) {
        match (e) {
            case IrLitInt(li) { return Optional.Some(li.value); }
            case IrUnaryOp(u) {
                if (u.op != UnOp.Neg) { return Optional[int64].None(); }
                match (u.operand) {
                    case IrLitInt(li) { return Optional.Some(0L - li.value); }
                    default { return Optional[int64].None(); }
                }
            }
            default { return Optional[int64].None(); }
        }
    }

    /*
     * CheckAssign - Reports a value that cannot be stored in the target type. A Result on either
     * side is left alone: the throws machinery has its own diagnostics and would double-report.
     */
    void func CheckAssign(IrExpr value, IrType target, String what, ResolveCtx ctx, String code) {
        match (Exprs2.TypeOf(value)) { case IrResultType(r) { return; } default { } }
        match (target) { case IrResultType(r) { return; } default { } }

        if (!self.Assignable(value, target)) {
            self.diag.Error(code, ctx.file, Exprs2.SpanOf(value),
                "cannot assign '" + self.Describe(Exprs2.TypeOf(value)) + "' to " + what +
                " of type '" + self.Describe(target) + "'");
            return;
        }
        self.CheckLiteralFits(value, target, what, ctx);
    }

    /*
     * CheckLiteralFits - Rejects an integer literal too large for the type it is stored in. The
     * conversion would be silent in C, so the hint says what would actually land there.
     */
    void func CheckLiteralFits(IrExpr value, IrType target, String what, ResolveCtx ctx) {
        match (self.LiteralValue(value)) {
            case None { }
            case Some(n) {
                match (target) {
                    case IrPrimType(pt) {
                        let int bits = PrimTypes.IntBits(pt.cName);
                        if (bits == 0 || bits == 1 || bits == 64) { return; }
                        let bool unsigned = PrimTypes.IsUnsignedCanon(pt.cName);
                        let int64 lo = self.RangeLo(bits, unsigned);
                        let int64 hi = self.RangeHi(bits, unsigned);
                        if (n >= lo && n <= hi) { return; }
                        let List[String] hints = new List[String]();
                        hints.Add("'" + self.Describe(target) + "' holds " + Long.ToString(lo) +
                                  " to " + Long.ToString(hi) + "; the conversion is silent, so this " +
                                  "would store " + Long.ToString(self.Truncate(n, bits, unsigned)));
                        hints.Add("widen the type, or write the value you meant");
                        self.diag.Error(Codes.TypeMismatch(), ctx.file, Exprs2.SpanOf(value),
                            Long.ToString(n) + " does not fit in '" + self.Describe(target) +
                            "', the type of " + what, hints);
                    }
                    default { }
                }
            }
        }
    }

    /*
     * RangeLo - The lowest value an integer primitive of this width holds
     */
    int64 func RangeLo(int bits, bool unsigned) {
        if (unsigned) { return 0L; }
        return 0L - (1L << (bits - 1));
    }

    /*
     * RangeHi - The highest value an integer primitive of this width holds
     */
    int64 func RangeHi(int bits, bool unsigned) {
        if (unsigned) { return (1L << bits) - 1L; }
        return (1L << (bits - 1)) - 1L;
    }

    /*
     * Truncate - What C would actually store, for the hint
     */
    int64 func Truncate(int64 n, int bits, bool unsigned) {
        let uint64 all = 18446744073709551615u;
        let uint64 mask = bits == 64 ? all : ((1u as uint64) << bits) - (1 as uint64);
        let uint64 masked = (n as uint64) & mask;
        if (unsigned || bits == 64) { return masked as int64; }
        let uint64 signBit = (1u as uint64) << (bits - 1);
        if ((masked & signBit) != (0 as uint64)) {
            return (masked as int64) - ((1u as uint64) << bits) as int64;
        }
        return masked as int64;
    }

    /*
     * ComparableEq - True when two expressions may be compared with == or !=
     */
    bool func ComparableEq(IrExpr l, IrExpr r) {
        let IrType a = Exprs2.TypeOf(l);
        let IrType b = Exprs2.TypeOf(r);
        if (Types.IsError(a) || Types.IsError(b)) { return true; }

        let bool lNull = false;
        let bool rNull = false;
        match (l) { case IrLitNull(x) { lNull = true; } default { } }
        match (r) { case IrLitNull(x) { rNull = true; } default { } }
        if (lNull || rNull) { return self.IsRefLike(lNull ? b : a); }

        if (self.IsNum(a) && self.IsNum(b)) { return true; }
        if (Types.IsString(a) && Types.IsString(b)) { return true; }
        return self.SameNamedKind(a, b);
    }

    /*
     * SameNamedKind - True when two types are the same pointer, class, enum, union or function
     * pointer. Named kinds compare by name so two references to one class are one type.
     */
    bool func SameNamedKind(IrType a, IrType b) {
        match (a) {
            case IrPtrType(x) { match (b) { case IrPtrType(y) { return true; } default { return false; } } }
            case IrClassRef(x) {
                match (b) { case IrClassRef(y) { return x.className == y.className; } default { return false; } }
            }
            case IrEnumType(x) {
                match (b) { case IrEnumType(y) { return x.name == y.name; } default { return false; } }
            }
            case IrUnionType(x) {
                match (b) { case IrUnionType(y) { return x.name == y.name; } default { return false; } }
            }
            case IrFuncPtrType(x) {
                match (b) { case IrFuncPtrType(y) { return Types.Same(a, b); } default { return false; } }
            }
            default { return false; }
        }
    }

    /*
     * IsLiteral - True for a bare constant: the one place a same-type cast is deliberate, since
     * '0x00100000 as int' pins a bit pattern's width where inference would otherwise decide it
     */
    bool func IsLiteral(IrExpr e) {
        match (e) {
            case IrLitInt(x)    { return true; }
            case IrLitFloat(x)  { return true; }
            case IrLitChar(x)   { return true; }
            case IrLitBool(x)   { return true; }
            case IrLitString(x) { return true; }
            case IrLitNull(x)   { return true; }
            case IrEnumConst(x) { return true; }
            default { return false; }
        }
    }

    /* ---------------------------------------------------------------------------------------
     * Reporting a name that exists somewhere else, or means something else
     * ------------------------------------------------------------------------------------ */

    /*
     * ReportWrongKind - Reports a name a scope does declare, but as something else - the function
     * 'kernel.X' where a type was wanted. A scope holds ONE meaning per name, so the outer
     * declaration this one displaced cannot be reached, and "unknown type" would be the single
     * answer that is untrue. Returns true when it reported, or already had.
     */
    bool func ReportWrongKind(String code, String wanted, String qualified, String file, TextSpan span) {
        match (self.mangler.ScopedKind(qualified)) {
            case None { return false; }
            case Some(have) {
                if (have == wanted) { return false; }
                if (!self.wrongKind.AddNew(file + "|" + qualified)) { return true; }
                let String shown = self.mangler.DisplayName(qualified);
                let List[String] hints = new List[String]();
                hints.Add("the declaration of '" + shown + "' takes over the name in its scope, so " +
                          wanted + " of that name outside it cannot be reached from here");
                self.diag.Error(code, file, span,
                    "'" + shown + "' is " + have + " here, not " + wanted, hints);
                return true;
            }
        }
    }

    /*
     * ReportNotVisible - Reports a name that does exist, but only inside a scope this code is not
     * in. False when nothing scoped declares it, which leaves the caller's own "no such name"
     * error to fire instead.
     */
    bool func ReportNotVisible(String kind, String bare, String file, TextSpan span) {
        let List[String] paths = self.mangler.ScopedCandidates(bare);
        if (paths.Length() == 0) { return false; }
        if (!self.notVisible.AddNew(file + "|" + bare)) { return true; }

        let List[String] quoted = new List[String]();
        let List[String] owners = new List[String]();
        let int i = 0;
        while (i < paths.Length()) {
            let String p = paths.Get(i);
            let int dot = p.LastIndexOf(".");
            let String owner = dot > 0 ? p.Substring(0, dot) : p;
            owners.Add(owner);
            quoted.Add("'" + owner + "'");
            i = i + 1;
        }

        let List[String] hints = new List[String]();
        hints.Add(owners.Length() == 1
            ? "reference it from inside '" + owners.Get(0) + "', or move it out to the enclosing realm"
            : "reference it from inside the declaring scope, or move it out to the enclosing realm");

        self.diag.Error(Codes.ScopedNameNotVisible(), file, span,
            kind + " '" + bare + "' is declared inside " + String.Join(quoted, " and ") +
            " and is not visible here", hints);
        return true;
    }

    /*
     * AddInstantiationHint - Names the generic instantiation an error came from.
     *
     * A stamped instance lives in the TEMPLATE's file, so 'Map[String, int]' reports a cast error
     * inside Map.g with nothing on the line to say which of the author's types is at fault. This
     * is what puts that back.
     */
    void func AddInstantiationHint(List[String] hints, String instance) {
        if (instance.Length() == 0) { return; }
        match (self.mangler.TryGetGenericInstance(instance)) {
            case None { }
            case Some(k) {
                hints.Add("this comes from the instantiation '" + self.mangler.DisplayName(instance) +
                          "'; the type arguments have to satisfy what the generic's body does with them");

                // The specific case worth naming: a String key in a reference-hashed container,
                // when a string-keyed sibling exists
                let List[String] args = GK.Args(k);
                if (!args.Contains("String")) { return; }
                let String sibling = "String" + GK.Base(k);
                if (!self.mangler.IsGenericTemplate(sibling) && !self.sym.IsClass(sibling)) { return; }

                let List[String] rest = new List[String]();
                let int i = 0;
                while (i < args.Length()) {
                    if (args.Get(i) != "String") { rest.Add(self.mangler.DisplayName(args.Get(i))); }
                    i = i + 1;
                }
                let String spelled = rest.Length() > 0
                    ? sibling + "[" + String.Join(rest, ", ") + "]"
                    : sibling;
                hints.Add("for a 'String' key, use '" + spelled + "' - it hashes the text rather " +
                          "than the reference, which is what '" +
                          self.mangler.DisplayName(GK.Base(k)) + "' cannot do");
            }
        }
    }

    /*
     * VisOf - The IR visibility a realm maps to
     */
    Visibility func VisOf(Realm r) {
        if (r == Realm.Kernel) { return Visibility.Kernel; }
        if (r == Realm.User)   { return Visibility.User; }
        return Visibility.Shared;
    }

    /* ---------------------------------------------------------------------------------------
     * Statement-level checks
     * ------------------------------------------------------------------------------------ */

    /*
     * WarnIfEmpty - An empty control-statement body is almost always an editing accident
     */
    void func WarnIfEmpty(IrBlock blk, String what, ResolveCtx ctx, TextSpan span) {
        if (blk.stmts.Length() == 0) {
            self.diag.Warn(Codes.EmptyBlock(), ctx.file, span, "empty '" + what + "' body");
        }
    }

    /*
     * CheckCondition - A condition must be bool. There is no truthiness, so an integer here is an
     * error rather than a silent zero test.
     */
    void func CheckCondition(IrExpr c, ResolveCtx ctx, bool allowConst) {
        let IrType ty = Exprs2.TypeOf(c);
        match (ty) { case IrResultType(r) { return; } default { } }
        if (Types.IsError(ty)) { return; }

        let bool isBool = false;
        match (ty) { case IrPrimType(p) { isBool = p.cName == "bool"; } default { } }
        if (!isBool) {
            self.diag.Error(Codes.ConditionNotBool(), ctx.file, Exprs2.SpanOf(c),
                "condition must be 'bool', got '" + self.Describe(ty) + "'");
            return;
        }
        self.WarnConstCondition(c, ctx, allowConst);
    }

    /*
     * WarnConstCondition - Warns when a condition is decided before it is evaluated: a literal, or
     * a comparison of a value against itself. 'while (true)' is exempt, which is what allowConst
     * carries.
     */
    void func WarnConstCondition(IrExpr c, ResolveCtx ctx, bool allowConst) {
        match (c) {
            case IrLitBool(lb) {
                if (!allowConst) {
                    let List[String] hints = new List[String]();
                    hints.Add(lb.value ? "the branch always runs" : "the branch is never taken");
                    self.diag.Warn(Codes.ConstantCondition(), ctx.file, Exprs2.SpanOf(c),
                        "this condition is always " + (lb.value ? "true" : "false"), hints);
                }
                return;
            }
            case IrBinOp(b) {
                if (self.IsComparison(b.op) && self.SameStorage(b.left, b.right)) {
                    self.WarnSelfComparison(c, ctx);
                }
                return;
            }
            default { }
        }
        if (self.IsSelfUnionComparison(c)) { self.WarnSelfComparison(c, ctx); }
    }

    /*
     * WarnSelfComparison - The shared body of the two self-comparison warnings
     */
    void func WarnSelfComparison(IrExpr c, ResolveCtx ctx) {
        let List[String] hints = new List[String]();
        hints.Add("did you mean to compare against a different value?");
        self.diag.Warn(Codes.SelfComparison(), ctx.file, Exprs2.SpanOf(c),
            "this compares a value against itself, so the result is constant", hints);
    }

    /*
     * IsComparison - True for the six relational and equality operators
     */
    bool func IsComparison(BinOp op) {
        return op == BinOp.Eq || op == BinOp.Ne || op == BinOp.Lt ||
               op == BinOp.Le || op == BinOp.Gt || op == BinOp.Ge;
    }

    /*
     * IsSelfUnionComparison - True for a union equality, or its negation, over two operands naming
     * the same storage. Matched by shape, since a union's equality is a generated function whose
     * name is mangled.
     */
    bool func IsSelfUnionComparison(IrExpr c) {
        let IrExpr e = c;
        match (e) {
            case IrUnaryOp(neg) { if (neg.op == UnOp.Not) { e = neg.operand; } }
            default { }
        }
        match (e) {
            case IrStaticCall(call) {
                return self.IsUnionEqCall(call) && call.args.Length() == 2 &&
                       self.SameStorage(call.args.Get(0), call.args.Get(1));
            }
            default { return false; }
        }
    }

    /*
     * IsUnionEqCall - True when a static call is a union's generated structural equality: two
     * arguments of one union type, dispatched to exactly that union's '__eq'
     */
    bool func IsUnionEqCall(IrStaticCall call) {
        if (call.args.Length() != 2) { return false; }
        match (Exprs2.TypeOf(call.args.Get(0))) {
            case IrUnionType(a) {
                match (Exprs2.TypeOf(call.args.Get(1))) {
                    case IrUnionType(b) {
                        return a.name == b.name && call.cName == self.mangler.UnionEq(a.name);
                    }
                    default { return false; }
                }
            }
            default { return false; }
        }
    }

    /*
     * SameStorage - True when two expressions name the same storage, so comparing them compares a
     * value with itself. Deliberately syntactic and shallow: only shapes with no side effect and
     * no indirection through a value this pass cannot see.
     */
    bool func SameStorage(IrExpr a, IrExpr b) {
        match (a) {
            case IrVar(x) {
                match (b) { case IrVar(y) { return x.name == y.name; } default { return false; } }
            }
            case IrSelfExpr(x) {
                match (b) {
                    case IrSelfExpr(y) { return x.className == y.className; }
                    default { return false; }
                }
            }
            case IrFieldLoad(x) {
                match (b) {
                    case IrFieldLoad(y) {
                        return x.field == y.field && self.SameStorage(x.obj, y.obj);
                    }
                    default { return false; }
                }
            }
            case IrDeref(x) {
                match (b) {
                    case IrDeref(y) { return self.SameStorage(x.ptr, y.ptr); }
                    default { return false; }
                }
            }
            case IrUnionField(x) {
                match (b) {
                    case IrUnionField(y) {
                        return x.field == y.field && x.variantIndex == y.variantIndex &&
                               self.SameStorage(x.target, y.target);
                    }
                    default { return false; }
                }
            }
            case IrIndex(x) {
                // Only a LITERAL index is safe to compare: 'a[i()] == a[i()]' need not name one slot
                match (b) {
                    case IrIndex(y) {
                        if (!self.SameStorage(x.obj, y.obj)) { return false; }
                        match (x.idx) {
                            case IrLitInt(xi) {
                                match (y.idx) {
                                    case IrLitInt(yi) { return xi.value == yi.value; }
                                    default { return false; }
                                }
                            }
                            default { return false; }
                        }
                    }
                    default { return false; }
                }
            }
            default { return false; }
        }
    }

    /*
     * CheckLValue - An assignment target must name storage
     */
    void func CheckLValue(IrExpr target, ResolveCtx ctx) {
        match (target) {
            case IrVar(x)       { return; }
            case IrGlobal(x)    { return; }
            case IrFieldLoad(x) { return; }
            case IrIndex(x)     { return; }
            case IrDeref(x)     { return; }
            default { }
        }
        self.diag.Error(Codes.NotAnLvalue(), ctx.file, Exprs2.SpanOf(target),
            "assignment target must be a variable, field, or element");
    }

    /*
     * CheckCompound - Both operands of a compound assignment. The bitwise forms want integers;
     * the arithmetic forms want numbers.
     */
    void func CheckCompound(AssignOp op, IrExpr target, IrExpr value, ResolveCtx ctx) {
        if (Types.IsError(Exprs2.TypeOf(target)) || Types.IsError(Exprs2.TypeOf(value))) { return; }
        let bool bitwise = Ops.IsBitwise(op);
        let bool okTarget = bitwise ? self.IsInteger(Exprs2.TypeOf(target))
                                    : self.IsArith(Exprs2.TypeOf(target));
        let bool okValue = bitwise ? self.IsInteger(Exprs2.TypeOf(value))
                                   : self.IsArith(Exprs2.TypeOf(value));
        if (!okTarget) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, Exprs2.SpanOf(target),
                "operator '" + Ops.AssignSym(op) + "' cannot be applied to '" +
                self.Describe(Exprs2.TypeOf(target)) + "'");
        } else if (!okValue) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, Exprs2.SpanOf(value),
                "operator '" + Ops.AssignSym(op) + "' requires a" +
                (bitwise ? "n integer" : " numeric") + " right-hand side, got '" +
                self.Describe(Exprs2.TypeOf(value)) + "'");
        }
    }

    /*
     * FindAsOperator - The destination class's 'as' operator whose parameter matches the source
     * type. 'as' is always a static factory on the type converted TO, so this is the only place a
     * match comes from, and conversions never chain.
     */
    Optional[Symbol] func FindAsOperator(String destCls, IrType from) {
        let List[Symbol] ops = self.sym.OperatorOverloads(destCls, "as");
        let int i = 0;
        while (i < ops.Length()) {
            let Symbol op = ops.Get(i);
            match (op.sig) {
                case Some(g) {
                    if (g.params.Length() == 1 &&
                        Types.Same(self.ResolveTypeSpec(g.params.Get(0).type), from) &&
                        Types.Same(self.ResolveType(g.returnType), self.t.ClassRef(destCls))) {
                        return Optional.Some(op);
                    }
                }
                case None { }
            }
            i = i + 1;
        }
        return Optional[Symbol].None();
    }

    /*
     * CheckCast - Validates an explicit cast: numeric, enum-to-integer, or pointer inside unsafe.
     * A class can be converted INTO by an 'as' operator, but never out to a primitive.
     */
    void func CheckCast(IrExpr value, IrType to, ResolveCtx ctx) {
        let IrType from = Exprs2.TypeOf(value);

        if (Types.Same(from, to)) {
            // Casting to the type a value already has converts nothing. It is usually left over
            // from an earlier signature, and it hides a later real type change. A literal is
            // exempt: pinning a bit pattern's width where it is written is deliberate.
            if (!Types.IsVoid(from) && !self.IsLiteral(value)) {
                let List[String] hints = new List[String]();
                hints.Add("remove the cast");
                self.diag.Warn(Codes.RedundantCast(), ctx.file, Exprs2.SpanOf(value),
                    "this cast is redundant: the value is already '" + self.Describe(to) + "'", hints);
            }
            return;
        }

        match (value) {
            case IrLitNull(n) {
                match (to) {
                    case IrClassRef(c) { return; }
                    case IrPtrType(p)  { return; }
                    default { }
                }
            }
            default { }
        }

        if (Types.IsError(from) || Types.IsError(to)) { return; }
        if (Types.IsVoid(from) || Types.IsVoid(to)) { self.RejectCast(value, from, to, ctx); return; }

        if (self.IsNum(from) && self.IsNum(to)) { return; }
        if (self.IsEnumIntCast(from, to)) { return; }

        if (self.IsPointerCast(from, to)) {
            if (!ctx.inUnsafe) {
                self.diag.Error(Codes.UnsafeRequired(), ctx.file, Exprs2.SpanOf(value),
                    "pointer cast requires an 'unsafe' block");
            }
            return;
        }
        self.RejectCast(value, from, to, ctx);
    }

    /*
     * IsEnumIntCast - True for enum-to-integer or integer-to-enum, the two directions that need no
     * conversion beyond a reinterpretation
     */
    bool func IsEnumIntCast(IrType from, IrType to) {
        match (from) { case IrEnumType(e) { if (self.IsInteger(to)) { return true; } } default { } }
        match (to)   { case IrEnumType(e) { if (self.IsInteger(from)) { return true; } } default { } }
        return false;
    }

    /*
     * IsPointerCast - True when either side is a pointer and both sides are a pointer or a
     * primitive, which is the shape that needs unsafe
     */
    bool func IsPointerCast(IrType from, IrType to) {
        let bool eitherPtr = false;
        match (from) { case IrPtrType(p) { eitherPtr = true; } default { } }
        match (to)   { case IrPtrType(p) { eitherPtr = true; } default { } }
        return eitherPtr && self.IsPtrOrPrim(from) && self.IsPtrOrPrim(to);
    }

    /*
     * IsPtrOrPrim - True for a pointer or a primitive
     */
    bool func IsPtrOrPrim(IrType ty) {
        match (ty) {
            case IrPtrType(p)  { return true; }
            case IrPrimType(p) { return true; }
            default { return false; }
        }
    }

    /*
     * RejectCast - The invalid-cast diagnostic, with the hint that names the fix when someone
     * tried to cast a class out to a primitive
     */
    void func RejectCast(IrExpr value, IrType from, IrType to, ResolveCtx ctx) {
        let List[String] hints = new List[String]();
        let bool classOut = false;
        match (from) {
            case IrClassRef(c) {
                match (to) {
                    case IrPrimType(p) { classOut = true; }
                    case IrEnumType(e) { classOut = true; }
                    default { }
                }
            }
            default { }
        }
        if (classOut) {
            hints.Add("'as' only converts INTO a class, never out of one to a primitive - add a " +
                      "named conversion method on '" + self.Describe(from) + "' instead, e.g. '" +
                      self.Describe(to) + " func ToSomething()'");
        }
        self.AddInstantiationHint(hints, self.InstanceOrClass(ctx));
        self.diag.Error(Codes.InvalidCast(), ctx.file, Exprs2.SpanOf(value),
            "cannot cast '" + self.Describe(from) + "' to '" + self.Describe(to) + "'", hints);
    }

    /*
     * WarnIfLooksInterpolated - Warns when a plain string contains '{name}' and 'name' is a
     * variable actually in scope: the signature of a '$' dropped from an interpolated string,
     * which otherwise fails silently by printing the braces verbatim.
     */
    void func WarnIfLooksInterpolated(StrLitExpr sl, ResolveCtx ctx) {
        let String raw = sl.value;
        let int i = 0;
        while (i < raw.Length()) {
            if (raw.CharAt(i) != '{') { i = i + 1; continue; }
            let int close = raw.IndexOf("}", i + 1);
            if (close < 0) { return; }
            let String inner = raw.Substring(i + 1, close - i - 1);
            i = close;
            if (inner.Length() == 0) { continue; }
            if (!(Char.IsLetter(inner.CharAt(0)) || inner.CharAt(0) == '_')) { continue; }

            let bool ident = true;
            let int j = 1;
            while (j < inner.Length() && ident) {
                ident = Char.IsLetterOrDigit(inner.CharAt(j)) || inner.CharAt(j) == '_';
                j = j + 1;
            }
            if (!ident) { continue; }
            if (IsNone(ctx.locals.Lookup(inner))) { continue; }

            let List[String] hints = new List[String]();
            hints.Add("write $\"...\" to substitute the value, or escape the brace if the text is literal");
            self.diag.Warn(Codes.MissingInterpolation(), ctx.file, sl.span,
                "this string contains '{" + inner + "}' and '" + inner +
                "' is a variable in scope, but the string is not interpolated", hints);
            return;
        }
    }

    /* ---------------------------------------------------------------------------------------
     * Control-flow analysis
     * ------------------------------------------------------------------------------------ */

    /*
     * ReturnsList - True when at least one statement in a list definitely returns
     */
    bool func ReturnsList(List[IrStmt] stmts) {
        let int i = 0;
        while (i < stmts.Length()) {
            if (self.DefinitelyReturns(stmts.Get(i))) { return true; }
            i = i + 1;
        }
        return false;
    }

    /*
     * DefinitelyReturns - True when a statement returns or throws on EVERY path.
     *
     * This is what decides G027. The interesting arms are the loops: 'while (true)' with no break
     * never falls out, so a function ending in one needs no return after it, and the same holds
     * for a 'for' with no condition.
     */
    bool func DefinitelyReturns(IrStmt s) {
        match (s) {
            case IrReturn(x)      { return true; }
            case IrThrow(x)       { return true; }
            case IrPanic(x)       { return true; }
            case IrBlock(b)       { return self.ReturnsList(b.stmts); }
            case IrUnsafeBlock(u) { return self.ReturnsList(u.body.stmts); }
            case IrIf(i) {
                match (i.otherwise) {
                    case None { return false; }
                    case Some(e) {
                        return self.DefinitelyReturns(IrStmt.IrBlock(i.then)) &&
                               self.DefinitelyReturns(IrStmt.IrBlock(e));
                    }
                }
            }
            case IrWhile(w) {
                return self.IsTrueLit(w.cond) && !self.HasLoopBreak(IrStmt.IrBlock(w.body));
            }
            case IrFor(f) {
                let bool always = false;
                match (f.cond) {
                    case None { always = true; }
                    case Some(c) { always = self.IsTrueLit(c); }
                }
                return always && !self.HasLoopBreak(IrStmt.IrBlock(f.body));
            }
            case IrTryCatch(t) {
                return self.DefinitelyReturns(IrStmt.IrBlock(t.tryBlock)) &&
                       self.DefinitelyReturns(IrStmt.IrBlock(t.catchBlock));
            }
            case IrSwitch(sw) {
                // Without a default the scrutinee may match nothing, so the statement can be
                // skipped entirely however exhaustive the cases look
                match (sw.otherwise) {
                    case None { return false; }
                    case Some(d) {
                        let int i = 0;
                        while (i < sw.cases.Length()) {
                            if (!self.DefinitelyReturns(IrStmt.IrBlock(sw.cases.Get(i).body))) {
                                return false;
                            }
                            i = i + 1;
                        }
                        return self.DefinitelyReturns(IrStmt.IrBlock(d));
                    }
                }
            }
            case IrMatch(ms) {
                // A match with no default is exhaustive by G039, so every variant is covered
                let int i = 0;
                while (i < ms.cases.Length()) {
                    if (!self.DefinitelyReturns(IrStmt.IrBlock(ms.cases.Get(i).body))) { return false; }
                    i = i + 1;
                }
                match (ms.otherwise) {
                    case None { return true; }
                    case Some(d) { return self.DefinitelyReturns(IrStmt.IrBlock(d)); }
                }
            }
            default { return false; }
        }
    }

    /*
     * IsTrueLit - True for the literal 'true', the condition that makes a loop unexitable
     */
    bool func IsTrueLit(IrExpr e) {
        match (e) { case IrLitBool(b) { return b.value; } default { return false; } }
    }

    /*
     * HasLoopBreak - True when a statement contains a 'break' that would exit the ENCLOSING loop.
     * Does not descend into a nested loop, whose breaks target that one instead. A catch handler
     * is part of the enclosing loop, so a break inside one does exit it.
     */
    bool func HasLoopBreak(IrStmt s) {
        match (s) {
            case IrBreak(x)       { return true; }
            case IrBlock(b) {
                let int i = 0;
                while (i < b.stmts.Length()) {
                    if (self.HasLoopBreak(b.stmts.Get(i))) { return true; }
                    i = i + 1;
                }
                return false;
            }
            case IrUnsafeBlock(u) { return self.HasLoopBreak(IrStmt.IrBlock(u.body)); }
            case IrDeclVar(d) {
                match (d.init) {
                    case Some(e) { return self.HasHandlerBreak(e); }
                    case None { return false; }
                }
            }
            case IrAssign(a)   { return self.HasHandlerBreak(a.value); }
            case IrExprStmt(e) { return self.HasHandlerBreak(e.expr); }
            case IrIf(i) {
                if (self.HasLoopBreak(IrStmt.IrBlock(i.then))) { return true; }
                match (i.otherwise) {
                    case Some(e) { return self.HasLoopBreak(IrStmt.IrBlock(e)); }
                    case None { return false; }
                }
            }
            case IrTryCatch(t) {
                return self.HasLoopBreak(IrStmt.IrBlock(t.tryBlock)) ||
                       self.HasLoopBreak(IrStmt.IrBlock(t.catchBlock));
            }
            case IrSwitch(sw) {
                let int i = 0;
                while (i < sw.cases.Length()) {
                    if (self.HasLoopBreak(IrStmt.IrBlock(sw.cases.Get(i).body))) { return true; }
                    i = i + 1;
                }
                match (sw.otherwise) {
                    case Some(d) { return self.HasLoopBreak(IrStmt.IrBlock(d)); }
                    case None { return false; }
                }
            }
            case IrMatch(m) {
                let int i = 0;
                while (i < m.cases.Length()) {
                    if (self.HasLoopBreak(IrStmt.IrBlock(m.cases.Get(i).body))) { return true; }
                    i = i + 1;
                }
                match (m.otherwise) {
                    case Some(d) { return self.HasLoopBreak(IrStmt.IrBlock(d)); }
                    case None { return false; }
                }
            }
            default { return false; }
        }
    }

    /*
     * HasHandlerBreak - True when a root-position expression carries a catch handler containing a
     * break. Handlers only ever sit at the root of a declaration, an assignment, or an expression
     * statement, which is why this is not a general expression walk.
     */
    bool func HasHandlerBreak(IrExpr e) {
        match (e) {
            case IrCatchCall(cc) { return self.HasLoopBreak(IrStmt.IrBlock(cc.handler)); }
            default { return false; }
        }
    }

    /*
     * CheckThrowsReturn - Rejects a 'throws' return type with no valid Result_T spelling. A
     * pointer, fixed array or function pointer would produce an illegal C typedef name, so it is
     * a compile error rather than a link-time surprise.
     */
    void func CheckThrowsReturn(IrType ret, bool isThrows, String display, ResolveCtx ctx, TextSpan span) {
        if (!isThrows) { return; }
        let bool bad = false;
        match (ret) {
            case IrPtrType(p)     { bad = true; }
            case IrArrayType(a)   { bad = true; }
            case IrFuncPtrType(f) { bad = true; }
            default { }
        }
        if (bad) {
            self.diag.Error(Codes.BadThrowsReturnType(), ctx.file, span,
                "'" + display + "': a 'throws' function cannot return '" + self.Describe(ret) +
                "'; supported 'throws' return types are void, primitives, enums, unions, String, and classes");
        }
    }

    /*
     * CheckMissingReturn - Reports a non-void function that does not return on every path
     */
    void func CheckMissingReturn(Optional[IrBlock] body, IrType ret, bool isThrows, TextSpan span,
                                 String display, ResolveCtx ctx) {
        match (body) {
            case None { return; }
            case Some(b) {
                if (isThrows) { return; }
                if (Types.IsVoid(ret)) { return; }
                match (ret) { case IrResultType(r) { return; } default { } }
                if (self.ReturnsList(b.stmts)) { return; }

                // A native body is invisible to this analysis, so say so rather than insisting on
                // a return the author already wrote in C
                let List[String] hints = new List[String]();
                if (self.HasNativeStmt(b.stmts)) {
                    hints.Add("a 'native { }' block is raw C, so a 'return' inside one is not " +
                              "visible to this check");
                    hints.Add("either make the whole body native - put 'native' after the signature " +
                              "instead of inside the braces - or have the native block store its " +
                              "result in a local and return that local");
                }
                self.diag.Error(Codes.MissingReturn(), ctx.file, span,
                    "'" + display + "' must return '" + self.Describe(ret) + "' on every path", hints);
            }
        }
    }

    /*
     * HasNativeStmt - True when a native block appears anywhere in a statement list. Walked with
     * IrWalk so a newly added statement kind cannot quietly hide one.
     */
    bool func HasNativeStmt(List[IrStmt] stmts) {
        let FoundFlag f = new FoundFlag();
        let IrWalk[FoundFlag] w = new IrWalk[FoundFlag](f, FindNativeStmt, null);
        let int i = 0;
        while (i < stmts.Length()) { w.WalkStmt(stmts.Get(i)); i = i + 1; }
        return f.found;
    }

    /*
     * CheckBodyQuality - The warnings that are about a body as a whole rather than any one
     * statement: a redundant trailing return, an unread local, an unread parameter, and a read
     * before assignment.
     *
     * All of them are skipped when the body contains raw C, which the walk cannot see into: a
     * local the native block reads would otherwise look unused.
     */
    void func CheckBodyQuality(IrBlock body, IrType ret, TextSpan span, ResolveCtx ctx,
                               List[Param] pars, TextSpan parSpan) {
        if (Types.IsVoid(ret) && body.stmts.Length() > 0) {
            match (body.stmts.Get(body.stmts.Length() - 1)) {
                case IrReturn(r) {
                    if (IsNone(r.value)) {
                        self.diag.Warn(Codes.RedundantReturn(), ctx.file, span,
                            "redundant trailing 'return;'");
                    }
                }
                default { }
            }
        }

        let BodyQuality q = new BodyQuality();
        let IrWalk[BodyQuality] w = new IrWalk[BodyQuality](q, BodyQualityStmt, BodyQualityExpr);
        w.WalkStmt(IrStmt.IrBlock(body));

        if (q.native) { return; }
        self.CheckDefiniteAssignment(body, ctx);

        let StringSet seen = new StringSet();
        let int i = 0;
        while (i < q.declNames.Length()) {
            let String name = q.declNames.Get(i);
            if (seen.AddNew(name) && !DeliberatelyUnused(name) && !q.used.Has(name)) {
                self.diag.Warn(Codes.UnusedVariable(), ctx.file, q.declSpans.Get(i),
                    "unused variable '" + name + "'");
            }
            i = i + 1;
        }

        let int j = 0;
        while (j < pars.Length()) {
            let Param p = pars.Get(j);
            j = j + 1;
            if (DeliberatelyUnused(p.name)) { continue; }
            // Only warn when the name is never mentioned in the body at all - a parameter that
            // was reassigned before being read is still used
            if (q.used.Has(p.name) || seen.Has(p.name)) { continue; }
            let List[String] hints = new List[String]();
            hints.Add("remove it, or prefix the name with '_' if it is deliberately ignored");
            self.diag.Warn(Codes.UnusedParameter(), ctx.file,
                TS.IsNone(p.span) ? parSpan : p.span,
                "unused parameter '" + p.name + "'", hints);
        }
    }

    /* ---------------------------------------------------------------------------------------
     * Access checks
     * ------------------------------------------------------------------------------------ */

    /*
     * CheckMemberAccess - Reports a private member reached from outside its declaring class
     */
    void func CheckMemberAccess(String owner, String member, ResolveCtx ctx, TextSpan span) {
        if (self.sym.IsPrivateMember(owner, member) && ctx.curClass != owner) {
            let String shown = self.mangler.DisplayName(owner);
            self.diag.Error(Codes.PrivateMember(), ctx.file, span,
                "'" + shown + "." + member + "' is private and cannot be accessed from outside '" +
                shown + "'");
        }
    }

    /*
     * CheckOperatorAccess - The same, for an operator overload
     */
    void func CheckOperatorAccess(String owner, String op, ResolveCtx ctx, TextSpan span) {
        if (self.sym.IsPrivateMember(owner, "operator " + op) && ctx.curClass != owner) {
            let String shown = self.mangler.DisplayName(owner);
            self.diag.Error(Codes.PrivateMember(), ctx.file, span,
                "operator '" + op + "' on '" + shown +
                "' is private and cannot be used from outside '" + shown + "'");
        }
    }

    /* ---------------------------------------------------------------------------------------
     * throws: where a failing call may appear, and what a handler must do
     * ------------------------------------------------------------------------------------ */

    /*
     * CheckThrowsHandled - A call that can fail must be somewhere the failure goes: inside a try,
     * inside another throws function, or under its own inline catch
     */
    void func CheckThrowsHandled(ResolveCtx ctx, TextSpan span) {
        if (!ctx.inTry && !ctx.inThrowsFunc && !ctx.catchWrapped) {
            let List[String] hints = new List[String]();
            hints.Add("or handle it in place: 'let T x = f() catch { assign <fallback>; };'");
            self.diag.Error(Codes.ThrowsOutsideTry(), ctx.file, span,
                "throwing call must be inside a 'try' block or a 'throws' function", hints);
        }
    }

    /*
     * AssignsOrExitsList - True when at least one statement in a list ends the handler
     */
    bool func AssignsOrExitsList(List[IrStmt] stmts) {
        let int i = 0;
        while (i < stmts.Length()) {
            if (self.AssignsOrExits(stmts.Get(i))) { return true; }
            i = i + 1;
        }
        return false;
    }

    /*
     * AssignsOrExits - True when a statement definitely ends its enclosing catch handler, either
     * by supplying a value with 'assign' or by transferring control out of it entirely
     */
    bool func AssignsOrExits(IrStmt s) {
        match (s) {
            case IrAssignValue(x) { return true; }
            case IrBreak(x)       { return true; }
            case IrContinue(x)    { return true; }
            case IrBlock(b)       { return self.AssignsOrExitsList(b.stmts); }
            case IrUnsafeBlock(u) { return self.AssignsOrExitsList(u.body.stmts); }
            case IrIf(i) {
                match (i.otherwise) {
                    case None { return false; }
                    case Some(e) {
                        return self.AssignsOrExits(IrStmt.IrBlock(i.then)) &&
                               self.AssignsOrExits(IrStmt.IrBlock(e));
                    }
                }
            }
            case IrTryCatch(t) {
                return self.AssignsOrExits(IrStmt.IrBlock(t.tryBlock)) &&
                       self.AssignsOrExits(IrStmt.IrBlock(t.catchBlock));
            }
            case IrSwitch(sw) {
                match (sw.otherwise) {
                    case None { return false; }
                    case Some(d) {
                        let int i = 0;
                        while (i < sw.cases.Length()) {
                            if (!self.AssignsOrExits(IrStmt.IrBlock(sw.cases.Get(i).body))) { return false; }
                            i = i + 1;
                        }
                        return self.AssignsOrExits(IrStmt.IrBlock(d));
                    }
                }
            }
            case IrMatch(ms) {
                let int i = 0;
                while (i < ms.cases.Length()) {
                    if (!self.AssignsOrExits(IrStmt.IrBlock(ms.cases.Get(i).body))) { return false; }
                    i = i + 1;
                }
                match (ms.otherwise) {
                    case None { return true; }
                    case Some(d) { return self.AssignsOrExits(IrStmt.IrBlock(d)); }
                }
            }
            default { return self.DefinitelyReturns(s); }
        }
    }

    /*
     * ContainsAssignValue - True when an 'assign' appears anywhere inside a statement. Used to
     * reject one in a handler that has no declaration to assign to.
     */
    bool func ContainsAssignValue(IrStmt s) {
        let ContainsFlag c = new ContainsFlag();
        let IrWalk[ContainsFlag] w = new IrWalk[ContainsFlag](c, FindAssignValue, null);
        w.WalkStmt(s);
        return c.found;
    }

    /*
     * CheckThrowsPlacement - The whole-body backstop for throws placement.
     *
     * ForbidNestedThrows is opt-IN: it is called from the positions that know they may hold one.
     * This is opt-OUT, reporting a throwing call anywhere outside the positions the language
     * permits - so a slot nobody thought of cannot let one reach the emitter and die there.
     */
    void func CheckThrowsPlacement(IrBlock body, ResolveCtx ctx) {
        let ThrowsPlacement st = new ThrowsPlacement(self, ctx.file);
        st.Check(body);
    }

    /*
     * CatchNotAtRoot - Spelled once because two sites report it
     */
    public String func CatchNotAtRoot() {
        return "a 'catch' handler must cover a whole declaration or assignment, not a call nested " +
               "inside a larger expression";
    }

    /*
     * CatchNotAtRootHints - The hints that go with it
     */
    public List[String] func CatchNotAtRootHints() {
        let List[String] h = new List[String]();
        h.Add("a handler supplies the value for one target, so it can only sit at one: " +
              "'let T x = f() catch { ... };' or 'x = f() catch { ... };'");
        h.Add("bind the call to its own local first, then use that local here");
        return h;
    }

    /*
     * ForbidNestedThrows - Reports a throwing call nested inside a larger expression. allowRoot
     * permits the call itself at the top of the tree, which is the one position that has storage
     * for its result.
     */
    void func ForbidNestedThrows(IrExpr e, ResolveCtx ctx, bool allowRoot) {
        if (!allowRoot) {
            match (e) {
                case IrThrowsCall(tc) {
                    self.diag.Error(Codes.ThrowsOutsideTry(), ctx.file, Exprs2.SpanOf(e),
                        "throwing call cannot appear inside a larger expression");
                }
                case IrThrowsInstanceCall(ti) {
                    self.diag.Error(Codes.ThrowsOutsideTry(), ctx.file, Exprs2.SpanOf(e),
                        "throwing call cannot appear inside a larger expression");
                }
                default { }
            }
        }

        // A catch handler is the one node whose treatment depends on allowRoot, so it is handled
        // here rather than by the generic child walk below
        match (e) {
            case IrCatchCall(cc) {
                if (!allowRoot) {
                    self.ReportPlacementOnce(Exprs2.SpanOf(e), self.CatchNotAtRoot(),
                                             self.CatchNotAtRootHints(), ctx);
                } else {
                    self.ForbidNestedThrows(cc.call, ctx, true);
                }
                return;
            }
            default { }
        }

        // Everything below the root is nested by definition
        let List[IrExpr] kids = ChildExprs(e);
        let int i = 0;
        while (i < kids.Length()) { self.ForbidNestedThrows(kids.Get(i), ctx, false); i = i + 1; }
    }

    /*
     * ForbidNestedThrowsOpt - ForbidNestedThrows over a value that may be absent
     */
    void func ForbidNestedThrowsOpt(Optional[IrExpr] e, ResolveCtx ctx, bool allowRoot) {
        match (e) { case Some(x) { self.ForbidNestedThrows(x, ctx, allowRoot); } case None { } }
    }

    /*
     * CheckRootThrowsValue - Checks a value in a position that MAY hold a throwing call: a
     * declaration initializer, or an assignment right-hand side. Both name storage the result
     * lands in, which is what a handler's 'assign' needs and what makes propagation well defined.
     */
    IrExpr func CheckRootThrowsValue(IrExpr value, IrType targetType, String what,
                                     ResolveCtx ctx, TextSpan span) {
        self.ForbidNestedThrows(value, ctx, true);

        match (value) {
            case IrCatchCall(cc) {
                if (!self.AssignsOrExits(IrStmt.IrBlock(cc.handler))) {
                    let List[String] hints = new List[String]();
                    hints.Add("end every path with 'assign <value>;'");
                    hints.Add("or leave the handler through 'return', 'throw', 'break', or 'continue'");
                    self.diag.Error(Codes.CatchHandlerNoAssign(), ctx.file, cc.handler.span,
                        "this 'catch' handler can finish without supplying a value for " + what, hints);
                }
            }
            default { }
        }

        match (Exprs2.TypeOf(value)) {
            case IrResultType(rt) {
                // The call propagates rather than being handled here, so what has to be
                // assignable is the value it would produce on success
                let IrExpr probe = IrExpr.IrVar(new IrVar("_v", rt.inner, false));
                if (!self.Assignable(probe, targetType)) {
                    self.diag.Error(Codes.TypeMismatch(), ctx.file, span,
                        "this throwing call produces '" + self.Describe(rt.inner) +
                        "', which cannot be assigned to " + what + " of type '" +
                        self.Describe(targetType) + "'");
                }
                return value;
            }
            default { }
        }

        let IrExpr coerced = self.Coerce(value, targetType, ctx);
        self.CheckAssign(coerced, targetType, what, ctx, Codes.TypeMismatch());
        return coerced;
    }

    /*
     * ReportPlacementOnce - Reports a misplaced throwing call unless something already complained
     * about the same span, so a form-specific message and the general one never both fire
     */
    void func ReportPlacementOnce(TextSpan span, String message, List[String] hints, ResolveCtx ctx) {
        if (self.AlreadyReportedThrowsAt(span)) { return; }
        self.diag.Error(Codes.ThrowsOutsideTry(), ctx.file, span, message, hints);
    }

    /*
     * AlreadyReportedThrowsAt - True when a throws-placement diagnostic already sits at this span
     */
    public bool func AlreadyReportedThrowsAt(TextSpan span) {
        let List[Diagnostic] all = self.diag.All();
        let int i = 0;
        while (i < all.Length()) {
            let Diagnostic d = all.Get(i);
            if (Diags.Code(d) == Codes.ThrowsOutsideTry() &&
                SameSpan(Locs.Span(Diags.Loc(d)), span)) {
                return true;
            }
            i = i + 1;
        }
        return false;
    }

    /*
     * ForbidThrowsInAssignForm - Rejects a throwing call in an assignment form with nowhere to put
     * the result: a compound assignment, whose target is read as well as written, and an index
     * setter, which is itself a call
     */
    void func ForbidThrowsInAssignForm(IrExpr value, String form, ResolveCtx ctx) {
        let bool throwing = false;
        match (value) {
            case IrCatchCall(x)          { throwing = true; }
            case IrThrowsCall(x)         { throwing = true; }
            case IrThrowsInstanceCall(x) { throwing = true; }
            default { }
        }
        if (!throwing) { return; }
        // Reported at the value's own span, which is where the per-body backstop would report it
        // too - that is what stops the two from both firing
        let List[String] hints = new List[String]();
        hints.Add("bind it first: 'let T tmp = f() catch { assign <fallback>; };', then use 'tmp' here");
        self.diag.Error(Codes.ThrowsOutsideTry(), ctx.file, Exprs2.SpanOf(value),
            "a throwing call cannot be the value of " + form, hints);
    }

    /*
     * IsPure - True when an expression is side-effect free, so it may be re-emitted or dropped
     */
    bool func IsPure(IrExpr e) {
        match (e) {
            case IrLitInt(x)    { return true; }
            case IrLitChar(x)   { return true; }
            case IrLitFloat(x)  { return true; }
            case IrLitBool(x)   { return true; }
            case IrLitString(x) { return true; }
            case IrLitNull(x)   { return true; }
            case IrEnumConst(x) { return true; }
            case IrVar(x)       { return true; }
            case IrSelfExpr(x)  { return true; }
            case IrFuncRef(x)   { return true; }
            case IrSizeof(x)    { return true; }
            case IrDefault(x)   { return true; }
            case IrFieldLoad(fl) { return self.IsPure(fl.obj); }
            case IrIndex(ix)     { return self.IsPure(ix.obj) && self.IsPure(ix.idx); }
            case IrUnionField(uf) { return self.IsPure(uf.target); }
            case IrUnaryOp(u)    { return self.IsPure(u.operand); }
            case IrBinOp(b)      { return self.IsPure(b.left) && self.IsPure(b.right); }
            case IrCast(c)       { return self.IsPure(c.value); }
            case IrAddrOf(a)     { return self.IsPure(a.target); }
            case IrDeref(d)      { return self.IsPure(d.ptr); }
            case IrStaticCall(sc) {
                // Calls are impure in general, but a union's generated equality only reads its two
                // by-value arguments - so 'u == v;' written where 'u = v;' was meant is reported
                // as a statement with no effect, exactly as 'i == j;' is
                if (!self.IsUnionEqCall(sc)) { return false; }
                let int i = 0;
                while (i < sc.args.Length()) {
                    if (!self.IsPure(sc.args.Get(i))) { return false; }
                    i = i + 1;
                }
                return true;
            }
            default { return false; }
        }
    }

    /*
     * WarnIfNoEffect - Warns when an expression is computed as a statement and its value dropped.
     * IsPure is exactly the right test on the lowered form: every shape it accepts is
     * side-effect free, so evaluating it for its own sake is dead work.
     */
    void func WarnIfNoEffect(Expr src, IrExpr e, ResolveCtx ctx) {
        match (src) {
            case CallExpr(x) { return; }
            case NewExpr(x)  { return; }
            default { }
        }
        if (!self.IsPure(e)) { return; }

        // The classic 'a == b;' where 'a = b;' was meant gets a hint that names the fix
        let bool isComparison = false;
        match (e) {
            case IrBinOp(b) { isComparison = b.op == BinOp.Eq || b.op == BinOp.Ne; }
            case IrStaticCall(sc) { isComparison = self.IsUnionEqCall(sc); }
            case IrUnaryOp(u) {
                if (u.op == UnOp.Not) {
                    match (u.operand) {
                        case IrStaticCall(sc2) { isComparison = self.IsUnionEqCall(sc2); }
                        default { }
                    }
                }
            }
            default { }
        }

        let List[String] hints = new List[String]();
        hints.Add(isComparison ? "'==' compares two values; use '=' to assign" : "remove it, or use its result");
        self.diag.Warn(Codes.NoEffect(), ctx.file, Exprs2.SpanOf(e),
            "this expression is computed as a statement but its value is never used", hints);
    }

    /*
     * RejectDiscardedRetain - Rejects a call to the retain intrinsic whose result is thrown away.
     * As a statement it does nothing: the +1 lands on a temporary this scope releases again.
     */
    void func RejectDiscardedRetain(Expr src, ResolveCtx ctx) {
        match (src) {
            case CallExpr(ce) {
                match (ce.callee) {
                    case IdentExpr(id) {
                        let Optional[Symbol] fsym = self.LookupFreeFuncVisible(id.name);
                        if (!self.FuncInScope(fsym)) { return; }
                        match (fsym) {
                            case None { return; }
                            case Some(f) {
                                match (self.sym.IntrinsicOrNull(Roles.Retain())) {
                                    case None { return; }
                                    case Some(rn) { if (f.cName != rn) { return; } }
                                }
                            }
                        }
                        let List[String] hints = new List[String]();
                        hints.Add("as a statement it does nothing: the count is added to a temporary " +
                                  "that this scope releases again");
                        hints.Add("store it where something owns it: 'self.data[i] = " + id.name + "(v);'");
                        hints.Add("or hand it on: 'unsafe { return " + id.name + "(self.data[i]); }'");
                        hints.Add("keeping an object alive in storage reference counting cannot see - " +
                                  "a raw slot in a native block - means counting it in the native body " +
                                  "that stores the pointer");
                        self.diag.Error(Codes.DiscardedRetain(), ctx.file, Exprs.Span(src),
                            "'" + id.name + "' returns the reference it counted, and this call discards it",
                            hints);
                    }
                    default { }
                }
            }
            default { }
        }
    }

    /*
     * CheckDefiniteAssignment - Reports a local read before anything can have been stored into it
     */
    void func CheckDefiniteAssignment(IrBlock body, ResolveCtx ctx) {
        let DefiniteAssignment pass = new DefiniteAssignment();
        pass.Run(body);
        let int i = 0;
        while (i < pass.foundNames.Length()) {
            let String name = pass.foundNames.Get(i);
            let List[String] hints = new List[String]();
            hints.Add("a 'let' with no initialiser leaves the variable holding whatever was already there");
            hints.Add("give it a value at the declaration - 'let T " + name + " = ...;' - or assign " +
                      "it on every path that reaches this read");
            self.diag.Error(Codes.UseBeforeAssignment(), ctx.file, pass.foundSpans.Get(i),
                "'" + name + "' is read before it is assigned", hints);
            i = i + 1;
        }
    }

    /* ---------------------------------------------------------------------------------------
     * IR utilities: hoisting, unification, coercion, stringification
     * ------------------------------------------------------------------------------------ */

    /*
     * HoistIfImpure - An expression unchanged when it is pure, or bound to a fresh temporary and
     * replaced by a reference to it. Used where lowering has to evaluate something twice.
     */
    IrExpr func HoistIfImpure(IrExpr e, String prefix, List[IrStmt] stmts) {
        if (self.IsPure(e)) { return e; }
        let String name = self.Tmp(prefix);
        let IrType ty = Exprs2.TypeOf(e);
        stmts.Add(IrStmt.IrDeclVar(new IrDeclVar(name, ty, Optional.Some(e))));
        return IrExpr.IrVar(new IrVar(name, ty, false));
    }

    /*
     * Seq - A statement list collapsed to one statement, avoiding a nested block when lowering
     * produced only a single statement
     */
    IrStmt func Seq(List[IrStmt] stmts, TextSpan span) {
        if (stmts.Length() == 1) { return stmts.Get(0); }
        let IrBlock b = new IrBlock(stmts);
        b.span = span;
        return IrStmt.IrBlock(b);
    }

    /*
     * UnifyTernary - The common type of two ternary arms, or None when they cannot be unified.
     * 'null : null' has nothing to unify to, which is why it is rejected rather than defaulted.
     */
    Optional[IrType] func UnifyTernary(IrExpr a, IrExpr b) {
        let bool aNull = false;
        let bool bNull = false;
        match (a) { case IrLitNull(x) { aNull = true; } default { } }
        match (b) { case IrLitNull(x) { bNull = true; } default { } }

        if (aNull && bNull) { return Optional[IrType].None(); }
        if (aNull) { return self.NullPartner(Exprs2.TypeOf(b)); }
        if (bNull) { return self.NullPartner(Exprs2.TypeOf(a)); }

        let IrType ta = Exprs2.TypeOf(a);
        let IrType tb = Exprs2.TypeOf(b);
        if (Types.Same(ta, tb)) { return Optional.Some(ta); }
        if (self.IsNum(ta) && self.IsNum(tb)) {
            return Optional.Some(self.NumRank(ta) >= self.NumRank(tb) ? ta : tb);
        }
        if (Types.IsString(ta) && Types.IsString(tb)) { return Optional.Some(self.t.Str()); }

        match (ta) {
            case IrPtrType(ap) {
                match (tb) {
                    case IrPtrType(bp) {
                        if (Types.Same(ap.inner, bp.inner)) { return Optional.Some(ta); }
                        if (Types.IsVoid(ap.inner)) { return Optional.Some(ta); }
                        if (Types.IsVoid(bp.inner)) { return Optional.Some(tb); }
                        return Optional[IrType].None();
                    }
                    default { return Optional[IrType].None(); }
                }
            }
            default { return Optional[IrType].None(); }
        }
    }

    /*
     * NullPartner - The type a 'null' arm takes from the other arm, when that arm can hold null
     */
    Optional[IrType] func NullPartner(IrType other) {
        match (other) {
            case IrClassRef(c) { return Optional.Some(other); }
            case IrPtrType(p)  { return Optional.Some(other); }
            default { return Optional[IrType].None(); }
        }
    }

    /*
     * CoerceTo - Adapts an expression to a unified type: retypes a null literal, widens a narrower
     * numeric with an explicit cast so the arithmetic happens in the type Gata says
     */
    IrExpr func CoerceTo(IrExpr e, IrType ty) {
        match (e) {
            case IrLitNull(n) {
                let IrLitNull ln = new IrLitNull(ty);
                ln.span = Exprs2.SpanOf(e);
                return IrExpr.IrLitNull(ln);
            }
            default { }
        }
        if (Types.Same(Exprs2.TypeOf(e), ty)) { return e; }
        if (self.IsNum(Exprs2.TypeOf(e)) && self.IsNum(ty)) {
            let IrCast c = new IrCast(ty, e);
            c.span = Exprs2.SpanOf(e);
            return IrExpr.IrCast(c);
        }
        return e;
    }

    /*
     * Coerce - Adapts a value to the type it is being stored in. Only fixed-array literals need
     * this: the literal's element type comes from its first element, which may be narrower than
     * the destination declares.
     */
    IrExpr func Coerce(IrExpr e, IrType expected, ResolveCtx ctx) {
        match (expected) {
            case IrArrayType(at) {
                match (e) {
                    case IrArrayLit(lit) {
                        if (lit.elems.Length() != at.size) { return e; }
                        let List[IrExpr] coerced = new List[IrExpr]();
                        let int i = 0;
                        while (i < lit.elems.Length()) {
                            coerced.Add(self.Coerce(lit.elems.Get(i), at.elem, ctx));
                            i = i + 1;
                        }
                        let IrArrayLit out = new IrArrayLit(self.Arr(at.elem, at.size), coerced);
                        out.span = Exprs2.SpanOf(e);
                        return IrExpr.IrArrayLit(out);
                    }
                    default { return e; }
                }
            }
            default { return e; }
        }
    }

    /*
     * InType - An expression evaluated in a given type. Binary arithmetic resolves at the
     * higher-ranked operand and converts BOTH sides into it first, so the arithmetic happens in
     * the domain Gata says rather than the one C's own promotions would pick.
     */
    IrExpr func InType(IrExpr e, IrType ty) {
        if (Types.Same(Exprs2.TypeOf(e), ty)) { return e; }
        let IrCast c = new IrCast(ty, e);
        c.span = Exprs2.SpanOf(e);
        return IrExpr.IrCast(c);
    }

    /*
     * Intrinsic - The C name bound to a role, or a diagnostic naming the role nothing bound. The
     * compiler never hardcodes a runtime symbol: it emits whatever carries the role.
     */
    String func Intrinsic(String role, ResolveCtx ctx, TextSpan span) {
        match (self.sym.IntrinsicOrNull(role)) {
            case Some(n) { return n; }
            case None {
                let List[String] hints = new List[String]();
                hints.Add("the binding lives in libgata; import the module that provides it, or " +
                          "update libgata if this compiler is newer than it");
                self.diag.Error(Codes.MissingIntrinsic(), ctx.file, span,
                    "nothing in the build binds @intrinsic(" + role + "), which this expression needs",
                    hints);
                return "appa_MISSING_" + role;
            }
        }
    }

    /*
     * StaticCallAt - A static call carrying a span, the shape stringification builds repeatedly
     */
    IrExpr func StaticCallAt(String cName, IrType ty, List[IrExpr] args, TextSpan span) {
        let IrStaticCall sc = new IrStaticCall(cName, ty, args);
        sc.span = span;
        return IrExpr.IrStaticCall(sc);
    }

    /*
     * OneArg - A single-element argument list
     */
    List[IrExpr] func OneArg(IrExpr e) {
        let List[IrExpr] a = new List[IrExpr]();
        a.Add(e);
        return a;
    }

    /*
     * EnsureString - An expression converted to String, by the order section 15.4 of the spec
     * gives: float, char, bool, unsigned, other numeric, then a class's own ToString.
     */
    IrExpr func EnsureString(IrExpr e, ResolveCtx ctx) {
        let IrType ty = Exprs2.TypeOf(e);
        let TextSpan span = Exprs2.SpanOf(e);
        if (Types.IsString(ty)) { return e; }

        if (Types.IsFloat(ty)) {
            return self.StaticCallAt(self.Intrinsic(Roles.StringifyFloat(), ctx, span),
                                     self.t.Str(), self.OneArg(e), span);
        }
        if (Types.IsChar(ty)) {
            return self.StaticCallAt(self.Intrinsic(Roles.StringifyChar(), ctx, span),
                                     self.t.Str(), self.OneArg(e), span);
        }

        // bool goes through String's own 'as' operator rather than an intrinsic, so the text it
        // produces is the library's to decide
        let bool isBool = false;
        match (ty) { case IrPrimType(p) { isBool = p.cName == "bool"; } default { } }
        if (isBool) {
            let String strCls = self.StringClass();
            match (self.FindAsOperator(strCls, ty)) {
                case Some(boolAs) {
                    return self.StaticCallAt(boolAs.cName, self.t.Str(), self.OneArg(e), span);
                }
                case None { }
            }
        }

        if (Types.IsUnsigned(ty)) {
            return self.StaticCallAt(self.Intrinsic(Roles.StringifyUint(), ctx, span),
                                     self.t.Str(), self.OneArg(e), span);
        }
        if (Types.IsNumeric(ty)) {
            let bool wide = false;
            match (ty) { case IrPrimType(p) { wide = PrimTypes.IntBits(p.cName) > 32; } default { } }
            let String role = wide ? Roles.StringifyLong() : Roles.StringifyInt();
            return self.StaticCallAt(self.Intrinsic(role, ctx, span), self.t.Str(),
                                     self.OneArg(e), span);
        }

        let String cls = self.ClassNameOf(ty);
        if (cls.Length() > 0) {
            match (self.sym.LookupMethod(cls, "ToString")) {
                case Some(ts) {
                    let IrInstanceCall ic = new IrInstanceCall(e, ts.cName, self.t.Str(),
                                                               new List[IrExpr]());
                    ic.span = span;
                    return IrExpr.IrInstanceCall(ic);
                }
                case None { }
            }
        }

        if (Types.IsError(ty)) { return self.EmptyString(span); }
        self.diag.Error(Codes.TypeMismatch(), ctx.file, span,
            cls.Length() > 0
                ? "'" + self.mangler.DisplayName(cls) +
                  "' has no 'String func ToString()' to convert it to a String"
                : "'" + self.Describe(ty) + "' cannot be converted to a String");
        return self.EmptyString(span);
    }

    /*
     * EmptyString - The empty string literal, used where a conversion already failed
     */
    IrExpr func EmptyString(TextSpan span) {
        let IrLitString ls = new IrLitString("\"\"", self.t.Str());
        ls.span = span;
        return IrExpr.IrLitString(ls);
    }

    /*
     * StringClass - The declaration bound to the String builtin slot, or the name itself when
     * nothing bound it
     */
    String func StringClass() {
        match (self.sym.builtins.Find(BuiltinTypes.Str())) {
            case Some(c) { return c; }
            case None { return BuiltinTypes.Str(); }
        }
    }

    /*
     * ClassNameOf - The class a type names, following one level of pointer indirection. "" when
     * the type names no class.
     */
    String func ClassNameOf(IrType ty) {
        match (ty) {
            case IrClassRef(cr) { return cr.className; }
            case IrPtrType(pt)  { return self.ClassNameOf(pt.inner); }
            default { return ""; }
        }
    }

    /*
     * DirectClassNameOf - The class a type names, WITHOUT following a pointer. Method lookup uses
     * this: a T* is not a T, and calling a method on one is a mistake worth reporting.
     */
    String func DirectClassNameOf(IrType ty) {
        match (ty) { case IrClassRef(cr) { return cr.className; } default { return ""; } }
    }

    /* ---------------------------------------------------------------------------------------
     * The remaining whole-body and whole-declaration warnings
     * ------------------------------------------------------------------------------------ */

    /*
     * IsManagedRef - True for values that participate in reference counting: a class reference, or
     * a union with a managed payload. A module is not one - it has no instances.
     */
    public bool func IsManagedRef(IrType ty) {
        match (ty) {
            case IrClassRef(cr) {
                return self.sym.IsClass(cr.className) && !self.sym.modules.Has(cr.className);
            }
            case IrUnionType(ut) { return self.IsManagedUnion(ut.name, new StringSet()); }
            default { return false; }
        }
    }

    /*
     * IsManagedUnion - True when a union stores a managed value in any variant, directly or
     * nested.
     *
     * The answer is cached, but NOT when the walk stood on a cycle: a union that reaches itself
     * gets 'false' for the inner visit, and that false is conditioned on where the walk started
     * rather than being a fact about the type. cycleCut carries exactly that, and the caller's own
     * flag is restored so an outer walk still knows its own answer was cut.
     */
    bool func IsManagedUnion(String name, StringSet visiting) {
        match (self.managedUnionCache.Find(name)) {
            case Some(cached) { return cached; }
            case None { }
        }
        if (!visiting.AddNew(name)) { self.cycleCut = true; return false; }

        let bool outerCut = self.cycleCut;
        self.cycleCut = false;
        let bool managed = false;

        match (self.sym.UnionDef(name)) {
            case Some(variants) {
                let int i = 0;
                while (i < variants.Length() && !managed) {
                    let List[Param] payload = variants.Get(i).variantFields;
                    let int j = 0;
                    while (j < payload.Length() && !managed) {
                        match (payload.Get(j).type) {
                            case NamedSpec(ns) {
                                let String fieldName = ns.Mangled();
                                if (self.sym.IsUnion(fieldName)) {
                                    if (self.IsManagedUnion(fieldName, visiting)) { managed = true; }
                                } else if (self.sym.IsClass(fieldName) &&
                                           !self.sym.modules.Has(fieldName)) {
                                    managed = true;
                                }
                            }
                            default { }
                        }
                        j = j + 1;
                    }
                    i = i + 1;
                }
            }
            case None { }
        }

        visiting.Remove(name);
        if (!self.cycleCut) { self.managedUnionCache.Put(name, managed); }
        self.cycleCut = self.cycleCut || outerCut;
        return managed;
    }

    /*
     * WarnManagedFixedArray - A fixed array is raw storage with no destructor, so whatever it
     * still holds when it dies is leaked. Stores into it are counted correctly, so nothing
     * dangles - which is why this is a warning and not an error.
     */
    void func WarnManagedFixedArray(IrType ty, String what, ResolveCtx ctx, TextSpan span) {
        match (ty) {
            case IrArrayType(at) {
                if (!self.IsManagedRef(at.elem)) { return; }
                let String el = self.Describe(at.elem);
                let List[String] hints = new List[String]();
                hints.Add("a fixed array is raw storage with no destructor, so whatever it still " +
                          "holds when it goes out of scope is leaked; stores into it are counted " +
                          "correctly, so nothing dangles");
                hints.Add("use 'List[" + el + "]' for owned elements, or clear the slots by hand " +
                          "before it dies");
                self.diag.Warn(Codes.ManagedFixedArray(), ctx.file, span,
                    what + " is a fixed array of '" + el + "', whose elements are never released",
                    hints);
            }
            default { }
        }
    }

    /*
     * Relational - The four operators that, unlike '==' and '!=', never derive from one another
     */
    List[String] func Relational() {
        let List[String] r = new List[String]();
        r.Add("<");
        r.Add(">");
        r.Add("<=");
        r.Add(">=");
        return r;
    }

    /*
     * WarnPartialRelationalSet - Warns when a class overloads some relational operators but not
     * their mirrors. '<' without '>' is not a half-finished feature, it is a type error at every
     * site that writes the missing one.
     */
    void func WarnPartialRelationalSet(ClassDecl cd, ResolveCtx ctx) {
        let StringSet declared = new StringSet();
        let List[String] rel = self.Relational();
        let int i = 0;
        while (i < cd.members.Length()) {
            match (cd.members.Get(i)) {
                case OperatorDecl(od) {
                    if (od.params.Length() == 1 && rel.Contains(od.op)) { declared.AddNew(od.op); }
                }
                default { }
            }
            i = i + 1;
        }
        if (declared.ToList().Length() == 0) { return; }

        let List[String] missing = new List[String]();
        if (declared.Has("<") != declared.Has(">"))   { missing.Add(declared.Has("<") ? ">" : "<"); }
        if (declared.Has("<=") != declared.Has(">=")) { missing.Add(declared.Has("<=") ? ">=" : "<="); }
        if (missing.Length() == 0) { return; }

        let List[String] have = declared.ToList();
        Algorithms.SortBy(have, StrLess);
        let List[String] haveQ = new List[String]();
        let int h = 0;
        while (h < have.Length()) { haveQ.Add("'" + have.Get(h) + "'"); h = h + 1; }
        let List[String] missQ = new List[String]();
        let int m = 0;
        while (m < missing.Length()) { missQ.Add("'" + missing.Get(m) + "'"); m = m + 1; }

        let String shown = self.mangler.DisplayName(cd.name);
        let List[String] hints = new List[String]();
        hints.Add("relational operators do not derive from one another the way '!=' derives from " +
                  "'==', so '" + missing.Get(0) + "' on two '" + shown +
                  "' values is a type error at every call site");
        hints.Add("declare the mirror, e.g. 'public operator bool func " + missing.Get(0) +
                  "(" + shown + " other) { ... }'");
        self.diag.Warn(Codes.PartialOperatorSet(), ctx.file, cd.span,
            "'" + shown + "' overloads " + String.Join(haveQ, " and ") + " but not " +
            String.Join(missQ, " or "), hints);
    }

    /*
     * MissingRelationalHint - Explains a relational operator rejected on a type that has some of
     * the family but not this one, which otherwise reads as "not numeric" with no mention of the
     * operators the type does have. Empty when there is nothing useful to add.
     */
    List[String] func MissingRelationalHint(String lhsClass, String op, IrType left, IrType right) {
        let List[String] hints = new List[String]();

        // Two enums of one type: the answer is not a missing operator but the wrong question
        match (left) {
            case IrEnumType(le) {
                match (right) {
                    case IrEnumType(re) {
                        if (le.name == re.name) {
                            hints.Add("an enum is a set of names, not an ordered range, so '" + op +
                                      "' is not defined on '" + self.mangler.DisplayName(le.name) + "'");
                            hints.Add("compare the values instead: 'a as int " + op + " b as int'");
                            hints.Add("'==' and '!=' do work directly, and 'match' covers one arm per member");
                            return hints;
                        }
                    }
                    default { }
                }
            }
            default { }
        }

        if (lhsClass.Length() == 0) { return hints; }
        let List[String] rel = self.Relational();
        let List[String] have = new List[String]();
        let int i = 0;
        while (i < rel.Length()) {
            if (IsSome(self.sym.LookupOperator(lhsClass, rel.Get(i), 1))) {
                have.Add("'" + rel.Get(i) + "'");
            }
            i = i + 1;
        }
        if (have.Length() == 0) { return hints; }

        let String shown = self.mangler.DisplayName(lhsClass);
        hints.Add("'" + shown + "' overloads " + String.Join(have, " and ") + ", but not '" + op +
                  "' - relational operators are each declared separately, none derives from another");
        hints.Add("add 'public operator bool func " + op + "(" + shown + " other) { ... }'");
        return hints;
    }

    /*
     * WarnUnsafeManagedTemporary - Warns when an unsafe block builds a managed value it therefore
     * never releases. 'unsafe' turns counting off for the WHOLE block, including values that did
     * not need it turned off.
     */
    void func WarnUnsafeManagedTemporary(IrBlock body, ResolveCtx ctx) {
        let UnsafeAlloc st = new UnsafeAlloc(self);
        match (self.sym.IntrinsicOrNull(Roles.Retain()))  { case Some(n) { st.retain = n; } case None { } }
        match (self.sym.IntrinsicOrNull(Roles.Release())) { case Some(n) { st.release = n; } case None { } }
        st.Run(body);

        // The author counting by hand is the case this warning exists to stay out of
        if (st.handManaged) { return; }
        match (st.found) {
            case None { }
            case Some(site) {
                let List[String] hints = new List[String]();
                hints.Add("'unsafe' turns off reference counting for the whole block, including " +
                          "values like this one that it did not need to be turned off for");
                hints.Add("move it out of the block, or bind it outside and use the binding here");
                self.diag.Warn(Codes.UnsafeAllocatingTemporary(), ctx.file, Exprs2.SpanOf(site),
                    "this builds a '" + self.Describe(Exprs2.TypeOf(site)) +
                    "' inside an 'unsafe' block, where it is never released", hints);
            }
        }
    }

    /* ---------------------------------------------------------------------------------------
     * Expressions
     * ------------------------------------------------------------------------------------ */

    /*
     * ResolveExpr - One expression, with the source span carried onto the IR node when the
     * resolver did not set a more precise one.
     *
     * The expected type is cleared for everything but a call and a ternary: it exists to pick a
     * union instantiation and to type a bare variant name, and letting it leak further would make
     * unrelated expressions resolve differently depending on where they sat.
     */
    IrExpr func ResolveExpr(Expr e, ResolveCtx ctx) {
        let ResolveCtx c = ctx;
        if (IsSome(ctx.expected)) {
            let bool keep = false;
            match (e) {
                case CallExpr(x)    { keep = true; }
                case TernaryExpr(x) { keep = true; }
                default { }
            }
            if (!keep) { c = ctx.NoExpected(); }
        }
        let IrExpr r = self.ResolveExprCore(e, c);
        if (TS.IsNone(Exprs2.SpanOf(r))) { Exprs2.SetSpan(r, Exprs.Span(e)); }
        return r;
    }

    /*
     * ResolveExprCore - The dispatch over every expression node
     */
    IrExpr func ResolveExprCore(Expr e, ResolveCtx ctx) {
        match (e) {
            case PoisonExpr(p) { return self.Poison(Exprs.Span(e)); }

            case ScopedNameExpr(sn) {
                // The binder resolves every qualifier it can reach; one still standing here was
                // written where no scope encloses it
                self.diag.Error(Codes.ScopeNotEnclosing(), ctx.file, sn.span,
                    "a scope qualifier is only meaningful inside a realm or process");
                return self.Poison(Exprs.Span(e));
            }

            case IntLitExpr(il) {
                match (Literals.ParseInt(il.value)) {
                    case Parsed(v, ty, ct) {
                        return IrExpr.IrLitInt(new IrLitInt(v, self.t.Prim(ty), ct));
                    }
                    case Bad {
                        self.diag.Error(Codes.TypeMismatch(), ctx.file, Exprs.Span(e),
                            "integer literal '" + il.value + "' does not fit in 64 bits");
                        return IrExpr.IrLitInt(new IrLitInt(0L, self.t.Int(), Optional[String].None()));
                    }
                }
            }
            case CharLitExpr(cl)  { return IrExpr.IrLitChar(new IrLitChar(cl.value, self.t.Char())); }
            case FloatLitExpr(fl) {
                return IrExpr.IrLitFloat(new IrLitFloat(fl.value, self.t.Prim(Literals.FloatType(fl.value))));
            }
            case BoolLitExpr(bl)  { return IrExpr.IrLitBool(new IrLitBool(bl.value == "true", self.t.Bool())); }
            case StrLitExpr(sl) {
                self.WarnIfLooksInterpolated(sl, ctx);
                return IrExpr.IrLitString(new IrLitString(sl.value, self.t.Str()));
            }
            case NullExpr(n) { return IrExpr.IrLitNull(new IrLitNull(self.t.Void())); }

            case IdentExpr(ie) { return self.ResolveIdent(ie, ctx); }
            case CastExpr(ce)  { return self.ResolveCast(ce, ctx); }
            case PostfixExpr(pf) { return self.ResolvePostfix(pf, ctx); }
            case UnaryExpr(un) { return self.ResolveUnary(un, ctx); }
            case BinExpr(be)   { return self.ResolveBin(be, ctx); }
            case CallExpr(ce)  { return self.ResolveCall(ce, ctx); }
            case CatchCallExpr(cce) { return self.ResolveCatchCall(cce, ctx); }
            case MemberAccessExpr(ma) { return self.ResolveMemberAccess(ma, ctx); }
            case NewExpr(ne)   { return self.ResolveNew(ne, ctx); }
            case ArrayLitExpr(al) { return self.ResolveArrayLit(al, ctx); }
            case IndexExpr(ix) { return self.ResolveIndex(ix, ctx); }
            case GenericTypeRefExpr(g) { return self.ResolveGenericTypeRef(g, ctx); }

            case SizeofExpr(so) {
                self.CheckType(Optional.Some(so.typeName), ctx, so.span, false);
                return IrExpr.IrSizeof(new IrSizeof(self.ResolveTypeSpec(so.typeName), self.t.SizeT()));
            }
            case DefaultExpr(de) {
                self.CheckType(Optional.Some(de.typeName), ctx, de.span, false);
                return IrExpr.IrDefault(new IrDefault(self.ResolveTypeSpec(de.typeName)));
            }
            case AddrOfExpr(ao) { return self.ResolveAddrOf(ao, ctx); }
            case DerefExpr(dr)  { return self.ResolveDeref(dr, ctx); }
            case TernaryExpr(te) { return self.ResolveTernary(te, ctx); }
            case InterpStrExpr(istr) {
                let List[IrExpr] parts = new List[IrExpr]();
                let int i = 0;
                while (i < istr.parts.Length()) {
                    parts.Add(self.EnsureString(self.ResolveExpr(istr.parts.Get(i), ctx), ctx));
                    i = i + 1;
                }
                if (parts.Length() == 0) { return self.EmptyString(istr.span); }
                return IrExpr.IrInterp(new IrInterp(parts, self.t.Str()));
            }
            default { return self.Poison(Exprs.Span(e)); }
        }
    }

    /*
     * ResolveCast - 'expr as T'. A user-defined 'as' operator on the DESTINATION class wins over
     * the built-in conversions, which is what makes '42 as String' work.
     */
    IrExpr func ResolveCast(CastExpr ce, ResolveCtx ctx) {
        self.CheckType(Optional.Some(ce.targetType), ctx, ce.span, true);
        let IrExpr inner = self.ResolveExpr(ce.value, ctx);
        let IrType to = self.ResolveTypeSpec(ce.targetType);

        if (!Types.Same(Exprs2.TypeOf(inner), to)) {
            let String destCls = self.DirectClassNameOf(to);
            if (destCls.Length() > 0) {
                match (self.FindAsOperator(destCls, Exprs2.TypeOf(inner))) {
                    case Some(asOp) {
                        self.CheckOperatorAccess(destCls, "as", ctx, ce.span);
                        return self.StaticCallAt(asOp.cName, to, self.OneArg(inner), ce.span);
                    }
                    case None { }
                }
            }
        }
        self.CheckCast(inner, to, ctx);
        return IrExpr.IrCast(new IrCast(to, inner));
    }

    /*
     * ResolvePostfix - 'x++' and 'x--'. On a class they dispatch to a zero-parameter overload that
     * mutates in place and returns void; on anything else they need an lvalue.
     */
    IrExpr func ResolvePostfix(PostfixExpr pf, ResolveCtx ctx) {
        let IrExpr opnd = self.ResolveExpr(pf.operand, ctx);
        let String sym = Ops.PostfixSym(pf.op);

        let String pfCls = self.DirectClassNameOf(Exprs2.TypeOf(opnd));
        if (pfCls.Length() > 0) {
            match (self.sym.LookupOperator(pfCls, sym, 0)) {
                case Some(pfOp) {
                    self.CheckOperatorAccess(pfCls, sym, ctx, pf.span);
                    return self.StaticCallAt(pfOp.cName, self.t.Void(), self.OneArg(opnd), pf.span);
                }
                case None { }
            }
        }

        if (Types.IsError(Exprs2.TypeOf(opnd))) { return self.Poison(pf.span); }

        if (!self.IsStorage(opnd)) {
            self.diag.Error(Codes.NotAnLvalue(), ctx.file, pf.span,
                "'" + sym + "' needs a variable, field, or element to modify");
        } else {
            let bool isPtr = false;
            match (Exprs2.TypeOf(opnd)) { case IrPtrType(p) { isPtr = true; } default { } }
            if (isPtr) {
                if (!ctx.inUnsafe) {
                    self.diag.Error(Codes.UnsafeRequired(), ctx.file, pf.span,
                        "pointer '" + sym + "' requires an 'unsafe' block");
                }
            } else if (!self.IsArith(Exprs2.TypeOf(opnd))) {
                self.diag.Error(Codes.TypeMismatch(), ctx.file, pf.span,
                    "'" + sym + "' requires a numeric operand, got '" +
                    self.Describe(Exprs2.TypeOf(opnd)) + "'");
            }
        }
        return IrExpr.IrPostfix(new IrPostfix(pf.op, opnd, Exprs2.TypeOf(opnd)));
    }

    /*
     * IsStorage - True for the expression forms that name storage and so may be modified
     */
    bool func IsStorage(IrExpr e) {
        match (e) {
            case IrVar(x)       { return true; }
            case IrGlobal(x)    { return true; }
            case IrFieldLoad(x) { return true; }
            case IrIndex(x)     { return true; }
            case IrDeref(x)     { return true; }
            default { return false; }
        }
    }

    /*
     * ResolveAddrOf - '&x', which needs unsafe and needs something that has an address
     */
    IrExpr func ResolveAddrOf(AddrOfExpr ao, ResolveCtx ctx) {
        if (!ctx.inUnsafe) {
            self.diag.Error(Codes.UnsafeRequired(), ctx.file, ao.span,
                "address-of '&' requires an 'unsafe' block");
        }
        let IrExpr target = self.ResolveExpr(ao.target, ctx);
        if (Types.IsError(Exprs2.TypeOf(target))) { return self.Poison(ao.span); }

        let bool ok = self.IsStorage(target);
        match (target) { case IrSelfExpr(x) { ok = true; } default { } }
        if (!ok) {
            let List[String] hints = new List[String]();
            hints.Add("bind the value to a local first, then take its address");
            self.diag.Error(Codes.NotAnLvalue(), ctx.file, ao.span,
                "address-of '&' needs a variable, field, or element; this operand has no address",
                hints);
        }
        return IrExpr.IrAddrOf(new IrAddrOf(target, self.t.Ptr(Exprs2.TypeOf(target))));
    }

    /*
     * ResolveDeref - '*p', which needs unsafe and needs a pointer
     */
    IrExpr func ResolveDeref(DerefExpr dr, ResolveCtx ctx) {
        if (!ctx.inUnsafe) {
            self.diag.Error(Codes.UnsafeRequired(), ctx.file, dr.span,
                "pointer dereference '*' requires an 'unsafe' block");
        }
        let IrExpr ptr = self.ResolveExpr(dr.ptr, ctx);
        if (Types.IsError(Exprs2.TypeOf(ptr))) { return self.Poison(dr.span); }

        let IrType inner = self.t.Error();
        match (Exprs2.TypeOf(ptr)) {
            case IrPtrType(pt) { inner = pt.inner; }
            default {
                self.diag.Error(Codes.TypeMismatch(), ctx.file, dr.span,
                    "pointer dereference '*' requires a pointer, got '" +
                    self.Describe(Exprs2.TypeOf(ptr)) + "'");
            }
        }
        return IrExpr.IrDeref(new IrDeref(ptr, inner));
    }

    /*
     * ResolveTernary - 'c ? a : b'. The two arms are unified, and a throwing call is forbidden in
     * all three positions, since there would be nowhere to put its result.
     */
    IrExpr func ResolveTernary(TernaryExpr te, ResolveCtx ctx) {
        let IrExpr cond = self.ResolveExpr(te.cond, ctx);
        self.ForbidNestedThrows(cond, ctx, false);
        self.CheckCondition(cond, ctx, false);

        let IrExpr then = self.ResolveExpr(te.then, ctx);
        let IrExpr els = self.ResolveExpr(te.otherwise, ctx);
        self.ForbidNestedThrows(then, ctx, false);
        self.ForbidNestedThrows(els, ctx, false);

        if (Types.IsError(Exprs2.TypeOf(then)) || Types.IsError(Exprs2.TypeOf(els))) {
            return self.Poison(te.span);
        }
        match (self.UnifyTernary(then, els)) {
            case Some(u) {
                return IrExpr.IrTernary(new IrTernary(cond, self.CoerceTo(then, u),
                                                      self.CoerceTo(els, u), u));
            }
            case None {
                self.diag.Error(Codes.TypeMismatch(), ctx.file, te.span,
                    "ternary branches have incompatible types '" +
                    self.Describe(Exprs2.TypeOf(then)) + "' and '" +
                    self.Describe(Exprs2.TypeOf(els)) + "'");
                return IrExpr.IrTernary(new IrTernary(cond, then, els, Exprs2.TypeOf(then)));
            }
        }
    }

    /*
     * ResolveUnary - '!', '-' and '~'. Each dispatches to a zero-parameter overload when the
     * operand is a class that declares one.
     */
    IrExpr func ResolveUnary(UnaryExpr un, ResolveCtx ctx) {
        let IrExpr operand = self.ResolveExpr(un.operand, ctx);
        if (Types.IsError(Exprs2.TypeOf(operand))) { return self.Poison(un.span); }

        let String sym = Ops.UnSym(un.op);
        let String opCls = self.DirectClassNameOf(Exprs2.TypeOf(operand));
        if (opCls.Length() > 0) {
            match (self.sym.LookupOperator(opCls, sym, 0)) {
                case Some(uop) {
                    self.CheckOperatorAccess(opCls, sym, ctx, un.span);
                    return self.StaticCallAt(uop.cName, self.ResolveType(uop.type),
                                             self.OneArg(operand), un.span);
                }
                case None { }
            }
        }

        let IrType ot = Exprs2.TypeOf(operand);
        let bool isBool = false;
        match (ot) { case IrPrimType(p) { isBool = p.cName == "bool"; } default { } }

        if (un.op == UnOp.Not && !isBool) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, un.span,
                "operator '!' requires 'bool', got '" + self.Describe(ot) + "'");
        } else if (un.op == UnOp.Neg && !self.IsArith(ot)) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, un.span,
                "unary '-' requires a numeric operand, got '" + self.Describe(ot) + "'");
        } else if (un.op == UnOp.BitNot && !self.IsInteger(ot)) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, un.span,
                "operator '~' requires an integer operand, got '" + self.Describe(ot) + "'");
        }

        let IrType rt = un.op == UnOp.Not ? self.t.Bool() : ot;
        return IrExpr.IrUnaryOp(new IrUnaryOp(un.op, operand, rt));
    }

    /*
     * CheckOpArg - Coerces and checks the right operand of a user-defined binary operator against
     * the parameter it declares
     */
    IrExpr func CheckOpArg(Symbol op, IrExpr right, ResolveCtx ctx) {
        match (op.sig) {
            case None { return right; }
            case Some(g) {
                if (g.params.Length() != 1) { return right; }
                let IrType pt = self.ResolveTypeSpec(g.params.Get(0).type);
                let IrExpr coerced = self.Coerce(right, pt, ctx);
                let bool isResult = false;
                match (Exprs2.TypeOf(coerced)) { case IrResultType(r) { isResult = true; } default { } }
                if (!isResult && !self.Assignable(coerced, pt)) {
                    let String owner = "";
                    match (op.owner) { case Some(o) { owner = o; } case None { } }
                    self.diag.Error(Codes.ArgTypeMismatch(), ctx.file, Exprs2.SpanOf(coerced),
                        "operator '" + op.name + "' on '" + self.mangler.DisplayName(owner) +
                        "' takes '" + self.Describe(pt) + "', got '" +
                        self.Describe(Exprs2.TypeOf(coerced)) + "'");
                }
                return coerced;
            }
        }
    }

    /*
     * ResolveBin - A binary expression. The order of the arms IS the language's dispatch order:
     * String concatenation first, then a user overload, then the built-in families.
     */
    IrExpr func ResolveBin(BinExpr be, ResolveCtx ctx) {
        let IrExpr left = self.ResolveExpr(be.left, ctx);
        let IrExpr right = self.ResolveExpr(be.right, ctx);
        if (Types.IsError(Exprs2.TypeOf(left)) || Types.IsError(Exprs2.TypeOf(right))) {
            return self.Poison(be.span);
        }

        let IrType lt = Exprs2.TypeOf(left);
        let IrType rt = Exprs2.TypeOf(right);
        let String sym = Ops.BinSym(be.op);
        let bool isEq = be.op == BinOp.Eq || be.op == BinOp.Ne;

        // '+' where either side is a String is ALWAYS concatenation, with the other side
        // stringified. A user '+' overload does not intercept it.
        if (be.op == BinOp.Add && (Types.IsString(lt) || Types.IsString(rt))) {
            let String stringClass = self.StringClass();
            let String cn = "";
            match (self.sym.LookupOperator(stringClass, "+")) {
                case Some(sop) { cn = sop.cName; }
                case None {
                    self.diag.Error(Codes.MissingIntrinsic(), ctx.file, be.span,
                        "String defines no '+' operator for concatenation");
                    cn = self.mangler.Operator(stringClass, "+", new List[Param](), false);
                }
            }
            let List[IrExpr] args = new List[IrExpr]();
            args.Add(self.EnsureString(left, ctx));
            args.Add(self.EnsureString(right, ctx));
            return self.StaticCallAt(cn, self.t.Str(), args, be.span);
        }

        // A comparison against the null LITERAL is a pointer check and never reaches a user '=='
        // - which is what lets String's own '==' null-check its operand without recursing
        let bool eitherNull = false;
        match (left)  { case IrLitNull(x) { eitherNull = true; } default { } }
        match (right) { case IrLitNull(x) { eitherNull = true; } default { } }
        if (isEq && eitherNull) {
            if (!self.ComparableEq(left, right)) { self.ReportNotComparable(sym, lt, rt, ctx, be.span); }
            return IrExpr.IrBinOp(new IrBinOp(be.op, left, right, self.t.Bool()));
        }

        // Dispatch is on the LEFT operand's class: 'int + Money' does not find 'Money.+'
        let String lhsClass = self.DirectClassNameOf(lt);
        if (lhsClass.Length() > 0) {
            match (self.sym.LookupOperator(lhsClass, sym, 1)) {
                case Some(op) {
                    self.CheckOperatorAccess(lhsClass, sym, ctx, be.span);
                    let IrExpr arg = self.CheckOpArg(op, right, ctx);
                    let List[IrExpr] args = new List[IrExpr]();
                    args.Add(left);
                    args.Add(arg);
                    return self.StaticCallAt(op.cName, self.ResolveType(op.type), args, be.span);
                }
                case None { }
            }
        }

        // '==' and '!=' DERIVE from each other: declaring only one gives you both
        if (isEq && lhsClass.Length() > 0) {
            let String mirror = be.op == BinOp.Eq ? "!=" : "==";
            match (self.sym.LookupOperator(lhsClass, mirror, 1)) {
                case Some(eqOp) {
                    let bool retsBool = false;
                    match (self.ResolveType(eqOp.type)) {
                        case IrPrimType(p) { retsBool = p.cName == "bool"; }
                        default { }
                    }
                    if (retsBool) {
                        self.CheckOperatorAccess(lhsClass, mirror, ctx, be.span);
                        let IrExpr arg = self.CheckOpArg(eqOp, right, ctx);
                        let List[IrExpr] args = new List[IrExpr]();
                        args.Add(left);
                        args.Add(arg);
                        let IrExpr call = self.StaticCallAt(eqOp.cName, self.t.Bool(), args, be.span);
                        return IrExpr.IrUnaryOp(new IrUnaryOp(UnOp.Not, call, self.t.Bool()));
                    }
                }
                case None { }
            }
        }

        // Pointer arithmetic
        let bool lIsPtr = false;
        match (lt) { case IrPtrType(p) { lIsPtr = true; } default { } }
        if (lIsPtr && (be.op == BinOp.Add || be.op == BinOp.Sub) && Types.IsNumeric(rt)) {
            if (!ctx.inUnsafe) {
                self.diag.Error(Codes.UnsafeRequired(), ctx.file, be.span,
                    "pointer arithmetic requires an 'unsafe' block");
            }
            return IrExpr.IrBinOp(new IrBinOp(be.op, left, right, lt));
        }

        // '&&' and '||' are not overloadable and take bool only
        if (be.op == BinOp.And || be.op == BinOp.Or) {
            if (!self.IsBoolType(lt) || !self.IsBoolType(rt)) {
                self.diag.Error(Codes.TypeMismatch(), ctx.file, be.span,
                    "operator '" + sym + "' requires 'bool' operands, got '" +
                    self.Describe(lt) + "' and '" + self.Describe(rt) + "'");
            }
            return IrExpr.IrBinOp(new IrBinOp(be.op, left, right, self.t.Bool()));
        }

        // Two values of one union type compare through that union's generated structural equality
        if (isEq) {
            match (lt) {
                case IrUnionType(lu) {
                    match (rt) {
                        case IrUnionType(ru) {
                            if (lu.name == ru.name) {
                                self.WarnOnUnionComparison(lu.name, ctx, be.span);
                                let List[IrExpr] args = new List[IrExpr]();
                                args.Add(left);
                                args.Add(right);
                                let IrExpr call = self.StaticCallAt(self.mangler.UnionEq(lu.name),
                                                                    self.t.Bool(), args, be.span);
                                if (be.op == BinOp.Eq) { return call; }
                                return IrExpr.IrUnaryOp(new IrUnaryOp(UnOp.Not, call, self.t.Bool()));
                            }
                        }
                        default { }
                    }
                }
                default { }
            }
        }

        if (isEq) {
            if (!self.ComparableEq(left, right)) { self.ReportNotComparable(sym, lt, rt, ctx, be.span); }
            return IrExpr.IrBinOp(new IrBinOp(be.op, left, right, self.t.Bool()));
        }

        // Relational
        if (be.op == BinOp.Lt || be.op == BinOp.Gt || be.op == BinOp.Le || be.op == BinOp.Ge) {
            if (!(self.IsArith(lt) && self.IsArith(rt))) {
                self.diag.Error(Codes.TypeMismatch(), ctx.file, be.span,
                    "operator '" + sym + "' requires numeric operands, got '" + self.Describe(lt) +
                    "' and '" + self.Describe(rt) + "'",
                    self.MissingRelationalHint(lhsClass, sym, lt, rt));
            } else {
                self.CheckMixedSignedness(be.op, left, right, ctx, be.span);
            }
            let IrType ct = self.NumRank(lt) >= self.NumRank(rt) ? lt : rt;
            return IrExpr.IrBinOp(new IrBinOp(be.op, self.InType(left, ct), self.InType(right, ct),
                                              self.t.Bool()));
        }

        // Bitwise and shifts
        if (be.op == BinOp.BitAnd || be.op == BinOp.BitOr || be.op == BinOp.BitXor ||
            be.op == BinOp.Shl || be.op == BinOp.Shr) {
            if (!(self.IsInteger(lt) && self.IsInteger(rt))) {
                self.diag.Error(Codes.TypeMismatch(), ctx.file, be.span,
                    "operator '" + sym + "' requires integer operands, got '" + self.Describe(lt) +
                    "' and '" + self.Describe(rt) + "'");
            }
            self.CheckShiftCount(be.op, lt, right, ctx, Exprs.Span(be.right));

            // A shift resolves at the LEFT operand's type; the count keeps its own
            if (be.op == BinOp.Shl || be.op == BinOp.Shr) {
                return IrExpr.IrBinOp(new IrBinOp(be.op, self.InType(left, lt), right, lt));
            }
            let IrType bt = self.NumRank(lt) >= self.NumRank(rt) ? lt : rt;
            return IrExpr.IrBinOp(new IrBinOp(be.op, self.InType(left, bt), self.InType(right, bt), bt));
        }

        // Arithmetic
        if (!(self.IsArith(lt) && self.IsArith(rt))) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, be.span,
                "operator '" + sym + "' cannot be applied to '" + self.Describe(lt) + "' and '" +
                self.Describe(rt) + "'");
        }
        if (be.op == BinOp.Mod && self.IsArith(lt) && self.IsArith(rt) &&
            !(self.IsInteger(lt) && self.IsInteger(rt))) {
            let List[String] hints = new List[String]();
            hints.Add("for a floating-point remainder, call the library's Math function instead");
            self.diag.Error(Codes.TypeMismatch(), ctx.file, be.span,
                "operator '%' requires integer operands, got '" + self.Describe(lt) + "' and '" +
                self.Describe(rt) + "'", hints);
        }

        self.CheckZeroDivisor(be.op, right, ctx, Exprs.Span(be.right));
        self.CheckMixedSignedness(be.op, left, right, ctx, be.span);
        self.WarnOnCharAddition(be.op, lt, rt, ctx, be.span);
        let IrType ty = self.NumRank(lt) >= self.NumRank(rt) ? lt : rt;
        return IrExpr.IrBinOp(new IrBinOp(be.op, self.InType(left, ty), self.InType(right, ty), ty));
    }

    /*
     * IsBoolType - True for exactly 'bool'
     */
    bool func IsBoolType(IrType ty) {
        match (ty) { case IrPrimType(p) { return p.cName == "bool"; } default { return false; } }
    }

    /*
     * ReportNotComparable - The shared 'these two cannot be compared' diagnostic
     */
    void func ReportNotComparable(String sym, IrType lt, IrType rt, ResolveCtx ctx, TextSpan span) {
        self.diag.Error(Codes.TypeMismatch(), ctx.file, span,
            "'" + sym + "' operands are not comparable: '" + self.Describe(lt) + "' and '" +
            self.Describe(rt) + "'");
    }

    /*
     * WarnOnCharAddition - '+' on two chars adds codepoints; it does not join text, and that is
     * almost never what was meant
     */
    void func WarnOnCharAddition(BinOp op, IrType l, IrType r, ResolveCtx ctx, TextSpan span) {
        if (op != BinOp.Add || !Types.IsChar(l) || !Types.IsChar(r)) { return; }
        let List[String] hints = new List[String]();
        hints.Add("the result is a 'char', so ''a' + 'b'' is codepoint 195, not \"ab\"");
        hints.Add("to build text, convert one side first: 'a as String + b'");
        hints.Add("if the codepoint arithmetic is what you meant, say so with a cast: " +
                  "'a as int + b as int'");
        self.diag.Warn(Codes.CharArithmetic(), ctx.file, span,
            "'+' on two 'char' values adds their codepoints; it does not join them into text", hints);
    }

    /*
     * CheckShiftCount - Rejects a literal shift count outside [0, width). Both ends are undefined
     * behaviour in C, so neither can be allowed to reach the backend.
     */
    void func CheckShiftCount(BinOp op, IrType shifted, IrExpr count, ResolveCtx ctx, TextSpan span) {
        if (op != BinOp.Shl && op != BinOp.Shr) { return; }
        match (self.LiteralValue(count)) {
            case None { }
            case Some(n) {
                match (shifted) {
                    case IrPrimType(p) {
                        let int bits = PrimTypes.IntBits(p.cName);
                        if (bits <= 0) { return; }
                        if (n >= 0L && n < (bits as int64)) { return; }
                        let List[String] hints = new List[String]();
                        hints.Add(n < 0L
                            ? "a negative shift count is undefined behaviour"
                            : "the count must be between 0 and " + Int.ToString(bits - 1));
                        self.diag.Error(Codes.BadShiftCount(), ctx.file, span,
                            "shift count " + Long.ToString(n) + " is out of range for '" +
                            self.Describe(shifted) + "' (" + Int.ToString(bits) + " bits)", hints);
                    }
                    default { }
                }
            }
        }
    }

    /*
     * CheckZeroDivisor - Rejects a literally zero integer divisor. It traps at runtime on every
     * target, so there is no program for which it is correct.
     */
    void func CheckZeroDivisor(BinOp op, IrExpr divisor, ResolveCtx ctx, TextSpan span) {
        if (op != BinOp.Div && op != BinOp.Mod) { return; }
        if (!self.IsInteger(Exprs2.TypeOf(divisor))) { return; }
        match (self.LiteralValue(divisor)) {
            case None { return; }
            case Some(n) { if (n != 0L) { return; } }
        }
        let List[String] hints = new List[String]();
        hints.Add("this traps at runtime; guard the divisor or use a non-zero constant");
        self.diag.Error(Codes.DivisionByZero(), ctx.file, span,
            "integer " + (op == BinOp.Div ? "division" : "remainder") + " by a literal zero", hints);
    }

    /*
     * CheckMixedSignedness - Rejects a signed operand mixed with an unsigned one for the operators
     * whose ANSWER, not merely whose result type, depends on which signedness wins.
     *
     * Not every mix is reported: a non-negative literal that fits the unsigned side changes
     * nothing, and neither does a mix that resolves at a signed type wide enough to hold the
     * unsigned one.
     */
    void func CheckMixedSignedness(BinOp op, IrExpr left, IrExpr right, ResolveCtx ctx, TextSpan span) {
        if (op != BinOp.Div && op != BinOp.Mod && op != BinOp.Lt && op != BinOp.Gt &&
            op != BinOp.Le && op != BinOp.Ge) { return; }

        let IrType l = Exprs2.TypeOf(left);
        let IrType r = Exprs2.TypeOf(right);
        let bool lPrim = false;
        let bool rPrim = false;
        let bool lUns = false;
        let bool rUns = false;
        match (l) { case IrPrimType(p) { lPrim = true; lUns = PrimTypes.IsUnsignedCanon(p.cName); } default { } }
        match (r) { case IrPrimType(p) { rPrim = true; rUns = PrimTypes.IsUnsignedCanon(p.cName); } default { } }
        if (!lPrim || !rPrim) { return; }
        if (lUns == rUns) { return; }

        let IrExpr signedSide = lUns ? right : left;
        let IrType signed = lUns ? r : l;
        let IrType unsigned = lUns ? l : r;

        // A known non-negative constant that fits the unsigned type converts exactly
        match (self.LiteralValue(signedSide)) {
            case Some(known) {
                if (known >= 0L && self.FitsInType(known, unsigned)) { return; }
            }
            case None { }
        }

        let IrType target = self.NumRank(l) >= self.NumRank(r) ? l : r;
        let bool targetUns = false;
        match (target) { case IrPrimType(p) { targetUns = PrimTypes.IsUnsignedCanon(p.cName); } default { } }
        if (!targetUns && self.NumRank(unsigned) < self.NumRank(signed)) { return; }

        let String verb = (op == BinOp.Div || op == BinOp.Mod) ? "compute" : "compare";
        let IrType lost = targetUns ? signed : unsigned;
        let String lostAs = targetUns ? "negative values wrap" : "large values go negative";

        let List[String] hints = new List[String]();
        hints.Add("'" + Ops.BinSym(op) + "' resolves at '" + self.Describe(target) + "', so the '" +
                  self.Describe(lost) + "' side converts into it and " + lostAs +
                  " - which changes the answer rather than just its type");
        hints.Add("cast the side you mean: 'x as " + self.Describe(signed) + "' to " + verb +
                  " as signed, or 'x as " + self.Describe(unsigned) + "' to " + verb + " as unsigned");
        if (self.NumRank(signed) < 5 && self.NumRank(unsigned) < 5) {
            hints.Add("or widen both sides to 'int64', which holds every value of either type");
        }
        self.diag.Error(Codes.MixedSignedness(), ctx.file, span,
            "operator '" + Ops.BinSym(op) + "' mixes signed '" + self.Describe(signed) +
            "' with unsigned '" + self.Describe(unsigned) + "'", hints);
    }

    /*
     * FitsInType - True when a known constant is representable in a primitive. A type whose range
     * RangeLo/RangeHi cannot express holds any int64, which is every constant this pass can see.
     */
    bool func FitsInType(int64 n, IrType ty) {
        match (ty) {
            case IrPrimType(p) {
                let int bits = PrimTypes.IntBits(p.cName);
                if (bits == 0 || bits == 1 || bits == 64) { return true; }
                let bool unsigned = PrimTypes.IsUnsignedCanon(p.cName);
                return n >= self.RangeLo(bits, unsigned) && n <= self.RangeHi(bits, unsigned);
            }
            default { return true; }
        }
    }

    /*
     * ResolveIdent - A bare name. 'true', 'false', 'null' and 'self' are resolved here rather than
     * being keywords, which is why 'self' outside an instance method is an undefined-name error
     * with a message that says which of the two reasons applies.
     */
    IrExpr func ResolveIdent(IdentExpr ie, ResolveCtx ctx) {
        let String name = ie.name;
        if (name == "true")  { return IrExpr.IrLitBool(new IrLitBool(true, self.t.Bool())); }
        if (name == "false") { return IrExpr.IrLitBool(new IrLitBool(false, self.t.Bool())); }
        if (name == "null")  { return IrExpr.IrLitNull(new IrLitNull(self.t.Void())); }

        if (name == "self") {
            if (!ctx.isStatic && ctx.curClass.Length() > 0) {
                return IrExpr.IrSelfExpr(new IrSelfExpr(ctx.curClass, self.t.ClassRef(ctx.curClass)));
            }
            self.diag.Error(Codes.UndefinedVariable(), ctx.file, ie.span,
                ctx.curClass.Length() == 0
                    ? "'self' is only valid inside an instance method"
                    : "'self' is not available in a static context");
            return IrExpr.IrSelfExpr(new IrSelfExpr(ctx.curClass, self.t.ClassRef(ctx.curClass)));
        }

        match (ctx.locals.Lookup(name)) {
            case Some(lt) { return IrExpr.IrVar(new IrVar(name, lt, ctx.locals.IsRef(name))); }
            case None { }
        }

        // A process variable is the only global state, and reading one declared below is an error
        // the declaration order decides
        match (self.processState.Find(name)) {
            case Some(slot) {
                self.ReportPendingProcessState(name, ctx, ie.span);
                return slot;
            }
            case None { }
        }

        if (self.ClassInScope(name)) {
            return IrExpr.IrVar(new IrVar(name, self.t.ClassRef(name), false));
        }

        // A bare function name is a function-pointer value, if the language can express its type
        let Optional[Symbol] fsym = self.LookupFreeFuncVisible(name);
        if (self.FuncInScope(fsym)) {
            match (fsym) {
                case Some(f) { return self.FuncRefValue(f, name, ie, ctx); }
                case None { }
            }
        }

        // The message that best explains a name that is not a value here
        let String msg = "";
        if (self.sym.IsField(ctx.curClass, name)) {
            msg = ctx.isStatic
                ? "'" + name + "' is an instance field and cannot be used in a static context"
                : "'" + name + "' is a field; write 'self." + name + "'";
        } else if (self.sym.IsClass(name)) {
            msg = "'" + self.mangler.DisplayName(name) + "' is not in scope; import its module";
        } else if (!self.ReportNotVisible("name", name, ctx.file, ie.span)) {
            msg = "'" + name + "' is not defined";
        }
        if (msg.Length() > 0) {
            self.diag.Error(Codes.UndefinedVariable(), ctx.file, ie.span, msg);
        }
        return IrExpr.IrVar(new IrVar(name, self.t.Error(), false));
    }

    /*
     * FuncRefValue - A function used as a value. Four shapes cannot be one, and each says why.
     */
    IrExpr func FuncRefValue(Symbol f, String name, IdentExpr ie, ResolveCtx ctx) {
        if (self.sym.IsOverloadedFunc(name)) {
            self.diag.Error(Codes.AmbiguousOverload(), ctx.file, ie.span,
                "cannot take the address of overloaded function '" + name + "'");
            return self.Poison(ie.span);
        }
        match (f.sig) {
            case None { return self.Poison(ie.span); }
            case Some(g) {
                if (g.isEntry) {
                    self.diag.Error(Codes.CallToEntry(), ctx.file, ie.span,
                        "'" + name + "' is an entry point and cannot be used as a value");
                    return self.Poison(ie.span);
                }
                if (g.isThrows) {
                    self.diag.Error(Codes.TypeMismatch(), ctx.file, ie.span,
                        "'" + name + "' is a 'throws' function and cannot be used as a " +
                        "function-pointer value");
                    return IrExpr.IrVar(new IrVar(name, self.t.Int(), false));
                }
                let int i = 0;
                while (i < g.params.Length()) {
                    if (g.params.Get(i).isRef) {
                        self.diag.Error(Codes.TypeMismatch(), ctx.file, ie.span,
                            "'" + name + "' has a 'ref' parameter and cannot be used as a " +
                            "function-pointer value (func(...) -> R types cannot express which " +
                            "parameters are 'ref')");
                        return IrExpr.IrVar(new IrVar(name, self.t.Int(), false));
                    }
                    i = i + 1;
                }
                let List[IrType] ps = new List[IrType]();
                let int j = 0;
                while (j < g.params.Length()) {
                    ps.Add(self.ResolveTypeSpec(g.params.Get(j).type));
                    j = j + 1;
                }
                return IrExpr.IrFuncRef(new IrFuncRef(f.cName,
                    self.FnPtr(self.ResolveType(g.returnType), ps)));
            }
        }
    }

    /*
     * ResolveMemberAccess - 'obj.member'. An enum constant and a union variant are both written
     * this way and neither is a field, so both are recognised before anything is resolved.
     */
    IrExpr func ResolveMemberAccess(MemberAccessExpr ma, ResolveCtx ctx) {
        match (ma.object) {
            case IdentExpr(eid) {
                // A local of the same name wins: the type name is only meant when nothing shadows it
                if (IsNone(ctx.locals.Lookup(eid.name))) {
                    if (self.sym.IsEnum(eid.name)) {
                        if (!self.sym.IsEnumMember(eid.name, ma.member)) {
                            self.diag.Error(Codes.UndefinedVariable(), ctx.file, ma.span,
                                "enum '" + eid.name + "' has no member '" + ma.member + "'");
                        }
                        let IrEnumConst ec = new IrEnumConst(eid.name, ma.member,
                                                             self.t.EnumType(eid.name));
                        ec.span = ma.span;
                        return IrExpr.IrEnumConst(ec);
                    }
                    if (self.sym.IsUnion(eid.name)) {
                        return self.ReportUnionMemberAccess(eid.name, ma, ctx);
                    }
                }
            }
            default { }
        }

        let IrExpr obj = self.ResolveExpr(ma.object, ctx);
        if (Types.IsError(Exprs2.TypeOf(obj))) { return self.Poison(ma.span); }

        let String cls = self.ClassNameOf(Exprs2.TypeOf(obj));
        if (cls.Length() == 0) {
            self.diag.Error(Codes.UndefinedVariable(), ctx.file, ma.span,
                "'" + self.Describe(Exprs2.TypeOf(obj)) + "' has no member '" + ma.member +
                "'; only class types have fields");
            return self.Poison(ma.span);
        }

        let IrType fieldType = self.t.Int();
        match (self.sym.FieldType(cls, ma.member)) {
            case Some(ft) {
                fieldType = self.ResolveTypeSpec(ft);
                self.CheckMemberAccess(cls, ma.member, ctx, ma.span);
            }
            case None {
                // The class itself was already reported as unreachable; do not pile on
                if (self.notVisible.Has(ctx.file + "|" + cls)) { return self.Poison(ma.span); }
                // An opaque-fielded class is C the compiler cannot see into, so silence is right
                if (!self.HasOpaqueFields(cls)) {
                    self.diag.Error(Codes.UndefinedVariable(), ctx.file, ma.span,
                        "'" + self.mangler.DisplayName(cls) + "' has no field '" + ma.member + "'");
                }
            }
        }
        return IrExpr.IrFieldLoad(new IrFieldLoad(obj, ma.member, fieldType));
    }

    /*
     * ReportUnionMemberAccess - 'U.Variant' without parentheses. Naming a variant is not reading a
     * field, so the message says which mistake it was.
     */
    IrExpr func ReportUnionMemberAccess(String uname, MemberAccessExpr ma, ResolveCtx ctx) {
        let bool known = false;
        match (self.sym.UnionDef(uname)) {
            case Some(variants) {
                let int i = 0;
                while (i < variants.Length()) {
                    if (variants.Get(i).name == ma.member) { known = true; }
                    i = i + 1;
                }
            }
            case None { }
        }
        if (known) {
            let List[String] hints = new List[String]();
            hints.Add("construct it by calling it: '" + uname + "." + ma.member + "()'");
            self.diag.Error(Codes.UndefinedVariable(), ctx.file, ma.span,
                "'" + uname + "." + ma.member + "' is a union variant, not a field", hints);
        } else {
            self.diag.Error(Codes.UndefinedVariable(), ctx.file, ma.span,
                "union '" + uname + "' has no variant '" + ma.member + "'");
        }
        let IrUnionConstruct uc = new IrUnionConstruct(self.t.UnionType(uname), 0, new List[IrExpr]());
        uc.span = ma.span;
        return IrExpr.IrUnionConstruct(uc);
    }

    /*
     * CoerceArgs - Coerces each argument to its parameter's type and checks ref passing.
     *
     * 'ref' is matched EXACTLY: the parameter takes the variable's address, so no conversion can
     * apply, and the argument becomes an address-of at this point.
     */
    void func CoerceArgs(List[IrExpr] args, Optional[MethodSig] sig, ResolveCtx ctx,
                         List[Expr] astArgs) {
        match (sig) {
            case None { }
            case Some(g) {
                let int i = 0;
                while (i < args.Length() && i < g.params.Length()) {
                    let Param p = g.params.Get(i);
                    let IrType pt = self.ResolveTypeSpec(p.type);
                    args.Set(i, self.Coerce(args.Get(i), pt, ctx));
                    self.CheckAssign(args.Get(i), pt, "parameter '" + p.name + "'", ctx,
                                     Codes.ArgTypeMismatch());

                    if (i < astArgs.Length()) {
                        let bool argIsRef = false;
                        match (astArgs.Get(i)) { case RefArgExpr(x) { argIsRef = true; } default { } }
                        let TextSpan at = Exprs.Span(astArgs.Get(i));

                        if (argIsRef && !p.isRef) {
                            self.diag.Error(Codes.RefArgMismatch(), ctx.file, at,
                                "argument " + Int.ToString(i + 1) + " is passed 'ref' but parameter '" +
                                p.name + "' is not 'ref'");
                        } else if (!argIsRef && p.isRef) {
                            self.diag.Error(Codes.RefArgMismatch(), ctx.file, at,
                                "parameter '" + p.name + "' is 'ref'; pass argument " +
                                Int.ToString(i + 1) + " as 'ref ...'");
                        } else if (argIsRef) {
                            self.CheckLValue(args.Get(i), ctx);
                            let IrType at2 = Exprs2.TypeOf(args.Get(i));
                            if (!Types.Same(at2, pt) && !Types.IsError(at2)) {
                                let List[String] hints = new List[String]();
                                hints.Add("a 'ref' parameter takes the variable's address, so no " +
                                          "conversion can apply");
                                self.diag.Error(Codes.RefArgMismatch(), ctx.file, at,
                                    "'ref' argument " + Int.ToString(i + 1) + " must be exactly '" +
                                    self.Describe(pt) + "', got '" + self.Describe(at2) + "'", hints);
                            }
                            args.Set(i, IrExpr.IrAddrOf(new IrAddrOf(args.Get(i), self.t.Ptr(at2))));
                        }
                    }
                    i = i + 1;
                }
            }
        }
    }

    /*
     * BuildCall - The common tail of every resolved call: pick the overload, settle the C name,
     * resolve the return type, coerce the arguments, then build the matching IR node. A throwing
     * callee produces the Result-carrying node instead, and is checked for a handler.
     */
    IrExpr func BuildCall(List[Symbol] cands, Optional[Symbol] primary, List[IrExpr] args,
                          String display, String fallbackCName, Optional[IrExpr] recv,
                          ResolveCtx ctx, CallExpr ce) {
        let Optional[Symbol] chosen = self.ChooseOverload(cands, primary, args, display, ctx, ce.span);
        let String cn = fallbackCName;
        let IrType ret = self.t.Void();
        match (chosen) {
            case Some(c) { cn = c.cName; ret = self.ResolveType(c.type); }
            case None { }
        }
        self.CoerceArgs(args, self.SigOf(chosen), ctx, ce.args);

        // 'throws' is a hard keyword, so the flag needs another name
        let bool canFail = false;
        match (self.SigOf(chosen)) { case Some(g) { canFail = g.isThrows; } case None { } }

        if (canFail) {
            self.CheckThrowsHandled(ctx, ce.span);
            match (recv) {
                case None {
                    return IrExpr.IrThrowsCall(new IrThrowsCall(cn, ret, self.t.Result(ret), args));
                }
                case Some(r) {
                    return IrExpr.IrThrowsInstanceCall(
                        new IrThrowsInstanceCall(r, cn, ret, self.t.Result(ret), args));
                }
            }
        }
        match (recv) {
            case None    { return IrExpr.IrStaticCall(new IrStaticCall(cn, ret, args)); }
            case Some(r) { return IrExpr.IrInstanceCall(new IrInstanceCall(r, cn, ret, args)); }
        }
    }

    /*
     * CheckIndexIsInteger - A raw subscript lowers straight to C 'a[i]', so a non-integer index
     * would otherwise reach the C compiler. The operator-'[]' path checks its own index against
     * the declared parameter instead.
     */
    void func CheckIndexIsInteger(IrExpr idx, ResolveCtx ctx, TextSpan span) {
        let IrType it = Exprs2.TypeOf(idx);
        if (self.IsInteger(it)) { return; }
        match (it) { case IrEnumType(e) { return; } default { } }
        self.diag.Error(Codes.TypeMismatch(), ctx.file, span,
            "index must be an integer, got '" + self.Describe(it) + "'");
    }

    /*
     * IndexGetter - The one-parameter '[]' overload on a class, or None
     */
    Optional[Symbol] func IndexGetter(String cls) {
        match (self.sym.LookupOperator(cls, "[]")) {
            case Some(op) {
                match (op.sig) {
                    case Some(g) { if (g.params.Length() == 1) { return Optional.Some(op); } }
                    case None { }
                }
                return Optional[Symbol].None();
            }
            case None { return Optional[Symbol].None(); }
        }
    }

    /*
     * IndexSetter - The two-parameter '[]=' overload on a class, or None
     */
    Optional[Symbol] func IndexSetter(String cls) {
        match (self.sym.LookupOperator(cls, "[]=")) {
            case Some(op) {
                match (op.sig) {
                    case Some(g) { if (g.params.Length() == 2) { return Optional.Some(op); } }
                    case None { }
                }
                return Optional[Symbol].None();
            }
            case None { return Optional[Symbol].None(); }
        }
    }

    /*
     * ElementTypeOf - The element type of an indexable, reporting what cannot be indexed at all
     */
    IrType func ElementTypeOf(IrExpr obj, ResolveCtx ctx, TextSpan span) {
        match (Exprs2.TypeOf(obj)) {
            case IrArrayType(at) { return at.elem; }
            case IrPtrType(pt) {
                if (!ctx.inUnsafe) {
                    self.diag.Error(Codes.UnsafeRequired(), ctx.file, span,
                        "pointer indexing requires an 'unsafe' block");
                }
                return pt.inner;
            }
            default {
                self.diag.Error(Codes.IndexOnNonCollection(), ctx.file, span,
                    "'" + self.Describe(Exprs2.TypeOf(obj)) + "' cannot be indexed");
                return self.t.Int();
            }
        }
    }

    /*
     * ResolveIndex - 'a[i]', through a class '[]' overload, a fixed array, or a pointer
     */
    IrExpr func ResolveIndex(IndexExpr ix, ResolveCtx ctx) {
        let IrExpr obj = self.ResolveExpr(ix.object, ctx);
        let IrExpr idx = self.ResolveExpr(ix.index, ctx);
        if (Types.IsError(Exprs2.TypeOf(obj)) || Types.IsError(Exprs2.TypeOf(idx))) {
            return self.Poison(ix.span);
        }

        match (Exprs2.TypeOf(obj)) {
            case IrClassRef(icr) {
                match (self.IndexGetter(icr.className)) {
                    case Some(getOp) {
                        self.CheckOperatorAccess(icr.className, "[]", ctx, ix.span);
                        let IrType idxType = self.ResolveTypeSpec(self.SigParam(getOp, 0));
                        let IrExpr ci = self.Coerce(idx, idxType, ctx);
                        self.CheckAssign(ci, idxType, "the index", ctx, Codes.TypeMismatch());
                        let IrInstanceCall call = new IrInstanceCall(obj, getOp.cName,
                            self.ResolveType(getOp.type), self.OneArg(ci));
                        call.span = ix.span;
                        return IrExpr.IrInstanceCall(call);
                    }
                    case None { }
                }
            }
            default { }
        }

        let IrType elem = self.ElementTypeOf(obj, ctx, ix.span);
        self.CheckIndexIsInteger(idx, ctx, Exprs.Span(ix.index));
        return IrExpr.IrIndex(new IrIndex(obj, idx, elem));
    }

    /*
     * SigParam - The type of a symbol's nth parameter, or int when there is none
     */
    TypeSpec func SigParam(Symbol s, int n) {
        match (s.sig) {
            case Some(g) {
                if (n < g.params.Length()) { return g.params.Get(n).type; }
                return Specs.Named("int");
            }
            case None { return Specs.Named("int"); }
        }
    }

    /*
     * ResolveNew - 'new T(...)'. Everything that is not a class in scope gets its own message,
     * because "not a class" alone never says what to write instead.
     */
    IrExpr func ResolveNew(NewExpr ne, ResolveCtx ctx) {
        let List[IrExpr] args = new List[IrExpr]();
        let int i = 0;
        while (i < ne.args.Length()) {
            let Expr a = ne.args.Get(i);
            match (a) {
                case RefArgExpr(ra) { args.Add(self.ResolveExpr(ra.target, ctx)); }
                default { args.Add(self.ResolveExpr(a, ctx)); }
            }
            i = i + 1;
        }

        let String typeName = Specs.ToSpecString(ne.type);
        if (typeName == Specs.Poison()) { return self.Poison(ne.span); }
        if (self.mangler.GenericFailed(typeName)) { return self.Poison(ne.span); }

        if (self.sym.modules.Has(typeName)) {
            let List[String] hints = new List[String]();
            hints.Add("a module has no instances; call its members directly, as '" +
                      self.mangler.DisplayName(typeName) + ".Member(...)'");
            self.diag.Error(Codes.NewOnNonClass(), ctx.file, ne.span,
                "'" + self.mangler.DisplayName(typeName) + "' is a module and cannot be instantiated",
                hints);
            return self.Poison(ne.span);
        }

        if (!self.ClassInScope(typeName)) {
            self.ReportBadNew(ne, typeName, ctx);
            return self.Poison(ne.span);
        }

        // Constructor arity, when there is a constructor that takes anything
        let bool checkedArgs = false;
        match (self.sym.LookupMethod(typeName, Lifecycle.Init())) {
            case Some(init) {
                match (init.sig) {
                    case Some(isig) {
                        if (isig.params.Length() > 0) {
                            self.CheckArgCount(init.sig, args.Length(),
                                self.mangler.DisplayName(typeName) + " constructor", ctx, ne.span);
                            self.CoerceArgs(args, init.sig, ctx, ne.args);
                            checkedArgs = true;
                        }
                    }
                    case None { }
                }
            }
            case None { }
        }
        if (!checkedArgs && args.Length() > 0) {
            self.diag.Error(Codes.WrongArgCount(), ctx.file, ne.span,
                "'" + self.mangler.DisplayName(typeName) + "' has no constructor taking arguments");
        }

        if (ne.collectionInit.Length() > 0) {
            return self.ResolveCollectionInit(ne, typeName, args, ctx);
        }
        return IrExpr.IrNew(new IrNew(typeName, args, self.t.ClassRef(typeName)));
    }

    /*
     * ReportBadNew - The 'new' diagnostics, each naming what to write instead
     */
    void func ReportBadNew(NewExpr ne, String typeName, ResolveCtx ctx) {
        let String shown = self.mangler.DisplayName(typeName);
        let List[String] hints = new List[String]();

        if (self.sym.IsClass(typeName)) {
            self.diag.Error(Codes.NewOnNonClass(), ctx.file, ne.span,
                "'" + shown + "' is not in scope; import its module");
            return;
        }
        if (PrimTypes.IsPrim(typeName)) {
            self.diag.Error(Codes.NewOnNonClass(), ctx.file, ne.span,
                "'" + shown + "' is a primitive; use 'let', not 'new'");
            return;
        }
        if (self.sym.IsUnion(typeName)) {
            hints.Add("a union value is one of its variants; construct one by calling it, as '" +
                      shown + ".Variant(...)'");
            self.diag.Error(Codes.NewOnNonClass(), ctx.file, ne.span,
                "'" + shown + "' is a union and cannot be instantiated with 'new'", hints);
            return;
        }
        if (self.sym.IsEnum(typeName)) {
            hints.Add("an enum value is one of its members; name one directly, as '" + shown +
                      ".Member'");
            self.diag.Error(Codes.NewOnNonClass(), ctx.file, ne.span,
                "'" + shown + "' is an enum and cannot be instantiated with 'new'", hints);
            return;
        }

        let String bare = typeName;
        let bool generic = false;
        match (ne.type) {
            case NamedSpec(nn) { bare = nn.name; generic = nn.args.Length() > 0; }
            default { }
        }
        if (self.ReportNotVisible("type", bare, ctx.file, ne.span)) { return; }
        if (self.ReportWrongKind(Codes.NewOnNonClass(), generic ? "a generic type" : "a type",
                                 bare, ctx.file, ne.span)) { return; }
        self.diag.Error(Codes.NewOnNonClass(), ctx.file, ne.span, "'" + shown + "' is not a class");
    }

    /*
     * ResolveCollectionInit - 'new C() { a, b }', which needs a one-argument Add
     */
    IrExpr func ResolveCollectionInit(NewExpr ne, String typeName, List[IrExpr] ctorArgs,
                                      ResolveCtx ctx) {
        let IrType cls = self.t.ClassRef(typeName);
        match (self.sym.LookupMethod(typeName, "Add")) {
            case None {
                self.diag.Error(Codes.UndefinedMethod(), ctx.file, ne.span,
                    "'" + self.mangler.DisplayName(typeName) +
                    "' has no 'Add' method for a collection initializer");
                return IrExpr.IrNew(new IrNew(typeName, ctorArgs, cls));
            }
            case Some(add) {
                match (add.sig) {
                    case None {
                        self.diag.Error(Codes.UndefinedMethod(), ctx.file, ne.span,
                            "'" + self.mangler.DisplayName(typeName) +
                            "' has no 'Add' method for a collection initializer");
                        return IrExpr.IrNew(new IrNew(typeName, ctorArgs, cls));
                    }
                    case Some(g) {
                        if (g.params.Length() != 1) {
                            self.diag.Error(Codes.WrongArgCount(), ctx.file, ne.span,
                                "'" + self.mangler.DisplayName(typeName) + ".Add' must take exactly " +
                                "one argument to be used in a collection initializer");
                            return IrExpr.IrNew(new IrNew(typeName, ctorArgs, cls));
                        }
                        let IrType elemType = self.ResolveTypeSpec(g.params.Get(0).type);
                        let List[IrExpr] inits = new List[IrExpr]();
                        let int i = 0;
                        while (i < ne.collectionInit.Length()) {
                            let IrExpr r = self.Coerce(
                                self.ResolveExpr(ne.collectionInit.Get(i), ctx), elemType, ctx);
                            self.CheckAssign(r, elemType,
                                "a '" + self.mangler.DisplayName(typeName) + "' element", ctx,
                                Codes.ArgTypeMismatch());
                            self.ForbidNestedThrows(r, ctx, false);
                            inits.Add(r);
                            i = i + 1;
                        }
                        return IrExpr.IrNewInit(
                            new IrNewInit(typeName, ctorArgs, add.cName, inits, cls));
                    }
                }
            }
        }
    }

    /*
     * ResolveArrayLit - '[1, 2, 3]'. The element type is the FIRST element's; the rest must be
     * assignable to it, which is what makes '[]' with no elements an error rather than a guess.
     */
    IrExpr func ResolveArrayLit(ArrayLitExpr al, ResolveCtx ctx) {
        if (al.elems.Length() == 0) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, al.span,
                "empty array literal '[]' has no element type");
            return IrExpr.IrArrayLit(new IrArrayLit(self.Arr(self.t.Int(), 0), new List[IrExpr]()));
        }
        let List[IrExpr] elems = new List[IrExpr]();
        let int i = 0;
        while (i < al.elems.Length()) { elems.Add(self.ResolveExpr(al.elems.Get(i), ctx)); i = i + 1; }

        let IrType elemType = Exprs2.TypeOf(elems.Get(0));
        let int j = 1;
        while (j < elems.Length()) {
            elems.Set(j, self.Coerce(elems.Get(j), elemType, ctx));
            self.CheckAssign(elems.Get(j), elemType, "an array element", ctx, Codes.TypeMismatch());
            j = j + 1;
        }
        return IrExpr.IrArrayLit(new IrArrayLit(self.Arr(elemType, elems.Length()), elems));
    }

    /*
     * ResolveGenericTypeRef - Settles a 'Name[Args]' the parser could not.
     *
     * It is an INDEX when the name denotes a value, or names no type at all; a generic type
     * reference otherwise. Only the index path knows about fields needing 'self.' and near-miss
     * spellings, which are far commoner than a misplaced type name.
     */
    IrExpr func ResolveGenericTypeRef(GenericTypeRefExpr g, ResolveCtx ctx) {
        let bool isTemplate = self.mangler.IsGenericTemplate(g.name);
        let bool namesType = isTemplate || self.sym.IsUnion(Exprs.Mangled(g)) || self.sym.IsClass(Exprs.Mangled(g));

        match (g.indexForm) {
            case Some(ixf) {
                if (!namesType || IsSome(ctx.locals.Lookup(g.name))) {
                    return self.ResolveIndex(
                        new IndexExpr(Expr.IdentExpr(new IdentExpr(g.name, g.span)), ixf, g.span), ctx);
                }
            }
            case None { }
        }

        if (isTemplate) {
            let String written = Exprs.Written(g, self.mangler);
            let List[String] hints = new List[String]();
            hints.Add("to build one of its variants, call it: '" + written + ".SomeVariant(...)'");
            self.diag.Error(Codes.TypeMismatch(), ctx.file, g.span,
                "'" + written + "' is a type, not a value", hints);
        } else if (self.sym.IsUnion(g.name) || self.sym.IsClass(g.name) || self.sym.IsEnum(g.name)) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, g.span,
                "'" + g.name + "' is not generic, so it takes no type arguments");
        } else {
            self.diag.Error(Codes.UndefinedType(), ctx.file, g.span,
                "unknown generic type '" + g.name + "'");
        }
        return self.Poison(g.span);
    }

    /*
     * VariantIndex - The position of a named variant in a union, or -1
     */
    int func VariantIndex(List[UnionVariant] variants, String name) {
        let int i = 0;
        while (i < variants.Length()) {
            if (variants.Get(i).name == name) { return i; }
            i = i + 1;
        }
        return -1;
    }

    /*
     * ResolveUnionConstruct - 'U.Variant(args)' against a known union
     */
    IrExpr func ResolveUnionConstruct(String unionName, String variant, List[IrExpr] args,
                                      ResolveCtx ctx, TextSpan span) {
        let IrType ut = self.t.UnionType(unionName);
        match (self.sym.UnionDef(unionName)) {
            case None { return IrExpr.IrUnionConstruct(new IrUnionConstruct(ut, 0, args)); }
            case Some(variants) {
                let int idx = self.VariantIndex(variants, variant);
                if (idx < 0) {
                    self.diag.Error(Codes.UndefinedVariable(), ctx.file, span,
                        "union '" + unionName + "' has no variant '" + variant + "'");
                    return IrExpr.IrUnionConstruct(new IrUnionConstruct(ut, 0, args));
                }
                let List[Param] payload = variants.Get(idx).variantFields;
                if (payload.Length() != args.Length()) {
                    self.diag.Error(Codes.WrongArgCount(), ctx.file, span,
                        "'" + unionName + "." + variant + "' expects " +
                        Int.ToString(payload.Length()) + " argument(s), got " +
                        Int.ToString(args.Length()));
                }
                let int i = 0;
                while (i < args.Length() && i < payload.Length()) {
                    let IrType ft = self.ResolveTypeSpec(payload.Get(i).type);
                    args.Set(i, self.Coerce(args.Get(i), ft, ctx));
                    if (!self.Assignable(args.Get(i), ft)) {
                        self.diag.Error(Codes.ArgTypeMismatch(), ctx.file,
                            Exprs2.SpanOf(args.Get(i)),
                            "argument " + Int.ToString(i + 1) + " ('" +
                            self.Describe(Exprs2.TypeOf(args.Get(i))) +
                            "') is not assignable to '" + self.Describe(ft) + "'");
                    }
                    i = i + 1;
                }
                return IrExpr.IrUnionConstruct(new IrUnionConstruct(ut, idx, args));
            }
        }
    }

    /*
     * ResolveCall - Every call shape the language has, in the order they are tried.
     *
     * The order matters and is the language's, not an implementation detail: a local function
     * pointer shadows a free function of the same name, a file-local private function takes
     * priority over an imported public one, and a sibling method is only reached once nothing
     * free matched.
     */
    IrExpr func ResolveCall(CallExpr ce, ResolveCtx ctx) {
        // Arguments are resolved with the catch wrapping and expected type cleared: neither
        // applies to a nested call, and letting them through would type it by its surroundings
        let ResolveCtx argCtx = (ctx.catchWrapped || IsSome(ctx.expected)) ? ctx.NoCatchWrap() : ctx;
        let List[IrExpr] args = new List[IrExpr]();
        let int i = 0;
        while (i < ce.args.Length()) {
            let Expr a = ce.args.Get(i);
            match (a) {
                case RefArgExpr(ra) { args.Add(self.ResolveExpr(ra.target, argCtx)); }
                default { args.Add(self.ResolveExpr(a, argCtx)); }
            }
            i = i + 1;
        }

        match (ce.callee) {
            case MemberAccessExpr(ma) { return self.ResolveMemberCall(ce, ma, args, ctx); }
            case IdentExpr(id)        { return self.ResolveBareCall(ce, id, args, ctx); }
            default { }
        }

        // Anything else must evaluate to a function pointer
        let IrExpr calleeExpr = self.ResolveExpr(ce.callee, ctx);
        match (Exprs2.TypeOf(calleeExpr)) {
            case IrFuncPtrType(gfp) {
                return self.ResolveIndirectCallArgs(calleeExpr, gfp, args, ctx, ce.span, ce.args);
            }
            default { }
        }
        if (Types.IsError(Exprs2.TypeOf(calleeExpr))) { return self.Poison(ce.span); }
        self.diag.Error(Codes.TypeMismatch(), ctx.file, ce.span, "callee expression is not callable");
        return IrExpr.IrLitInt(new IrLitInt(0L, self.t.Int(), Optional[String].None()));
    }

    /*
     * ResolveMemberCall - 'x.M(...)', where x may be a value, a type name, a generic instance, or
     * an imported file's basename
     */
    IrExpr func ResolveMemberCall(CallExpr ce, MemberAccessExpr ma, List[IrExpr] args, ResolveCtx ctx) {
        // 'Maybe[int].Found(...)' - an explicitly instantiated generic
        match (ma.object) {
            case GenericTypeRefExpr(gt) {
                if (self.mangler.IsGenericTemplate(gt.name) &&
                    (IsNone(gt.indexForm) || IsNone(ctx.locals.Lookup(gt.name)))) {
                    if (self.sym.IsUnion(Exprs.Mangled(gt))) {
                        return self.ResolveUnionConstruct(Exprs.Mangled(gt), ma.member, args, ctx, ce.span);
                    }
                    if (self.ClassInScope(Exprs.Mangled(gt))) {
                        // Re-enter with the instance name in place of the written form
                        let MemberAccessExpr flat = new MemberAccessExpr(
                            Expr.IdentExpr(new IdentExpr(Exprs.Mangled(gt), gt.span)), ma.member, ma.span);
                        return self.ResolveMemberCall(ce, flat, args, ctx);
                    }
                    self.diag.Error(Codes.UndefinedType(), ctx.file, gt.span,
                        "'" + Exprs.Written(gt, self.mangler) + "' names no union or class, so it has no '" +
                        ma.member + "'");
                    return self.Poison(gt.span);
                }
            }
            default { }
        }

        let String objName = "";
        match (ma.object) { case IdentExpr(oid) { objName = oid.name; } default { } }
        let bool nameIsFree = objName.Length() > 0 && IsNone(ctx.locals.Lookup(objName));

        if (nameIsFree && self.sym.IsUnion(objName)) {
            return self.ResolveUnionConstruct(objName, ma.member, args, ctx, ce.span);
        }
        if (nameIsFree) {
            match (self.ResolveGenericUnionConstruct(objName, ma.member, args, ctx, ce.span)) {
                case Some(gu) { return gu; }
                case None { }
            }
        }

        // A class or module name: a static call
        if (nameIsFree && self.ClassInScope(objName)) {
            return self.ResolveStaticCall(ce, ma, objName, args, ctx);
        }

        // An in-scope file's basename: the escape hatch for a collision nothing else can qualify
        if (nameIsFree && !self.ClassInScope(objName)) {
            match (self.TryResolveFileNamespacedCall(objName, ma.member, args, ctx, ce)) {
                case Some(nsCall) { return nsCall; }
                case None { }
            }
        }

        // An ordinary instance call
        let IrExpr recv = self.ResolveExpr(ma.object, ctx);
        let String cls = self.ClassNameOf(Exprs2.TypeOf(recv));
        if (cls.Length() > 0) { return self.ResolveInstanceCall(ce, ma, cls, recv, args, ctx); }

        if (Types.IsError(Exprs2.TypeOf(recv))) { return self.Poison(ce.span); }
        self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
            "cannot call '" + ma.member + "' on '" + self.Describe(Exprs2.TypeOf(recv)) + "'");
        return IrExpr.IrInstanceCall(new IrInstanceCall(recv,
            self.mangler.FreeFunc(ma.member, new List[Param](), false, false, false),
            self.t.Error(), args));
    }

    /*
     * ResolveStaticCall - 'Type.M(...)' where Type is a class or module in scope
     */
    IrExpr func ResolveStaticCall(CallExpr ce, MemberAccessExpr ma, String objName,
                                  List[IrExpr] args, ResolveCtx ctx) {
        let String display = self.mangler.DisplayName(objName) + "." + ma.member;

        match (self.methodTemplates.Find(MemberKey(objName, ma.member))) {
            case Some(mtmpl) {
                // A template has no registered signature yet, so 'static' is assumed unless the
                // table says otherwise
                let bool tIsStatic = self.MethodIsStatic(objName, ma.member, true);
                if (!tIsStatic) {
                    self.diag.Error(Codes.StaticOnInstance(), ctx.file, ce.span,
                        "'" + display + "' is an instance method; call it on a value");
                }
                self.CheckMemberAccess(objName, ma.member, ctx, ce.span);
                return self.ResolveGenericMethodCall(mtmpl, objName, tIsStatic, args, ctx, ce.span,
                                                     Optional[IrExpr].None(), ce.args);
            }
            case None { }
        }

        let Optional[Symbol] msym = self.sym.LookupMethod(objName, ma.member);
        match (msym) {
            case None {
                // An opaque struct is C the compiler cannot see into, so an unknown method on one
                // is not reportable
                if (!self.IsOpaqueStruct(objName)) {
                    self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
                        "'" + self.mangler.DisplayName(objName) + "' has no method '" + ma.member + "'",
                        Suggest.Hints(ma.member, self.sym.MethodNames(objName)));
                    return self.Poison(ce.span);
                }
            }
            case Some(m) {
                match (m.sig) {
                    case Some(g) {
                        if (!g.isStatic) {
                            self.diag.Error(Codes.StaticOnInstance(), ctx.file, ce.span,
                                "'" + display + "' is an instance method; call it on a value");
                        }
                    }
                    case None { }
                }
            }
        }
        self.CheckMemberAccess(objName, ma.member, ctx, ce.span);
        return self.BuildCall(self.sym.MethodOverloads(objName, ma.member), msym, args, display,
            self.mangler.Method(objName, ma.member, new List[Param](), false),
            Optional[IrExpr].None(), ctx, ce);
    }

    /*
     * ResolveInstanceCall - 'value.M(...)' against the class the receiver's type names
     */
    IrExpr func ResolveInstanceCall(CallExpr ce, MemberAccessExpr ma, String cls, IrExpr recv,
                                    List[IrExpr] args, ResolveCtx ctx) {
        let String display = self.mangler.DisplayName(cls) + "." + ma.member;

        match (self.methodTemplates.Find(MemberKey(cls, ma.member))) {
            case Some(imtmpl) {
                let bool iIsStatic = self.MethodIsStatic(cls, ma.member, false);
                if (iIsStatic) {
                    self.diag.Error(Codes.InstanceOnStatic(), ctx.file, ce.span,
                        "'" + display + "' is static; call it as '" + display + "(...)'");
                }
                self.CheckMemberAccess(cls, ma.member, ctx, ce.span);
                return self.ResolveGenericMethodCall(imtmpl, cls, iIsStatic, args, ctx, ce.span,
                                                     Optional.Some(recv), ce.args);
            }
            case None { }
        }

        let Optional[Symbol] msym = self.sym.LookupMethod(cls, ma.member);
        match (msym) {
            case None {
                // A field holding a function pointer, used as a callback
                match (self.sym.FieldType(cls, ma.member)) {
                    case Some(cbt) {
                        match (self.ResolveTypeSpec(cbt)) {
                            case IrFuncPtrType(cbfp) {
                                self.CheckMemberAccess(cls, ma.member, ctx, ce.span);
                                let IrExpr load = IrExpr.IrFieldLoad(
                                    new IrFieldLoad(recv, ma.member, self.ResolveTypeSpec(cbt)));
                                return self.ResolveIndirectCallArgs(load, cbfp, args, ctx, ce.span,
                                                                    ce.args);
                            }
                            default { }
                        }
                    }
                    case None { }
                }
                if (!self.IsOpaqueStruct(cls)) {
                    self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
                        "'" + self.mangler.DisplayName(cls) + "' has no method '" + ma.member + "'",
                        Suggest.Hints(ma.member, self.sym.MethodNames(cls)));
                    return self.Poison(ce.span);
                }
            }
            case Some(m) {
                match (m.sig) {
                    case Some(g) {
                        if (g.isStatic) {
                            self.diag.Error(Codes.InstanceOnStatic(), ctx.file, ce.span,
                                "'" + display + "' is static; call it as '" + display + "(...)'");
                        }
                    }
                    case None { }
                }
            }
        }
        self.CheckMemberAccess(cls, ma.member, ctx, ce.span);
        return self.BuildCall(self.sym.MethodOverloads(cls, ma.member), msym, args, display,
            self.mangler.Method(cls, ma.member, new List[Param](), false),
            Optional.Some(recv), ctx, ce);
    }

    /*
     * MethodIsStatic - Whether a method is static, falling back for a template the table has not
     * registered a signature for
     */
    bool func MethodIsStatic(String cls, String name, bool fallback) {
        match (self.sym.LookupMethod(cls, name)) {
            case Some(m) {
                match (m.sig) { case Some(g) { return g.isStatic; } case None { return fallback; } }
            }
            case None { return fallback; }
        }
    }

    /*
     * ResolveBareCall - 'f(...)' with no receiver
     */
    IrExpr func ResolveBareCall(CallExpr ce, IdentExpr id, List[IrExpr] args, ResolveCtx ctx) {
        // A local holding a function pointer shadows any free function of the same name
        match (ctx.locals.Lookup(id.name)) {
            case Some(lt) {
                match (lt) {
                    case IrFuncPtrType(localFp) {
                        let IrExpr v = IrExpr.IrVar(
                            new IrVar(id.name, lt, ctx.locals.IsRef(id.name)));
                        return self.ResolveIndirectCallArgs(v, localFp, args, ctx, ce.span, ce.args);
                    }
                    default { }
                }
            }
            case None { }
        }

        match (self.processState.Find(id.name)) {
            case Some(calleeState) {
                match (Exprs2.TypeOf(calleeState)) {
                    case IrFuncPtrType(stateFp) {
                        self.ReportPendingProcessState(id.name, ctx, ce.span);
                        return self.ResolveIndirectCallArgs(calleeState, stateFp, args, ctx,
                                                            ce.span, ce.args);
                    }
                    default { }
                }
            }
            case None { }
        }

        match (self.TryResolveArcIntrinsic(id.name, args, ctx, ce.span)) {
            case Some(arc) { return arc; }
            case None { }
        }

        // A generic free function template
        let List[String] colliding = new List[String]();
        match (self.ResolveFuncTemplate(id.name, ctx.file, colliding)) {
            case Some(tmpl) { return self.ResolveTemplateCall(ce, id, args, ctx, tmpl, colliding); }
            case None { }
        }

        // A file-local private function takes priority over an imported public one
        match (self.sym.LookupPrivateFunc(ctx.file, id.name)) {
            case Some(pfsym) {
                return self.BuildCall(self.sym.PrivateFuncOverloads(ctx.file, id.name),
                    Optional.Some(pfsym), args, id.name,
                    self.mangler.PrivateFreeFunc(Mangle.FileToken(ctx.file), id.name,
                                                 new List[Param](), false),
                    Optional[IrExpr].None(), ctx, ce);
            }
            case None { }
        }

        let Optional[Symbol] fsym = self.LookupFreeFuncVisible(id.name);
        if (self.FuncInScope(fsym)) {
            match (fsym) {
                case Some(f) {
                    match (f.sig) {
                        case Some(g) {
                            if (g.isEntry) {
                                self.diag.Error(Codes.CallToEntry(), ctx.file, ce.span,
                                    "'" + id.name + "' is an entry point and cannot be called directly");
                            }
                        }
                        case None { }
                    }
                    return self.BuildCall(self.sym.FuncOverloads(id.name), fsym, args, id.name,
                        self.mangler.FreeFunc(id.name, new List[Param](), false, false, false),
                        Optional[IrExpr].None(), ctx, ce);
                }
                case None { }
            }
        }

        // A sibling method of the enclosing class
        if (ctx.curClass.Length() > 0) {
            match (self.ResolveSiblingCall(ce, id, args, ctx)) {
                case Some(r) { return r; }
                case None { }
            }
        }

        return self.ReportUncallable(ce, id, args, ctx);
    }

    /*
     * ResolveSiblingCall - A method of the enclosing class called without a receiver. An instance
     * method needs one, and the error says exactly what to write.
     */
    Optional[IrExpr] func ResolveSiblingCall(CallExpr ce, IdentExpr id, List[IrExpr] args,
                                             ResolveCtx ctx) {
        let String cls = ctx.curClass;
        let String display = self.mangler.DisplayName(cls) + "." + id.name;

        match (self.methodTemplates.Find(MemberKey(cls, id.name))) {
            case Some(smtmpl) {
                let bool sIsStatic = self.MethodIsStatic(cls, id.name, true);
                if (!sIsStatic) {
                    self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
                        "'" + id.name + "' is an instance method; call it as 'self." + id.name + "(...)'");
                    let IrExpr slf = IrExpr.IrSelfExpr(new IrSelfExpr(cls, self.t.ClassRef(cls)));
                    return Optional.Some(self.ResolveGenericMethodCall(smtmpl, cls, false, args, ctx,
                        ce.span, Optional.Some(slf), ce.args));
                }
                return Optional.Some(self.ResolveGenericMethodCall(smtmpl, cls, true, args, ctx,
                    ce.span, Optional[IrExpr].None(), ce.args));
            }
            case None { }
        }

        match (self.sym.LookupMethod(cls, id.name)) {
            case None { return Optional[IrExpr].None(); }
            case Some(msym) {
                let bool isStatic = false;
                match (msym.sig) { case Some(g) { isStatic = g.isStatic; } case None { } }

                if (!isStatic) {
                    // Still resolved, so the arguments are checked and one error is reported
                    let Optional[Symbol] ichosen = self.ChooseOverload(
                        self.sym.MethodOverloads(cls, id.name), Optional.Some(msym), args,
                        display, ctx, ce.span);
                    self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
                        "'" + id.name + "' is an instance method; call it as 'self." + id.name + "(...)'");
                    self.CoerceArgs(args, self.SigOf(ichosen), ctx, ce.args);
                    let String cn = self.mangler.Method(cls, id.name, new List[Param](), false);
                    let IrType ret = self.t.Void();
                    match (ichosen) {
                        case Some(c) { cn = c.cName; ret = self.ResolveType(c.type); }
                        case None { }
                    }
                    let IrExpr slf = IrExpr.IrSelfExpr(new IrSelfExpr(cls, self.t.ClassRef(cls)));
                    return Optional.Some(IrExpr.IrInstanceCall(
                        new IrInstanceCall(slf, cn, ret, args)));
                }
                return Optional.Some(self.BuildCall(self.sym.MethodOverloads(cls, id.name),
                    Optional.Some(msym), args, display,
                    self.mangler.Method(cls, id.name, new List[Param](), false),
                    Optional[IrExpr].None(), ctx, ce));
            }
        }
    }

    /*
     * ReportUncallable - The end of the bare-call chain: nothing callable answers to this name,
     * and the message says which of the several reasons applies
     */
    IrExpr func ReportUncallable(CallExpr ce, IdentExpr id, List[IrExpr] args, ResolveCtx ctx) {
        let String fallback = self.mangler.FreeFunc(id.name, new List[Param](), false, false, false);

        match (ctx.locals.Lookup(id.name)) {
            case Some(shadowing) {
                let List[String] hints = new List[String]();
                hints.Add("only a function, or a variable of function-pointer type, can be called");
                hints.Add("a callable variable is declared as 'let func(<params>) -> <ret> " +
                          id.name + " = ...;'");
                self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
                    "'" + id.name + "' is a '" + self.Describe(shadowing) + "', which cannot be called",
                    hints);
                return IrExpr.IrStaticCall(new IrStaticCall(fallback, self.t.Error(), args));
            }
            case None { }
        }

        match (self.processState.Find(id.name)) {
            case Some(stateVar) {
                let List[String] hints = new List[String]();
                hints.Add("only a function, or a variable of function-pointer type, can be called");
                self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
                    "process variable '" + self.LastSegment(self.mangler.DisplayName(id.name)) +
                    "' is a '" + self.Describe(Exprs2.TypeOf(stateVar)) + "', which cannot be called",
                    hints);
                return IrExpr.IrStaticCall(new IrStaticCall(fallback, self.t.Error(), args));
            }
            case None { }
        }

        if (IsSome(self.sym.LookupFreeFunc(id.name))) {
            self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
                "'" + id.name + "' is not in scope; import its module");
        } else if (!self.ReportNotVisible("function", id.name, ctx.file, ce.span) &&
                   !self.ReportWrongKind(Codes.UndefinedMethod(), "a function", id.name,
                                         ctx.file, ce.span)) {
            self.diag.Error(Codes.UndefinedMethod(), ctx.file, ce.span,
                "call to undefined function '" + id.name + "'");
        }
        return IrExpr.IrStaticCall(new IrStaticCall(fallback, self.t.Error(), args));
    }

    /*
     * LastSegment - The part of a dotted name after the final dot
     */
    String func LastSegment(String s) {
        let int dot = s.LastIndexOf(".");
        return dot < 0 ? s : s.Substring(dot + 1, s.Length() - dot - 1);
    }

    /*
     * ResolveIndirectCallArgs - A call through a function pointer, checked against the signature
     * the pointer's type carries. 'ref' cannot travel through one - the type cannot say which
     * parameters are by reference.
     */
    IrExpr func ResolveIndirectCallArgs(IrExpr target, IrFuncPtrType fpt, List[IrExpr] args,
                                        ResolveCtx ctx, TextSpan span, List[Expr] astArgs) {
        if (args.Length() != fpt.params.Length()) {
            self.diag.Error(Codes.WrongArgCount(), ctx.file, span,
                "function pointer expects " + Int.ToString(fpt.params.Length()) +
                " argument(s), got " + Int.ToString(args.Length()));
        }
        let int i = 0;
        while (i < args.Length() && i < fpt.params.Length()) {
            let IrType pt = fpt.params.Get(i);
            args.Set(i, self.Coerce(args.Get(i), pt, ctx));
            self.CheckAssign(args.Get(i), pt, "argument " + Int.ToString(i + 1), ctx,
                             Codes.ArgTypeMismatch());
            if (i < astArgs.Length()) {
                match (astArgs.Get(i)) {
                    case RefArgExpr(x) {
                        self.diag.Error(Codes.RefArgMismatch(), ctx.file, Exprs.Span(astArgs.Get(i)),
                            "indirect call through a function pointer does not support 'ref' arguments");
                    }
                    default { }
                }
            }
            i = i + 1;
        }
        return IrExpr.IrIndirectCall(new IrIndirectCall(target, fpt.ret, args));
    }

    /*
     * ReportPendingProcessState - Reports a read of a process variable whose initialiser has not
     * run yet. Initialisers run in DECLARATION ORDER, so only the ones above have a value.
     */
    void func ReportPendingProcessState(String qualified, ResolveCtx ctx, TextSpan span) {
        match (self.processStatePending.Find(qualified)) {
            case None { }
            case Some(written) {
                let bool itself = qualified == self.processStateCurrent;
                let List[String] hints = new List[String]();
                if (itself) {
                    hints.Add("it holds nothing yet: the read happens as part of the store that " +
                              "gives it a value");
                    hints.Add("give it a value that does not depend on itself");
                } else {
                    hints.Add("a process's variables are initialised in declaration order, so only " +
                              "the ones declared above this line have a value yet");
                    hints.Add("move the declaration of '" + written + "' above the one that reads it");
                }
                self.diag.Error(Codes.UseBeforeAssignment(), ctx.file, span,
                    itself
                        ? "process variable '" + written + "' is read by its own initialiser"
                        : "process variable '" + written + "' is read before it is initialised",
                    hints);
            }
        }
    }

    /*
     * TryResolveArcIntrinsic - Recognises a bare call to the retain/release intrinsics.
     *
     * These are not ordinary calls: they need unsafe, and a union dispatches to its own generated
     * retain/release rather than the class one. A value that is not managed at all needs no
     * counting, so retain hands the value straight back and release becomes a cast to void.
     */
    Optional[IrExpr] func TryResolveArcIntrinsic(String name, List[IrExpr] args, ResolveCtx ctx,
                                                 TextSpan span) {
        let Optional[Symbol] fsym = self.LookupFreeFuncVisible(name);
        if (!self.FuncInScope(fsym)) { return Optional[IrExpr].None(); }
        match (fsym) {
            case None { return Optional[IrExpr].None(); }
            case Some(f) {
                let bool isRetain = self.IntrinsicIs(Roles.Retain(), f.cName);
                let bool isRelease = self.IntrinsicIs(Roles.Release(), f.cName);
                if (!isRetain && !isRelease) { return Optional[IrExpr].None(); }

                if (!ctx.inUnsafe) {
                    self.diag.Error(Codes.UnsafeRequired(), ctx.file, span,
                        "'" + name + "' requires an 'unsafe' block");
                }
                if (args.Length() != 1) {
                    self.diag.Error(Codes.WrongArgCount(), ctx.file, span,
                        "'" + name + "' expects 1 argument, got " + Int.ToString(args.Length()));
                    return Optional.Some(IrExpr.IrLitInt(
                        new IrLitInt(0L, self.t.Int(), Optional[String].None())));
                }

                let IrExpr a = args.Get(0);
                let IrType at = Exprs2.TypeOf(a);
                if (!self.IsManagedRef(at)) {
                    // Nothing to count: retain is the identity, release is a discard
                    if (isRetain) { return Optional.Some(a); }
                    return Optional.Some(IrExpr.IrCast(new IrCast(self.t.Void(), a)));
                }

                let String cname = f.cName;
                match (at) {
                    case IrUnionType(ut) {
                        cname = isRetain ? self.mangler.UnionRetain(ut.name)
                                         : self.mangler.UnionRelease(ut.name);
                    }
                    default { }
                }
                return Optional.Some(IrExpr.IrStaticCall(
                    new IrStaticCall(cname, isRetain ? at : self.t.Void(), self.OneArg(a))));
            }
        }
    }

    /*
     * IntrinsicIs - True when a role is bound to exactly this C name
     */
    bool func IntrinsicIs(String role, String cName) {
        match (self.sym.IntrinsicOrNull(role)) {
            case Some(n) { return n == cName; }
            case None { return false; }
        }
    }

    /*
     * WarnOnUnionComparison - The two ways a union comparison can mean something other than "these
     * hold the same value". Worth saying only because the comparison is GENERATED - nobody wrote
     * the identity check the payload gets. Reported at the comparison, so a union nobody compares
     * stays silent.
     */
    void func WarnOnUnionComparison(String unionName, ResolveCtx ctx, TextSpan span) {
        let List[String] identity = new List[String]();
        let List[String] imprecise = new List[String]();
        self.CollectComparisonHazards(unionName, "", new StringSet(), identity, imprecise);

        if (identity.Length() > 0) {
            let List[String] hints = new List[String]();
            hints.Add("two separately built payloads will differ even when they hold the same data");
            hints.Add("declare an '==' operator on the payload class to compare it by value");
            self.diag.Warn(Codes.IdentityPayloadComparison(), ctx.file, span,
                "comparing '" + unionName + "' compares " + self.DescribeFields(identity) +
                " by identity, not by value", hints);
        }
        if (imprecise.Length() > 0) {
            let List[String] hints = new List[String]();
            hints.Add("values produced by different arithmetic rarely compare equal; compare with " +
                      "a tolerance instead");
            self.diag.Warn(Codes.ImprecisePayloadComparison(), ctx.file, span,
                "comparing '" + unionName + "' compares " + self.DescribeFields(imprecise) +
                " with floating-point '=='", hints);
        }
    }

    /*
     * DescribeFields - A field list for the union-comparison warnings, capped at three so a wide
     * union does not print a paragraph
     */
    String func DescribeFields(List[String] names) {
        if (names.Length() == 1) { return "variant field " + names.Get(0); }
        let List[String] head = new List[String]();
        let int i = 0;
        while (i < names.Length() && i < 3) { head.Add(names.Get(i)); i = i + 1; }
        let String s = "variant fields " + String.Join(head, ", ");
        if (names.Length() > 3) {
            s = s + " and " + Int.ToString(names.Length() - 3) + " more";
        }
        return s;
    }

    /*
     * CollectComparisonHazards - The fields whose generated comparison is by identity or by
     * floating point, through nested unions and arrays.
     *
     * The qualifier reports a nested field as 'Mixed.Ident.p', since 'Ident.p' would point at the
     * wrong declaration.
     */
    void func CollectComparisonHazards(String unionName, String qualifier, StringSet visiting,
                                       List[String] identity, List[String] imprecise) {
        if (!visiting.AddNew(unionName)) { return; }
        match (self.sym.UnionDef(unionName)) {
            case None { visiting.Remove(unionName); return; }
            case Some(variants) {
                let int i = 0;
                while (i < variants.Length()) {
                    let UnionVariant v = variants.Get(i);
                    let int j = 0;
                    while (j < v.variantFields.Length()) {
                        let Param f = v.variantFields.Get(j);
                        self.InspectHazard(self.ResolveTypeSpec(f.type),
                            "'" + qualifier + v.name + "." + f.name + "'",
                            qualifier, visiting, identity, imprecise);
                        j = j + 1;
                    }
                    i = i + 1;
                }
            }
        }
        visiting.Remove(unionName);
    }

    /*
     * InspectHazard - One field's type, for CollectComparisonHazards
     */
    void func InspectHazard(IrType ty, String label, String qualifier, StringSet visiting,
                            List[String] identity, List[String] imprecise) {
        match (ty) {
            case IrArrayType(a) {
                self.InspectHazard(a.elem, label, qualifier, visiting, identity, imprecise);
            }
            case IrUnionType(nested) {
                self.CollectComparisonHazards(nested.name, qualifier + nested.name + ".",
                                              visiting, identity, imprecise);
            }
            case IrClassRef(cr) {
                if (!self.sym.IsClass(cr.className) || self.sym.modules.Has(cr.className)) { return; }
                // A stamped generic instance is exempt: the author never wrote the payload type,
                // so telling them to add an '==' to it names a declaration they do not have
                if (IsSome(self.sym.LookupOperator(cr.className, "==", 1))) { return; }
                if (IsSome(self.mangler.TryGetGenericInstance(cr.className))) { return; }
                identity.Add(label + " (" + self.mangler.DisplayName(cr.className) + ")");
            }
            case IrPrimType(p) {
                if (PrimTypes.IsFloat(p.cName)) { imprecise.Add(label + " (" + p.cName + ")"); }
            }
            default { }
        }
    }

    /*
     * ResolveCatchCall - 'f() catch { ... }'. The handler runs in a context where 'assign' is
     * legal and must supply the call's success type.
     */
    IrExpr func ResolveCatchCall(CatchCallExpr cce, ResolveCtx ctx) {
        // The call is resolved as HANDLED, which is what stops it also reporting G021
        let IrExpr call = self.ResolveExpr(cce.call, ctx.WithCatchWrapped());

        let IrType inner = self.t.Void();
        match (Exprs2.TypeOf(call)) {
            case IrResultType(rt) { inner = rt.inner; }
            default {
                let List[String] hints = new List[String]();
                hints.Add("remove the catch block");
                self.diag.Error(Codes.ThrowsOutsideTry(), ctx.file, cce.span,
                    "this call cannot fail, so it has nothing to catch", hints);
            }
        }

        // The handler's RETURN type is the enclosing function's, not the caught call's. A 'return;'
        // inside a handler leaves the function, so it is checked against what that function
        // promised - passing 'inner' here checks it against the value the call would have produced,
        // which rejects every correct handler in a void function.
        let IrType outerRet = self.t.Void();
        match (ctx.retType) { case Some(r) { outerRet = r; } case None { } }

        let ResolveCtx hctx = ctx.WithCatchHandler(inner).PushScope(false);
        let IrBlock handler = self.ResolveBlock(cce.handler, hctx, outerRet);
        return IrExpr.IrCatchCall(new IrCatchCall(call, handler, inner));
    }

    /* ---------------------------------------------------------------------------------------
     * Generic functions and methods: inferring the arguments, stamping the instance
     * ------------------------------------------------------------------------------------ */

    /*
     * ResolveFuncTemplate - The generic free-function template a bare call resolves to. An
     * own-file private template always wins; otherwise the first in-scope public one, and any
     * further ones are reported through collidingFiles.
     */
    Optional[FuncTemplate] func ResolveFuncTemplate(String name, String ctxFile,
                                                    List[String] collidingFiles) {
        match (self.funcTemplates.Find(name)) {
            case None { return Optional[FuncTemplate].None(); }
            case Some(bucket) {
                if (bucket.Length() == 0) { return Optional[FuncTemplate].None(); }

                let int i = 0;
                while (i < bucket.Length()) {
                    let FuncTemplate e = bucket.Get(i);
                    if (e.isPrivate && e.file == ctxFile) { return Optional.Some(e); }
                    i = i + 1;
                }

                let List[FuncTemplate] publicInScope = new List[FuncTemplate]();
                let StringSet files = new StringSet();
                let int j = 0;
                while (j < bucket.Length()) {
                    let FuncTemplate e = bucket.Get(j);
                    if (!e.isPrivate && self.scope.Has(e.file)) {
                        publicInScope.Add(e);
                        if (files.AddNew(e.file)) { collidingFiles.Add(e.file); }
                    }
                    j = j + 1;
                }
                if (publicInScope.Length() == 0) {
                    collidingFiles.Clear();
                    return Optional[FuncTemplate].None();
                }
                if (collidingFiles.Length() <= 1) { collidingFiles.Clear(); }
                return Optional.Some(publicInScope.Get(0));
            }
        }
    }

    /*
     * ResolveTemplateCall - A bare call that reached a generic template. Ambiguity is reported
     * before stamping, because a call that could mean two things must not silently pick one.
     */
    IrExpr func ResolveTemplateCall(CallExpr ce, IdentExpr id, List[IrExpr] args, ResolveCtx ctx,
                                    FuncTemplate tmpl, List[String] collidingFiles) {
        let String fallback = self.mangler.FreeFunc(id.name, new List[Param](), false, false, false);

        if (collidingFiles.Length() > 1) {
            let List[String] bases = new List[String]();
            let int i = 0;
            while (i < collidingFiles.Length()) {
                bases.Add(FileStem(collidingFiles.Get(i)));
                i = i + 1;
            }
            self.diag.Error(Codes.AmbiguousCall(), ctx.file, ce.span,
                "'" + id.name + "' is ambiguous: a public generic function named '" + id.name +
                "' is declared in more than one imported file (" + String.Join(bases, ", ") +
                "); qualify with '<FileName>." + id.name + "(...)'");
            return IrExpr.IrStaticCall(new IrStaticCall(fallback, self.t.Void(), args));
        }

        // A template competing with an ordinary function or a method of the same name
        let Optional[Symbol] otherPf = self.sym.LookupPrivateFunc(ctx.file, id.name);
        let Optional[Symbol] otherFsym = self.LookupFreeFuncVisible(id.name);
        let bool otherFsymInScope = self.FuncInScope(otherFsym);
        let bool hasMethodCandidate = ctx.curClass.Length() > 0 &&
            (IsSome(self.sym.LookupMethod(ctx.curClass, id.name)) ||
             self.methodTemplates.Has(MemberKey(ctx.curClass, id.name)));

        if (IsSome(otherPf) || otherFsymInScope || hasMethodCandidate) {
            let String otherDesc = "";
            if (IsSome(otherPf)) {
                otherDesc = "a private free function in '" + FileStem(ctx.file) + "'";
            } else if (otherFsymInScope) {
                let String mod = "";
                match (otherFsym) { case Some(f) { mod = f.declFile; } case None { } }
                otherDesc = "a free function in '" + FileStem(mod) + "'";
            } else {
                otherDesc = "a method of '" + self.mangler.DisplayName(ctx.curClass) + "'";
            }
            let String extra = hasMethodCandidate
                ? ", 'self." + id.name + "(...)', or '" + self.mangler.DisplayName(ctx.curClass) +
                  "." + id.name + "(...)' as appropriate"
                : "";
            self.diag.Error(Codes.AmbiguousCall(), ctx.file, ce.span,
                "'" + id.name + "' is ambiguous between the generic function declared in '" +
                FileStem(tmpl.file) + "' and " + otherDesc + "; qualify with '" +
                FileStem(tmpl.file) + "." + id.name + "(...)'" + extra);
            return IrExpr.IrStaticCall(new IrStaticCall(fallback, self.t.Void(), args));
        }

        return self.ResolveGenericCall(tmpl, args, ctx, ce.span, ce.args);
    }

    /*
     * TryResolveFileNamespacedCall - 'file.name(...)' where 'file' is an in-scope file's basename.
     * The escape hatch for a collision that cannot be qualified through a class or a module, and
     * the way a file reaches past its own local function to the imported one it displaced.
     */
    Optional[IrExpr] func TryResolveFileNamespacedCall(String ns, String name, List[IrExpr] args,
                                                       ResolveCtx ctx, CallExpr ce) {
        match (self.funcTemplates.Find(name)) {
            case Some(bucket) {
                let int i = 0;
                while (i < bucket.Length()) {
                    let FuncTemplate e = bucket.Get(i);
                    if (FileStem(e.file) == ns &&
                        (e.file == ctx.file || (!e.isPrivate && self.scope.Has(e.file)))) {
                        return Optional.Some(self.ResolveGenericCall(e, args, ctx, ce.span, ce.args));
                    }
                    i = i + 1;
                }
            }
            case None { }
        }

        match (self.sym.LookupPrivateFunc(ctx.file, name)) {
            case Some(priv) {
                if (FileStem(ctx.file) == ns) {
                    return Optional.Some(self.BuildCall(
                        self.sym.PrivateFuncOverloads(ctx.file, name), Optional.Some(priv), args,
                        name,
                        self.mangler.PrivateFreeFunc(Mangle.FileToken(ctx.file), name,
                                                     new List[Param](), false),
                        Optional[IrExpr].None(), ctx, ce));
                }
            }
            case None { }
        }

        let Optional[Symbol] fsym = self.LookupFreeFuncVisible(name);
        match (fsym) {
            case Some(f) {
                if (FileStem(f.declFile) == ns && self.scope.Has(f.declFile)) {
                    return Optional.Some(self.BuildCall(self.sym.FuncOverloads(name), fsym, args,
                        name,
                        self.mangler.FreeFunc(name, new List[Param](), false, false, false),
                        Optional[IrExpr].None(), ctx, ce));
                }
            }
            case None { }
        }
        return Optional[IrExpr].None();
    }

    /*
     * AnyUnbindableArg - True when an argument's type cannot take part in inference: a Result from
     * an unhandled throwing call, or a type that is already an error
     */
    bool func AnyUnbindableArg(List[IrExpr] args) {
        let int i = 0;
        while (i < args.Length()) {
            let IrType ty = Exprs2.TypeOf(args.Get(i));
            match (ty) { case IrResultType(r) { return true; } default { } }
            if (Types.IsError(ty)) { return true; }
            i = i + 1;
        }
        return false;
    }

    /*
     * InferBinds - Binds each type parameter from the argument types, reporting a conflict.
     * Returns the names that could not be inferred at all.
     */
    List[String] func InferBinds(List[Param] ps, List[String] gparams, List[IrExpr] args,
                                 StringMap[TypeSpec] binds, String what, ResolveCtx ctx,
                                 TextSpan span) {
        let int i = 0;
        while (i < ps.Length() && i < args.Length()) {
            if (!UnifyParam(ps.Get(i).type, Exprs2.TypeOf(args.Get(i)), gparams, binds,
                            self.mangler)) {
                self.diag.Error(Codes.ArgTypeMismatch(), ctx.file, span,
                    "in call to generic '" + what + "', argument " + Int.ToString(i + 1) + " ('" +
                    self.Describe(Exprs2.TypeOf(args.Get(i))) +
                    "') conflicts with an earlier binding of the same type parameter");
            }
            i = i + 1;
        }
        let List[String] missing = new List[String]();
        let int j = 0;
        while (j < gparams.Length()) {
            if (!binds.Has(gparams.Get(j))) { missing.Add("'" + gparams.Get(j) + "'"); }
            j = j + 1;
        }
        return missing;
    }

    /*
     * MangledInstance - The instance name a set of bindings produces
     */
    String func MangledInstance(String base, List[String] gparams, StringMap[TypeSpec] binds) {
        let List[String] argNames = new List[String]();
        let int i = 0;
        while (i < gparams.Length()) {
            match (binds.Find(gparams.Get(i))) {
                case Some(ts) { argNames.Add(SanitizeTypeName(ts)); }
                case None { argNames.Add("int"); }
            }
            i = i + 1;
        }
        return self.mangler.GenericInstance(base, argNames);
    }

    /*
     * SubCtxOf - The substitution context a set of bindings defines
     */
    SubstitutionContext func SubCtxOf(StringMap[TypeSpec] binds) {
        let StringMap[String] cMap = new StringMap[String]();
        let List[String] keys = binds.Keys();
        let int i = 0;
        while (i < keys.Length()) {
            match (binds.Find(keys.Get(i))) {
                case Some(ts) { cMap.Put(keys.Get(i), CTypeOf(ts, self.mangler)); }
                case None { }
            }
            i = i + 1;
        }
        return new SubstitutionContext(binds, cMap);
    }

    /*
     * ResolveGenericCall - A call to a generic free function: infer the type arguments, mangle the
     * instance name, queue it for stamping, and build the call to the name it will be emitted
     * under
     */
    IrExpr func ResolveGenericCall(FuncTemplate tm, List[IrExpr] args, ResolveCtx ctx,
                                   TextSpan span, List[Expr] astArgs) {
        let FuncDecl fd = tm.decl;
        let String fallback = self.mangler.FreeFunc(fd.name, new List[Param](), false, false, false);

        if (fd.params.Length() != args.Length()) {
            self.diag.Error(Codes.WrongArgCount(), ctx.file, span,
                "generic '" + fd.name + "' expects " + Int.ToString(fd.params.Length()) +
                " argument(s), got " + Int.ToString(args.Length()));
            return IrExpr.IrStaticCall(new IrStaticCall(fallback, self.t.Void(), args));
        }
        if (self.AnyUnbindableArg(args)) {
            return IrExpr.IrStaticCall(new IrStaticCall(fallback, self.t.Error(), args));
        }

        let StringMap[TypeSpec] binds = new StringMap[TypeSpec]();
        let List[String] missing = self.InferBinds(fd.params, fd.genericParams, args, binds,
                                                   fd.name, ctx, span);
        if (missing.Length() > 0) {
            self.diag.Error(Codes.UndefinedType(), ctx.file, span,
                "cannot infer type argument " + String.Join(missing, ", ") + " for generic '" +
                fd.name + "' from its arguments");
            return IrExpr.IrStaticCall(new IrStaticCall(fallback, self.t.Void(), args));
        }

        let String mangled = self.MangledInstance(fd.name, fd.genericParams, binds);
        self.usedFuncTemplates.AddNew(MemberKey(tm.file, fd.name));
        if (self.genericSeen.AddNew(mangled)) {
            self.genericQueue.Add(new GenericJob(fd, tm.file, tm.realmKind, binds, mangled,
                                                 self.scope));
        }

        let SubstitutionContext sctx = self.SubCtxOf(binds);
        let List[Param] concreteParams = SubParams(fd.params, sctx);
        let bool isPrivate = Mods.Has(fd.modifiers, Modifiers.Private);
        let String cname = isPrivate
            ? self.mangler.PrivateFreeFunc(Mangle.FileToken(tm.file), mangled, concreteParams,
                  self.sym.PrivateFuncOverloads(tm.file, mangled).Length() > 1)
            : self.mangler.FreeFunc(mangled, concreteParams, false, false, false);

        let IrType ret = self.ResolveType(SubOptType(fd.returnType, sctx));
        self.CoerceArgs(args, Optional.Some(new MethodSig(fd.returnType, concreteParams, true,
            fd.isThrows, false, fd.annotations, false)), ctx, astArgs);

        if (fd.isThrows) {
            self.CheckThrowsHandled(ctx, span);
            return IrExpr.IrThrowsCall(new IrThrowsCall(cname, ret, self.t.Result(ret), args));
        }
        return IrExpr.IrStaticCall(new IrStaticCall(cname, ret, args));
    }

    /*
     * ResolveGenericMethodCall - The same for a generic method, static or instance, on a class or
     * a module
     */
    IrExpr func ResolveGenericMethodCall(MethodTemplate tm, String owner, bool isStatic,
                                         List[IrExpr] args, ResolveCtx ctx, TextSpan span,
                                         Optional[IrExpr] recv, List[Expr] astArgs) {
        let MethodDecl md = tm.decl;
        let String fallback = self.mangler.Method(owner, md.name, new List[Param](), false);
        let String display = self.mangler.DisplayName(owner) + "." + md.name;

        if (md.params.Length() != args.Length()) {
            self.diag.Error(Codes.WrongArgCount(), ctx.file, span,
                "generic '" + display + "' expects " + Int.ToString(md.params.Length()) +
                " argument(s), got " + Int.ToString(args.Length()));
            return self.CallOrInstance(recv, fallback, self.t.Void(), args);
        }
        if (self.AnyUnbindableArg(args)) {
            return self.CallOrInstance(recv, fallback, self.t.Void(), args);
        }

        let StringMap[TypeSpec] binds = new StringMap[TypeSpec]();
        let List[String] missing = self.InferBinds(md.params, md.genericParams, args, binds,
                                                   display, ctx, span);
        if (missing.Length() > 0) {
            self.diag.Error(Codes.UndefinedType(), ctx.file, span,
                "cannot infer type argument " + String.Join(missing, ", ") + " for generic '" +
                display + "' from its arguments");
            return self.CallOrInstance(recv, fallback, self.t.Void(), args);
        }

        let String mangled = self.MangledInstance(md.name, md.genericParams, binds);
        // The owner is part of the seen key: two classes may each stamp the same instance name
        let String seenKey = owner + "::" + mangled;
        self.usedMethodTemplates.AddNew(MemberKey(owner, md.name));
        if (self.genericSeen.AddNew(seenKey)) {
            self.genericMethodQueue.Add(new GenericMethodJob(md, owner, tm.file, tm.realmKind,
                                                             binds, mangled, self.scope));
        }

        let SubstitutionContext sctx = self.SubCtxOf(binds);
        let List[Param] concreteParams = SubParams(md.params, sctx);
        let String cname = self.mangler.Method(owner, mangled, concreteParams, false);
        let IrType ret = self.ResolveType(SubOptType(md.returnType, sctx));
        self.CoerceArgs(args, Optional.Some(new MethodSig(md.returnType, concreteParams, isStatic,
            md.isThrows, false, md.annotations, false)), ctx, astArgs);

        if (md.isThrows) {
            self.CheckThrowsHandled(ctx, span);
            match (recv) {
                case Some(r) {
                    return IrExpr.IrThrowsInstanceCall(
                        new IrThrowsInstanceCall(r, cname, ret, self.t.Result(ret), args));
                }
                case None {
                    return IrExpr.IrThrowsCall(new IrThrowsCall(cname, ret, self.t.Result(ret), args));
                }
            }
        }
        return self.CallOrInstance(recv, cname, ret, args);
    }

    /*
     * CallOrInstance - A static or instance call, whichever the receiver says
     */
    IrExpr func CallOrInstance(Optional[IrExpr] recv, String cname, IrType ret, List[IrExpr] args) {
        match (recv) {
            case Some(r) { return IrExpr.IrInstanceCall(new IrInstanceCall(r, cname, ret, args)); }
            case None    { return IrExpr.IrStaticCall(new IrStaticCall(cname, ret, args)); }
        }
    }

    /* ---------------------------------------------------------------------------------------
     * Statements
     * ------------------------------------------------------------------------------------ */

    /*
     * ResolveBlock - A block in its own scope, warning once about code after a statement that
     * always leaves
     */
    IrBlock func ResolveBlock(Block b, ResolveCtx ctx, IrType retType) {
        let ResolveCtx inner = ctx.PushScope(false);
        let List[IrStmt] stmts = new List[IrStmt]();
        let int i = 0;
        while (i < b.stmts.Length()) {
            stmts.Add(self.ResolveStmt(b.stmts.Get(i), inner, retType));
            i = i + 1;
        }
        let int j = 1;
        while (j < stmts.Length()) {
            let IrStmt prev = stmts.Get(j - 1);
            let bool leaves = self.DefinitelyReturns(prev);
            match (prev) {
                case IrBreak(x)    { leaves = true; }
                case IrContinue(x) { leaves = true; }
                default { }
            }
            if (leaves) {
                self.diag.Warn(Codes.UnreachableCode(), ctx.file, Stmts2.SpanOf(stmts.Get(j)),
                    "unreachable code");
                break;
            }
            j = j + 1;
        }
        let IrBlock blk = new IrBlock(stmts);
        blk.span = b.span;
        return blk;
    }

    /*
     * ResolveStmt - One statement, with the source span carried onto the IR node
     */
    IrStmt func ResolveStmt(Stmt s, ResolveCtx ctx, IrType retType) {
        let IrStmt r = self.ResolveStmtCore(s, ctx, retType);
        if (TS.IsNone(Stmts2.SpanOf(r))) { Stmts2.SetSpan(r, Stmts.Span(s)); }
        return r;
    }

    /*
     * WrapBlock - A single statement as a block, without double-wrapping one that already is
     */
    IrBlock func WrapBlock(Stmt s, ResolveCtx ctx, IrType retType) {
        match (s) { case Block(b) { return self.ResolveBlock(b, ctx, retType); } default { } }
        let ResolveCtx inner = ctx.PushScope(false);
        let List[IrStmt] one = new List[IrStmt]();
        one.Add(self.ResolveStmt(s, inner, retType));
        let IrBlock blk = new IrBlock(one);
        blk.span = Stmts.Span(s);
        return blk;
    }

    /*
     * ResolveStmtCore - The dispatch over every statement node
     */
    IrStmt func ResolveStmtCore(Stmt s, ResolveCtx ctx, IrType retType) {
        match (s) {
            case NativeStmt(ns) { return IrStmt.IrNativeStmt(new IrNativeStmt(ns.body.c)); }
            case Block(b)       { return IrStmt.IrBlock(self.ResolveBlock(b, ctx, retType)); }
            case LetStmt(ls)    { return IrStmt.IrDeclVar(self.ResolveLet(ls, ctx)); }
            case AssignStmt(asgn) { return self.ResolveAssign(asgn, ctx); }
            case ExprStmt(es)   { return self.ResolveExprStmt(es, ctx); }
            case ReturnStmt(rs) { return self.ResolveReturn(rs, ctx, retType); }

            case IfStmt(ifs) {
                let IrExpr cond = self.ResolveExpr(ifs.cond, ctx);
                self.ForbidNestedThrows(cond, ctx, false);
                self.CheckCondition(cond, ctx, false);
                let IrBlock then = self.WrapBlock(ifs.then, ctx, retType);
                self.WarnIfEmpty(then, "if", ctx, ifs.span);
                let Optional[IrBlock] els = Optional[IrBlock].None();
                match (ifs.otherwise) {
                    case Some(e) {
                        let IrBlock eb = self.WrapBlock(e, ctx, retType);
                        self.WarnIfEmpty(eb, "else", ctx, ifs.span);
                        els = Optional.Some(eb);
                    }
                    case None { }
                }
                return IrStmt.IrIf(new IrIf(cond, then, els));
            }

            case WhileStmt(ws) {
                let IrExpr cond = self.ResolveExpr(ws.cond, ctx);
                self.ForbidNestedThrows(cond, ctx, false);
                // 'while (true)' is the idiom for a loop that exits by break, so a constant
                // condition is allowed here and nowhere else
                self.CheckCondition(cond, ctx, true);
                let IrBlock body = self.WrapBlock(ws.body, ctx.WithLoop(), retType);
                self.WarnIfEmpty(body, "while", ctx, ws.span);
                return IrStmt.IrWhile(new IrWhile(cond, body));
            }

            case ForStmt(fs)   { return IrStmt.IrFor(self.ResolveFor(fs, ctx, retType)); }
            case ForInStmt(fi) { return IrStmt.IrForIn(self.ResolveForIn(fi, ctx, retType)); }

            case UnsafeBlock(ub) {
                let ResolveCtx uctx = ctx.WithUnsafe(true).PushScope(false);
                let List[IrStmt] stmts = new List[IrStmt]();
                let int i = 0;
                while (i < ub.stmts.Length()) {
                    stmts.Add(self.ResolveStmt(ub.stmts.Get(i), uctx, retType));
                    i = i + 1;
                }
                let IrBlock body = new IrBlock(stmts);
                body.span = ub.span;
                self.WarnUnsafeManagedTemporary(body, ctx);
                return IrStmt.IrUnsafeBlock(new IrUnsafeBlock(body));
            }

            case SwitchStmt(sw) { return IrStmt.IrSwitch(self.ResolveSwitch(sw, ctx, retType)); }
            case MatchStmt(ms)  { return IrStmt.IrMatch(self.ResolveMatch(ms, ctx, retType)); }

            case BreakStmt(b) {
                if (ctx.loopDepth == 0) {
                    self.diag.Error(Codes.BreakOutsideLoop(), ctx.file, Stmts.Span(s),
                        "'break' is only valid inside a loop");
                }
                if (ctx.inDefer) {
                    self.diag.Error(Codes.DeferTransfer(), ctx.file, Stmts.Span(s),
                        "a 'defer' body cannot 'break'");
                }
                return IrStmt.IrBreak(new IrBreak());
            }
            case ContinueStmt(c) {
                if (ctx.loopDepth == 0) {
                    self.diag.Error(Codes.BreakOutsideLoop(), ctx.file, Stmts.Span(s),
                        "'continue' is only valid inside a loop");
                }
                if (ctx.inDefer) {
                    self.diag.Error(Codes.DeferTransfer(), ctx.file, Stmts.Span(s),
                        "a 'defer' body cannot 'continue'");
                }
                return IrStmt.IrContinue(new IrContinue());
            }

            case TryCatchStmt(tc) { return IrStmt.IrTryCatch(self.ResolveTryCatch(tc, ctx, retType)); }

            case DeferStmt(ds) {
                if (ctx.inDefer) {
                    self.diag.Error(Codes.DeferTransfer(), ctx.file, ds.span,
                        "a 'defer' body cannot itself 'defer'");
                }
                match (ds.action) {
                    case LetStmt(dlet) {
                        let List[String] hints = new List[String]();
                        hints.Add("declare the variable before the 'defer' and use it in the " +
                                  "deferred action");
                        hints.Add("or wrap the action in a block: 'defer { ... }'");
                        self.diag.Error(Codes.NoEffect(), ctx.file, ds.span,
                            "a 'defer' body cannot be a declaration; '" + dlet.name +
                            "' would go out of scope immediately", hints);
                    }
                    default { }
                }
                let ResolveCtx dctx = ctx.WithDefer().PushScope(false);
                return IrStmt.IrDefer(new IrDefer(self.ResolveStmt(ds.action, dctx, retType)));
            }

            case ThrowStmt(th) {
                if (ctx.inDefer) {
                    self.diag.Error(Codes.DeferTransfer(), ctx.file, Stmts.Span(s),
                        "a 'defer' body cannot 'throw'");
                }
                self.CheckThrowsHandled(ctx, Stmts.Span(s));
                return IrStmt.IrThrow(new IrThrow());
            }

            case AssignValueStmt(av) { return self.ResolveAssignValue(av, ctx, Stmts.Span(s)); }

            case DebugStmt(d) {
                if (self.releaseMode) { self.RejectInRelease("debug", ctx, Stmts.Span(s)); }
                let IrDebug dd = new IrDebug(d.raw);
                dd.span = Stmts.Span(s);
                return IrStmt.IrDebug(dd);
            }
            case PanicStmt(p) {
                if (self.releaseMode) { self.RejectInRelease("panic", ctx, Stmts.Span(s)); }
                if (ctx.realmKind != Realm.Kernel) {
                    self.diag.Error(Codes.PanicOutsideKernel(), ctx.file, Stmts.Span(s),
                        "'panic' is only valid in the kernel realm");
                }
                let IrPanic pp = new IrPanic(p.raw);
                pp.span = Stmts.Span(s);
                return IrStmt.IrPanic(pp);
            }
        }
    }

    /*
     * RejectInRelease - 'debug' and 'panic' are development statements, not shipping ones
     */
    void func RejectInRelease(String what, ResolveCtx ctx, TextSpan span) {
        let List[String] hints = new List[String]();
        hints.Add("remove it before shipping");
        self.diag.Error(Codes.DiagInRelease(), ctx.file, span,
            "'" + what + "' is not allowed in a release build", hints);
    }

    /*
     * ResolveAssign - 'x = v' and the compound forms. An indexed target is its own path, since a
     * '[]=' setter is a call rather than storage.
     */
    IrStmt func ResolveAssign(AssignStmt asgn, ResolveCtx ctx) {
        match (asgn.target) {
            case IndexExpr(ixt) { return self.ResolveIndexAssign(ixt, asgn, ctx); }
            default { }
        }

        let IrExpr target = self.ResolveExpr(asgn.target, ctx);
        let IrExpr value = self.ResolveExpr(asgn.value, ctx);
        self.CheckLValue(target, ctx);

        if (asgn.op == AssignOp.Assign) {
            if (self.SameStorage(target, value)) {
                let String shown = "field";
                match (target) { case IrVar(tv) { shown = tv.name; } default { } }
                let List[String] hints = new List[String]();
                hints.Add("did you mean to assign a different value, or to write 'self." + shown +
                          "' on one side?");
                self.diag.Warn(Codes.SelfAssignment(), ctx.file, asgn.span,
                    "this assignment stores a value into itself and has no effect", hints);
            }
            let IrExpr v = self.CheckRootThrowsValue(value, Exprs2.TypeOf(target),
                                                     "the assignment target", ctx, asgn.span);
            return IrStmt.IrAssign(new IrAssign(target, AssignOp.Assign, v));
        }

        self.ForbidThrowsInAssignForm(value, "a '" + Ops.AssignSym(asgn.op) +
                                             "' compound assignment", ctx);
        let String baseOp = self.BaseOpSym(asgn.op);
        let String lhsClass = self.DirectClassNameOf(Exprs2.TypeOf(target));
        if (lhsClass.Length() > 0) {
            match (self.sym.LookupOperator(lhsClass, baseOp, 1)) {
                case Some(opSym) {
                    // 'a += b' on a class composes from that class's '+'
                    self.CheckOperatorAccess(lhsClass, baseOp, ctx, asgn.span);
                    let IrExpr arg = self.CheckOpArg(opSym, value, ctx);
                    let List[IrExpr] cargs = new List[IrExpr]();
                    cargs.Add(target);
                    cargs.Add(arg);
                    let IrExpr composed = IrExpr.IrStaticCall(
                        new IrStaticCall(opSym.cName, self.ResolveType(opSym.type), cargs));
                    self.CheckAssign(composed, Exprs2.TypeOf(target), "the assignment target", ctx,
                                     Codes.TypeMismatch());
                    self.ForbidNestedThrows(composed, ctx, false);
                    return IrStmt.IrAssign(new IrAssign(target, AssignOp.Assign, composed));
                }
                case None { }
            }
        }
        self.CheckCompound(asgn.op, target, value, ctx);
        self.ForbidNestedThrows(value, ctx, false);
        return IrStmt.IrAssign(new IrAssign(target, asgn.op,
            self.CompoundValue(asgn, target, value, ctx)));
    }

    /*
     * BaseOpSym - The binary operator a compound assignment composes from
     */
    String func BaseOpSym(AssignOp op) {
        match (Ops.BaseOp(op)) { case Some(b) { return Ops.BinSym(b); } case None { return "="; } }
    }

    /*
     * CompoundValue - Applies to 'a op= b' the checks and conversion 'a = a op b' would have got
     * from ResolveBin, and returns the value to store
     */
    IrExpr func CompoundValue(AssignStmt asgn, IrExpr target, IrExpr value, ResolveCtx ctx) {
        match (Ops.BaseOp(asgn.op)) {
            case None { return value; }
            case Some(op) {
                self.CheckShiftCount(op, Exprs2.TypeOf(target), value, ctx, Exprs.Span(asgn.value));
                self.CheckZeroDivisor(op, value, ctx, Exprs.Span(asgn.value));
                self.CheckMixedSignedness(op, target, value, ctx, asgn.span);
                // A shift keeps its count's own type; everything else converts into the target's
                if (op == BinOp.Shl || op == BinOp.Shr) { return value; }
                return self.InType(value, Exprs2.TypeOf(target));
            }
        }
    }

    /*
     * ResolveExprStmt - An expression evaluated for its effect
     */
    IrStmt func ResolveExprStmt(ExprStmt es, ResolveCtx ctx) {
        let IrExpr e = self.ResolveExpr(es.e, ctx);
        self.ForbidNestedThrows(e, ctx, true);

        // A handler on a discarded call has nothing to assign to
        match (e) {
            case IrCatchCall(sc) {
                if (!Types.IsVoid(sc.type) &&
                    self.ContainsAssignValue(IrStmt.IrBlock(sc.handler))) {
                    let List[String] hints = new List[String]();
                    hints.Add("bind the call first: 'let T x = ... catch { assign <value>; };'");
                    self.diag.Error(Codes.AssignOutsideCatch(), ctx.file, sc.handler.span,
                        "'assign' needs a declaration to supply a value for, and this call's " +
                        "result is discarded", hints);
                }
            }
            default { }
        }

        self.RejectDiscardedRetain(es.e, ctx);
        self.WarnIfNoEffect(es.e, e, ctx);
        return IrStmt.IrExprStmt(new IrExprStmt(e));
    }

    /*
     * ResolveReturn - 'return' and 'return v'
     */
    IrStmt func ResolveReturn(ReturnStmt rs, ResolveCtx ctx, IrType retType) {
        if (ctx.inDefer) {
            self.diag.Error(Codes.DeferTransfer(), ctx.file, rs.span, "a 'defer' body cannot 'return'");
        }
        if (ctx.inProcessInit) {
            let List[String] hints = new List[String]();
            hints.Add("the only function to return from here is the one generated to initialise " +
                      "this process, so this would leave this variable - and every one declared " +
                      "below it - holding nothing");
            hints.Add("end the handler with 'assign <value>;' instead");
            self.diag.Error(Codes.UninitialisedProcessVar(), ctx.file, rs.span,
                "a 'catch' handler on a process variable cannot 'return'", hints);
            return IrStmt.IrReturn(new IrReturn(Optional[IrExpr].None()));
        }

        match (rs.value) {
            case None {
                let bool isResult = false;
                match (retType) { case IrResultType(r) { isResult = true; } default { } }
                if (!Types.IsVoid(retType) && !isResult) {
                    self.diag.Error(Codes.ReturnTypeMismatch(), ctx.file, rs.span,
                        "function must return '" + self.Describe(retType) + "'");
                }
                return IrStmt.IrReturn(new IrReturn(Optional[IrExpr].None()));
            }
            case Some(rv) {
                // A throws function returns the SUCCESS type, so that is what the value is
                // expected to be
                let IrType want = retType;
                match (retType) { case IrResultType(rrt) { want = rrt.inner; } default { } }
                let IrExpr v = self.Coerce(self.ResolveExpr(rv, ctx.WithExpected(want)), retType, ctx);
                self.ForbidNestedThrows(v, ctx, false);
                self.CheckAssign(v, retType, "the function's return", ctx,
                                 Codes.ReturnTypeMismatch());
                return IrStmt.IrReturn(new IrReturn(Optional.Some(v)));
            }
        }
    }

    /*
     * ResolveAssignValue - 'assign v', legal only inside an inline catch handler
     */
    IrStmt func ResolveAssignValue(AssignValueStmt av, ResolveCtx ctx, TextSpan span) {
        match (ctx.assignType) {
            case None {
                let List[String] hints = new List[String]();
                hints.Add("it supplies the value for the declaration the handler belongs to");
                hints.Add("to return from the enclosing function, use 'return'");
                self.diag.Error(Codes.AssignOutsideCatch(), ctx.file, span,
                    "'assign' is only valid inside a 'catch' handler attached to a call", hints);
                return IrStmt.IrAssignValue(new IrAssignValue(self.ResolveExpr(av.value, ctx)));
            }
            case Some(at) {
                if (ctx.inDefer) {
                    self.diag.Error(Codes.DeferTransfer(), ctx.file, span,
                        "a 'defer' body cannot 'assign'");
                }
                if (Types.IsVoid(at)) {
                    let List[String] hints = new List[String]();
                    hints.Add("the handler ends through 'return', 'throw', 'break', or 'continue', " +
                              "or simply by reaching its closing brace");
                    hints.Add("give the function a return type - 'throws T func ...' - if the call " +
                              "was meant to produce one");
                    self.diag.Error(Codes.AssignOutsideCatch(), ctx.file, span,
                        "this call produces no value, so there is nothing for 'assign' to supply",
                        hints);
                    return IrStmt.IrAssignValue(new IrAssignValue(self.ResolveExpr(av.value, ctx)));
                }
                let IrExpr value = self.ResolveExpr(av.value, ctx);
                self.ForbidNestedThrows(value, ctx, false);
                let IrExpr c = self.Coerce(value, at, ctx);
                self.CheckAssign(c, at, "'assign'", ctx, Codes.TypeMismatch());
                return IrStmt.IrAssignValue(new IrAssignValue(c));
            }
        }
    }

    /*
     * ResolveFor - A C-style for. Both clauses go through the full statement resolver, so an
     * assignment in one gets lvalue, type and throws checking like any other.
     */
    IrFor func ResolveFor(ForStmt fs, ResolveCtx ctx, IrType retType) {
        let ResolveCtx fctx = ctx.PushScope(false).WithLoop();
        let Optional[IrStmt] init = Optional[IrStmt].None();
        match (fs.init) {
            case Some(x) { init = Optional.Some(self.ResolveStmt(x, fctx, retType)); }
            case None { }
        }
        let Optional[IrExpr] cond = Optional[IrExpr].None();
        match (fs.cond) {
            case Some(c) {
                let IrExpr rc = self.ResolveExpr(c, fctx);
                self.ForbidNestedThrows(rc, fctx, false);
                self.CheckCondition(rc, fctx, true);
                cond = Optional.Some(rc);
            }
            case None { }
        }
        let Optional[IrStmt] step = Optional[IrStmt].None();
        match (fs.step) {
            case Some(x) { step = Optional.Some(self.ResolveStmt(x, fctx, retType)); }
            case None { }
        }
        let IrBlock body = self.ResolveBlock(fs.body, fctx, retType);
        self.WarnIfEmpty(body, "for", fctx, fs.span);
        return new IrFor(init, cond, step, body);
    }

    /*
     * ResolveForIn - Iteration over a fixed array, or over any class with both 'Length()'
     * returning an integer and 'Get(int)'. There is no iterator protocol beyond that pair.
     */
    IrForIn func ResolveForIn(ForInStmt fi, ResolveCtx ctx, IrType retType) {
        let IrExpr collection = self.ResolveExpr(fi.collection, ctx);
        self.ForbidNestedThrows(collection, ctx, false);

        match (Exprs2.TypeOf(collection)) {
            case IrArrayType(at) {
                let ResolveCtx ainner = ctx.PushScope(false).WithLoop();
                self.CheckNotReservedLocal(fi.varName, fi.span, "loop variable", ctx);
                ainner.locals.Declare(fi.varName, at.elem, false);
                let IrBlock abody = self.ResolveBlock(fi.body, ainner, retType);
                self.WarnIfEmpty(abody, "for..in", ctx, fi.span);
                return new IrForIn(fi.varName, at.elem, "", "", collection, abody, at.size);
            }
            default { }
        }

        let String collClass = self.ClassNameOf(Exprs2.TypeOf(collection));
        let String lenCName = "";
        let String getCName = "";
        let IrType elemType = self.t.Int();

        let Optional[Symbol] lenSym = collClass.Length() > 0
            ? self.sym.LookupMethod(collClass, "Length") : Optional[Symbol].None();
        let Optional[Symbol] getSym = collClass.Length() > 0
            ? self.sym.LookupMethod(collClass, "Get") : Optional[Symbol].None();

        let bool lengthOk = false;
        match (lenSym) {
            case Some(l) {
                match (l.sig) {
                    case Some(g) {
                        lengthOk = g.params.Length() == 0 && self.IsInteger(self.ResolveType(l.type));
                    }
                    case None { }
                }
            }
            case None { }
        }
        let bool getOk = false;
        match (getSym) {
            case Some(gs) {
                match (gs.sig) {
                    case Some(g) {
                        getOk = g.params.Length() == 1 &&
                                self.IsInteger(self.ResolveTypeSpec(g.params.Get(0).type));
                    }
                    case None { }
                }
            }
            case None { }
        }

        if (lengthOk && getOk) {
            match (lenSym) { case Some(l) { lenCName = l.cName; } case None { } }
            match (getSym) {
                case Some(gs) { getCName = gs.cName; elemType = self.ResolveType(gs.type); }
                case None { }
            }
        } else if (Types.IsError(Exprs2.TypeOf(collection))) {
            elemType = self.t.Error();
        } else {
            // The message names WHICH half is missing, since that is the whole fix
            let String why = "";
            if (collClass.Length() > 0) {
                if (!lengthOk && !getOk) { why = " (no 'Length() -> int' or 'Get(int)' method)"; }
                else if (!lengthOk)      { why = " (no 'Length() -> int' method)"; }
                else                     { why = " (no 'Get(int)' method)"; }
            }
            self.diag.Error(Codes.NotIterable(), ctx.file, Exprs.Span(fi.collection),
                "'" + self.Describe(Exprs2.TypeOf(collection)) +
                "' is not iterable with 'for..in'" + why);
        }

        let ResolveCtx inner = ctx.PushScope(false).WithLoop();
        self.CheckNotReservedLocal(fi.varName, fi.span, "loop variable", ctx);
        inner.locals.Declare(fi.varName, elemType, false);
        let IrBlock body = self.ResolveBlock(fi.body, inner, retType);
        self.WarnIfEmpty(body, "for..in", ctx, fi.span);
        // -1, not 0: arraySize is the FIXED-ARRAY size, and the backend reads 'arraySize >= 0' as
        // "this is an array, index it directly". A collection has no such size and must take the
        // Length()/Get(i) path, so it says so with a negative. C# spells this as the parameter's
        // default of -1.
        return new IrForIn(fi.varName, elemType, lenCName, getCName, collection, body, 0 - 1);
    }

    /*
     * ResolveSwitch - A switch over an integer or an enum. There is no fallthrough, so each arm is
     * an ordinary block.
     */
    IrSwitch func ResolveSwitch(SwitchStmt sw, ResolveCtx ctx, IrType retType) {
        let IrExpr scrut = self.ResolveExpr(sw.scrutinee, ctx);
        self.ForbidNestedThrows(scrut, ctx, false);

        let IrType st = Exprs2.TypeOf(scrut);
        let bool isEnum = false;
        match (st) { case IrEnumType(e) { isEnum = true; } default { } }
        if (!(self.IsInteger(st) || isEnum || Types.IsError(st))) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, Exprs.Span(sw.scrutinee),
                "switch requires an integer or enum value, got '" + self.Describe(st) + "'");
        }

        let List[IrSwitchCase] cases = new List[IrSwitchCase]();
        let StringSet seenLabels = new StringSet();
        let int i = 0;
        while (i < sw.cases.Length()) {
            let SwitchCase c = sw.cases.Get(i);
            let List[IrExpr] labels = new List[IrExpr]();
            let int j = 0;
            while (j < c.labels.Length()) {
                labels.Add(self.ResolveExpr(c.labels.Get(j), ctx));
                j = j + 1;
            }
            let int k = 0;
            while (k < labels.Length()) {
                let IrExpr lbl = labels.Get(k);
                if (!self.ComparableEq(scrut, lbl)) {
                    self.diag.Error(Codes.TypeMismatch(), ctx.file, Exprs2.SpanOf(lbl),
                        "case label of type '" + self.Describe(Exprs2.TypeOf(lbl)) +
                        "' is not comparable to the switch value '" + self.Describe(st) + "'");
                }
                let String key = self.ConstLabelKey(lbl);
                if (key.Length() > 0 && !seenLabels.AddNew(key)) {
                    self.diag.Error(Codes.DuplicateName(), ctx.file, Exprs2.SpanOf(lbl),
                        "this 'case' value is already handled by an earlier arm");
                }
                k = k + 1;
            }
            cases.Add(new IrSwitchCase(labels, self.ResolveBlock(c.body, ctx, retType)));
            i = i + 1;
        }

        let Optional[IrBlock] def = Optional[IrBlock].None();
        match (sw.otherwise) {
            case Some(d) { def = Optional.Some(self.ResolveBlock(d, ctx, retType)); }
            case None { }
        }
        return new IrSwitch(scrut, cases, def);
    }

    /*
     * ConstLabelKey - A duplicate-detection key for a constant case label, "" for one that cannot
     * be checked. Int and char share a key space, since C compares them as integers.
     */
    String func ConstLabelKey(IrExpr lbl) {
        match (lbl) {
            case IrLitInt(li)   { return "n:" + Long.ToString(li.value); }
            case IrLitChar(lc)  { return "n:" + Int.ToString(lc.codepoint); }
            case IrEnumConst(ec) { return "e:" + ec.enumName + "." + ec.member; }
            default { return ""; }
        }
    }

    /*
     * ResolveMatch - A match over a union. Without a default it must cover every variant, which is
     * what makes adding a variant a compile error at every site that handles them.
     */
    IrMatch func ResolveMatch(MatchStmt ms, ResolveCtx ctx, IrType retType) {
        let IrExpr scrut = self.ResolveExpr(ms.scrutinee, ctx);
        self.ForbidNestedThrows(scrut, ctx, false);

        let String uname = "";
        match (Exprs2.TypeOf(scrut)) { case IrUnionType(ut) { uname = ut.name; } default { } }

        if (uname.Length() == 0) {
            if (!Types.IsError(Exprs2.TypeOf(scrut))) {
                self.diag.Error(Codes.TypeMismatch(), ctx.file, Exprs.Span(ms.scrutinee),
                    "'match' requires a union value, got '" +
                    self.Describe(Exprs2.TypeOf(scrut)) + "'");
            }
            // Still resolve the arms, so their own errors are reported in one pass
            let List[IrMatchCase] fallbackCases = new List[IrMatchCase]();
            let int i = 0;
            while (i < ms.cases.Length()) {
                fallbackCases.Add(new IrMatchCase(0, new List[IrMatchBind](),
                    self.ResolveBlock(ms.cases.Get(i).body, ctx, retType)));
                i = i + 1;
            }
            let Optional[IrBlock] fdef = Optional[IrBlock].None();
            match (ms.otherwise) {
                case Some(d) { fdef = Optional.Some(self.ResolveBlock(d, ctx, retType)); }
                case None { }
            }
            return new IrMatch(scrut, self.t.UnionType("?"), fallbackCases, fdef);
        }

        let List[UnionVariant] variants = new List[UnionVariant]();
        match (self.sym.UnionDef(uname)) { case Some(v) { variants = v; } case None { } }

        let List[IrMatchCase] cases = new List[IrMatchCase]();
        let StringSet covered = new StringSet();
        let int ci = 0;
        while (ci < ms.cases.Length()) {
            let MatchCase c = ms.cases.Get(ci);
            ci = ci + 1;

            let int idx = self.VariantIndex(variants, c.variant);
            if (idx < 0) {
                self.diag.Error(Codes.UndefinedVariable(), ctx.file, c.span,
                    "union '" + uname + "' has no variant '" + c.variant + "'");
                cases.Add(new IrMatchCase(0, new List[IrMatchBind](),
                    self.ResolveBlock(c.body, ctx, retType)));
                continue;
            }
            if (!covered.AddNew(Int.ToString(idx))) {
                self.diag.Error(Codes.DuplicateName(), ctx.file, c.span,
                    "variant '" + c.variant + "' is already matched in this 'match'");
            }

            let List[Param] payload = variants.Get(idx).variantFields;
            if (c.bindings.Length() != payload.Length()) {
                self.diag.Error(Codes.WrongArgCount(), ctx.file, c.span,
                    "'" + c.variant + "' has " + Int.ToString(payload.Length()) +
                    " field(s), but " + Int.ToString(c.bindings.Length()) +
                    " binding(s) were given");
            }

            let ResolveCtx caseCtx = ctx.PushScope(false);
            let List[IrMatchBind] binds = new List[IrMatchBind]();
            let int b = 0;
            while (b < c.bindings.Length() && b < payload.Length()) {
                let IrType ft = self.ResolveTypeSpec(payload.Get(b).type);
                self.CheckNotReservedLocal(c.bindings.Get(b), c.span, "binding", ctx);
                caseCtx.locals.Declare(c.bindings.Get(b), ft, false);
                binds.Add(new IrMatchBind(payload.Get(b).name, c.bindings.Get(b), ft));
                b = b + 1;
            }
            cases.Add(new IrMatchCase(idx, binds, self.ResolveBlock(c.body, caseCtx, retType)));
        }

        let Optional[IrBlock] def = Optional[IrBlock].None();
        match (ms.otherwise) {
            case Some(d) { def = Optional.Some(self.ResolveBlock(d, ctx, retType)); }
            case None { }
        }

        let int coveredCount = covered.ToList().Length();
        if (IsSome(def) && coveredCount == variants.Length() && variants.Length() > 0) {
            let List[String] hints = new List[String]();
            hints.Add("remove the 'default' so a new variant becomes a compile error instead of " +
                      "silently falling through");
            self.diag.Warn(Codes.UnreachableCase(), ctx.file, ms.span,
                "this 'default' can never run: all " + Int.ToString(variants.Length()) +
                " variant(s) of '" + uname + "' are already matched", hints);
        }
        if (IsNone(def) && coveredCount < variants.Length()) {
            let List[String] missingList = new List[String]();
            let int m = 0;
            while (m < variants.Length()) {
                if (!covered.Has(Int.ToString(m))) { missingList.Add(variants.Get(m).name); }
                m = m + 1;
            }
            self.diag.Error(Codes.NonExhaustiveMatch(), ctx.file, ms.span,
                "'match' on '" + uname + "' is not exhaustive; missing variant(s): " +
                String.Join(missingList, ", ") + " (add a 'default' case or handle them all)");
        }
        return new IrMatch(scrut, self.t.UnionType(uname), cases, def);
    }

    /*
     * ResolveTryCatch - The try block carries a label a throwing call inside it jumps to
     */
    IrTryCatch func ResolveTryCatch(TryCatchStmt tc, ResolveCtx ctx, IrType retType) {
        let int seq = self.labelSeq;
        self.labelSeq = self.labelSeq + 1;
        let ResolveCtx tctx = ctx.WithTry("__catch_" + Int.ToString(seq));
        let IrBlock tryBlock = self.ResolveBlock(tc.tryBlock, tctx, retType);
        let IrBlock catchBlock = self.ResolveBlock(tc.catchBlock, ctx, retType);
        return new IrTryCatch(tryBlock, catchBlock, seq);
    }

    /*
     * ResolveLet - A declaration: settle its type, resolve the initialiser, check assignability,
     * and bind the name.
     *
     * The order matters. The declared type is resolved FIRST so it can be the expected type for
     * the initialiser, which is what lets 'let Maybe[int] m = Maybe.Missing();' pick an
     * instantiation the arguments alone could not.
     */
    IrDeclVar func ResolveLet(LetStmt ls, ResolveCtx ctx) {
        let bool hasDeclared = false;
        let IrType declared = self.t.Int();
        match (ls.type) {
            case Some(ts) {
                self.CheckType(ls.type, ctx, ls.span, false);
                declared = self.ResolveTypeSpec(ts);
                hasDeclared = true;
            }
            case None { }
        }

        let ResolveCtx ictx = hasDeclared ? ctx.WithExpected(declared) : ctx;
        let Optional[IrExpr] init = Optional[IrExpr].None();
        match (ls.init) {
            case Some(e) { init = Optional.Some(self.ResolveExpr(e, ictx)); }
            case None { }
        }

        let IrType type = self.t.Int();
        if (hasDeclared) {
            type = declared;
        } else {
            match (init) {
                case None {
                    self.diag.Error(Codes.CannotInfer(), ctx.file, ls.span,
                        "cannot infer a type for '" + ls.name + "'; add a type ('let int " +
                        ls.name + ";') or an initializer");
                }
                case Some(iv) {
                    // A throwing initialiser declares the variable at the SUCCESS type
                    type = Exprs2.TypeOf(iv);
                    match (type) { case IrResultType(rt) { type = rt.inner; } default { } }

                    let bool isNull = false;
                    match (iv) { case IrLitNull(x) { isNull = true; } default { } }
                    if (isNull) {
                        self.diag.Error(Codes.CannotInfer(), ctx.file, ls.span,
                            "cannot infer a type for '" + ls.name +
                            "' from 'null'; give it an explicit type");
                        type = self.t.Int();
                    } else if (Types.IsVoid(type)) {
                        self.diag.Error(Codes.CannotInfer(), ctx.file, ls.span,
                            "cannot declare '" + ls.name +
                            "': the initializer has no value (its type is 'void')");
                        type = self.t.Int();
                    }
                }
            }
        }

        match (init) {
            case Some(iv) {
                let bool isResult = false;
                let IrType inner = self.t.Void();
                match (Exprs2.TypeOf(iv)) {
                    case IrResultType(irt) { isResult = true; inner = irt.inner; }
                    default { }
                }
                if (!isResult) {
                    let IrExpr c = self.Coerce(iv, type, ctx);
                    init = Optional.Some(c);
                    if (hasDeclared) {
                        self.CheckAssign(c, type, "'" + ls.name + "'", ctx, Codes.TypeMismatch());
                    }
                } else if (hasDeclared) {
                    // The call propagates, so what must fit is the value it produces on success
                    let IrExpr probe = IrExpr.IrVar(new IrVar(ls.name, inner, false));
                    if (!self.Assignable(probe, type)) {
                        self.diag.Error(Codes.TypeMismatch(), ctx.file, Exprs2.SpanOf(iv),
                            "this throwing call produces '" + self.Describe(inner) +
                            "', which cannot initialize '" + ls.name + "' of type '" +
                            self.Describe(type) + "'");
                    }
                }
            }
            case None { }
        }

        match (init) {
            case Some(iv) {
                self.ForbidNestedThrows(iv, ctx, true);
                match (iv) {
                    case IrCatchCall(cc) {
                        if (!self.AssignsOrExits(IrStmt.IrBlock(cc.handler))) {
                            let List[String] hints = new List[String]();
                            hints.Add("end every path with 'assign <value>;'");
                            hints.Add("or leave the handler through 'return', 'throw', 'break', " +
                                      "or 'continue'");
                            self.diag.Error(Codes.CatchHandlerNoAssign(), ctx.file, cc.handler.span,
                                "this 'catch' handler can finish without supplying a value for '" +
                                ls.name + "'", hints);
                        }
                    }
                    default { }
                }
            }
            case None { }
        }

        self.CheckNotReservedLocal(ls.name, ls.span, "variable", ctx);

        // Redeclaring is an error; shadowing an outer scope is a warning; a parameter is neither,
        // because it shares one C scope with the top-level locals and no renaming can separate them
        if (ctx.locals.DeclaredHere(ls.name)) {
            self.diag.Error(Codes.DuplicateName(), ctx.file, ls.span,
                "'" + ls.name + "' is already declared in this scope");
        } else if (ctx.locals.CollidesWithParam(ls.name)) {
            let List[String] hints = new List[String]();
            hints.Add("a parameter and a top-level local share one scope; rename one of them");
            hints.Add("shadowing is fine inside a nested block");
            self.diag.Error(Codes.DuplicateName(), ctx.file, ls.span,
                "'" + ls.name + "' is already a parameter of this function", hints);
        } else if (ctx.locals.ShadowsOuter(ls.name)) {
            let List[String] hints = new List[String]();
            hints.Add("rename this one if the outer variable was meant to stay reachable");
            self.diag.Warn(Codes.ShadowedVariable(), ctx.file, ls.span,
                "'" + ls.name + "' shadows a variable of the same name from an enclosing scope",
                hints);
        } else if (self.processStateNames.Has(ls.name)) {
            let List[String] hints = new List[String]();
            hints.Add("writes here change this local, not the state the other threads read");
            hints.Add("rename this one if the process variable was meant to stay reachable");
            self.diag.Warn(Codes.ShadowedVariable(), ctx.file, ls.span,
                "'" + ls.name + "' shadows the process variable of the same name", hints);
        }

        self.WarnManagedFixedArray(type, "'" + ls.name + "'", ctx, ls.span);
        ctx.locals.Declare(ls.name, type, false);
        return new IrDeclVar(ls.name, type, init);
    }

    /*
     * ResolveIndexAssign - 'a[i] = v' and its compound forms.
     *
     * Through a '[]=' setter this is a CALL, not a store, so a compound form has to read through
     * '[]' first - and the receiver and index are hoisted so neither is evaluated twice.
     */
    IrStmt func ResolveIndexAssign(IndexExpr ixt, AssignStmt asgn, ResolveCtx ctx) {
        let IrExpr obj = self.ResolveExpr(ixt.object, ctx);
        let IrExpr idx = self.ResolveExpr(ixt.index, ctx);
        let String cls = self.DirectClassNameOf(Exprs2.TypeOf(obj));

        if (cls.Length() > 0) {
            match (self.IndexSetter(cls)) {
                case Some(setOp) {
                    return self.ResolveSetterAssign(ixt, asgn, ctx, obj, idx, cls, setOp);
                }
                case None {
                    if (IsSome(self.IndexGetter(cls))) {
                        self.diag.Error(Codes.NoIndexSetter(), ctx.file, asgn.span,
                            "'" + self.Describe(Exprs2.TypeOf(obj)) +
                            "' has a '[]' getter but no '[]=' setter; cannot assign to it");
                        return IrStmt.IrExprStmt(new IrExprStmt(
                            IrExpr.IrLitInt(new IrLitInt(0L, self.t.Int(), Optional[String].None()))));
                    }
                }
            }
        }

        let IrType elem = self.ElementTypeOf(obj, ctx, ixt.span);
        self.CheckIndexIsInteger(idx, ctx, Exprs.Span(ixt.index));
        let IrExpr val = self.ResolveExpr(asgn.value, ctx);

        if (asgn.op == AssignOp.Assign) {
            let IrIndex tgt = new IrIndex(obj, idx, elem);
            tgt.span = ixt.span;
            let IrExpr v = self.CheckRootThrowsValue(val, elem, "the assignment target", ctx,
                                                     asgn.span);
            return IrStmt.IrAssign(new IrAssign(IrExpr.IrIndex(tgt), AssignOp.Assign, v));
        }

        // A compound assignment on an element whose type overloads the base operator
        let String elemBaseOp = self.BaseOpSym(asgn.op);
        let String elemClass = self.DirectClassNameOf(elem);
        if (elemClass.Length() > 0) {
            match (self.sym.LookupOperator(elemClass, elemBaseOp, 1)) {
                case Some(elemOp) {
                    self.CheckOperatorAccess(elemClass, elemBaseOp, ctx, asgn.span);
                    let IrExpr arg = self.CheckOpArg(elemOp, val, ctx);
                    let List[IrStmt] stmts = new List[IrStmt]();
                    let IrExpr objRef = self.HoistIfImpure(obj, "__ixo", stmts);
                    let IrExpr idxRef = self.HoistIfImpure(idx, "__ixi", stmts);
                    let IrIndex readT = new IrIndex(objRef, idxRef, elem);
                    readT.span = ixt.span;
                    let IrIndex writeT = new IrIndex(objRef, idxRef, elem);
                    writeT.span = ixt.span;
                    let List[IrExpr] cargs = new List[IrExpr]();
                    cargs.Add(IrExpr.IrIndex(readT));
                    cargs.Add(arg);
                    let IrExpr composed = IrExpr.IrStaticCall(
                        new IrStaticCall(elemOp.cName, self.ResolveType(elemOp.type), cargs));
                    self.CheckAssign(composed, elem, "the assignment target", ctx,
                                     Codes.TypeMismatch());
                    self.ForbidNestedThrows(composed, ctx, false);
                    stmts.Add(IrStmt.IrAssign(
                        new IrAssign(IrExpr.IrIndex(writeT), AssignOp.Assign, composed)));
                    return self.Seq(stmts, asgn.span);
                }
                case None { }
            }
        }

        let IrIndex plainT = new IrIndex(obj, idx, elem);
        plainT.span = ixt.span;
        let IrExpr plain = IrExpr.IrIndex(plainT);
        self.CheckCompound(asgn.op, plain, val, ctx);
        self.ForbidNestedThrows(val, ctx, false);
        return IrStmt.IrAssign(new IrAssign(plain, asgn.op, val));
    }

    /*
     * ResolveSetterAssign - The '[]=' half of ResolveIndexAssign
     */
    IrStmt func ResolveSetterAssign(IndexExpr ixt, AssignStmt asgn, ResolveCtx ctx, IrExpr obj,
                                    IrExpr idx, String cls, Symbol setOp) {
        self.CheckOperatorAccess(cls, "[]=", ctx, asgn.span);
        let IrType idxType = self.ResolveTypeSpec(self.SigParam(setOp, 0));
        let IrType valType = self.ResolveTypeSpec(self.SigParam(setOp, 1));
        let IrExpr ci = self.Coerce(idx, idxType, ctx);
        self.CheckAssign(ci, idxType, "the index", ctx, Codes.TypeMismatch());

        if (asgn.op == AssignOp.Assign) {
            let IrExpr value = self.Coerce(self.ResolveExpr(asgn.value, ctx), valType, ctx);
            self.CheckAssign(value, valType, "the assignment target", ctx, Codes.TypeMismatch());
            self.ForbidThrowsInAssignForm(value,
                "an index assignment through a '[]=' operator", ctx);
            self.ForbidNestedThrows(value, ctx, false);
            let List[IrExpr] sargs = new List[IrExpr]();
            sargs.Add(ci);
            sargs.Add(value);
            let IrExprStmt st = new IrExprStmt(IrExpr.IrInstanceCall(
                new IrInstanceCall(obj, setOp.cName, self.t.Void(), sargs)));
            st.span = asgn.span;
            return IrStmt.IrExprStmt(st);
        }

        // 'xs[i] += v' reads through '[]', applies the operator, writes through '[]='
        let List[IrStmt] stmts = new List[IrStmt]();
        let IrExpr objRef = self.HoistIfImpure(obj, "__ixo", stmts);
        let IrExpr idxRef = self.HoistIfImpure(ci, "__ixi", stmts);

        let IrExpr current = IrExpr.IrLitInt(new IrLitInt(0L, self.t.Int(), Optional[String].None()));
        match (self.IndexGetter(cls)) {
            case Some(getOp) {
                self.CheckOperatorAccess(cls, "[]", ctx, ixt.span);
                let IrInstanceCall gc = new IrInstanceCall(objRef, getOp.cName,
                    self.ResolveType(getOp.type), self.OneArg(idxRef));
                gc.span = ixt.span;
                current = IrExpr.IrInstanceCall(gc);
            }
            case None {
                self.diag.Error(Codes.NoIndexSetter(), ctx.file, asgn.span,
                    "'" + self.Describe(Exprs2.TypeOf(obj)) +
                    "' has '[]=' but no '[]' getter; cannot use a compound assignment");
            }
        }

        let IrExpr rhs = self.ResolveExpr(asgn.value, ctx);
        let String baseOp = self.BaseOpSym(asgn.op);
        let String elemClass = self.DirectClassNameOf(Exprs2.TypeOf(current));
        let IrExpr combined = current;
        let bool viaOperator = false;
        if (elemClass.Length() > 0) {
            match (self.sym.LookupOperator(elemClass, baseOp, 1)) {
                case Some(elemOp) {
                    self.CheckOperatorAccess(elemClass, baseOp, ctx, asgn.span);
                    let IrExpr arg = self.CheckOpArg(elemOp, rhs, ctx);
                    let List[IrExpr] cargs = new List[IrExpr]();
                    cargs.Add(current);
                    cargs.Add(arg);
                    combined = IrExpr.IrStaticCall(
                        new IrStaticCall(elemOp.cName, self.ResolveType(elemOp.type), cargs));
                    viaOperator = true;
                }
                case None { }
            }
        }
        if (!viaOperator) {
            self.CheckCompound(asgn.op, current, rhs, ctx);
            match (Ops.BaseOp(asgn.op)) {
                case Some(bop) {
                    combined = IrExpr.IrBinOp(
                        new IrBinOp(bop, current, rhs, Exprs2.TypeOf(current)));
                }
                case None { }
            }
        }

        let IrExpr value2 = self.Coerce(combined, valType, ctx);
        self.ForbidNestedThrows(value2, ctx, false);
        let List[IrExpr] sargs2 = new List[IrExpr]();
        sargs2.Add(idxRef);
        sargs2.Add(value2);
        stmts.Add(IrStmt.IrExprStmt(new IrExprStmt(IrExpr.IrInstanceCall(
            new IrInstanceCall(objRef, setOp.cName, self.t.Void(), sargs2)))));
        return self.Seq(stmts, asgn.span);
    }

    /*
     * ResolveGenericUnionConstruct - 'Maybe.Found(7)' where Maybe is generic: decide WHICH stamped
     * instance is meant.
     *
     * The arguments decide it when exactly one instantiation accepts them all; otherwise the
     * expected type from the enclosing let or return does. None when the name is not a generic
     * union at all, so the caller falls through to its other cases.
     */
    Optional[IrExpr] func ResolveGenericUnionConstruct(String baseName, String variant,
                                                       List[IrExpr] args, ResolveCtx ctx,
                                                       TextSpan span) {
        let List[String] instances = new List[String]();
        let List[String] all = self.mangler.InstancesOf(baseName);
        let int i = 0;
        while (i < all.Length()) {
            if (self.sym.IsUnion(all.Get(i))) { instances.Add(all.Get(i)); }
            i = i + 1;
        }

        if (instances.Length() == 0) {
            if (self.mangler.IsGenericTemplate(baseName)) {
                let List[String] hints = new List[String]();
                hints.Add("name the type somewhere first, e.g. 'let " + baseName + "[int] x = " +
                          baseName + "." + variant + "(...);'");
                self.diag.Error(Codes.CannotInfer(), ctx.file, span,
                    "generic '" + baseName + "' is never instantiated, so '" + baseName + "." +
                    variant + "' has no type", hints);
                return Optional.Some(IrExpr.IrUnionConstruct(
                    new IrUnionConstruct(self.t.UnionType(baseName), 0, args)));
            }
            return Optional[IrExpr].None();
        }

        // Instantiations having this variant at this arity
        let List[String] candidates = new List[String]();
        let int j = 0;
        while (j < instances.Length()) {
            match (self.sym.UnionDef(instances.Get(j))) {
                case Some(variants) {
                    let int idx = self.VariantIndex(variants, variant);
                    if (idx >= 0 && variants.Get(idx).variantFields.Length() == args.Length()) {
                        candidates.Add(instances.Get(j));
                    }
                }
                case None { }
            }
            j = j + 1;
        }

        if (candidates.Length() == 0) {
            let List[String] hints = new List[String]();
            hints.Add("instantiated as: " + self.DisplayList(instances));
            self.diag.Error(Codes.UndefinedVariable(), ctx.file, span,
                "no instantiation of generic union '" + baseName + "' has a variant '" + variant +
                "' taking " + Int.ToString(args.Length()) + " argument(s)", hints);
            return Optional.Some(IrExpr.IrUnionConstruct(
                new IrUnionConstruct(self.t.UnionType(instances.Get(0)), 0, args)));
        }

        // The arguments settle it when exactly one candidate accepts them all
        let List[String] accepting = new List[String]();
        let int k = 0;
        while (k < candidates.Length()) {
            match (self.sym.UnionDef(candidates.Get(k))) {
                case Some(variants) {
                    let List[Param] payload =
                        variants.Get(self.VariantIndex(variants, variant)).variantFields;
                    let bool ok = true;
                    let int a = 0;
                    while (a < args.Length() && ok) {
                        ok = self.Assignable(args.Get(a),
                                             self.ResolveTypeSpec(payload.Get(a).type));
                        a = a + 1;
                    }
                    if (ok) { accepting.Add(candidates.Get(k)); }
                }
                case None { }
            }
            k = k + 1;
        }

        let String chosen = accepting.Length() == 1 ? accepting.Get(0) : "";

        // Otherwise the expected type, when it names an instantiation of this same generic
        if (chosen.Length() == 0) {
            match (ctx.expected) {
                case Some(want) {
                    match (want) {
                        case IrUnionType(wu) {
                            let List[String] pool = accepting.Length() == 0 ? candidates : accepting;
                            if (pool.Contains(wu.name)) { chosen = wu.name; }
                        }
                        default { }
                    }
                }
                case None { }
            }
        }

        if (chosen.Length() == 0) {
            let List[String] pool = accepting.Length() > 0 ? accepting : candidates;
            let List[String] hints = new List[String]();
            hints.Add("it could be: " + self.DisplayList(pool));
            hints.Add("give the target an explicit type, e.g. 'let " +
                      self.mangler.DisplayName(candidates.Get(0)) + " x = " + baseName + "." +
                      variant + "(...);'");
            self.diag.Error(Codes.CannotInfer(), ctx.file, span,
                "cannot tell which instantiation of '" + baseName + "' this means", hints);
            chosen = candidates.Get(0);
        }

        return Optional.Some(self.ResolveUnionConstruct(chosen, variant, args, ctx, span));
    }

    /* ---------------------------------------------------------------------------------------
     * Declarations
     * ------------------------------------------------------------------------------------ */

    /*
     * ResolveBodyOrNative - A method body: either resolved statements, or raw C left verbatim
     */
    void func ResolveBodyOrNative(MethodBody b, ResolveCtx ctx, IrType ret,
                                  ref Optional[IrBlock] body, ref Optional[String] native) {
        body = Optional[IrBlock].None();
        native = Optional[String].None();
        match (b) {
            case NativeMethodBody(nmb) { native = Optional.Some(nmb.native.c); }
            case BlockBody(bb) {
                body = Optional.Some(self.ResolveBlock(bb.block, ctx.WithRetType(ret), ret));
            }
        }
    }

    /*
     * ParamsToIr - A parameter list in IR form
     */
    List[IrParam] func ParamsToIr(List[Param] ps) {
        let List[IrParam] out = new List[IrParam]();
        let int i = 0;
        while (i < ps.Length()) {
            let Param p = ps.Get(i);
            out.Add(new IrParam(p.name, self.ResolveTypeSpec(p.type), p.isRef));
            i = i + 1;
        }
        return out;
    }

    /*
     * DeclareParams - Binds every parameter in a function's scope
     */
    void func DeclareParams(List[Param] ps, ResolveCtx ctx) {
        let int i = 0;
        while (i < ps.Length()) {
            let Param p = ps.Get(i);
            ctx.locals.Declare(p.name, self.ResolveTypeSpec(p.type), p.isRef);
            i = i + 1;
        }
    }

    /*
     * CheckParamTypes - Every parameter's written type
     */
    void func CheckParamTypes(List[Param] ps, ResolveCtx ctx) {
        let int i = 0;
        while (i < ps.Length()) {
            self.CheckType(Optional.Some(ps.Get(i).type), ctx, ps.Get(i).span, false);
            i = i + 1;
        }
    }

    /*
     * HasKeep - True when a declaration carries '@keep'
     */
    bool func HasKeep(List[Annotation] anns) {
        let int i = 0;
        while (i < anns.Length()) {
            match (anns.Get(i)) { case KeepAnnotation(k) { return true; } default { } }
            i = i + 1;
        }
        return false;
    }

    /*
     * ResolveClass - A class or module, with every field, method and operator
     */
    IrClass func ResolveClass(ClassDecl cd, ResolveCtx ctx) {
        let bool lib = ctx.realmKind == Realm.None;
        let Visibility vis = self.VisOf(ctx.realmKind);
        let ResolveCtx classCtx = ctx.WithClass(cd.name);

        // A stamped instance is a machine-generated copy, so one bad type argument is reported
        // once rather than once per line of the template that happens to touch it
        let bool stamped = IsSome(self.mangler.TryGetGenericInstance(cd.name));
        let String prevScope = stamped ? self.diag.PushInstance(cd.name) : "";
        let String prevInstance = self.curInstance;
        if (stamped) { self.curInstance = cd.name; }

        let List[RawFieldBlock] rawFields = new List[RawFieldBlock]();
        let List[IrField] classFields = new List[IrField]();
        let List[IrFunction] methods = new List[IrFunction]();
        let List[IrOperator] operators = new List[IrOperator]();
        let StringMap[IrExpr] fieldInits = new StringMap[IrExpr]();

        let int i = 0;
        while (i < cd.members.Length()) {
            match (cd.members.Get(i)) {
                case FieldsBlock(fb) { rawFields.Add(new RawFieldBlock(fb.body.c)); }
                case FieldDecl(fd) {
                    self.ResolveField(fd, classCtx, classFields, fieldInits);
                }
                case MethodDecl(md) {
                    // A generic method is stamped on demand, per call site
                    if (md.genericParams.Length() == 0) {
                        methods.Add(self.ResolveMethod(cd.name, md, classCtx, lib, vis, cd.isModule));
                    }
                }
                case OperatorDecl(od) {
                    operators.Add(self.ResolveOperator(cd.name, od, classCtx, lib, vis));
                }
            }
            i = i + 1;
        }

        self.WarnPartialRelationalSet(cd, ctx);

        self.curInstance = prevInstance;
        if (stamped) { self.diag.PopInstance(prevScope); }

        return new IrClass(cd.name, self.mangler.Class(cd.name), lib, vis, rawFields, classFields,
            methods, operators, self.hasInit.Has(cd.name), fieldInits, cd.isModule,
            self.HasKeep(cd.annotations));
    }

    /*
     * ResolveField - One field: its type, and its initialiser if it has one
     */
    void func ResolveField(FieldDecl fd, ResolveCtx classCtx,
                           List[IrField] classFields, StringMap[IrExpr] fieldInits) {
        let TypeSpec fspec = Specs.NamedAt("int", fd.span);
        let bool known = false;
        match (fd.type) {
            case Some(ts) { fspec = ts; known = true; }
            case None {
                match (Literals.InferFieldTypeSpec(fd.init)) {
                    case Some(ts) { fspec = ts; known = true; }
                    case None { }
                }
            }
        }
        if (!known) {
            self.diag.Error(Codes.CannotInfer(), classCtx.file, fd.span,
                "cannot infer a type for field '" + fd.name + "'; only literal initializers can " +
                "infer a field's type - give it an explicit type");
        }

        self.CheckType(Optional.Some(fspec), classCtx, fd.span, false);
        let IrType ft = self.ResolveTypeSpec(fspec);

        let Optional[IrExpr] init = Optional[IrExpr].None();
        match (fd.init) {
            case Some(ie) {
                // A field initialiser runs as part of construction, where there is no 'self' yet
                let IrExpr r = self.Coerce(self.ResolveExpr(ie, classCtx.WithStatic(false)), ft,
                                           classCtx);
                self.CheckAssign(r, ft, "field '" + fd.name + "'", classCtx, Codes.TypeMismatch());
                self.ForbidNestedThrows(r, classCtx, false);
                fieldInits.Put(fd.name, r);
                init = Optional.Some(r);
            }
            case None { }
        }
        self.WarnManagedFixedArray(ft, "field '" + fd.name + "'", classCtx, fd.span);
        classFields.Add(new IrField(fd.name, ft, init));
    }

    /*
     * ResolveMethod - A method's signature and body
     */
    IrFunction func ResolveMethod(String cls, MethodDecl md, ResolveCtx ctx, bool lib,
                                  Visibility vis, bool isModule) {
        let bool isStatic = Mods.Has(md.modifiers, Modifiers.Static) || isModule;
        // A 'throws' return type is checked by CheckThrowsReturn instead, which knows which
        // shapes have no Result spelling
        if (!md.isThrows) { self.CheckType(md.returnType, ctx, md.span, true); }
        self.CheckParamTypes(md.params, ctx);
        self.CheckParams(md.params, ctx);

        let IrType ret = self.ResolveType(md.returnType);
        let String display = self.mangler.DisplayName(cls) + "." + md.name;
        self.CheckThrowsReturn(ret, md.isThrows, display, ctx, md.span);

        let List[IrParam] pars = self.ParamsToIr(md.params);
        let String cname = self.mangler.Method(cls, md.name, md.params,
                                               self.sym.IsOverloadedMethod(cls, md.name));

        let ResolveCtx mctx = ctx.WithClass(cls).WithFunc(md.name).WithStatic(isStatic)
                                 .WithThrowsFunc(md.isThrows).PushScope(true);
        if (!isStatic) { mctx.locals.Declare("self", self.t.ClassRef(cls), false); }
        self.DeclareParams(md.params, mctx);

        let Optional[IrBlock] body = Optional[IrBlock].None();
        let Optional[String] native = Optional[String].None();
        self.ResolveBodyOrNative(md.body, mctx, ret, ref body, ref native);

        self.CheckMissingReturn(body, ret, md.isThrows, md.span, display, ctx);
        match (body) {
            case Some(b) {
                self.CheckBodyQuality(b, ret, md.span, ctx, md.params, md.span);
                self.CheckThrowsPlacement(b, mctx);
            }
            case None { }
        }
        return new IrFunction(md.name, cname, ret, pars, isStatic, md.isEntry, md.isThrows, lib,
            vis, Optional.Some(cls), body, native, md.annotations);
    }

    /*
     * ResolveOperator - An operator overload. Arity, return type and mutation are all constrained
     * by the symbol, and each violation says what the symbol requires.
     */
    IrOperator func ResolveOperator(String cls, OperatorDecl od, ResolveCtx ctx, bool lib,
                                    Visibility vis) {
        let bool isAs = od.op == "as";
        let int want = OperatorRules.RequiredArity(od.op, od.params.Length());
        if (od.params.Length() != want) {
            self.diag.Error(Codes.WrongArgCount(), ctx.file, od.span,
                "operator '" + od.op + "' must take exactly " + Int.ToString(want) +
                " parameter(s), got " + Int.ToString(od.params.Length()));
        }
        self.CheckType(od.returnType, ctx, od.span, true);
        self.CheckParamTypes(od.params, ctx);
        self.CheckParams(od.params, ctx);

        let bool isCmp = OperatorRules.IsComparison(od.op);
        let bool isMutator = OperatorRules.IsMutator(od.op);
        let TypeSpec retSpec = Specs.NamedAt(OperatorRules.DefaultReturn(od.op, cls), od.span);
        let bool wrote = false;
        match (od.returnType) { case Some(rs) { retSpec = rs; wrote = true; } case None { } }
        let IrType ret = self.ResolveTypeSpec(retSpec);

        let String shown = self.mangler.DisplayName(cls);
        if (isAs && wrote && !Types.Same(ret, self.t.ClassRef(cls))) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, od.span,
                "'as' converts its parameter to '" + shown + "' and must return '" + shown +
                "', not '" + self.Describe(ret) + "'");
        }
        if ((isCmp || od.op == "!") && !self.IsBoolType(ret)) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, od.span,
                "operator '" + od.op + "' must return 'bool', not '" + self.Describe(ret) + "'");
        }
        if (isMutator && !Types.IsVoid(ret)) {
            self.diag.Error(Codes.TypeMismatch(), ctx.file, od.span,
                "operator '" + od.op + "' mutates in place and must return 'void', not '" +
                self.Describe(ret) + "'");
        }

        let List[IrParam] pars = self.ParamsToIr(od.params);
        let String cname = self.mangler.Operator(cls, od.op, od.params,
                                                 self.sym.IsOverloadedOperator(cls, od.op));

        // An 'as' operator is implicitly static: it converts INTO the class, so there is no self
        let ResolveCtx octx = ctx.WithClass(cls).WithFunc("op_" + Mangle.OpSuffix(od.op))
                                 .WithStatic(isAs).PushScope(true);
        if (!isAs) { octx.locals.Declare("self", self.t.ClassRef(cls), false); }
        self.DeclareParams(od.params, octx);

        let Optional[IrBlock] body = Optional[IrBlock].None();
        let Optional[String] native = Optional[String].None();
        self.ResolveBodyOrNative(od.body, octx, ret, ref body, ref native);

        self.CheckMissingReturn(body, ret, false, od.span,
                                "operator " + od.op + " on " + shown, ctx);
        match (body) {
            case Some(b) {
                self.CheckBodyQuality(b, ret, od.span, ctx, od.params, od.span);
                self.CheckThrowsPlacement(b, octx);
            }
            case None { }
        }
        return new IrOperator(od.op, cname, ret, pars, cls, lib, vis, body, native, isAs);
    }

    /*
     * ResolveFreeFunc - A free function's signature and body
     */
    IrFunction func ResolveFreeFunc(FuncDecl fd, ResolveCtx ctx) {
        let bool lib = ctx.realmKind == Realm.None;
        let Visibility vis = self.VisOf(ctx.realmKind);

        // An entry point is invoked by the runtime through a fixed ABI, so its shape is not the
        // author's to choose
        if (fd.isEntry) {
            if (fd.params.Length() > 0) {
                self.diag.Error(Codes.BadEntrySignature(), ctx.file, fd.span,
                    "'" + fd.name + "': an 'entry func' takes no parameters (it is invoked by the " +
                    "runtime, never called with arguments)");
            }
            if (IsSome(fd.returnType)) {
                self.diag.Error(Codes.BadEntrySignature(), ctx.file, fd.span,
                    "'" + fd.name + "': an 'entry func' has no return value; remove the return type");
            }
            if (fd.isThrows) {
                self.diag.Error(Codes.BadEntrySignature(), ctx.file, fd.span,
                    "'" + fd.name + "': an 'entry func' cannot be 'throws' - there is no caller to " +
                    "receive the error");
            }
        }

        if (!fd.isThrows) { self.CheckType(fd.returnType, ctx, fd.span, true); }
        self.CheckParamTypes(fd.params, ctx);
        self.CheckParams(fd.params, ctx);

        let IrType ret = self.ResolveType(fd.returnType);
        self.CheckThrowsReturn(ret, fd.isThrows, fd.name, ctx, fd.span);
        let List[IrParam] pars = self.ParamsToIr(fd.params);

        let String cname = Mods.Has(fd.modifiers, Modifiers.Private)
            ? self.mangler.PrivateFreeFunc(Mangle.FileToken(ctx.file), fd.name, fd.params,
                  self.sym.PrivateFuncOverloads(ctx.file, fd.name).Length() > 1)
            : self.mangler.FreeFunc(fd.name, fd.params, self.sym.IsOverloadedFunc(fd.name),
                                    fd.isEntry, false);

        let ResolveCtx fctx = ctx.WithFunc(fd.name).WithStatic(true)
                                 .WithThrowsFunc(fd.isThrows).PushScope(true);
        self.DeclareParams(fd.params, fctx);

        let Optional[IrBlock] body = Optional[IrBlock].None();
        let Optional[String] native = Optional[String].None();
        self.ResolveBodyOrNative(fd.body, fctx, ret, ref body, ref native);

        self.CheckMissingReturn(body, ret, fd.isThrows, fd.span, fd.name, ctx);
        match (body) {
            case Some(b) {
                self.CheckBodyQuality(b, ret, fd.span, ctx, fd.params, fd.span);
                self.CheckThrowsPlacement(b, fctx);
            }
            case None { }
        }
        return new IrFunction(fd.name, cname, ret, pars, true, fd.isEntry, fd.isThrows, lib, vis,
            Optional[String].None(), body, native, fd.annotations);
    }

    /*
     * ResolveEnum - An enum's members and their values. A member with no value continues from the
     * previous one, and an explicit value is a constant integer EXPRESSION, not just a literal.
     */
    IrEnum func ResolveEnum(EnumDecl ed, ResolveCtx ctx) {
        if (ed.members.Length() == 0) {
            let List[String] hints = new List[String]();
            hints.Add("an enum needs at least one member, e.g. 'enum " + ed.name + " { First }'");
            self.diag.Error(Codes.BadDeclHeader(), ctx.file, ed.span,
                "enum '" + ed.name + "' declares no members", hints);
        }

        let List[IrEnumMember] members = new List[IrEnumMember]();
        let StringSet seen = new StringSet();
        let StringMap[int64] values = new StringMap[int64]();
        let int64 next = 0L;

        let int i = 0;
        while (i < ed.members.Length()) {
            let EnumMember m = ed.members.Get(i);
            i = i + 1;

            if (!seen.AddNew(m.name)) {
                self.diag.Error(Codes.DuplicateName(), ctx.file, m.span,
                    "enum '" + ed.name + "' already declares a member '" + m.name + "'");
            }

            let Optional[String] cval = Optional[String].None();
            match (m.value) {
                case Some(ve) {
                    let int64 v = 0L;
                    if (self.TryConstEval(ve, ed.name, values, ref v)) {
                        cval = Optional.Some(Long.ToString(v));
                        next = v;
                    } else {
                        self.diag.Error(Codes.TypeMismatch(), ctx.file, m.span,
                            "enum '" + ed.name + "' member '" + m.name + "' must be a constant " +
                            "integer expression (integer/char literals, earlier members, and " +
                            "+ - * / % << >> & | ^ ~ -)");
                    }
                }
                case None { }
            }

            // Members are read as 'int', so a value outside that range is not representable
            if (next < 0L - 2147483648L || next > 2147483647L) {
                let List[String] hints = new List[String]();
                hints.Add("enum members are read as 'int', so this would be used as " +
                          Long.ToString(self.Truncate(next, 32, false)));
                hints.Add("pick a value in -2147483648 to 2147483647");
                self.diag.Error(Codes.TypeMismatch(), ctx.file, m.span,
                    "enum '" + self.mangler.DisplayName(ed.name) + "' member '" + m.name + "' is " +
                    Long.ToString(next) + ", which does not fit in 'int'", hints);
                next = 0L;
            }

            values.Put(m.name, next);
            members.Add(new IrEnumMember(m.name, cval));
            next = next + 1L;
        }
        return new IrEnum(ed.name, self.mangler.EnumName(ed.name), members);
    }

    /*
     * TryConstEval - Folds a constant integer expression: literals, unary negate and complement,
     * the arithmetic and bitwise operators, and EARLIER members of the enclosing enum. False on
     * any non-constant subexpression, or a division by zero.
     */
    bool func TryConstEval(Expr e, String enumName, StringMap[int64] members, ref int64 v) {
        match (e) {
            case IntLitExpr(il) {
                match (Literals.ParseInt(il.value)) {
                    case Parsed(pv, ty, ct) { v = pv; return true; }
                    case Bad { return false; }
                }
            }
            case CharLitExpr(cl) { v = cl.value as int64; return true; }
            case IdentExpr(ie) {
                match (members.Find(ie.name)) {
                    case Some(mv) { v = mv; return true; }
                    case None { return false; }
                }
            }
            case MemberAccessExpr(ma) {
                // 'Enum.Member' is only constant when it names THIS enum's earlier member
                match (ma.object) {
                    case IdentExpr(oid) {
                        if (oid.name != enumName) { return false; }
                        match (members.Find(ma.member)) {
                            case Some(mv) { v = mv; return true; }
                            case None { return false; }
                        }
                    }
                    default { return false; }
                }
            }
            case UnaryExpr(un) {
                let int64 o = 0L;
                if (!self.TryConstEval(un.operand, enumName, members, ref o)) { return false; }
                if (un.op == UnOp.Neg)    { v = 0L - o; return true; }
                if (un.op == UnOp.BitNot) { v = ~o; return true; }
                return false;
            }
            case BinExpr(be) {
                let int64 l = 0L;
                let int64 r = 0L;
                if (!self.TryConstEval(be.left, enumName, members, ref l))  { return false; }
                if (!self.TryConstEval(be.right, enumName, members, ref r)) { return false; }
                if (be.op == BinOp.Add) { v = l + r; return true; }
                if (be.op == BinOp.Sub) { v = l - r; return true; }
                if (be.op == BinOp.Mul) { v = l * r; return true; }
                if (be.op == BinOp.Div) { if (r == 0L) { return false; } v = l / r; return true; }
                if (be.op == BinOp.Mod) { if (r == 0L) { return false; } v = l % r; return true; }
                if (be.op == BinOp.Shl) { v = l << ((r & 63L) as int); return true; }
                if (be.op == BinOp.Shr) { v = l >> ((r & 63L) as int); return true; }
                if (be.op == BinOp.BitAnd) { v = l & r; return true; }
                if (be.op == BinOp.BitOr)  { v = l | r; return true; }
                if (be.op == BinOp.BitXor) { v = l ^ r; return true; }
                return false;
            }
            default { return false; }
        }
    }

    /*
     * UnionContains - True when a union stores another by VALUE, directly or through further
     * unions. A pointer is a fixed-size field and breaks the cycle, which is why the walk only
     * follows named specs.
     */
    bool func UnionContains(String from, String target, StringSet visited) {
        if (from == target) { return true; }
        if (!visited.AddNew(from)) { return false; }
        match (self.sym.UnionDef(from)) {
            case None { return false; }
            case Some(variants) {
                let int i = 0;
                while (i < variants.Length()) {
                    let List[Param] payload = variants.Get(i).variantFields;
                    let int j = 0;
                    while (j < payload.Length()) {
                        match (payload.Get(j).type) {
                            case NamedSpec(ns) {
                                if (self.UnionContains(ns.Mangled(), target, visited)) {
                                    return true;
                                }
                            }
                            default { }
                        }
                        j = j + 1;
                    }
                    i = i + 1;
                }
                return false;
            }
        }
    }

    /*
     * ResolveUnion - A union's variants and their payload fields
     */
    IrUnion func ResolveUnion(UnionDecl ud, ResolveCtx ctx) {
        let bool stamped = IsSome(self.mangler.TryGetGenericInstance(ud.name));
        let String prevScope = stamped ? self.diag.PushInstance(ud.name) : "";
        let String prevInstance = self.curInstance;
        if (stamped) { self.curInstance = ud.name; }

        if (ud.variants.Length() == 0) {
            let List[String] hints = new List[String]();
            hints.Add("a union needs at least one variant, e.g. 'union " + ud.name + " { First }'");
            self.diag.Error(Codes.BadDeclHeader(), ctx.file, ud.span,
                "union '" + ud.name + "' declares no variants", hints);
        }

        let List[IrUnionVariant] variants = new List[IrUnionVariant]();
        let StringSet seen = new StringSet();
        let int i = 0;
        while (i < ud.variants.Length()) {
            let UnionVariant v = ud.variants.Get(i);
            i = i + 1;

            if (!seen.AddNew(v.name)) {
                self.diag.Error(Codes.DuplicateName(), ctx.file, v.span,
                    "union '" + ud.name + "' already declares a variant '" + v.name + "'");
            }

            let List[IrParam] payload = new List[IrParam]();
            let StringSet seenFields = new StringSet();
            let int j = 0;
            while (j < v.variantFields.Length()) {
                let Param f = v.variantFields.Get(j);
                j = j + 1;

                self.CheckType(Optional.Some(f.type), ctx, f.span, false);
                let IrType ft = self.ResolveTypeSpec(f.type);

                match (ft) {
                    case IrClassRef(mcr) {
                        if (self.sym.modules.Has(mcr.className)) {
                            let List[String] hints = new List[String]();
                            hints.Add("a module is a namespace for functions, not a value; it " +
                                      "cannot be stored");
                            self.diag.Error(Codes.TypeMismatch(), ctx.file, f.span,
                                "union variant field '" + f.name + "' has type '" +
                                self.Describe(ft) + "', which is a module", hints);
                        }
                    }
                    default { }
                }

                if (!seenFields.AddNew(f.name)) {
                    self.diag.Error(Codes.DuplicateName(), ctx.file, f.span,
                        "variant '" + v.name + "' already declares a field '" + f.name + "'");
                }

                // A union cannot contain itself by value: the two would have no size
                match (f.type) {
                    case NamedSpec(ns) {
                        if (self.UnionContains(ns.Mangled(), ud.name, new StringSet())) {
                            let List[String] hints = new List[String]();
                            hints.Add("store a pointer, or hold it through a container such as List");
                            self.diag.Error(Codes.TypeMismatch(), ctx.file, f.span,
                                ns.Mangled() == ud.name
                                    ? "variant field '" + f.name + "' has type '" +
                                      self.mangler.DisplayName(ud.name) + "', the union being " +
                                      "declared; a union cannot contain itself by value"
                                    : "variant field '" + f.name + "' has type '" +
                                      self.mangler.DisplayName(ns.Mangled()) + "', which contains '" +
                                      self.mangler.DisplayName(ud.name) +
                                      "' by value; the two would have no size",
                                hints);
                        }
                    }
                    default { }
                }
                payload.Add(new IrParam(f.name, ft, false));
            }
            variants.Add(new IrUnionVariant(v.name, self.mangler.UnionTag(ud.name, v.name), payload));
        }

        self.curInstance = prevInstance;
        if (stamped) { self.diag.PopInstance(prevScope); }
        return new IrUnion(ud.name, self.mangler.UnionName(ud.name), variants);
    }

    /*
     * ResolveProcessState - A process's variables, and the generated function that assigns them.
     *
     * Two passes: every slot is registered first, so a read of one declared BELOW can be reported
     * as exactly that rather than as an unknown name, then the initialisers run in declaration
     * order with each variable dropping out of 'pending' as it gets its value.
     */
    void func ResolveProcessState(ProcessDecl pd, String procFull, ResolveCtx ctx, Visibility vis,
                                  List[IrProcessVar] state, ref Optional[IrFunction] init) {
        init = Optional[IrFunction].None();
        let List[IrStmt] stores = new List[IrStmt]();
        let StringSet seen = new StringSet();

        let List[ProcessVarDecl] decls = new List[ProcessVarDecl]();
        let List[String] writtens = new List[String]();
        let List[IrExpr] slots = new List[IrExpr]();

        let int i = 0;
        while (i < pd.items.Length()) {
            match (pd.items.Get(i)) {
                case ProcessVarDecl(pv) {
                    self.CheckType(Optional.Some(pv.type), ctx, pv.span, false);
                    let IrType type = self.ResolveTypeSpec(pv.type);
                    let String written = self.LastSegment(self.mangler.DisplayName(pv.name));

                    if (!seen.AddNew(pv.name)) {
                        self.diag.Error(Codes.DuplicateName(), ctx.file, pv.span,
                            "process variable '" + written + "' is already declared in process '" +
                            pd.name + "'");
                    } else {
                        let String cname = self.mangler.ProcessVar(procFull, written);
                        let IrExpr slot = IrExpr.IrGlobal(new IrGlobal(cname, type));
                        state.Add(new IrProcessVar(written, cname, type));
                        self.processState.Put(pv.name, slot);
                        self.processStateNames.AddNew(written);
                        self.processStatePending.Put(pv.name, written);
                        decls.Add(pv);
                        writtens.Add(written);
                        slots.Add(slot);
                    }
                }
                default { }
            }
            i = i + 1;
        }

        let int d = 0;
        while (d < decls.Length()) {
            let ProcessVarDecl pv = decls.Get(d);
            let IrExpr slot = slots.Get(d);
            let String written = writtens.Get(d);
            d = d + 1;

            match (pv.init) {
                case None {
                    // The parser already reported the missing initialiser
                    self.processStatePending.Remove(pv.name);
                }
                case Some(ie) {
                    self.processStateCurrent = pv.name;
                    let IrType slotT = Exprs2.TypeOf(slot);
                    let ResolveCtx initCtx = ctx.WithProcessInit();
                    let IrExpr v = self.CheckRootThrowsValue(
                        self.ResolveExpr(ie, initCtx.WithExpected(slotT)), slotT,
                        "process variable '" + written + "'", initCtx, pv.span);
                    self.processStateCurrent = "";
                    self.processStatePending.Remove(pv.name);
                    let IrAssign st = new IrAssign(slot, AssignOp.Assign, v);
                    st.span = pv.span;
                    stores.Add(IrStmt.IrAssign(st));
                }
            }
        }

        if (stores.Length() == 0) { return; }
        let IrBlock body = new IrBlock(stores);
        init = Optional.Some(new IrFunction(procFull + "__state_init",
            self.mangler.ProcessStateInit(procFull), self.t.Void(), new List[IrParam](),
            true, false, false, false, vis, Optional[String].None(), Optional.Some(body),
            Optional[String].None(), new List[Annotation]()));
    }

    /*
     * ResolveProcess - A process: its shared variables, its threads, and whatever else it declares
     */
    IrProcess func ResolveProcess(ProcessDecl pd, ResolveCtx ctx, IrModule mod) {
        let Visibility vis = self.VisOf(ctx.realmKind);
        let String procFull = NameOfRealm(ctx.realmKind) + "_" + pd.name;

        let List[IrProcessVar] state = new List[IrProcessVar]();
        let Optional[IrFunction] stateInit = Optional[IrFunction].None();
        self.ResolveProcessState(pd, procFull, ctx, vis, state, ref stateInit);

        let List[IrThread] threads = new List[IrThread]();
        let StringSet seenThreads = new StringSet();
        let int i = 0;
        while (i < pd.threads.Length()) {
            let ThreadDecl td = pd.threads.Get(i);
            i = i + 1;

            match (td.mode) {
                case Some(m) {
                    self.diag.Error(Codes.ThreadModeNotAllowed(), ctx.file, td.span,
                        "thread '" + td.name + "' has explicit mode '" + m +
                        "'; threads do not support 'foreground' or 'background' modifiers");
                }
                case None { }
            }
            if (!seenThreads.AddNew(td.name)) {
                self.diag.Error(Codes.DuplicateName(), ctx.file, td.span,
                    "thread '" + td.name + "' is already declared in process '" + pd.name + "'");
            }
            let String tFull = NameOfRealm(ctx.realmKind) + "_" + pd.name + "_" + td.name;
            threads.Add(new IrThread(td.name, tFull,
                Optional.Some(self.ResolveThreadEntry(tFull, td.entryFunc, ctx, vis))));
        }

        let int j = 0;
        while (j < pd.items.Length()) {
            let TopLevel item = pd.items.Get(j);
            j = j + 1;
            match (item) {
                case ProcessVarDecl(pv) { continue; }   // resolved above
                case FuncDecl(ef) {
                    if (ef.isEntry) {
                        let List[String] hints = new List[String]();
                        hints.Add("a process's entry points are its threads; declare a 'thread' " +
                                  "instead, or move the function out of the process");
                        self.diag.Error(Codes.EntryOutsideKernel(), ctx.file, ef.span,
                            "'" + ef.name + "' is declared 'entry' inside process '" + pd.name + "'",
                            hints);
                        continue;
                    }
                }
                default { }
            }
            self.ResolveTop(item, ctx, mod);
        }

        // The names are per-process, so the next one does not inherit this one's shadow warnings
        self.processStateNames.Clear();
        self.processStatePending.Clear();

        let IrProcess proc = new IrProcess(pd.name, pd.mode, threads);
        proc.state = state;
        proc.stateInit = stateInit;
        return proc;
    }

    /*
     * ResolveThreadEntry - A thread's entry function. The runtime dispatches it through a fixed
     * void(*)(void*) ABI, so it takes no parameters and returns nothing.
     */
    IrFunction func ResolveThreadEntry(String fullName, EntryFuncDecl ef, ResolveCtx ctx,
                                       Visibility vis) {
        self.CheckParamTypes(ef.params, ctx);
        self.CheckParams(ef.params, ctx);
        let List[IrParam] pars = self.ParamsToIr(ef.params);

        let ResolveCtx fctx = ctx.WithStatic(true).PushScope(true);
        self.DeclareParams(ef.params, fctx);
        let IrBlock body = self.ResolveBlock(ef.body, fctx, self.t.Void());
        self.CheckBodyQuality(body, self.t.Void(), ef.span, ctx, ef.params, ef.span);
        self.CheckThrowsPlacement(body, fctx);

        return new IrFunction(fullName, Mangle.ThreadEntry(fullName), self.t.Void(), pars,
            true, true, false, false, vis, Optional[String].None(), Optional.Some(body),
            Optional[String].None(), new List[Annotation]());
    }

    /* ---------------------------------------------------------------------------------------
     * The pass itself
     * ------------------------------------------------------------------------------------ */

    /*
     * Resolve - Every program in the build, resolved into one typed IrModule.
     *
     * Templates are collected first across ALL files, because a call site may reach a generic
     * declared in a file resolved later. The instances those calls ask for are stamped after the
     * main pass, which is what DrainGenericInstances is for.
     */
    public IrModule func Resolve(List[ProgramFile] programs) {
        let IrModule mod = new IrModule(new List[IrNativeBlock](), new List[IrNativeType](),
            new List[IrClass](), new List[IrFunction](), new List[IrProcess](), self.arrays,
            new List[IrEnum](), self.sym, self.funcPtrTypes, new List[IrUnion]());

        let int i = 0;
        while (i < programs.Length()) {
            self.CollectFuncTemplates(programs.Get(i).prog.items, Realm.None,
                                      programs.Get(i).path);
            i = i + 1;
        }

        let int j = 0;
        while (j < programs.Length()) {
            let ProgramFile pf = programs.Get(j);
            j = j + 1;
            self.fileScope = self.VisibleTo(pf.path);
            let ResolveCtx ctx = new ResolveCtx(pf.path);
            let int k = 0;
            while (k < pf.prog.items.Length()) {
                let TopLevel item = pf.prog.items.Get(k);
                k = k + 1;
                self.scope = self.ScopeFor(item, pf.path);
                self.ResolveTop(item, ctx, mod);
            }
            self.scope = self.fileScope;
        }

        self.DrainGenericInstances(mod);
        return mod;
    }

    /*
     * VisibleTo - The modules a file can see: itself plus the transitive closure of its imports
     */
    StringSet func VisibleTo(String file) {
        match (self.visible.Find(file)) {
            case Some(v) { return v; }
            case None {
                let StringSet own = new StringSet();
                own.AddNew(file);
                return own;
            }
        }
    }

    /*
     * ScopeFor - The module scope a top-level item resolves under.
     *
     * The enclosing file's, except for a stamped generic instance: the Monomorphizer splices one
     * into the TEMPLATE's file, though its type arguments were named at the use site, so it also
     * needs to see whatever the file that named them could.
     */
    StringSet func ScopeFor(TopLevel item, String file) {
        let String name = "";
        match (item) {
            case ClassDecl(cd) { name = cd.name; }
            case UnionDecl(ud) { name = ud.name; }
            default { }
        }
        if (name.Length() == 0) { return self.fileScope; }

        match (self.seedScopes.Find(name)) {
            case Some(seeded) { return self.InstanceScope(file, seeded); }
            case None { }
        }
        match (self.genericRequestFile.Find(name)) {
            case None { return self.fileScope; }
            case Some(requester) { return self.InstanceScope(file, self.VisibleTo(requester)); }
        }
    }

    /*
     * InstanceScope - The scope a stamped instance resolves under: the file it is emitted into,
     * widened by whatever the file that named the type arguments could see.
     *
     * Taken from the TEMPLATE's file rather than fileScope, because the drain runs after the main
     * pass, where fileScope still holds whichever file happened to be resolved last.
     */
    StringSet func InstanceScope(String templateFile, StringSet requestScope) {
        let StringSet baseScope = self.VisibleTo(templateFile);
        if (baseScope == requestScope) { return baseScope; }

        let StringSet widened = new StringSet();
        let List[String] b = baseScope.ToList();
        let int i = 0;
        while (i < b.Length()) { widened.AddNew(b.Get(i)); i = i + 1; }
        let List[String] r = requestScope.ToList();
        let int j = 0;
        while (j < r.Length()) { widened.AddNew(r.Get(j)); j = j + 1; }
        return widened;
    }

    /*
     * CollectFuncTemplates - Registers every generic function and method for on-demand stamping
     */
    void func CollectFuncTemplates(List[TopLevel] items, Realm r, String file) {
        let int i = 0;
        while (i < items.Length()) {
            match (items.Get(i)) {
                case FuncDecl(fd) {
                    if (fd.genericParams.Length() > 0) {
                        // Bucketed by name: several files may each declare their own private
                        // generic under one name without clobbering each other
                        let List[FuncTemplate] bucket = new List[FuncTemplate]();
                        match (self.funcTemplates.Find(fd.name)) {
                            case Some(b) { bucket = b; }
                            case None { self.funcTemplates.Put(fd.name, bucket); }
                        }
                        bucket.Add(new FuncTemplate(fd, file, r,
                            Mods.Has(fd.modifiers, Modifiers.Private)));
                    }
                }
                case ContextDecl(cd) { self.CollectFuncTemplates(cd.items, cd.kind, file); }
                case ProcessDecl(pd) { self.CollectFuncTemplates(pd.items, r, file); }
                case ClassDecl(cls) {
                    let int m = 0;
                    while (m < cls.members.Length()) {
                        match (cls.members.Get(m)) {
                            case MethodDecl(md) {
                                if (md.genericParams.Length() > 0) {
                                    self.methodTemplates.Put(MemberKey(cls.name, md.name),
                                        new MethodTemplate(md, file, r));
                                }
                            }
                            default { }
                        }
                        m = m + 1;
                    }
                }
                default { }
            }
            i = i + 1;
        }
    }

    /*
     * ResolveTop - One top-level declaration, adding whatever it produces to the module
     */
    void func ResolveTop(TopLevel item, ResolveCtx ctx, IrModule mod) {
        match (item) {
            // Nothing to resolve: an import is a visibility fact, and an extern has no body
            case ImportDecl(x)     { }
            case ExternFuncDecl(x) { }

            case EnvironmentDecl(ed) {
                if (ctx.realmKind != Realm.None) {
                    self.diag.Error(Codes.MisplacedEnvironment(), ctx.file, ed.span,
                        "an '@environment' declaration is only valid at the top level of a file, " +
                        "not inside a context block");
                }
            }

            case NativeBlock(nb) { mod.nativeBlocks.Add(self.ResolveNativeBlock(nb, ctx)); }

            case ClassDecl(cd) { mod.classes.Add(self.ResolveClass(cd, ctx)); }

            case ContextDecl(cdecl) {
                let ResolveCtx inner = ctx.WithRealm(cdecl.kind);
                let int i = 0;
                while (i < cdecl.items.Length()) {
                    self.ResolveTop(cdecl.items.Get(i), inner, mod);
                    i = i + 1;
                }
            }

            case FuncDecl(fd) {
                // A generic template is stamped per call site, not resolved here
                if (fd.genericParams.Length() == 0) {
                    mod.freeFunctions.Add(self.ResolveFreeFunc(fd, ctx));
                }
            }

            case NativeTypeDecl(nd) {
                mod.nativeTypes.Add(new IrNativeType(nd.name, self.mangler.Class(nd.name),
                                                     nd.cBody, self.VisOf(ctx.realmKind)));
            }
            case EnumDecl(ed)   { mod.enums.Add(self.ResolveEnum(ed, ctx)); }
            case UnionDecl(ud)  { mod.unions.Add(self.ResolveUnion(ud, ctx)); }
            case ProcessDecl(pd) { mod.processes.Add(self.ResolveProcess(pd, ctx, mod)); }
            default { }
        }
    }

    /*
     * ResolveNativeBlock - A native block's section and visibility, decided by its @preamble
     */
    IrNativeBlock func ResolveNativeBlock(NativeBlock nb, ResolveCtx ctx) {
        let List[PreambleAnnotation] preambles = new List[PreambleAnnotation]();
        let int i = 0;
        while (i < nb.annotations.Length()) {
            match (nb.annotations.Get(i)) {
                case KeepAnnotation(k) {
                    self.diag.Error(Codes.WrongAnnotationKind(), ctx.file, nb.span,
                        "'@keep' is not valid on a native block; use it on a free function");
                }
                case PreambleAnnotation(pa) { preambles.Add(pa); }
                default { }
            }
            i = i + 1;
        }
        if (preambles.Length() > 1) {
            self.diag.Error(Codes.WrongAnnotationKind(), ctx.file, nb.span,
                "a native block can carry only one '@preamble'; remove the extra one(s)");
        }

        // Without a preamble the block is a type declaration, emitted into its realm's unit
        let NativeSection section = NativeSection.Types;
        let Visibility vis = self.VisOf(ctx.realmKind);
        if (preambles.Length() > 0) {
            let String target = preambles.Get(0).target;
            if (target == "boot")        { section = NativeSection.Boot;     vis = Visibility.Kernel; }
            else if (target == "kernel") { section = NativeSection.Preamble; vis = Visibility.Kernel; }
            else if (target == "user")   { section = NativeSection.Preamble; vis = Visibility.User; }
            else {
                self.diag.Error(Codes.UnknownPreambleTarget(), ctx.file, nb.span,
                    "unknown @preamble target '" + target +
                    "'; expected 'boot', 'kernel', or 'user'");
                section = NativeSection.Preamble;
                vis = Visibility.Shared;
            }
        }
        return new IrNativeBlock(nb.body.c, vis, section);
    }

    /*
     * DrainGenericInstances - Stamps every instantiation the main pass asked for.
     *
     * Both queues are drained until neither grows, because stamping one instance can name another
     * - 'List[Pair[int]]' asks for 'Pair[int]' only once its own body is resolved.
     */
    void func DrainGenericInstances(IrModule mod) {
        while (self.genericQueue.Length() > 0 || self.genericMethodQueue.Length() > 0) {
            while (self.genericQueue.Length() > 0) {
                let GenericJob job = self.genericQueue.Get(0);
                self.genericQueue.RemoveAt(0);
                self.StampFunction(job, mod);
            }
            while (self.genericMethodQueue.Length() > 0) {
                let GenericMethodJob job = self.genericMethodQueue.Get(0);
                self.genericMethodQueue.RemoveAt(0);
                self.StampMethod(job, mod);
            }
        }
    }

    /*
     * StampFunction - One generic free-function instance
     */
    void func StampFunction(GenericJob job, IrModule mod) {
        let SubstitutionContext sctx = self.SubCtxOf(job.binds);
        let Optional[TypeSpec] instRet = SubOptType(job.decl.returnType, sctx);
        if (job.decl.isThrows) { self.sym.RegisterThrows(instRet); }

        let FuncDecl inst = new FuncDecl(job.decl.modifiers, job.decl.annotations, instRet,
            job.mangled, new List[String](), SubParams(job.decl.params, sctx), job.decl.isEntry,
            job.decl.isThrows, SubBody(job.decl.body, sctx), job.decl.span);

        self.scope = self.InstanceScope(job.file, job.requestScope);
        let ResolveCtx ctx = new ResolveCtx(job.file).WithRealm(job.realmKind);
        mod.freeFunctions.Add(self.ResolveFreeFunc(inst, ctx));
    }

    /*
     * StampMethod - One generic method instance, appended to the class it belongs to
     */
    void func StampMethod(GenericMethodJob job, IrModule mod) {
        let SubstitutionContext sctx = self.SubCtxOf(job.binds);
        let Optional[TypeSpec] instRet = SubOptType(job.decl.returnType, sctx);
        if (job.decl.isThrows) { self.sym.RegisterThrows(instRet); }

        let MethodDecl inst = new MethodDecl(job.decl.modifiers, job.decl.annotations, instRet,
            job.mangled, new List[String](), SubParams(job.decl.params, sctx), job.decl.isEntry,
            job.decl.isThrows, SubBody(job.decl.body, sctx), job.decl.span);

        self.scope = self.InstanceScope(job.file, job.requestScope);
        let ResolveCtx ctx = new ResolveCtx(job.file).WithRealm(job.realmKind);
        let bool isModule = self.sym.modules.Has(job.owner);
        let bool lib = job.realmKind == Realm.None;
        let IrFunction fn = self.ResolveMethod(job.owner, inst, ctx.WithClass(job.owner), lib,
                                               self.VisOf(job.realmKind), isModule);

        let int i = 0;
        while (i < mod.classes.Length()) {
            if (mod.classes.Get(i).name == job.owner) {
                mod.classes.Get(i).methods.Add(fn);
                return;
            }
            i = i + 1;
        }
    }
}



/* ===========================================================================================
 * The analysis walkers.
 *
 * Each is a state class plus one or two hook functions, standing in for a C# nested class that
 * overrode IrWalker. The hooks are free functions because Gata has no closures: everything they
 * touch travels through the walker's state.
 * ======================================================================================== */

/*
 * A plain "did we see one" flag, for the walks that only answer yes or no
 */
class FoundFlag {
    public bool found;
    func _init() { self.found = false; }
}

/*
 * FindNativeStmt - Sets the flag on reaching a raw C statement
 */
bool func FindNativeStmt(IrWalk[FoundFlag] w, IrStmt s) {
    match (s) { case IrNativeStmt(n) { w.state.found = true; } default { } }
    return true;
}

/*
 * What CheckBodyQuality collects in one pass: every local declared, every name read, and whether
 * the body contains raw C - which makes the other two unreliable and turns the warnings off.
 *
 * Declarations are two parallel lists rather than a list of pairs, since Gata has no tuples and a
 * carrier class for a purely local pairing would not earn its name.
 */
class BodyQuality {
    public List[String] declNames;
    public List[TextSpan] declSpans;
    public StringSet used;
    public bool native;
    func _init() {
        self.declNames = new List[String]();
        self.declSpans = new List[TextSpan]();
        self.used = new StringSet();
        self.native = false;
    }
}

/*
 * BodyQualityStmt - Records a declaration, and notices raw C
 */
bool func BodyQualityStmt(IrWalk[BodyQuality] w, IrStmt s) {
    match (s) {
        case IrDeclVar(d) {
            w.state.declNames.Add(d.name);
            w.state.declSpans.Add(d.span);
        }
        case IrNativeStmt(n) { w.state.native = true; }
        default { }
    }
    return true;
}

/*
 * BodyQualityExpr - Records a name being read
 */
bool func BodyQualityExpr(IrWalk[BodyQuality] w, IrExpr e) {
    match (e) { case IrVar(v) { w.state.used.AddNew(v.name); } default { } }
    return true;
}

/*
 * DeliberatelyUnused - A leading underscore is the convention for a binding that exists only to
 * satisfy a shape and is not meant to be read, so such names opt out of the unused warnings
 */
bool func DeliberatelyUnused(String name) {
    return name.Length() > 0 && name.CharAt(0) == '_';
}


/*
 * SameSpan - Two spans pointing at the same text. TextSpan is a union, so '==' would compare it
 * structurally; this says the intent, and is what the report-once checks compare on.
 */
bool func SameSpan(TextSpan a, TextSpan b) {
    return TS.Start(a) == TS.Start(b) && TS.Length(a) == TS.Length(b);
}

/*
 * A flag for the walks that ask "does this subtree contain one"
 */
class ContainsFlag {
    public bool found;
    func _init() { self.found = false; }
}

/*
 * FindAssignValue - Sets the flag on reaching an 'assign'
 */
bool func FindAssignValue(IrWalk[ContainsFlag] w, IrStmt s) {
    match (s) { case IrAssignValue(x) { w.state.found = true; } default { } }
    return true;
}

/*
 * The direct children of one expression, gathered through the shared traversal so a newly added
 * expression kind cannot hide a subtree from the analyses that walk children by hand.
 */
class ChildList {
    public List[IrExpr] out;
    public bool atRoot;
    func _init() { self.out = new List[IrExpr](); self.atRoot = true; }
}

/*
 * CollectChild - Descends through the root node, then collects each node below it without
 * descending further. One level, which is what the callers recurse over themselves.
 */
bool func CollectChild(IrWalk[ChildList] w, IrExpr e) {
    if (w.state.atRoot) { w.state.atRoot = false; return true; }
    w.state.out.Add(e);
    return false;
}

/*
 * ChildExprs - The immediate sub-expressions of a node
 */
List[IrExpr] func ChildExprs(IrExpr e) {
    let ChildList c = new ChildList();
    let IrWalk[ChildList] w = new IrWalk[ChildList](c, null, CollectChild);
    w.WalkExpr(e);
    return c.out;
}


/*
 * The whole-body backstop for throws placement.
 *
 * Written by hand rather than as an IrWalk hook, because the two node kinds are not treated the
 * same: a statement routes its ONE legal root slot through WalkRoot, where a throwing call is
 * permitted, and everything else lands in WalkExpr, where by definition it is nested. That is a
 * traversal difference, not a visit difference, so a hook could not express it.
 */
class ThrowsPlacement {
    TypeResolver r;
    String file;

    func _init(TypeResolver r, String file) {
        self.r = r;
        self.file = file;
    }

    /*
     * Check - Walks a resolved body, reporting every misplaced throwing call
     */
    public void func Check(IrBlock body) { self.WalkStmt(IrStmt.IrBlock(body)); }

    /*
     * WalkStmt - Routes the three root-position slots through WalkRoot; everything else recurses
     * through the shared traversal, whose expression side is this class's WalkExpr
     */
    void func WalkStmt(IrStmt s) {
        match (s) {
            case IrDeclVar(d) {
                match (d.init) { case Some(e) { self.WalkRoot(e); } case None { } }
                return;
            }
            case IrExprStmt(e) { self.WalkRoot(e.expr); return; }
            case IrAssign(a) {
                if (a.op == AssignOp.Assign) {
                    self.WalkExpr(a.target);
                    self.WalkRoot(a.value);
                    return;
                }
            }
            default { }
        }
        self.WalkChildren(s);
    }

    /*
     * WalkChildren - The children of a statement, dispatched back through this class so the
     * root/nested distinction survives the descent
     */
    void func WalkChildren(IrStmt s) {
        let List[IrStmt] kids = ChildStmts(s);
        let int i = 0;
        while (i < kids.Length()) { self.WalkStmt(kids.Get(i)); i = i + 1; }
        let List[IrExpr] es = RootExprs(s);
        let int j = 0;
        while (j < es.Length()) { self.WalkExpr(es.Get(j)); j = j + 1; }
    }

    /*
     * WalkRoot - Visits an expression where a throwing call IS legal, then keeps walking its
     * children, where one no longer is
     */
    void func WalkRoot(IrExpr e) {
        match (e) {
            case IrCatchCall(cc) {
                self.WalkRoot(cc.call);
                self.WalkStmt(IrStmt.IrBlock(cc.handler));
                return;
            }
            case IrThrowsCall(tc) {
                let int i = 0;
                while (i < tc.args.Length()) { self.WalkExpr(tc.args.Get(i)); i = i + 1; }
                return;
            }
            case IrThrowsInstanceCall(ti) {
                self.WalkExpr(ti.recv);
                let int i = 0;
                while (i < ti.args.Length()) { self.WalkExpr(ti.args.Get(i)); i = i + 1; }
                return;
            }
            default { }
        }
        self.WalkExpr(e);
    }

    /*
     * WalkExpr - Anywhere here, a throwing call or a catch handler is misplaced
     */
    void func WalkExpr(IrExpr e) {
        match (e) {
            case IrThrowsCall(tc) {
                self.Report(Exprs2.SpanOf(e), "throwing call cannot appear inside a larger expression",
                            new List[String]());
            }
            case IrThrowsInstanceCall(ti) {
                self.Report(Exprs2.SpanOf(e), "throwing call cannot appear inside a larger expression",
                            new List[String]());
            }
            case IrCatchCall(cc) {
                self.Report(Exprs2.SpanOf(e), self.r.CatchNotAtRoot(), self.r.CatchNotAtRootHints());
                self.WalkStmt(IrStmt.IrBlock(cc.handler));
                return;
            }
            default { }
        }
        let List[IrExpr] kids = ChildExprs(e);
        let int i = 0;
        while (i < kids.Length()) { self.WalkExpr(kids.Get(i)); i = i + 1; }

        // A catch handler nested in an expression still has statements worth checking
        match (e) {
            case IrCatchCall(cc2) { self.WalkStmt(IrStmt.IrBlock(cc2.handler)); }
            default { }
        }
    }

    /*
     * Report - Reports unless the per-site check already complained at this span, which would
     * otherwise print the same thing twice
     */
    void func Report(TextSpan span, String message, List[String] hints) {
        if (self.r.AlreadyReportedThrowsAt(span)) { return; }
        self.r.diag.Error(Codes.ThrowsOutsideTry(), self.file, span, message, hints);
    }
}

/*
 * Collecting the immediate children of a statement, one level deep
 */
class StmtKids {
    public List[IrStmt] stmts;
    public List[IrExpr] exprs;
    public bool atRoot;
    func _init() {
        self.stmts = new List[IrStmt]();
        self.exprs = new List[IrExpr]();
        self.atRoot = true;
    }
}

bool func CollectKidStmt(IrWalk[StmtKids] w, IrStmt s) {
    if (w.state.atRoot) { w.state.atRoot = false; return true; }
    w.state.stmts.Add(s);
    return false;
}

bool func CollectKidExpr(IrWalk[StmtKids] w, IrExpr e) {
    w.state.exprs.Add(e);
    return false;
}

/*
 * ChildStmts - The immediate child statements of a statement
 */
List[IrStmt] func ChildStmts(IrStmt s) {
    let StmtKids k = new StmtKids();
    let IrWalk[StmtKids] w = new IrWalk[StmtKids](k, CollectKidStmt, CollectKidExpr);
    w.WalkStmt(s);
    return k.stmts;
}

/*
 * RootExprs - The expressions a statement holds directly
 */
List[IrExpr] func RootExprs(IrStmt s) {
    let StmtKids k = new StmtKids();
    let IrWalk[StmtKids] w = new IrWalk[StmtKids](k, CollectKidStmt, CollectKidExpr);
    w.WalkStmt(s);
    return k.exprs;
}

/*
 * Walks a body in EXECUTION ORDER, tracking which uninitialised locals have been stored into and
 * reporting a read of one that has not.
 *
 * Hand-written rather than hooked, for the same reason the C# original is: statement order and
 * branch merging both matter here, and the shared traversal promises neither. The merging rule is
 * deliberately permissive - PreAssign marks everything a subtree stores into before walking it -
 * so a store later in a loop body counts for a read earlier in it, and the analysis reports only
 * what is wrong on every path rather than guessing about paths it cannot order.
 */
class DefiniteAssignment {
    // Declared with no initialiser and not yet stored into: name -> the declaration's span
    StringMap[TextSpan] pending;
    StringSet assigned;

    public List[String] foundNames;
    public List[TextSpan] foundSpans;

    func _init() {
        self.pending = new StringMap[TextSpan]();
        self.assigned = new StringSet();
        self.foundNames = new List[String]();
        self.foundSpans = new List[TextSpan]();
    }

    public void func Run(IrBlock body) { self.WalkStmt(IrStmt.IrBlock(body)); }

    /*
     * PreAssign - Marks every variable a subtree stores into, without walking its reads. Run ahead
     * of a loop body and each branch arm, so a store later in the subtree still counts as having
     * possibly happened before a read earlier in it.
     */
    void func PreAssign(IrStmt s) {
        let StoreFinder f = new StoreFinder();
        let IrWalk[StoreFinder] w = new IrWalk[StoreFinder](f, FindStoreStmt, FindStoreExpr);
        w.WalkStmt(s);
        let List[String] names = f.stored.ToList();
        let int i = 0;
        while (i < names.Length()) { self.assigned.AddNew(names.Get(i)); i = i + 1; }
    }

    void func PreAssignOpt(Optional[IrBlock] b) {
        match (b) { case Some(x) { self.PreAssign(IrStmt.IrBlock(x)); } case None { } }
    }

    /*
     * WalkStmt - One statement, in execution order
     */
    void func WalkStmt(IrStmt s) {
        match (s) {
            case IrBlock(b) {
                let int i = 0;
                while (i < b.stmts.Length()) { self.WalkStmt(b.stmts.Get(i)); i = i + 1; }
            }
            case IrUnsafeBlock(u) { self.WalkStmt(IrStmt.IrBlock(u.body)); }
            case IrDeclVar(d) {
                match (d.init) {
                    case Some(e) { self.WalkExpr(e); self.assigned.AddNew(d.name); }
                    case None {
                        // Only primitives are tracked: a managed local is zeroed on declaration,
                        // so reading one before a store is defined, if useless
                        match (d.type) {
                            case IrPrimType(p) { self.pending.Put(d.name, d.span); }
                            default { }
                        }
                    }
                }
            }
            case IrAssign(a) {
                self.WalkExpr(a.value);
                // A compound assignment READS its target as well as writing it
                if (a.op != AssignOp.Assign) { self.WalkExpr(a.target); }
                match (a.target) {
                    case IrVar(v) { self.assigned.AddNew(v.name); }
                    default { self.WalkExpr(a.target); }
                }
            }
            case IrIf(i) {
                self.WalkExpr(i.cond);
                self.PreAssign(IrStmt.IrBlock(i.then));
                self.PreAssignOpt(i.otherwise);
                self.WalkStmt(IrStmt.IrBlock(i.then));
                match (i.otherwise) { case Some(e) { self.WalkStmt(IrStmt.IrBlock(e)); } case None { } }
            }
            case IrWhile(w) {
                self.PreAssign(IrStmt.IrBlock(w.body));
                self.WalkExpr(w.cond);
                self.WalkStmt(IrStmt.IrBlock(w.body));
            }
            case IrFor(f) {
                match (f.init) { case Some(x) { self.WalkStmt(x); } case None { } }
                self.PreAssign(IrStmt.IrBlock(f.body));
                match (f.step) { case Some(x) { self.PreAssign(x); } case None { } }
                match (f.cond) { case Some(c) { self.WalkExpr(c); } case None { } }
                self.WalkStmt(IrStmt.IrBlock(f.body));
                match (f.step) { case Some(x) { self.WalkStmt(x); } case None { } }
            }
            case IrForIn(fi) {
                self.WalkExpr(fi.collection);
                self.assigned.AddNew(fi.varName);
                self.PreAssign(IrStmt.IrBlock(fi.body));
                self.WalkStmt(IrStmt.IrBlock(fi.body));
            }
            case IrTryCatch(t) {
                self.PreAssign(IrStmt.IrBlock(t.tryBlock));
                self.PreAssign(IrStmt.IrBlock(t.catchBlock));
                self.WalkStmt(IrStmt.IrBlock(t.tryBlock));
                self.WalkStmt(IrStmt.IrBlock(t.catchBlock));
            }
            case IrSwitch(sw) {
                self.WalkExpr(sw.scrutinee);
                let int i = 0;
                while (i < sw.cases.Length()) {
                    self.PreAssign(IrStmt.IrBlock(sw.cases.Get(i).body));
                    i = i + 1;
                }
                self.PreAssignOpt(sw.otherwise);
                let int j = 0;
                while (j < sw.cases.Length()) {
                    self.WalkStmt(IrStmt.IrBlock(sw.cases.Get(j).body));
                    j = j + 1;
                }
                match (sw.otherwise) { case Some(d) { self.WalkStmt(IrStmt.IrBlock(d)); } case None { } }
            }
            case IrMatch(m) {
                self.WalkExpr(m.scrutinee);
                let int i = 0;
                while (i < m.cases.Length()) {
                    self.PreAssign(IrStmt.IrBlock(m.cases.Get(i).body));
                    i = i + 1;
                }
                self.PreAssignOpt(m.otherwise);
                let int j = 0;
                while (j < m.cases.Length()) {
                    let IrMatchCase c = m.cases.Get(j);
                    let int k = 0;
                    while (k < c.binds.Length()) {
                        self.assigned.AddNew(c.binds.Get(k).bindName);
                        k = k + 1;
                    }
                    self.WalkStmt(IrStmt.IrBlock(c.body));
                    j = j + 1;
                }
                match (m.otherwise) { case Some(d) { self.WalkStmt(IrStmt.IrBlock(d)); } case None { } }
            }
            // A defer runs on exit, so its stores may have happened by any later read
            case IrDefer(d2)      { self.PreAssign(d2.action); }
            case IrReturn(r)      { match (r.value) { case Some(v) { self.WalkExpr(v); } case None { } } }
            case IrExprStmt(es)   { self.WalkExpr(es.expr); }
            case IrAssignValue(av) { self.WalkExpr(av.value); }
            case IrNativeStmt(n) {
                // Raw C can store into anything the analysis is watching
                let List[String] keys = self.pending.Keys();
                let int i = 0;
                while (i < keys.Length()) { self.assigned.AddNew(keys.Get(i)); i = i + 1; }
            }
            default { }
        }
    }

    /*
     * WalkExpr - One expression, reporting the first read of a variable nothing has stored into
     */
    void func WalkExpr(IrExpr e) {
        match (e) {
            case IrVar(v) {
                match (self.pending.Find(v.name)) {
                    case Some(declSpan) {
                        if (!self.assigned.Has(v.name)) {
                            self.foundNames.Add(v.name);
                            self.foundSpans.Add(TS.IsNone(v.span) ? declSpan : v.span);
                            // Reported once: every later read would say the same thing
                            self.assigned.AddNew(v.name);
                        }
                    }
                    case None { }
                }
                return;
            }
            case IrAddrOf(a) {
                // Taking a variable's address hands it to something that may store through it
                match (a.target) {
                    case IrVar(av) { self.assigned.AddNew(av.name); return; }
                    default { }
                }
            }
            case IrCatchCall(cc) {
                self.WalkExpr(cc.call);
                self.PreAssign(IrStmt.IrBlock(cc.handler));
                self.WalkStmt(IrStmt.IrBlock(cc.handler));
                return;
            }
            default { }
        }
        let List[IrExpr] kids = ChildExprs(e);
        let int i = 0;
        while (i < kids.Length()) { self.WalkExpr(kids.Get(i)); i = i + 1; }
    }
}

/*
 * Every variable a subtree stores into: by assignment, by for-in binding, by an initialised
 * declaration, or by having its address taken
 */
class StoreFinder {
    public StringSet stored;
    func _init() { self.stored = new StringSet(); }
}

bool func FindStoreStmt(IrWalk[StoreFinder] w, IrStmt s) {
    match (s) {
        case IrAssign(a) {
            match (a.target) { case IrVar(v) { w.state.stored.AddNew(v.name); } default { } }
        }
        case IrForIn(fi) { w.state.stored.AddNew(fi.varName); }
        case IrDeclVar(d) {
            match (d.init) { case Some(x) { w.state.stored.AddNew(d.name); } case None { } }
        }
        case IrNativeStmt(n) { w.state.stored.AddNew("*"); }
        default { }
    }
    return true;
}

bool func FindStoreExpr(IrWalk[StoreFinder] w, IrExpr e) {
    match (e) {
        case IrAddrOf(a) {
            match (a.target) { case IrVar(v) { w.state.stored.AddNew(v.name); } default { } }
        }
        default { }
    }
    return true;
}


/*
 * Finds the first expression in an unsafe block that ALLOCATES a managed value: an interpolation,
 * a 'new', or a call handing one back. Reading an existing managed binding is fine - nothing was
 * allocated, so nothing leaks.
 *
 * Two exemptions keep it quiet where it should be. A value bound to a declaration or returned is
 * owned by something, so it is not a temporary. And a block that names retain or release is being
 * counted by hand, which is exactly what 'unsafe' is for.
 */
class UnsafeAlloc {
    TypeResolver r;
    public String retain;
    public String release;
    public Optional[IrExpr] found;
    public bool handManaged;

    // The value the current statement owns, which is therefore not a leaked temporary
    Optional[IrExpr] owned;

    func _init(TypeResolver r) {
        self.r = r;
        self.retain = "";
        self.release = "";
        self.found = Optional[IrExpr].None();
        self.handManaged = false;
        self.owned = Optional[IrExpr].None();
    }

    public void func Run(IrBlock body) {
        let IrWalk[UnsafeAlloc] w = new IrWalk[UnsafeAlloc](self, UnsafeAllocStmt, UnsafeAllocExpr);
        w.WalkStmt(IrStmt.IrBlock(body));
    }

    /*
     * Owns - True when this is the very expression the current statement binds or returns
     */
    public bool func Owns(IrExpr e) {
        match (self.owned) { case Some(o) { return SameIrExpr(o, e); } case None { return false; } }
    }

    public void func SetOwned(Optional[IrExpr] e) { self.owned = e; }

    /*
     * IsArcCall - True for a call to the retain/release intrinsics, or to a union's generated
     * retain/release, which is the same thing for a union payload
     */
    public bool func IsArcCall(IrStaticCall sc) {
        if (sc.cName == self.retain || sc.cName == self.release) { return true; }
        if (sc.args.Length() != 1) { return false; }
        match (Exprs2.TypeOf(sc.args.Get(0))) {
            case IrUnionType(ut) {
                return sc.cName == self.r.mangler.UnionRetain(ut.name) ||
                       sc.cName == self.r.mangler.UnionRelease(ut.name);
            }
            default { return false; }
        }
    }

    /*
     * Allocates - True for the expression shapes that hand back a fresh managed value
     */
    public bool func Allocates(IrExpr e) {
        match (e) {
            case IrInterp(x)             { return true; }
            case IrNew(x)                { return true; }
            case IrNewInit(x)            { return true; }
            case IrStaticCall(x)         { return true; }
            case IrInstanceCall(x)       { return true; }
            case IrThrowsCall(x)         { return true; }
            case IrThrowsInstanceCall(x) { return true; }
            case IrIndirectCall(x)       { return true; }
            default { return false; }
        }
    }

    public bool func IsManaged(IrType ty) { return self.r.IsManagedRef(ty); }
    public void func SetFound(IrExpr e) { self.found = Optional.Some(e); }
    public bool func HasFound() { return IsSome(self.found); }
    public void func SetHandManaged() { self.handManaged = true; }
}

/*
 * UnsafeAllocStmt - Records what the current statement owns, and stops at a nested unsafe block,
 * whose own resolution already warned about it
 */
bool func UnsafeAllocStmt(IrWalk[UnsafeAlloc] w, IrStmt s) {
    match (s) { case IrUnsafeBlock(u) { return false; } default { } }
    match (s) {
        case IrDeclVar(d) { w.state.SetOwned(d.init); }
        case IrReturn(r)  { w.state.SetOwned(r.value); }
        default { w.state.SetOwned(Optional[IrExpr].None()); }
    }
    return true;
}

/*
 * UnsafeAllocExpr - Notices hand counting, and the first unowned managed allocation
 */
bool func UnsafeAllocExpr(IrWalk[UnsafeAlloc] w, IrExpr e) {
    match (e) {
        case IrStaticCall(sc) { if (w.state.IsArcCall(sc)) { w.state.SetHandManaged(); } }
        default { }
    }
    if (!w.state.HasFound() && !w.state.Owns(e) && w.state.Allocates(e) &&
        w.state.IsManaged(Exprs2.TypeOf(e))) {
        w.state.SetFound(e);
    }
    return true;
}

/*
 * SameIrExpr - Reference identity over IR expressions, standing in for C#'s ReferenceEquals.
 *
 * The question is deliberately "is this the very same node", not "do these mean the same thing":
 * UnsafeAlloc asks whether the expression it is looking at IS the one the current statement binds.
 * Funnelled here so G083, which is right that a union compares its payload by identity, is raised
 * once rather than at the call site. Mirrors Types.Same and Monomorphizer.g's SameExpr family.
 */
bool func SameIrExpr(IrExpr a, IrExpr b) { return a == b; }
