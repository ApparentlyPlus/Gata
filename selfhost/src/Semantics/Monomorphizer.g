/*
 * Monomorphizer.g - stamps one concrete copy of a generic template per distinct instantiation
 *
 * Ports Appa/src/Semantics/Monomorphizer.cs.
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
import "src/Backend/Mangler.g";
import "src/Semantics/ScopeTree.g";
import "src/Semantics/ScopeBinder.g";
import "src/Semantics/SymbolTable.g";

/*
 * A generic type instantiation the resolver found it needed but the Monomorphizer had no way to
 * see: one written over a generic function's or method's own type parameter, which only becomes
 * concrete when that function is stamped, in a later pass.
 */
class GenericSeed {
    public String base;
    public List[String] args;
    public TextSpan span;
    public String file;

    /*
     * The module scope in force where the instantiation was discovered. Carried rather than
     * recovered from file, because the discovery happens while resolving a stamped generic body,
     * whose file is the template's - the type argument came from somewhere that file need never
     * import. The stamped instance is resolved under this.
     */
    public List[String] scope;

    func _init(String base, List[String] args, TextSpan span, String file) {
        self.base = base;
        self.args = args;
        self.span = span;
        self.file = file;
        self.scope = new List[String]();
    }

    /*
     * Key - The mangled instance name, which is what makes a seed comparable to another
     */
    public String func Key(Mangler m) { return m.GenericInstance(self.base, self.args); }
}

/*
 * The bindings one substitution walk applies, plus everything it needs to decide what a name means
 * at the point it is rewriting.
 */
class SubstitutionContext {
    public StringMap[TypeSpec] specMap;
    public StringMap[String] cMap;

    /*
     * Rewrites the base name of a generic reference: 'Box[int]' inside a realm declaring Box means
     * 'Box@kernel[int]'. specMap binds whole types and cannot say this. Empty for
     * monomorphization, where a template's base is never scoped.
     */
    public StringMap[String] nameMap;

    /*
     * Also rewrite bare identifiers naming a substituted type, not just type positions. Off for
     * monomorphization, where an identifier spelled like a type parameter is a variable; on for
     * scope binding, where 'Tagged.Ident(...)' has to follow 'let Tagged x'.
     */
    public bool rewriteTypeNames;

    /*
     * The scope-binding resolver, and the state C#'s two delegates would have captured. null when
     * this is an ordinary monomorphization walk, where a qualified name cannot appear.
     */
    public ScopeBinder binder;
    public ScopeTree tree;
    public ScopeIndex index;
    public ScopeId from;
    public String file;

    // Names a local binding owns at the point being rewritten.
    List[String] bound;

    func _init(StringMap[TypeSpec] specMap, StringMap[String] cMap) {
        self.specMap = specMap;
        self.cMap = cMap == null ? new StringMap[String]() : cMap;
        self.nameMap = new StringMap[String]();
        self.rewriteTypeNames = false;
        self.binder = null;
        self.tree = null;
        self.index = null;
        self.from = Sc.Root();
        self.file = "";
        self.bound = new List[String]();
    }

    /*
     * BindScopes - Turns on scoped-name resolution, naming the state C# would have closed over
     */
    public void func BindScopes(ScopeBinder binder, ScopeTree tree, ScopeIndex index, ScopeId from, String file) {
        self.binder = binder;
        self.tree = tree;
        self.index = index;
        self.from = from;
        self.file = file;
    }

    public bool func HasScopedResolver() { return self.binder != null; }

    /*
     * Mark - The current binding depth, to be handed back to Release when the scope closes
     */
    public int func Mark() { return self.bound.Length(); }

    /*
     * Release - Drops every binding made since the mark
     */
    public void func Release(int mark) {
        while (self.bound.Length() > mark) { self.bound.RemoveLast(); }
    }

    /*
     * Bind - Records that a name now belongs to a local, a parameter or a pattern binding
     */
    public void func Bind(String name) { self.bound.Add(name); }

    public void func BindParams(List[Param] ps) {
        let int i = 0;
        while (i < ps.Length()) { self.bound.Add(ps.Get(i).name); i = i + 1; }
    }

    public void func BindNames(List[String] names) {
        let int i = 0;
        while (i < names.Length()) { self.bound.Add(names.Get(i)); i = i + 1; }
    }

    /*
     * IsBound - True when a local binding, not a declaration in some scope, owns this name here
     */
    public bool func IsBound(String name) { return self.bound.Contains(name); }

    /*
     * SubWords - Substitutes type parameters in raw native C text, replacing whole words that match
     * a type parameter with its concrete C type. Native bodies are the one place where substitution
     * is genuinely textual. Everything else is rewritten structurally.
     */
    public String func SubWords(String text) {
        let List[String] keys = self.cMap.Keys();
        let bool containsParam = false;
        let int k = 0;
        while (k < keys.Length()) {
            if (text.Contains(keys.Get(k))) { containsParam = true; break; }
            k = k + 1;
        }
        if (!containsParam) { return text; }

        let StringBuilder sb = new StringBuilder();
        let int idx = 0;
        while (idx < text.Length()) {
            if (Mangle.IsIdentChar(text.CharAt(idx))) {
                let int start = idx;
                while (idx < text.Length() && Mangle.IsIdentChar(text.CharAt(idx))) { idx = idx + 1; }
                let String word = text.Substring(start, idx - start);
                match (self.cMap.Find(word)) {
                    case Some(replacement) { sb.Put(replacement); }
                    case None { sb.Put(word); }
                }
            } else {
                sb.AppendChar(text.CharAt(idx));
                idx = idx + 1;
            }
        }
        return sb.ToString();
    }

    /*
     * SubType - Structurally substitutes type parameters in a type spec tree. Returns the same
     * reference when nothing changed so callers can cheaply detect no-ops.
     */
    public TypeSpec func SubType(TypeSpec t) {
        match (t) {
            case NamedSpec(n) {
                let bool qualified = false;
                match (n.scope) { case Some(sc) { qualified = true; } case None { } }
                if (qualified && self.HasScopedResolver()) {
                    let NamedSpec resolved = self.binder.ResolveScopedType(n, self.tree, self.index,
                                                                          self.from, self.file);
                    let List[NamedSpec] qArgs = self.SubArgs(resolved.args);
                    if (qArgs == null) { return TypeSpec.NamedSpec(resolved); }
                    let NamedSpec copy = new NamedSpec(resolved.name, qArgs, resolved.span);
                    copy.scope = resolved.scope;
                    return TypeSpec.NamedSpec(copy);
                }
                if (n.args.Length() == 0) {
                    match (self.specMap.Find(n.name)) {
                        case Some(bound) { return bound; }
                        case None { return t; }
                    }
                }
                let List[NamedSpec] newArgs = self.SubArgs(n.args);
                let String newName = n.name;
                match (self.nameMap.Find(n.name)) { case Some(nm) { newName = nm; } case None { } }
                if (newArgs == null && newName == n.name) { return t; }
                let NamedSpec ns = new NamedSpec(newName, newArgs == null ? n.args : newArgs, n.span);
                ns.scope = n.scope;
                return TypeSpec.NamedSpec(ns);
            }
            case PtrSpec(p) {
                let TypeSpec inner = self.SubType(p.inner);
                if (SameSpec(inner, p.inner)) { return t; }
                return TypeSpec.PtrSpec(new PtrSpec(inner, p.span));
            }
            case ArraySpec(a) {
                let TypeSpec elem = self.SubType(a.elem);
                if (SameSpec(elem, a.elem)) { return t; }
                return TypeSpec.ArraySpec(new ArraySpec(a.sizeText, elem, a.span));
            }
            case FuncSpec(f) {
                let List[TypeSpec] newPs = null;
                let int i = 0;
                while (i < f.params.Length()) {
                    let TypeSpec np = self.SubType(f.params.Get(i));
                    if (!SameSpec(np, f.params.Get(i)) && newPs == null) {
                        newPs = new List[TypeSpec]();
                        let int c = 0;
                        while (c < i) { newPs.Add(f.params.Get(c)); c = c + 1; }
                    }
                    if (newPs != null) { newPs.Add(np); }
                    i = i + 1;
                }
                let TypeSpec nr = self.SubType(f.ret);
                if (newPs == null && SameSpec(nr, f.ret)) { return t; }
                return TypeSpec.FuncSpec(new FuncSpec(newPs == null ? f.params : newPs, nr, f.span));
            }
        }
    }

    /*
     * SubArgs - Substitutes every argument slot, or null when none of them changed
     */
    List[NamedSpec] func SubArgs(List[NamedSpec] args) {
        let List[NamedSpec] newArgs = null;
        let int i = 0;
        while (i < args.Length()) {
            let NamedSpec na = self.SubArg(args.Get(i));
            if (na != args.Get(i) && newArgs == null) {
                newArgs = new List[NamedSpec]();
                let int c = 0;
                while (c < i) { newArgs.Add(args.Get(c)); c = c + 1; }
            }
            if (newArgs != null) { newArgs.Add(na); }
            i = i + 1;
        }
        return newArgs;
    }

    /*
     * SubArg - Substitutes one generic argument slot. Argument slots hold named types only, so a
     * binding to a non named spec (like a pointer bound by generic-function inference) folds to its
     * sanitized mangled fragment to stay a valid slot.
     */
    NamedSpec func SubArg(NamedSpec a) {
        let TypeSpec sub = self.SubType(TypeSpec.NamedSpec(a));
        match (sub) {
            case NamedSpec(ns) { return ns; }
            default { return new NamedSpec(SanitizeTypeName(sub), new List[NamedSpec](), a.span); }
        }
    }
}

/*
 * One instantiation request the worklist has not yet stamped.
 */
class GenericRequest {
    public String base;
    public List[String] args;
    public TextSpan span;
    public String file;
    func _init(String base, List[String] args, TextSpan span, String file) {
        self.base = base;
        self.args = args;
        self.span = span;
        self.file = file;
    }
}

/*
 * A generic template, either a class or a union. Both are stamped through the same worklist so one
 * can reach the other - a union variant holding a List[T], a class field holding a Maybe[T] - and
 * so the two share one namespace for duplicate detection.
 */
class Template {
    public TopLevel decl;
    public List[String] params;
    public String baseName;
    public String file;
    func _init(TopLevel decl, List[String] params, String baseName, String file) {
        self.decl = decl;
        self.params = params;
        self.baseName = baseName;
        self.file = file;
    }
}

/*
 * A generic use paired with the file it was written in.
 */
class UseInFile {
    public GenericUse use;
    public String file;
    func _init(GenericUse use, String file) { self.use = use; self.file = file; }
}

class Monomorphizer {
    DiagnosticBag diag;
    Mangler mangler;

    // Set by Strip while it rewrites one program's items.
    bool stripChanged;

    func _init(DiagnosticBag diag, Mangler mangler) {
        self.diag = diag;
        self.mangler = mangler;
        self.stripChanged = false;
    }

    /*
     * Process - Stamps a concrete class per distinct instantiation breadth-first, rewriting each
     * program's items to replace templates with instances. A use deferred because one template
     * reaches another through its own parameters replays once its owner is stamped.
     */
    public StringMap[String] func Process(List[ProgramFile] programs, List[GenericSeed] seeds) {
        let StringMap[Template] templates = new StringMap[Template]();
        let StringSet tmplNames = new StringSet();

        let int p = 0;
        while (p < programs.Length()) {
            let ProgramFile pf = programs.Get(p);
            p = p + 1;
            let List[TopLevel] decls = EachDecl(pf.prog.items);
            let int i = 0;
            while (i < decls.Length()) {
                let TopLevel item = decls.Get(i);
                i = i + 1;
                let List[String] genericParams = GenericParamsOf(item);
                if (genericParams == null) { continue; }
                let String baseName = TemplateBaseName(item);

                let StringSet seenParams = new StringSet();
                let int g = 0;
                while (g < genericParams.Length()) {
                    let String gp = genericParams.Get(g);
                    g = g + 1;
                    if (!seenParams.AddNew(gp)) {
                        self.diag.Error(Codes.DuplicateName(), pf.path, Tops.Span(item),
                            "generic type '" + self.mangler.DisplayName(baseName)
                            + "' declares the type parameter '" + gp + "' twice");
                    }
                }

                if (templates.Has(baseName)) {
                    self.diag.Error(Codes.DuplicateName(), pf.path, Tops.Span(item),
                        "generic type '" + self.mangler.DisplayName(baseName) + "' is already declared");
                }
                templates.Put(baseName, new Template(item, genericParams, baseName, pf.path));
                self.mangler.RegisterGenericTemplate(baseName);
                tmplNames.AddNew(self.mangler.GenericInstance(baseName, genericParams));
            }
        }

        let StringMap[String] requestedFrom = new StringMap[String]();
        if (templates.Length() == 0) { return requestedFrom; }

        // Split every use into one that can be stamped now and one that has to wait for its owner
        let List[UseInFile] directUses = new List[UseInFile]();
        let StringMap[List[UseInFile]] deferredByOwner = new StringMap[List[UseInFile]]();

        p = 0;
        while (p < programs.Length()) {
            let ProgramFile pf = programs.Get(p);
            p = p + 1;

            let List[Template] ownersInFile = new List[Template]();
            let List[String] tkeys = templates.Keys();
            let int t = 0;
            while (t < tkeys.Length()) {
                let Template tm = templates.Get(tkeys.Get(t));
                t = t + 1;
                if (tm.file == pf.path) { ownersInFile.Add(tm); }
            }

            let List[FuncDecl] funcOwners = new List[FuncDecl]();
            let List[TopLevel] decls = EachDecl(pf.prog.items);
            let int d = 0;
            while (d < decls.Length()) {
                match (decls.Get(d)) {
                    case FuncDecl(fd) { if (fd.genericParams.Length() > 0) { funcOwners.Add(fd); } }
                    default { }
                }
                d = d + 1;
            }

            let int u = 0;
            while (u < pf.prog.genericUses.Length()) {
                let GenericUse use = pf.prog.genericUses.Get(u);
                u = u + 1;
                let bool inFunc = false;
                let int f = 0;
                while (f < funcOwners.Length()) {
                    let FuncDecl fd = funcOwners.Get(f);
                    f = f + 1;
                    if (Within(use.span, fd.span) && MentionsParam(use, fd.genericParams)) {
                        inFunc = true;
                        break;
                    }
                }
                if (inFunc) { continue; }

                let Template owner = null;
                let int o = 0;
                while (o < ownersInFile.Length()) {
                    let Template tm = ownersInFile.Get(o);
                    o = o + 1;
                    if (tm.baseName != use.base && Within(use.span, Tops.Span(tm.decl))
                        && MentionsParam(use, tm.params)) {
                        owner = tm;
                        break;
                    }
                }

                if (owner != null) {
                    let List[UseInFile] l = null;
                    match (deferredByOwner.Find(owner.baseName)) {
                        case Some(found) { l = found; }
                        case None { l = new List[UseInFile](); deferredByOwner.Put(owner.baseName, l); }
                    }
                    l.Add(new UseInFile(use, pf.path));
                } else {
                    directUses.Add(new UseInFile(use, pf.path));
                }
            }
        }

        let StringMap[GenericRequest] requests = new StringMap[GenericRequest]();
        let StringMap[String] scopeRequester = new StringMap[String]();
        let List[String] pending = new List[String]();

        let int du = 0;
        while (du < directUses.Length()) {
            let UseInFile uf = directUses.Get(du);
            du = du + 1;
            self.AddRequest(templates, tmplNames, requests, scopeRequester, pending,
                            uf.use.base, uf.use.args, uf.use.span, uf.file, uf.file);
        }
        if (seeds != null) {
            let int si = 0;
            while (si < seeds.Length()) {
                let GenericSeed sd = seeds.Get(si);
                si = si + 1;
                self.AddRequest(templates, tmplNames, requests, scopeRequester, pending,
                                sd.base, sd.args, sd.span, sd.file, sd.file);
            }
        }

        let StringMap[List[TopLevel]] instancesByBase = new StringMap[List[TopLevel]]();
        let StringSet done = new StringSet();

        let int head = 0;
        while (head < pending.Length()) {
            let String mangled = pending.Get(head);
            head = head + 1;
            if (!done.AddNew(mangled)) { continue; }

            let GenericRequest rq = requests.Get(mangled);
            let Template tmpl = templates.Get(rq.base);

            if (tmpl.params.Length() != rq.args.Length()) {
                self.diag.Error(Codes.WrongArgCount(), rq.file, rq.span,
                    "generic '" + rq.base + "' expects " + Int.ToString(tmpl.params.Length())
                    + " type argument(s) (" + String.Join(tmpl.params, ", ") + "), got "
                    + Int.ToString(rq.args.Length()) + " (" + String.Join(rq.args, ", ") + ")");
                self.mangler.RegisterGenericInstance(mangled);
                self.mangler.MarkGenericFailed(mangled);
                continue;
            }

            let bool sawVoid = false;
            let int a = 0;
            while (a < rq.args.Length()) {
                if (rq.args.Get(a).Trim() == "void") { sawVoid = true; }
                a = a + 1;
            }
            if (sawVoid) {
                self.diag.Error(Codes.UndefinedType(), rq.file, rq.span,
                    "'void' is not a valid type argument to '" + rq.base + "'");
                self.mangler.RegisterGenericInstance(mangled);
                self.mangler.MarkGenericFailed(mangled);
                continue;
            }

            let StringMap[String] binds = new StringMap[String]();
            let TopLevel concrete = self.Instantiate(tmpl, rq.args, mangled, binds);
            self.mangler.RegisterGenericInstance(mangled);

            let String requester = rq.file;
            match (scopeRequester.Find(mangled)) { case Some(r) { requester = r; } case None { } }
            requestedFrom.Put(mangled, requester);

            let List[TopLevel] list = null;
            match (instancesByBase.Find(rq.base)) {
                case Some(found) { list = found; }
                case None { list = new List[TopLevel](); instancesByBase.Put(rq.base, list); }
            }
            list.Add(concrete);

            match (deferredByOwner.Find(rq.base)) {
                case Some(deferred) {
                    let int k = 0;
                    while (k < deferred.Length()) {
                        let UseInFile df = deferred.Get(k);
                        k = k + 1;
                        let List[String] concreteArgs = self.SubstituteArgs(df.use, binds);
                        self.AddRequest(templates, tmplNames, requests, scopeRequester, pending,
                                        df.use.base, concreteArgs, df.use.span, df.file, requester);
                    }
                }
                case None { }
            }
        }

        let int i2 = 0;
        while (i2 < programs.Length()) {
            let ProgramFile pf = programs.Get(i2);
            i2 = i2 + 1;
            self.stripChanged = false;
            let List[TopLevel] hoisted = new List[TopLevel]();
            let List[TopLevel] rewritten = self.Strip(pf.prog.items, instancesByBase, hoisted);
            if (self.stripChanged) {
                let List[TopLevel] combined = new List[TopLevel]();
                combined.AddRange(hoisted);
                combined.AddRange(rewritten);
                pf.prog.items = combined;
            }
        }

        return requestedFrom;
    }

    /*
     * AddRequest - Files one instantiation request, queueing it when it is new. A request naming no
     * template, or naming the template's own parameter list, is not one.
     */
    bool func AddRequest(StringMap[Template] templates, StringSet tmplNames,
                         StringMap[GenericRequest] requests, StringMap[String] scopeRequester,
                         List[String] pending, String b, List[String] a, TextSpan sp,
                         String file, String requester) {
        if (!templates.Has(b)) { return false; }
        let String mangled = self.mangler.GenericInstance(b, a);
        if (tmplNames.Has(mangled)) { return false; }
        if (requests.Has(mangled)) { return false; }
        requests.Put(mangled, new GenericRequest(b, a, sp, file));
        scopeRequester.Put(mangled, requester);
        pending.Add(mangled);
        return true;
    }

    /*
     * Strip - Removes every generic template from a list of items, splicing the instances stamped
     * from it into `hoisted`, and recursing into realm and process bodies
     */
    List[TopLevel] func Strip(List[TopLevel] items, StringMap[List[TopLevel]] instancesByBase,
                              List[TopLevel] hoisted) {
        let List[TopLevel] kept = new List[TopLevel]();
        let int i = 0;
        while (i < items.Length()) {
            let TopLevel item = items.Get(i);
            i = i + 1;

            if (GenericParamsOf(item) != null) {
                self.stripChanged = true;
                match (instancesByBase.Find(TemplateBaseName(item))) {
                    case Some(instances) { hoisted.AddRange(instances); }
                    case None { }
                }
                continue;
            }

            match (item) {
                case ContextDecl(cd) {
                    let List[TopLevel] inner = self.Strip(cd.items, instancesByBase, hoisted);
                    let ContextDecl fresh = new ContextDecl(cd.kind, inner, cd.span);
                    kept.Add(TopLevel.ContextDecl(fresh));
                }
                case ProcessDecl(pd) {
                    let List[TopLevel] inner = self.Strip(pd.items, instancesByBase, hoisted);
                    let ProcessDecl fresh = new ProcessDecl(pd.name, pd.mode, pd.threads, pd.span);
                    fresh.items = inner;
                    kept.Add(TopLevel.ProcessDecl(fresh));
                }
                default { kept.Add(item); }
            }
        }
        return kept;
    }

    /*
     * SubstituteArgs - Rewrites a deferred use's type arguments against its owner's bindings, so
     * 'List[T]' in 'Foo[T]' becomes 'List[int]' when Foo[int] is stamped. Structural where the
     * parse kept the shape, since a whole-string lookup only catches a bare parameter.
     */
    List[String] func SubstituteArgs(GenericUse du, StringMap[String] binds) {
        let List[NamedSpec] specs = null;
        match (du.argSpecs) { case Some(s) { specs = s; } case None { } }

        if (specs == null || specs.Length() != du.args.Length()) {
            let List[String] flat = new List[String]();
            let int i = 0;
            while (i < du.args.Length()) {
                let String a = du.args.Get(i);
                i = i + 1;
                match (binds.Find(a)) { case Some(c) { flat.Add(c); } case None { flat.Add(a); } }
            }
            return flat;
        }

        let StringMap[TypeSpec] specMap = new StringMap[TypeSpec]();
        let List[String] bkeys = binds.Keys();
        let int b = 0;
        while (b < bkeys.Length()) {
            let String param = bkeys.Get(b);
            b = b + 1;
            specMap.Put(param, Specs.Named(binds.Get(param)));
        }
        let SubstitutionContext ctx = new SubstitutionContext(specMap, null);

        let List[String] result = new List[String]();
        let int i2 = 0;
        while (i2 < specs.Length()) {
            let TypeSpec sub = ctx.SubType(TypeSpec.NamedSpec(specs.Get(i2)));
            match (sub) {
                case NamedSpec(ns) { result.Add(ns.Mangled()); }
                default { result.Add(du.args.Get(i2)); }
            }
            i2 = i2 + 1;
        }
        return result;
    }

    /*
     * Instantiate - Clones a generic template with concrete type arguments, substituting type
     * parameters throughout signatures, native fields, and statement bodies. Fills `binds` with the
     * parameter-to-argument mapping the deferred replay needs.
     */
    TopLevel func Instantiate(Template tmpl, List[String] args, String mangled, StringMap[String] binds) {
        let StringMap[TypeSpec] specMap = new StringMap[TypeSpec]();
        let StringMap[String] cMap = new StringMap[String]();
        let int i = 0;
        while (i < tmpl.params.Length()) {
            let String prm = tmpl.params.Get(i);
            binds.Put(prm, args.Get(i));
            let TypeSpec spec = Specs.Named(args.Get(i));
            specMap.Put(prm, spec);
            cMap.Put(prm, CTypeOf(spec, self.mangler));
            i = i + 1;
        }
        let SubstitutionContext ctx = new SubstitutionContext(specMap, cMap);
        match (tmpl.decl) {
            case UnionDecl(utd) {
                let List[UnionVariant] variants = SubVariants(utd.variants, ctx);
                let UnionDecl fresh = new UnionDecl(mangled, new List[String](), variants,
                                                    utd.span, utd.annotations);
                return TopLevel.UnionDecl(fresh);
            }
            case ClassDecl(classTmpl) {
                let List[ClassMember] members = SubMembers(classTmpl.members, ctx);
                let ClassDecl fresh = new ClassDecl(mangled, new List[String](), classTmpl.annotations,
                                                    members, classTmpl.span, classTmpl.isModule);
                return TopLevel.ClassDecl(fresh);
            }
            default { return tmpl.decl; }
        }
    }

}

/*
 * CTypeOf - The C-type spelling for a Gata type argument, used when substituting type parameters
 * inside native struct fields and native bodies.
 *
 * A free function rather than a method because it needs nothing but the mangler, and the
 * TypeResolver has to answer the same question when it stamps an instance of its own.
 */
String func CTypeOf(TypeSpec t, Mangler m) {
    match (t) {
        case PtrSpec(p) { return CTypeOf(p.inner, m) + "*"; }
        case NamedSpec(n) {
            let String name = n.Mangled();
            if (name == "void") { return "void"; }
            if (PrimTypes.IsPrim(name)) { return PrimTypes.ToC(name); }
            if (name == BuiltinTypes.Str()) { return m.Class(BuiltinTypes.Str()) + "*"; }
            if (name == BuiltinTypes.Process() || name == BuiltinTypes.Thread()) { return "void*"; }
            return m.Class(name) + "*";
        }
        // Array/function specs cannot appear as generic type arguments.
        default { return Specs.ToSpecString(t); }
    }
}

/*
 * SubMembers - Substitutes every type mentioned in a class's members, returning the same list when
 * nothing changed
 */
List[ClassMember] func SubMembers(List[ClassMember] members, SubstitutionContext ctx) {
    let List[ClassMember] result = null;
    let int i = 0;
    while (i < members.Length()) {
        let ClassMember sm = SubMember(members.Get(i), ctx);
        if (!SameMember(sm, members.Get(i)) && result == null) {
            result = new List[ClassMember]();
            let int c = 0;
            while (c < i) { result.Add(members.Get(c)); c = c + 1; }
        }
        if (result != null) { result.Add(sm); }
        i = i + 1;
    }
    return result == null ? members : result;
}

/*
 * SubVariants - Substitutes every type mentioned in a union's variant payloads
 */
List[UnionVariant] func SubVariants(List[UnionVariant] variants, SubstitutionContext ctx) {
    let List[UnionVariant] result = new List[UnionVariant]();
    let int i = 0;
    while (i < variants.Length()) {
        let UnionVariant v = variants.Get(i);
        i = i + 1;
        result.Add(new UnionVariant(v.name, SubParams(v.variantFields, ctx), v.span));
    }
    return result;
}

/*
 * SubMember - Substitutes type parameters in a single class member (field, method, or operator)
 */
ClassMember func SubMember(ClassMember m, SubstitutionContext ctx) {
    match (m) {
        case FieldsBlock(fb) {
            let NativeBody nb = SubNative(fb.body, ctx);
            if (nb == fb.body) { return m; }
            return ClassMember.FieldsBlock(new FieldsBlock(nb, fb.span));
        }
        case FieldDecl(fd) { return SubFieldDecl(fd, ctx); }
        case MethodDecl(md) { return SubMethodDecl(md, ctx); }
        case OperatorDecl(od) { return SubOperatorDecl(od, ctx); }
    }
}

/*
 * SubFieldDecl - Substitutes type parameters in a field declaration, including its type and
 * initializer expression
 */
ClassMember func SubFieldDecl(FieldDecl fd, SubstitutionContext ctx) {
    let Optional[TypeSpec] newType = SubOptType(fd.type, ctx);
    let Optional[Expr] newInit = SubOptExpr(fd.init, ctx);
    if (SameOptSpec(newType, fd.type) && SameOptExpr(newInit, fd.init)) {
        return ClassMember.FieldDecl(fd);
    }
    return ClassMember.FieldDecl(new FieldDecl(fd.modifiers, newType, fd.name, fd.span, newInit));
}

/*
 * SubMethodDecl - Substitutes type parameters in a method declaration, including its return type,
 * parameters, and body
 */
ClassMember func SubMethodDecl(MethodDecl md, SubstitutionContext ctx) {
    let Optional[TypeSpec] newRet = SubOptType(md.returnType, ctx);
    let List[Param] newParams = SubParams(md.params, ctx);
    let MethodBody newBody = SubBodyBound(md.body, md.params, ctx);
    if (SameOptSpec(newRet, md.returnType) && newParams == md.params && SameBody(newBody, md.body)) {
        return ClassMember.MethodDecl(md);
    }
    return ClassMember.MethodDecl(new MethodDecl(md.modifiers, md.annotations, newRet, md.name,
        md.genericParams, newParams, md.isEntry, md.isThrows, newBody, md.span));
}

/*
 * SubOperatorDecl - Substitutes type parameters in an operator declaration, including its return
 * type, parameters, and body
 */
ClassMember func SubOperatorDecl(OperatorDecl od, SubstitutionContext ctx) {
    let List[Param] newParams = SubParams(od.params, ctx);
    let Optional[TypeSpec] newRet = SubOptType(od.returnType, ctx);
    let MethodBody newBody = SubBodyBound(od.body, od.params, ctx);
    if (newParams == od.params && SameOptSpec(newRet, od.returnType) && SameBody(newBody, od.body)) {
        return ClassMember.OperatorDecl(od);
    }
    return ClassMember.OperatorDecl(new OperatorDecl(od.modifiers, od.op, newParams, newRet,
                                                     newBody, od.span));
}

/*
 * SubParams - Substitutes type parameters in a parameter list, returning the same list when
 * nothing changed
 */
List[Param] func SubParams(List[Param] ps, SubstitutionContext ctx) {
    let List[Param] newParams = null;
    let int i = 0;
    while (i < ps.Length()) {
        let Param prm = ps.Get(i);
        let TypeSpec newType = ctx.SubType(prm.type);
        if (!SameSpec(newType, prm.type) && newParams == null) {
            newParams = new List[Param]();
            let int c = 0;
            while (c < i) { newParams.Add(ps.Get(c)); c = c + 1; }
        }
        if (newParams != null) { newParams.Add(new Param(newType, prm.name, prm.span, prm.isRef)); }
        i = i + 1;
    }
    return newParams == null ? ps : newParams;
}

/*
 * SubBodyBound - Substitutes a method body with its parameters bound, so a parameter named like a
 * scoped type keeps meaning the parameter
 */
MethodBody func SubBodyBound(MethodBody b, List[Param] ps, SubstitutionContext ctx) {
    let int mark = ctx.Mark();
    ctx.BindParams(ps);
    let MethodBody result = SubBody(b, ctx);
    ctx.Release(mark);
    return result;
}

/*
 * SubBody - Substitutes type parameters in a method body, dispatching to the native or block form
 */
MethodBody func SubBody(MethodBody b, SubstitutionContext ctx) {
    match (b) {
        case NativeMethodBody(nmb) {
            let NativeBody nb = SubNative(nmb.native, ctx);
            if (nb == nmb.native) { return b; }
            return MethodBody.NativeMethodBody(new NativeMethodBody(nb));
        }
        case BlockBody(bb) {
            let Block nblk = SubBlock(bb.block, ctx);
            if (nblk == bb.block) { return b; }
            return MethodBody.BlockBody(new BlockBody(nblk));
        }
    }
}

/*
 * SubNative - Substitutes type parameters in a native body's code string
 */
NativeBody func SubNative(NativeBody nb, SubstitutionContext ctx) {
    let String newC = ctx.SubWords(nb.c);
    if (newC == nb.c) { return nb; }
    return new NativeBody(newC);
}

/*
 * SubBlock - Substitutes type parameters in a block of statements, returning the same block when
 * nothing changed
 */
Block func SubBlock(Block b, SubstitutionContext ctx) {
    let int mark = ctx.Mark();
    let List[Stmt] newStmts = null;
    let int i = 0;
    while (i < b.stmts.Length()) {
        let Stmt s = b.stmts.Get(i);
        let Stmt ns = SubStmt(s, ctx);
        match (s) { case LetStmt(ls) { ctx.Bind(ls.name); } default { } }
        if (!SameStmt(s, ns) && newStmts == null) {
            newStmts = new List[Stmt]();
            let int c = 0;
            while (c < i) { newStmts.Add(b.stmts.Get(c)); c = c + 1; }
        }
        if (newStmts != null) { newStmts.Add(ns); }
        i = i + 1;
    }
    ctx.Release(mark);
    if (newStmts == null) { return b; }
    return new Block(newStmts, b.span);
}

/*
 * SubExprList - Substitutes every expression in a list, or null when none changed
 */
List[Expr] func SubExprList(List[Expr] xs, SubstitutionContext ctx) {
    let List[Expr] result = null;
    let int i = 0;
    while (i < xs.Length()) {
        let Expr na = SubExpr(xs.Get(i), ctx);
        if (!SameExpr(na, xs.Get(i)) && result == null) {
            result = new List[Expr]();
            let int c = 0;
            while (c < i) { result.Add(xs.Get(c)); c = c + 1; }
        }
        if (result != null) { result.Add(na); }
        i = i + 1;
    }
    return result;
}

/*
 * SubStmt - Substitutes type parameters in a single statement, recursively processing any nested
 * statements or expressions.
 *
 * The match is exhaustive on purpose: C# guards its default arm with a DEBUG-only assertion that a
 * statement reaching it has nothing to substitute, and an exhaustive match makes a new statement
 * kind a compile error instead.
 */
Stmt func SubStmt(Stmt s, SubstitutionContext ctx) {
    match (s) {
        case Block(b) {
            let Block nb = SubBlock(b, ctx);
            if (nb == b) { return s; }
            return Stmt.Block(nb);
        }
        case LetStmt(ls) {
            let Optional[TypeSpec] newType = SubOptType(ls.type, ctx);
            let Optional[Expr] newInit = SubOptExpr(ls.init, ctx);
            if (SameOptSpec(newType, ls.type) && SameOptExpr(newInit, ls.init)) { return s; }
            return Stmt.LetStmt(new LetStmt(newType, ls.name, newInit, ls.span));
        }
        case AssignStmt(a) {
            let Expr nt = SubExpr(a.target, ctx);
            let Expr nv = SubExpr(a.value, ctx);
            if (SameExpr(nt, a.target) && SameExpr(nv, a.value)) { return s; }
            return Stmt.AssignStmt(new AssignStmt(nt, a.op, nv, a.span));
        }
        case ExprStmt(es) {
            let Expr ne = SubExpr(es.e, ctx);
            if (SameExpr(ne, es.e)) { return s; }
            return Stmt.ExprStmt(new ExprStmt(ne, es.span));
        }
        case IfStmt(ifs) {
            let Expr nc = SubExpr(ifs.cond, ctx);
            let Stmt nt = SubStmt(ifs.then, ctx);
            let Optional[Stmt] nel = SubOptStmt(ifs.otherwise, ctx);
            if (SameExpr(nc, ifs.cond) && SameStmt(nt, ifs.then) && SameOptStmt(nel, ifs.otherwise)) {
                return s;
            }
            return Stmt.IfStmt(new IfStmt(nc, nt, nel, ifs.span));
        }
        case WhileStmt(ws) {
            let Expr nc = SubExpr(ws.cond, ctx);
            let Stmt nb = SubStmt(ws.body, ctx);
            if (SameExpr(nc, ws.cond) && SameStmt(nb, ws.body)) { return s; }
            return Stmt.WhileStmt(new WhileStmt(nc, nb, ws.span));
        }
        case ForStmt(fs) {
            let int forMark = ctx.Mark();
            let Optional[Stmt] ni = SubOptStmt(fs.init, ctx);
            match (fs.init) {
                case Some(initStmt) {
                    match (initStmt) { case LetStmt(fl) { ctx.Bind(fl.name); } default { } }
                }
                case None { }
            }
            let Optional[Expr] nc = SubOptExpr(fs.cond, ctx);
            let Optional[Stmt] nst = SubOptStmt(fs.step, ctx);
            let Block nb = SubBlock(fs.body, ctx);
            ctx.Release(forMark);
            if (SameOptStmt(ni, fs.init) && SameOptExpr(nc, fs.cond) && SameOptStmt(nst, fs.step)
                && nb == fs.body) {
                return s;
            }
            return Stmt.ForStmt(new ForStmt(ni, nc, nst, nb, fs.span));
        }
        case ForInStmt(fi) {
            let Expr nc = SubExpr(fi.collection, ctx);
            let int inMark = ctx.Mark();
            ctx.Bind(fi.varName);
            let Block nb = SubBlock(fi.body, ctx);
            ctx.Release(inMark);
            if (SameExpr(nc, fi.collection) && nb == fi.body) { return s; }
            return Stmt.ForInStmt(new ForInStmt(fi.varName, nc, nb, fi.span));
        }
        case ReturnStmt(rs) {
            let Optional[Expr] nv = SubOptExpr(rs.value, ctx);
            if (SameOptExpr(nv, rs.value)) { return s; }
            return Stmt.ReturnStmt(new ReturnStmt(nv, rs.span));
        }
        case AssignValueStmt(av) {
            let Expr nv = SubExpr(av.value, ctx);
            if (SameExpr(nv, av.value)) { return s; }
            return Stmt.AssignValueStmt(new AssignValueStmt(nv, av.span));
        }
        case TryCatchStmt(tc) {
            let Block nt = SubBlock(tc.tryBlock, ctx);
            let Block ncb = SubBlock(tc.catchBlock, ctx);
            if (nt == tc.tryBlock && ncb == tc.catchBlock) { return s; }
            return Stmt.TryCatchStmt(new TryCatchStmt(nt, ncb, tc.span));
        }
        case DeferStmt(dfr) {
            let Stmt na = SubStmt(dfr.action, ctx);
            if (SameStmt(na, dfr.action)) { return s; }
            return Stmt.DeferStmt(new DeferStmt(na, dfr.span));
        }
        case UnsafeBlock(ub) {
            let List[Stmt] newStmts = null;
            let int i = 0;
            while (i < ub.stmts.Length()) {
                let Stmt nx = SubStmt(ub.stmts.Get(i), ctx);
                if (!SameStmt(nx, ub.stmts.Get(i)) && newStmts == null) {
                    newStmts = new List[Stmt]();
                    let int c = 0;
                    while (c < i) { newStmts.Add(ub.stmts.Get(c)); c = c + 1; }
                }
                if (newStmts != null) { newStmts.Add(nx); }
                i = i + 1;
            }
            if (newStmts == null) { return s; }
            return Stmt.UnsafeBlock(new UnsafeBlock(newStmts, ub.span));
        }
        case SwitchStmt(sw) {
            let Expr nscrut = SubExpr(sw.scrutinee, ctx);
            let List[SwitchCase] newCases = null;
            let int i = 0;
            while (i < sw.cases.Length()) {
                let SwitchCase c = sw.cases.Get(i);
                let List[Expr] newLabels = SubExprList(c.labels, ctx);
                let Block newBody = SubBlock(c.body, ctx);
                let bool caseChanged = newLabels != null || newBody != c.body;
                if (caseChanged && newCases == null) {
                    newCases = new List[SwitchCase]();
                    let int k = 0;
                    while (k < i) { newCases.Add(sw.cases.Get(k)); k = k + 1; }
                }
                if (newCases != null) {
                    newCases.Add(caseChanged
                        ? new SwitchCase(newLabels == null ? c.labels : newLabels, newBody, c.span)
                        : c);
                }
                i = i + 1;
            }
            let Optional[Block] newDef = SubOptBlock(sw.otherwise, ctx);
            if (SameExpr(nscrut, sw.scrutinee) && newCases == null && SameOptBlock(newDef, sw.otherwise)) {
                return s;
            }
            return Stmt.SwitchStmt(new SwitchStmt(nscrut, newCases == null ? sw.cases : newCases,
                                                  newDef, sw.span));
        }
        case MatchStmt(ms) {
            let Expr nscrut = SubExpr(ms.scrutinee, ctx);
            let List[MatchCase] newCases = null;
            let int i = 0;
            while (i < ms.cases.Length()) {
                let MatchCase c = ms.cases.Get(i);
                let int caseMark = ctx.Mark();
                ctx.BindNames(c.bindings);
                let Block newBody = SubBlock(c.body, ctx);
                ctx.Release(caseMark);
                if (newBody != c.body && newCases == null) {
                    newCases = new List[MatchCase]();
                    let int k = 0;
                    while (k < i) { newCases.Add(ms.cases.Get(k)); k = k + 1; }
                }
                if (newCases != null) {
                    newCases.Add(newBody != c.body
                        ? new MatchCase(c.variant, c.bindings, newBody, c.span)
                        : c);
                }
                i = i + 1;
            }
            let Optional[Block] newDef = SubOptBlock(ms.otherwise, ctx);
            if (SameExpr(nscrut, ms.scrutinee) && newCases == null && SameOptBlock(newDef, ms.otherwise)) {
                return s;
            }
            return Stmt.MatchStmt(new MatchStmt(nscrut, newCases == null ? ms.cases : newCases,
                                                newDef, ms.span));
        }

        // Nothing to substitute in any of these.
        case NativeStmt(x)   { return s; }
        case BreakStmt(x)    { return s; }
        case ContinueStmt(x) { return s; }
        case ThrowStmt(x)    { return s; }
        case DebugStmt(x)    { return s; }
        case PanicStmt(x)    { return s; }
    }
}

/*
 * SubExpr - Substitutes type parameters in an expression, recursively processing any
 * sub-expressions and types. Exhaustive for the same reason SubStmt is.
 */
Expr func SubExpr(Expr e, SubstitutionContext ctx) {
    match (e) {
        case ScopedNameExpr(sn) {
            if (ctx.HasScopedResolver()) {
                return ctx.binder.ResolveScopedExpr(sn, ctx.tree, ctx.index, ctx.from, ctx.file);
            }
            return e;
        }
        case IdentExpr(id) {
            if (ctx.rewriteTypeNames && !ctx.IsBound(id.name)) {
                match (ctx.specMap.Find(id.name)) {
                    case Some(bound) {
                        match (bound) {
                            case NamedSpec(ns) {
                                if (ns.args.Length() == 0) {
                                    return Expr.IdentExpr(new IdentExpr(ns.name, id.span));
                                }
                            }
                            default { }
                        }
                    }
                    case None { }
                }
            }
            return e;
        }
        case CastExpr(ce) {
            let TypeSpec nt = ctx.SubType(ce.targetType);
            let Expr nv = SubExpr(ce.value, ctx);
            if (SameSpec(nt, ce.targetType) && SameExpr(nv, ce.value)) { return e; }
            return Expr.CastExpr(new CastExpr(nt, nv, ce.span));
        }
        case GenericTypeRefExpr(gt) {
            let List[NamedSpec] subArgs = new List[NamedSpec]();
            let bool argsChanged = false;
            let int i = 0;
            while (i < gt.args.Length()) {
                let TypeSpec sub = ctx.SubType(TypeSpec.NamedSpec(gt.args.Get(i)));
                let NamedSpec picked = gt.args.Get(i);
                match (sub) { case NamedSpec(ns) { picked = ns; } default { } }
                if (picked != gt.args.Get(i)) { argsChanged = true; }
                subArgs.Add(picked);
                i = i + 1;
            }
            let Optional[Expr] subIndex = SubOptExpr(gt.indexForm, ctx);
            let String subName = gt.name;
            if (ctx.rewriteTypeNames && !ctx.IsBound(gt.name)) {
                match (ctx.nameMap.Find(gt.name)) { case Some(nm) { subName = nm; } case None { } }
            }
            if (!argsChanged && SameOptExpr(subIndex, gt.indexForm) && subName == gt.name) { return e; }
            return Expr.GenericTypeRefExpr(new GenericTypeRefExpr(subName, subArgs, subIndex, gt.span));
        }
        case TernaryExpr(te) {
            let Expr nc = SubExpr(te.cond, ctx);
            let Expr nt = SubExpr(te.then, ctx);
            let Expr nel = SubExpr(te.otherwise, ctx);
            if (SameExpr(nc, te.cond) && SameExpr(nt, te.then) && SameExpr(nel, te.otherwise)) { return e; }
            return Expr.TernaryExpr(new TernaryExpr(nc, nt, nel, te.span));
        }
        case NewExpr(ne) {
            let TypeSpec nt = ctx.SubType(ne.type);
            let List[Expr] nargs = SubExprList(ne.args, ctx);
            let List[Expr] ncoll = SubExprList(ne.collectionInit, ctx);
            if (SameSpec(nt, ne.type) && nargs == null && ncoll == null) { return e; }
            return Expr.NewExpr(new NewExpr(nt, nargs == null ? ne.args : nargs,
                                            ncoll == null ? ne.collectionInit : ncoll, ne.span));
        }
        case ArrayLitExpr(al) {
            let List[Expr] nelems = SubExprList(al.elems, ctx);
            if (nelems == null) { return e; }
            return Expr.ArrayLitExpr(new ArrayLitExpr(nelems, al.span));
        }
        case CatchCallExpr(cc) {
            let Expr ncall = SubExpr(cc.call, ctx);
            let Block nh = SubBlock(cc.handler, ctx);
            if (SameExpr(ncall, cc.call) && nh == cc.handler) { return e; }
            return Expr.CatchCallExpr(new CatchCallExpr(ncall, nh, cc.span));
        }
        case CallExpr(cx) {
            let Expr ncallee = SubExpr(cx.callee, ctx);
            let List[Expr] nargs = SubExprList(cx.args, ctx);
            if (SameExpr(ncallee, cx.callee) && nargs == null) { return e; }
            return Expr.CallExpr(new CallExpr(ncallee, nargs == null ? cx.args : nargs, cx.span));
        }
        case MemberAccessExpr(ma) {
            let Expr nobj = SubExpr(ma.object, ctx);
            if (SameExpr(nobj, ma.object)) { return e; }
            return Expr.MemberAccessExpr(new MemberAccessExpr(nobj, ma.member, ma.span));
        }
        case IndexExpr(ix) {
            let Expr nobj = SubExpr(ix.object, ctx);
            let Expr nidx = SubExpr(ix.index, ctx);
            if (SameExpr(nobj, ix.object) && SameExpr(nidx, ix.index)) { return e; }
            return Expr.IndexExpr(new IndexExpr(nobj, nidx, ix.span));
        }
        case BinExpr(be) {
            let Expr nl = SubExpr(be.left, ctx);
            let Expr nr = SubExpr(be.right, ctx);
            if (SameExpr(nl, be.left) && SameExpr(nr, be.right)) { return e; }
            return Expr.BinExpr(new BinExpr(be.op, nl, nr, be.span));
        }
        case UnaryExpr(un) {
            let Expr no = SubExpr(un.operand, ctx);
            if (SameExpr(no, un.operand)) { return e; }
            return Expr.UnaryExpr(new UnaryExpr(un.op, no, un.span));
        }
        case PostfixExpr(pf) {
            let Expr no = SubExpr(pf.operand, ctx);
            if (SameExpr(no, pf.operand)) { return e; }
            return Expr.PostfixExpr(new PostfixExpr(pf.op, no, pf.span));
        }
        case AddrOfExpr(ao) {
            let Expr nt = SubExpr(ao.target, ctx);
            if (SameExpr(nt, ao.target)) { return e; }
            return Expr.AddrOfExpr(new AddrOfExpr(nt, ao.span));
        }
        case DerefExpr(dr) {
            let Expr np = SubExpr(dr.ptr, ctx);
            if (SameExpr(np, dr.ptr)) { return e; }
            return Expr.DerefExpr(new DerefExpr(np, dr.span));
        }
        case RefArgExpr(ra) {
            let Expr nt = SubExpr(ra.target, ctx);
            if (SameExpr(nt, ra.target)) { return e; }
            return Expr.RefArgExpr(new RefArgExpr(nt, ra.span));
        }
        case InterpStrExpr(ip) {
            let List[Expr] nparts = SubExprList(ip.parts, ctx);
            if (nparts == null) { return e; }
            return Expr.InterpStrExpr(new InterpStrExpr(nparts, ip.span));
        }
        case SizeofExpr(so) {
            let TypeSpec nt = ctx.SubType(so.typeName);
            if (SameSpec(nt, so.typeName)) { return e; }
            return Expr.SizeofExpr(new SizeofExpr(nt, so.span));
        }
        case DefaultExpr(de) {
            let TypeSpec nt = ctx.SubType(de.typeName);
            if (SameSpec(nt, de.typeName)) { return e; }
            return Expr.DefaultExpr(new DefaultExpr(nt, de.span));
        }

        // Literals and the poison node: nothing to substitute.
        case IntLitExpr(x)   { return e; }
        case CharLitExpr(x)  { return e; }
        case FloatLitExpr(x) { return e; }
        case BoolLitExpr(x)  { return e; }
        case StrLitExpr(x)   { return e; }
        case NullExpr(x)     { return e; }
        case PoisonExpr(x)   { return e; }
    }
}

/*
 * UnifyParam - Tries to bind a type parameter inferred from one argument position
 */
bool func UnifyParam(TypeSpec paramType, IrType argType, List[String] gparams,
                     StringMap[TypeSpec] binds, Mangler m) {
    match (paramType) {
        case NamedSpec(n) {
            if (n.args.Length() == 0 && gparams.Contains(n.name)) {
                return BindParam(n.name, SpecOf(argType), binds);
            }
            if (n.args.Length() > 0) {
                let String instName = NameOfInstance(argType);
                if (instName == null) { return true; }
                match (m.TryGetGenericInstance(instName)) {
                    case None { return true; }
                    case Some(key) {
                        let List[String] instArgs = GK.Args(key);
                        if (GK.Base(key) != n.name || instArgs.Length() != n.args.Length()) { return true; }
                        let int i = 0;
                        while (i < n.args.Length()) {
                            let NamedSpec an = n.args.Get(i);
                            if (an.args.Length() == 0 && gparams.Contains(an.name)) {
                                if (!BindParam(an.name, Specs.Named(instArgs.Get(i)), binds)) {
                                    return false;
                                }
                            }
                            i = i + 1;
                        }
                        return true;
                    }
                }
            }
            return true;
        }
        case PtrSpec(p) {
            match (p.inner) {
                case NamedSpec(pn) {
                    if (pn.args.Length() == 0 && gparams.Contains(pn.name)) {
                        match (argType) {
                            case IrPtrType(ptr) { return BindParam(pn.name, SpecOf(ptr.inner), binds); }
                            default { return true; }
                        }
                    }
                    return true;
                }
                default { return true; }
            }
        }
        default { return true; }
    }
}

/*
 * NameOfInstance - The declared name of a type that could be a stamped generic instance - a class
 * reference or a union - or null for anything that could not be one
 */
String func NameOfInstance(IrType t) {
    match (t) {
        case IrClassRef(cr) { return cr.className; }
        case IrUnionType(ut) { return ut.name; }
        default { return null; }
    }
}

/*
 * BindParam - Records one inference, or rejects a second one disagreeing with the first
 */
bool func BindParam(String param, TypeSpec spec, StringMap[TypeSpec] binds) {
    match (binds.Find(param)) {
        case Some(prev) { return Specs.ToSpecString(prev) == Specs.ToSpecString(spec); }
        case None { binds.Put(param, spec); return true; }
    }
}

/*
 * SpecOf - The type spec for a resolved IR type, used as the binding value when inferring type
 * arguments from call-site argument types
 */
TypeSpec func SpecOf(IrType t) {
    match (t) {
        case IrPrimType(p)  { return Specs.Named(p.cName); }
        case IrClassRef(c)  { return Specs.Named(c.className); }
        case IrEnumType(en) { return Specs.Named(en.name); }
        case IrUnionType(u) { return Specs.Named(u.name); }
        case IrVoidType(v)  { return Specs.Named("void"); }
        case IrPtrType(pt)  { return TypeSpec.PtrSpec(new PtrSpec(SpecOf(pt.inner), TS.NoneSpan())); }
        case IrArrayType(a) {
            return TypeSpec.ArraySpec(new ArraySpec(Int.ToString(a.size), SpecOf(a.elem), TS.NoneSpan()));
        }
        case IrFuncPtrType(f) {
            let List[TypeSpec] ps = new List[TypeSpec]();
            let int i = 0;
            while (i < f.params.Length()) { ps.Add(SpecOf(f.params.Get(i))); i = i + 1; }
            return TypeSpec.FuncSpec(new FuncSpec(ps, SpecOf(f.ret), TS.NoneSpan()));
        }
        default { return Specs.Named(Types.MangledName(t)); }
    }
}

/*
 * SanitizeTypeName - Reduces a type name to a valid C-identifier fragment for use in mangled
 * generic names. Pointer stars become "_p"; all other non-identifier characters are dropped.
 */
String func SanitizeTypeName(TypeSpec t) {
    let StringBuilder sb = new StringBuilder();
    AppendSanitized(sb, t);
    let String s = sb.ToString();
    return s.Length() == 0 ? "x" : s;
}

/*
 * AppendSanitized - Appends one spec's C-identifier fragment: identifier text is kept, a pointer
 * star becomes a _p marker, and the punctuation the flat spelling would have introduced is never
 * written in the first place
 */
void func AppendSanitized(StringBuilder sb, TypeSpec t) {
    match (t) {
        case NamedSpec(n) {
            AppendIdentifierChars(sb, n.name);
            let int i = 0;
            while (i < n.args.Length()) {
                sb.AppendChar('_');
                AppendSanitized(sb, TypeSpec.NamedSpec(n.args.Get(i)));
                i = i + 1;
            }
        }
        case PtrSpec(p) { AppendSanitized(sb, p.inner); sb.Put("_p"); }
        case ArraySpec(a) { AppendIdentifierChars(sb, a.sizeText); AppendSanitized(sb, a.elem); }
        case FuncSpec(f) {
            sb.Put("func");
            let int i = 0;
            while (i < f.params.Length()) { AppendSanitized(sb, f.params.Get(i)); i = i + 1; }
            AppendSanitized(sb, f.ret);
        }
    }
}

/*
 * AppendIdentifierChars - Appends the characters of a written name that a C identifier may carry
 */
void func AppendIdentifierChars(StringBuilder sb, String s) {
    let int i = 0;
    while (i < s.Length()) {
        let char c = s.CharAt(i);
        if (Mangle.IsIdentChar(c)) { sb.AppendChar(c); }
        i = i + 1;
    }
}

/*
 * EachDecl - Every declaration in a program, descending into realm and process bodies. The single
 * walk shared by template collection, owner lookup, the splice and the reference-cycle report, so
 * a declaration form one of them can see is never one another silently cannot.
 */
List[TopLevel] func EachDecl(List[TopLevel] items) {
    let List[TopLevel] out = new List[TopLevel]();
    let int i = 0;
    while (i < items.Length()) {
        let TopLevel item = items.Get(i);
        i = i + 1;
        out.Add(item);
        match (item) {
            case ContextDecl(cd) { out.AddRange(EachDecl(cd.items)); }
            case ProcessDecl(pd) { out.AddRange(EachDecl(pd.items)); }
            default { }
        }
    }
    return out;
}

/*
 * GenericParamsOf - The type parameters of a generic class or union template, or null for anything
 * that is not one
 */
List[String] func GenericParamsOf(TopLevel item) {
    match (item) {
        case ClassDecl(cd) { return cd.genericParams.Length() > 0 ? cd.genericParams : null; }
        case UnionDecl(ud) { return ud.genericParams.Length() > 0 ? ud.genericParams : null; }
        default { return null; }
    }
}

/*
 * TemplateBaseName - The written base name of a generic template
 */
String func TemplateBaseName(TopLevel item) {
    match (item) {
        case ClassDecl(cd) { return cd.baseName; }
        case UnionDecl(ud) { return ud.baseName; }
        default { return ""; }
    }
}

/*
 * Within - True when the inner span lies inside the outer one
 */
bool func Within(TextSpan inner, TextSpan outer) {
    return TS.Start(inner) >= TS.Start(outer) && TS.End(inner) <= TS.End(outer);
}

/*
 * MentionsParam - True if any type argument mentions one of the given parameters, at any depth.
 * Testing whether an argument *is* one caught 'List[T]' in 'Foo[T]' but not 'List[Node[T]]' in
 * 'Node[T]'; requiring *every* argument to be one missed 'Pair[T, int]'.
 */
bool func MentionsParam(GenericUse use, List[String] parameters) {
    if (parameters.Length() == 0) { return false; }

    let List[NamedSpec] specs = null;
    match (use.argSpecs) { case Some(s) { specs = s; } case None { } }

    if (specs == null || specs.Length() != use.args.Length()) {
        let int i = 0;
        while (i < use.args.Length()) {
            if (parameters.Contains(use.args.Get(i))) { return true; }
            i = i + 1;
        }
        return false;
    }

    let int j = 0;
    while (j < specs.Length()) {
        if (SpecMentions(specs.Get(j), parameters)) { return true; }
        j = j + 1;
    }
    return false;
}

/*
 * SpecMentions - True when a spec names one of the parameters at any depth
 */
bool func SpecMentions(NamedSpec s, List[String] parameters) {
    if (s.args.Length() == 0) { return parameters.Contains(s.name); }
    let int i = 0;
    while (i < s.args.Length()) {
        if (SpecMentions(s.args.Get(i), parameters)) { return true; }
        i = i + 1;
    }
    return false;
}

/*
 * SubOptType / SubOptExpr / SubOptStmt / SubOptBlock - The Optional forms of the walkers, standing
 * in for C#'s `x is null ? null : Sub(x)`
 */
Optional[TypeSpec] func SubOptType(Optional[TypeSpec] t, SubstitutionContext ctx) {
    match (t) {
        case Some(v) { return Optional.Some(ctx.SubType(v)); }
        case None { return t; }
    }
}

Optional[Expr] func SubOptExpr(Optional[Expr] e, SubstitutionContext ctx) {
    match (e) {
        case Some(v) { return Optional.Some(SubExpr(v, ctx)); }
        case None { return e; }
    }
}

Optional[Stmt] func SubOptStmt(Optional[Stmt] s, SubstitutionContext ctx) {
    match (s) {
        case Some(v) { return Optional.Some(SubStmt(v, ctx)); }
        case None { return s; }
    }
}

Optional[Block] func SubOptBlock(Optional[Block] b, SubstitutionContext ctx) {
    match (b) {
        case Some(v) { return Optional.Some(SubBlock(v, ctx)); }
        case None { return b; }
    }
}

/*
 * The identity comparisons standing in for C#'s ReferenceEquals. A union holding one class
 * reference compares by exactly that identity, so each of these is the reference check C# writes -
 * funnelled to one site per union so G083, which is right, is raised once rather than everywhere.
 */
bool func SameSpec(TypeSpec a, TypeSpec b) { return a == b; }
bool func SameExpr(Expr a, Expr b) { return a == b; }
bool func SameStmt(Stmt a, Stmt b) { return a == b; }
bool func SameMember(ClassMember a, ClassMember b) { return a == b; }
bool func SameBody(MethodBody a, MethodBody b) { return a == b; }

bool func SameOptSpec(Optional[TypeSpec] a, Optional[TypeSpec] b) {
    match (a) {
        case Some(x) { match (b) { case Some(y) { return SameSpec(x, y); } case None { return false; } } }
        case None { match (b) { case Some(y) { return false; } case None { return true; } } }
    }
}

bool func SameOptExpr(Optional[Expr] a, Optional[Expr] b) {
    match (a) {
        case Some(x) { match (b) { case Some(y) { return SameExpr(x, y); } case None { return false; } } }
        case None { match (b) { case Some(y) { return false; } case None { return true; } } }
    }
}

bool func SameOptStmt(Optional[Stmt] a, Optional[Stmt] b) {
    match (a) {
        case Some(x) { match (b) { case Some(y) { return SameStmt(x, y); } case None { return false; } } }
        case None { match (b) { case Some(y) { return false; } case None { return true; } } }
    }
}

bool func SameOptBlock(Optional[Block] a, Optional[Block] b) {
    match (a) {
        case Some(x) { match (b) { case Some(y) { return x == y; } case None { return false; } } }
        case None { match (b) { case Some(y) { return false; } case None { return true; } } }
    }
}
