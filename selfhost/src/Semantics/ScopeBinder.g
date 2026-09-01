/*
 * ScopeBinder.g - resolves scoped declaration names to globally unique ones, ahead of every
 * other pass
 *
 * Ports Appa/src/Semantics/ScopeBinder.cs.
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
import "src/Semantics/ScopeTree.g";
import "src/Semantics/Monomorphizer.g";
import "src/Backend/Mangler.g";

/*
 * The scope tree of a program plus the index of what each scope declares.
 */
class ScopeBindResult {
    public ScopeTree tree;
    public ScopeIndex index;
    func _init(ScopeTree tree, ScopeIndex index) { self.tree = tree; self.index = index; }
}

/*
 * Maps a written name to the globally unique name it refers to, from a given scope.
 */
class ScopeIndex {
    ScopeTree tree;
    Map[int, StringMap[String]] byScope;
    StringMap[int] declScopeOf;

    func _init(ScopeTree tree) {
        self.tree = tree;
        self.byScope = new Map[int, StringMap[String]]();
        self.declScopeOf = new StringMap[int]();
    }

    /*
     * HasScopedDeclarations - True when any declaration at all lives outside the root scope
     */
    public bool func HasScopedDeclarations() { return self.declScopeOf.Length() > 0; }

    /*
     * Declare - Records that `scope` declares `name`, which is globally known as `qualified`
     */
    public void func Declare(ScopeId scope, String name, String qualified) {
        let StringMap[String] names = null;
        match (self.byScope.Find(Sc.Value(scope))) {
            case Some(existing) { names = existing; }
            case None { names = new StringMap[String](); self.byScope.Put(Sc.Value(scope), names); }
        }
        names.Put(name, qualified);
        if (!Sc.IsRoot(scope)) { self.declScopeOf.Put(qualified, Sc.Value(scope)); }
    }

    /*
     * DeclaredIn - Every written name declared directly in a scope, in insertion-independent
     * order.
     */
    public List[String] func DeclaredIn(ScopeId scope) {
        match (self.byScope.Find(Sc.Value(scope))) {
            case Some(names) { return names.Keys(); }
            case None { return new List[String](); }
        }
    }

    /*
     * TryDeclared - The qualified name a scope declares directly, or None.
     */
    public Optional[String] func TryDeclared(ScopeId scope, String written) {
        match (self.byScope.Find(Sc.Value(scope))) {
            case Some(names) { return names.Find(written); }
            case None { return Optional[String].None(); }
        }
    }

    /*
     * Resolve - Resolves a written name as seen from `from`, walking outward.
     */
    public Optional[String] func Resolve(ScopeId from, String written) {
        let ScopeId s = from;
        while (true) {
            match (self.byScope.Find(Sc.Value(s))) {
                case Some(names) {
                    match (names.Find(written)) {
                        case Some(q) { return Optional.Some(q); }
                        case None { }
                    }
                }
                case None { }
            }
            if (Sc.IsRoot(s)) { return Optional[String].None(); }
            s = self.tree.Parent(s);
        }
    }

    /*
     * ScopeOf - The scope a qualified name was declared in, or root if it is an ordinary global
     * name. Used to reject a scoped name reached from outside its scope.
     */
    public ScopeId func ScopeOf(String qualified) {
        match (self.declScopeOf.Find(qualified)) {
            case Some(v) { return ScopeId.Id(v); }
            case None { return Sc.Root(); }
        }
    }
}

/*
 * What a name means in the scope that declares it.
 */
enum NameKind { Type, Generic, Func, Process, State }

/*
 * One declaration claiming a name in a scope.
 */
class Named {
    public String name;
    public ScopeId scope;
    public NameKind kind;
    public bool isPrivate;
    public String file;
    public TextSpan span;
    func _init(String name, ScopeId scope, NameKind kind, bool isPrivate, String file, TextSpan span) {
        self.name = name;
        self.scope = scope;
        self.kind = kind;
        self.isPrivate = isPrivate;
        self.file = file;
        self.span = span;
    }
}

/*
 * One top level declaration of a name: the file it is written in, and whether it is file local.
 */
class RootDecl {
    public String file;
    public bool isPrivate;
    func _init(String file, bool isPrivate) { self.file = file; self.isPrivate = isPrivate; }
}

/*
 * One scoped declaration awaiting the shadowing pass.
 */
class DeclaredItem {
    public String file;
    public ScopeId scope;
    public String name;
    public TopLevel item;
    func _init(String file, ScopeId scope, String name, TopLevel item) {
        self.file = file;
        self.scope = scope;
        self.name = name;
        self.item = item;
    }
}

/*
 * One parsed source file, as the binder receives them.
 */
class ProgramFile {
    public String path;
    public Program prog;
    func _init(String path, Program prog) { self.path = path; self.prog = prog; }
}

class ScopeBinder {
    DiagnosticBag diag;
    Mangler mangler;

    // Process names per realm, and the repeats.
    StringSet processes;
    List[ProcessDecl] duplicates;

    // Every scoped declaration, for the shadowing pass.
    List[DeclaredItem] declared;

    // Qualifiers already rejected, per file
    StringSet badQualifier;

    // Every top level name in the build, so '::Name' can say when nothing declares it
    StringMap[List[RootDecl]] atRoot;

    // Every declaration that claims a name, in every scope including root, keyed the way both the
    // one-meaning check and the outward walk ask for it.
    StringMap[List[Named]] named;

    // Private functions already reported as shadowing, so a set of overloads says it once.
    StringSet privateShadow;

    func _init(DiagnosticBag diag, Mangler mangler) {
        self.diag = diag;
        self.mangler = mangler;
        self.processes = new StringSet();
        self.duplicates = new List[ProcessDecl]();
        self.declared = new List[DeclaredItem]();
        self.badQualifier = new StringSet();
        self.atRoot = new StringMap[List[RootDecl]]();
        self.named = new StringMap[List[Named]]();
        self.privateShadow = new StringSet();
    }

    /*
     * Bind - Interns every realm and process scope, records what each declares, then runs the
     * hygiene checks.
     */
    public ScopeBindResult func Bind(List[ProgramFile] programs, StringMap[StringSet] visible) {
        let ScopeTree tree = new ScopeTree();
        self.mangler.SetScopes(tree);
        let ScopeIndex index = new ScopeIndex(tree);
        self.RootDeclarations(programs);

        let List[String] procFiles = new List[String]();
        let List[int] procScopes = new List[int]();
        let List[ProcessDecl] procDecls = new List[ProcessDecl]();

        let int p = 0;
        while (p < programs.Length()) {
            let ProgramFile pf = programs.Get(p);
            let int i = 0;
            while (i < pf.prog.items.Length()) {
                match (pf.prog.items.Get(i)) {
                    case ContextDecl(cd) {
                        if (cd.kind != Realm.None) {
                            let ScopeId scope = tree.Intern(Sc.Root(), NameOfRealm(cd.kind), cd.kind);
                            let int j = 0;
                            while (j < cd.items.Length()) {
                                let TopLevel inner = cd.items.Get(j);
                                self.DeclareItem(tree, index, scope, inner, pf.path);
                                match (inner) {
                                    case ProcessDecl(pd) {
                                        procFiles.Add(pf.path);
                                        procScopes.Add(Sc.Value(scope));
                                        procDecls.Add(pd);
                                    }
                                    default { }
                                }
                                j = j + 1;
                            }
                        }
                    }
                    default { }
                }
                i = i + 1;
            }
            p = p + 1;
        }

        // each process's own declarations, under a scope of its own
        let int k = 0;
        while (k < procDecls.Length()) {
            let String file = procFiles.Get(k);
            let ScopeId scope = ScopeId.Id(procScopes.Get(k));
            let ProcessDecl pd = procDecls.Get(k);
            k = k + 1;

            // Two processes of one name intern to one scope, so their declarations would merge and
            // be reported as duplicates of each other
            let String pkey = Int.ToString(Sc.Value(scope)) + String.FromChar(31 as char) + pd.name;
            if (!self.processes.AddNew(pkey)) {
                self.diag.Error(Codes.DuplicateName(), file, pd.span,
                    "process '" + pd.name + "' is already declared in '" + Owner(tree, scope) + "'");
                self.duplicates.Add(pd);
                continue;
            }

            // A process name segments the scope path, so 'kernel.P' would name both the process and
            // a class P declared beside it
            self.Claim(new Named(pd.name, scope, NameKind.Process, false, file, pd.span));

            // A process nests under its realm and declares no realm of its own, so
            // ScopeTree.RealmOf walks past it
            let ScopeId proc = tree.Intern(scope, pd.name, Realm.None);
            let int q = 0;
            while (q < pd.items.Length()) {
                self.DeclareItem(tree, index, proc, pd.items.Get(q), file);
                q = q + 1;
            }
        }

        // shadowing and name hygiene, once every scope knows what it holds
        self.CheckShadowing(tree, programs, visible);
        self.CheckOneMeaningPerName(tree);

        // Skipped when nothing is scoped, so such a program emits identical C
        let bool anyQualifier = false;
        let int aq = 0;
        while (aq < programs.Length()) {
            if (programs.Get(aq).prog.hasScopedRefs) { anyQualifier = true; }
            aq = aq + 1;
        }
        if (!index.HasScopedDeclarations() && self.duplicates.Length() == 0 && !anyQualifier) {
            return new ScopeBindResult(tree, index);
        }

        self.Rewrite(programs, tree, index);
        return new ScopeBindResult(tree, index);
    }

    /*
     * Rewrite - Rewrites every declaration and every type position naming a scoped declaration to
     * the qualified spelling.
     */
    void func Rewrite(List[ProgramFile] programs, ScopeTree tree, ScopeIndex index) {
        let int i = 0;
        while (i < programs.Length()) {
            let ProgramFile pf = programs.Get(i);
            i = i + 1;
            let List[TopLevel] items = pf.prog.items;
            let List[GenericUse] uses = pf.prog.genericUses;

            // Root-scope declarations, and the uses written outside every realm block
            if (pf.prog.hasScopedRefs) {
                let SubstitutionContext rootSub = self.SubstitutionFor(tree, index, Sc.Root(), pf.path);
                let int j = 0;
                while (j < items.Length()) {
                    let TopLevel it = items.Get(j);
                    let bool isRealm = false;
                    match (it) { case ContextDecl(cd) { isRealm = true; } default { } }
                    if (!isRealm) {
                        items.Set(j, self.RewriteItem(it, tree, index, Sc.Root(), rootSub, pf.path));
                    }
                    j = j + 1;
                }
                let int u = 0;
                while (u < uses.Length()) {
                    let GenericUse use = uses.Get(u);
                    u = u + 1;
                    let bool scoped = false;
                    match (use.scope) { case Some(sc) { scoped = true; } case None { } }
                    if (!scoped) { continue; }
                    if (self.InsideAnyRealm(items, use.span)) { continue; }
                    uses.Set(u - 1, self.RewriteUse(use, index, Sc.Root(), tree, pf.path));
                }
            }

            // Each realm block, and the uses written inside it
            let int k = 0;
            while (k < items.Length()) {
                let TopLevel it = items.Get(k);
                k = k + 1;
                match (it) {
                    case ContextDecl(realmDecl) {
                        if (realmDecl.kind == Realm.None) { continue; }
                        let ScopeId scope = tree.Intern(Sc.Root(), NameOfRealm(realmDecl.kind), realmDecl.kind);
                        let SubstitutionContext sub = self.SubstitutionFor(tree, index, scope, pf.path);

                        let int n = 0;
                        while (n < realmDecl.items.Length()) {
                            realmDecl.items.Set(n, self.RewriteItem(realmDecl.items.Get(n), tree, index,
                                                                    scope, sub, pf.path));
                            n = n + 1;
                        }

                        let int u = 0;
                        while (u < uses.Length()) {
                            let GenericUse use = uses.Get(u);
                            u = u + 1;
                            if (!Within(use.span, realmDecl.span)) { continue; }

                            // A use inside a process belongs to that process's scope
                            let ScopeId useScope = scope;
                            let int q = 0;
                            while (q < realmDecl.items.Length()) {
                                match (realmDecl.items.Get(q)) {
                                    case ProcessDecl(pd) {
                                        if (Within(use.span, pd.span)) {
                                            useScope = tree.Intern(scope, pd.name, Realm.None);
                                        }
                                    }
                                    default { }
                                }
                                q = q + 1;
                            }
                            uses.Set(u - 1, self.RewriteUse(use, index, useScope, tree, pf.path));
                        }
                    }
                    default { }
                }
            }
        }
    }

    /*
     * InsideAnyRealm - True when a span falls inside one of the realm blocks in this file, so a
     * generic use is attributed to that realm rather than to the root scope
     */
    bool func InsideAnyRealm(List[TopLevel] items, TextSpan span) {
        let int i = 0;
        while (i < items.Length()) {
            match (items.Get(i)) {
                case ContextDecl(cd) { if (Within(span, cd.span)) { return true; } }
                default { }
            }
            i = i + 1;
        }
        return false;
    }

    /*
     * SubstitutionFor - Builds the name-to-qualified-type map visible from a scope.
     */
    SubstitutionContext func SubstitutionFor(ScopeTree tree, ScopeIndex index, ScopeId scope, String file) {
        let StringMap[TypeSpec] specs = new StringMap[TypeSpec]();
        let StringMap[String] names = new StringMap[String]();
        let StringMap[String] cTypes = new StringMap[String]();

        let ScopeId s = scope;
        let bool more = true;
        while (more) {
            let List[String] written = index.DeclaredIn(s);
            let int i = 0;
            while (i < written.Length()) {
                let String w = written.Get(i);
                i = i + 1;
                let String qualified = w;
                match (index.TryDeclared(s, w)) { case Some(q) { qualified = q; } case None { } }
                if (w == qualified || specs.Has(w)) { continue; }
                specs.Put(w, Specs.Named(qualified));
                names.Put(w, qualified);
                cTypes.Put(w, self.mangler.Class(qualified) + "*");
            }
            if (Sc.IsRoot(s)) { more = false; } else { s = tree.Parent(s); }
        }

        let SubstitutionContext ctx = new SubstitutionContext(specs, cTypes);
        ctx.rewriteTypeNames = true;
        ctx.nameMap = names;
        ctx.BindScopes(self, tree, index, scope, file);
        return ctx;
    }

    /*
     * RewriteItem - Rewrites one declaration: its own name, and every type it mentions
     */
    TopLevel func RewriteItem(TopLevel item, ScopeTree tree, ScopeIndex index, ScopeId scope,
                              SubstitutionContext sub, String file) {
        match (item) {
            case ProcessVarDecl(pv) {
                let ProcessVarDecl fresh = new ProcessVarDecl(self.Q(index, scope, pv.name),
                    sub.SubType(pv.type), SubOptExpr(pv.init, sub), pv.span);
                return TopLevel.ProcessVarDecl(fresh);
            }
            case ClassDecl(cd) {
                let String qbase = self.Q(index, scope, cd.baseName);
                let ClassDecl fresh = new ClassDecl(
                    self.Requalify(cd.name, cd.baseName, qbase, cd.genericParams),
                    cd.genericParams, cd.annotations, SubMembers(cd.members, sub), cd.span, cd.isModule);
                fresh.baseName = qbase;
                return TopLevel.ClassDecl(fresh);
            }
            case UnionDecl(ud) {
                let String qbase = self.Q(index, scope, ud.baseName);
                let UnionDecl fresh = new UnionDecl(
                    self.Requalify(ud.name, ud.baseName, qbase, ud.genericParams),
                    ud.genericParams, SubVariants(ud.variants, sub), ud.span, ud.annotations);
                fresh.baseName = qbase;
                return TopLevel.UnionDecl(fresh);
            }
            case EnumDecl(ed) {
                return TopLevel.EnumDecl(new EnumDecl(self.Q(index, scope, ed.name), ed.members,
                                                      ed.span, ed.annotations));
            }
            case NativeTypeDecl(nd) {
                return TopLevel.NativeTypeDecl(new NativeTypeDecl(self.Q(index, scope, nd.name),
                                                                  nd.cBody, nd.span, nd.annotations));
            }
            case ProcessDecl(pd) { return self.RewriteProcess(pd, tree, index, scope, file); }
            case FuncDecl(fd) {
                let FuncDecl fresh = new FuncDecl(fd.modifiers, fd.annotations,
                    SubOptType(fd.returnType, sub), self.Q(index, scope, fd.name), fd.genericParams,
                    SubParams(fd.params, sub), fd.isEntry, fd.isThrows,
                    SubBodyBound(fd.body, fd.params, sub), fd.span);
                return TopLevel.FuncDecl(fresh);
            }
            default { return item; }
        }
    }

    /*
     * Q - The qualified name a written one resolves to from this scope, or the written name
     */
    String func Q(ScopeIndex index, ScopeId scope, String name) {
        match (index.Resolve(scope, name)) {
            case Some(q) { return q; }
            case None { return name; }
        }
    }

    /*
     * Requalify - The declaration's internal name after its base is qualified.
     */
    String func Requalify(String name, String baseName, String qualBase, List[String] generics) {
        if (generics.Length() == 0) { return qualBase; }
        if (name == baseName) { return qualBase; }
        return self.mangler.GenericInstance(qualBase, generics);
    }

    /*
     * RewriteProcess - Rewrites a process: its own declarations and its threads, both under the
     * process scope
     */
    TopLevel func RewriteProcess(ProcessDecl pd, ScopeTree tree, ScopeIndex index,
                                 ScopeId realmScope, String file) {
        if (self.IsDuplicateProcess(pd)) {
            let ProcessDecl empty = new ProcessDecl(pd.name, pd.mode, new List[ThreadDecl](), pd.span);
            return TopLevel.ProcessDecl(empty);
        }

        let ScopeId proc = tree.Intern(realmScope, pd.name, Realm.None);
        let SubstitutionContext sub = self.SubstitutionFor(tree, index, proc, file);

        let List[TopLevel] items = new List[TopLevel]();
        let int i = 0;
        while (i < pd.items.Length()) {
            items.Add(self.RewriteItem(pd.items.Get(i), tree, index, proc, sub, file));
            i = i + 1;
        }

        let ProcessDecl fresh = new ProcessDecl(pd.name, pd.mode, RewriteThreads(pd.threads, sub), pd.span);
        fresh.items = items;
        return TopLevel.ProcessDecl(fresh);
    }

    /*
     * RewriteUse - Requalifies a generic instantiation: its base, if the template itself is scoped,
     * and each of its type arguments
     */
    GenericUse func RewriteUse(GenericUse use, ScopeIndex index, ScopeId scope, ScopeTree tree, String file) {
        let String baseName = "";
        match (use.scope) {
            case Some(sc) {
                let NamedSpec spec = new NamedSpec(use.base, new List[NamedSpec](), use.span);
                spec.scope = use.scope;
                baseName = self.ResolveScopedType(spec, tree, index, scope, file).name;
            }
            case None { baseName = self.Q(index, scope, use.base); }
        }

        let List[NamedSpec] specs = null;
        match (use.argSpecs) {
            case Some(argSpecs) {
                specs = new List[NamedSpec]();
                let int i = 0;
                while (i < argSpecs.Length()) {
                    specs.Add(self.RewriteSpec(argSpecs.Get(i), index, scope, tree, file));
                    i = i + 1;
                }
            }
            case None { }
        }

        let List[String] args = new List[String]();
        let int j = 0;
        while (j < use.args.Length()) {
            if (specs != null && j < specs.Length()) { args.Add(specs.Get(j).Mangled()); }
            else { args.Add(self.Q(index, scope, use.args.Get(j))); }
            j = j + 1;
        }

        let GenericUse fresh = new GenericUse(baseName, args, use.span,
            specs == null ? use.argSpecs : Optional.Some(specs));
        fresh.scope = use.scope;
        return fresh;
    }

    /*
     * RewriteSpec - Requalifies a type argument, recursing through its own arguments.
     */
    NamedSpec func RewriteSpec(NamedSpec s, ScopeIndex index, ScopeId scope, ScopeTree tree, String file) {
        let List[NamedSpec] args = new List[NamedSpec]();
        let int i = 0;
        while (i < s.args.Length()) {
            args.Add(self.RewriteSpec(s.args.Get(i), index, scope, tree, file));
            i = i + 1;
        }

        match (s.scope) {
            case Some(sc) {
                let NamedSpec resolved = self.ResolveScopedType(s, tree, index, scope, file);
                return new NamedSpec(resolved.name, args, resolved.span);
            }
            case None {
                return new NamedSpec(self.Q(index, scope, s.name), args, s.span);
            }
        }
    }

    /*
     * DeclareItem - Records a single declaration's name in its scope, and rejects the forms that
     * cannot be scoped yet.
     */
    void func DeclareItem(ScopeTree tree, ScopeIndex index, ScopeId scope, TopLevel item, String file) {
        match (NameOfItem(item)) {
            case None {
                self.RejectStrayShadows(item, file, "it belongs on a class, module, enum, union, "
                                                    + "native type or free function");
                return;
            }
            case Some(name) {
                let String qualified = tree.Qualify(scope, name);
                index.Declare(scope, name, qualified);
                tree.SetKind(qualified, Describe(KindOfItem(item)));
                self.declared.Add(new DeclaredItem(file, scope, name, item));
                self.Claim(new Named(name, scope, KindOfItem(item), IsPrivateItem(item), file, Tops.Span(item)));
            }
        }
    }

    /*
     * NamedKey - The (scope, name) key the claim table is indexed by
     */
    String func NamedKey(ScopeId scope, String name) {
        return Int.ToString(Sc.Value(scope)) + String.FromChar(31 as char) + name;
    }

    /*
     * Claim - Records a declaration under the name and scope it claims
     */
    void func Claim(Named d) {
        let String key = self.NamedKey(d.scope, d.name);
        match (self.named.Find(key)) {
            case Some(list) { list.Add(d); }
            case None {
                let List[Named] list = new List[Named]();
                list.Add(d);
                self.named.Put(key, list);
            }
        }
    }

    /*
     * ClaimsAt - Every declaration claiming a name in a scope
     */
    List[Named] func ClaimsAt(ScopeId scope, String name) {
        match (self.named.Find(self.NamedKey(scope, name))) {
            case Some(list) { return list; }
            case None { return new List[Named](); }
        }
    }

    /*
     * CheckOneMeaningPerName - Reports a name given two different meanings in one scope.
     */
    void func CheckOneMeaningPerName(ScopeTree tree) {
        let List[String] keys = self.named.Keys();
        let int ki = 0;
        while (ki < keys.Length()) {
            let List[Named] decls = self.named.Get(keys.Get(ki));
            ki = ki + 1;
            let int i = 1;
            while (i < decls.Length()) {
                let Named prev = decls.Get(0);
                let Named d = decls.Get(i);
                i = i + 1;
                if (prev.kind == d.kind) { continue; }

                // A private function is file local, so it only takes a name away inside its own file
                if ((prev.isPrivate || d.isPrivate) && !PathsEqual(prev.file, d.file)) { continue; }

                let String where = Sc.IsRoot(d.scope) ? "" : " in '" + Owner(tree, d.scope) + "'";
                let String noun = Describe(d.kind);
                self.diag.Error(Codes.DuplicateName(), d.file, d.span,
                    "'" + d.name + "' is already declared" + where + " as " + Describe(prev.kind),
                    HintList.Of1("one name means one thing in a scope; rename this "
                                 + noun.Substring(2, noun.Length() - 2)));
                break;
            }
        }
    }

    /*
     * RootDeclarations - Every top level declaration in the build, mapped to the file that
     * declares it
     */
    void func RootDeclarations(List[ProgramFile] programs) {
        let int p = 0;
        while (p < programs.Length()) {
            let ProgramFile pf = programs.Get(p);
            p = p + 1;
            let int i = 0;
            while (i < pf.prog.items.Length()) {
                let TopLevel item = pf.prog.items.Get(i);
                i = i + 1;
                match (RootNameOfItem(item)) {
                    case None { }
                    case Some(n) {
                        let bool priv = IsPrivateItem(item);
                        match (self.atRoot.Find(n)) {
                            case Some(list) { list.Add(new RootDecl(pf.path, priv)); }
                            case None {
                                let List[RootDecl] list = new List[RootDecl]();
                                list.Add(new RootDecl(pf.path, priv));
                                self.atRoot.Put(n, list);
                            }
                        }
                        self.Claim(new Named(n, Sc.Root(), KindOfItem(item), priv, pf.path, Tops.Span(item)));
                    }
                }
            }
        }
    }

    /*
     * CheckShadowing - Reports every scoped declaration whose intent about shadowing does not
     * match what it does.
     */
    void func CheckShadowing(ScopeTree tree, List[ProgramFile] programs, StringMap[StringSet] visible) {
        let int p = 0;
        while (p < programs.Length()) {
            let ProgramFile pf = programs.Get(p);
            p = p + 1;
            let int i = 0;
            while (i < pf.prog.items.Length()) {
                let TopLevel item = pf.prog.items.Get(i);
                i = i + 1;
                let bool handled = false;
                match (item) {
                    case FuncDecl(fd) {
                        if (!fd.isEntry && Mods.Has(fd.modifiers, Modifiers.Private)) {
                            self.CheckPrivateShadow(fd, pf.path, visible);
                            handled = true;
                        }
                    }
                    default { }
                }
                if (handled) { continue; }
                self.RejectStrayShadows(item, pf.path, "move the declaration inside the realm or "
                                                       + "process it belongs to, or remove the annotation");
            }
        }

        let int d = 0;
        while (d < self.declared.Length()) {
            let DeclaredItem di = self.declared.Get(d);
            d = d + 1;
            let bool marked = HasShadows(AnnotationsOf(di.item));
            let Optional[String] outer = self.OuterDeclaring(tree, di.scope, di.name, di.file, visible);

            match (outer) {
                case Some(where) {
                    if (!marked) {
                        self.diag.Error(Codes.UnmarkedShadow(), di.file, Tops.Span(di.item),
                            "'" + di.name + "' shadows the '" + di.name + "' declared in " + where,
                            HintList.Of2("write '@shadows' before it if displacing that name is deliberate",
                                         "otherwise rename this one; the outer declaration is not reachable from here"));
                    }
                }
                case None {
                    if (marked) {
                        self.diag.Error(Codes.UnmarkedShadow(), di.file, Tops.Span(di.item),
                            "'" + di.name + "' is marked '@shadows' but nothing outside '"
                            + Owner(tree, di.scope) + "' declares it",
                            HintList.Of1("remove '@shadows'"));
                    }
                }
            }
        }
    }

    /*
     * OuterDeclaring - Where an enclosing scope declares this name, rendered for a diagnostic, or
     * None.
     */
    Optional[String] func OuterDeclaring(ScopeTree tree, ScopeId scope, String name, String file,
                                         StringMap[StringSet] visible) {
        let ScopeId s = tree.Parent(scope);
        while (!Sc.IsRoot(s)) {
            let List[Named] claims = self.ClaimsAt(s, name);
            let int i = 0;
            while (i < claims.Length()) {
                let Named d = claims.Get(i);
                i = i + 1;
                if (!d.isPrivate || PathsEqual(d.file, file)) {
                    return Optional.Some("'" + Owner(tree, s) + "'");
                }
            }
            s = tree.Parent(s);
        }

        let List[RootDecl] decls = null;
        match (self.atRoot.Find(name)) {
            case Some(list) { decls = list; }
            case None { return Optional[String].None(); }
        }

        let StringSet reachable = null;
        if (visible != null) {
            match (visible.Find(file)) { case Some(r) { reachable = r; } case None { } }
        }

        let Optional[String] imported = Optional[String].None();
        let int j = 0;
        while (j < decls.Length()) {
            let RootDecl d = decls.Get(j);
            j = j + 1;
            if (PathsEqual(d.file, file)) { return Optional.Some("the top level of this file"); }
            if (d.isPrivate || reachable == null || !reachable.Has(d.file)) { continue; }
            match (imported) {
                case None { imported = Optional.Some("'" + ModuleName(d.file) + "'"); }
                case Some(x) { }
            }
        }
        return imported;
    }

    /*
     * CheckPrivateShadow - Reports a file-local function that takes a name an imported file
     * already gave a public meaning
     */
    void func CheckPrivateShadow(FuncDecl fd, String file, StringMap[StringSet] visible) {
        let bool marked = HasShadows(fd.annotations);
        let Optional[String] owner = self.ImportedDeclaring(fd.name, file, visible);

        match (owner) {
            case Some(own) {
                if (!marked) {
                    let String key = file + String.FromChar(31 as char) + fd.name;
                    if (!self.privateShadow.AddNew(key)) { return; }
                    self.diag.Warn(Codes.ShadowedFunction(), file, fd.span,
                        "'" + fd.name + "' shadows the '" + fd.name + "' declared in '" + own + "'",
                        HintList.Of3("every call to '" + fd.name + "' in this file resolves to this one",
                                     "reach the other through its file: '" + own + "." + fd.name + "(...)'",
                                     "write '@shadows' before it if displacing that name is deliberate, "
                                     + "or rename this one"));
                }
            }
            case None {
                if (marked) {
                    self.RejectStrayShadowsFunc(fd, file, "nothing this file imports declares that name");
                }
            }
        }
    }

    /*
     * ImportedDeclaring - The module basename of an imported file declaring this name publicly, or None.
     */
    Optional[String] func ImportedDeclaring(String name, String file, StringMap[StringSet] visible) {
        let List[RootDecl] decls = null;
        match (self.atRoot.Find(name)) {
            case Some(list) { decls = list; }
            case None { return Optional[String].None(); }
        }
        if (visible == null) { return Optional[String].None(); }
        let StringSet reachable = null;
        match (visible.Find(file)) { case Some(r) { reachable = r; } case None { return Optional[String].None(); } }

        let int i = 0;
        while (i < decls.Length()) {
            let RootDecl d = decls.Get(i);
            i = i + 1;
            if (d.isPrivate || PathsEqual(d.file, file)) { continue; }
            if (reachable.Has(d.file)) { return Optional.Some(ModuleName(d.file)); }
        }
        return Optional[String].None();
    }

    /*
     * RejectStrayShadows - Reports '@shadows' written where it can never mean anything.
     */
    void func RejectStrayShadows(TopLevel item, String file, String advice) {
        match (FirstShadows(AnnotationsOf(item))) {
            case Some(stray) {
                self.diag.Error(Codes.UnmarkedShadow(), file, stray.span, "'@shadows' displaces nothing here",
                                HintList.Of1(advice));
            }
            case None { }
        }
    }

    /*
     * RejectStrayShadowsFunc - The same, for a FuncDecl reached directly
     */
    void func RejectStrayShadowsFunc(FuncDecl fd, String file, String advice) {
        match (FirstShadows(fd.annotations)) {
            case Some(stray) {
                self.diag.Error(Codes.UnmarkedShadow(), file, stray.span, "'@shadows' displaces nothing here",
                                HintList.Of1(advice));
            }
            case None { }
        }
    }

    /*
     * ResolveScopedType - Resolves a type name written under an explicit scope qualifier
     */
    public NamedSpec func ResolveScopedType(NamedSpec spec, ScopeTree tree, ScopeIndex index, ScopeId from, String file) {
        let List[String] path = new List[String]();
        match (spec.scope) { case Some(sc) { path = sc; } case None { } }

        let NamedSpec bare = new NamedSpec(spec.name, spec.args, spec.span);
        match (self.ScopeFor(path, tree, from, file, spec.span)) {
            case None { return Poisoned(bare); }
            case Some(scope) {
                match (self.NameIn(scope, spec.name, path, index, file, spec.span)) {
                    case Some(q) { return new NamedSpec(q, spec.args, spec.span); }
                    case None { return Poisoned(bare); }
                }
            }
        }
    }

    /*
     * ResolveScopedExpr - Resolves a name written under an explicit scope qualifier in expression
     * position, where the segments after it may be more scopes, then the name, then member
     * accesses.
     */
    public Expr func ResolveScopedExpr(ScopedNameExpr sn, ScopeTree tree, ScopeIndex index,
                                       ScopeId from, String file) {
        match (sn.generic) {
            case Some(g) {
                let NamedSpec resolved = self.ResolveScopedType(g, tree, index, from, file);
                if (resolved.name == Specs.Poison()) { return Fallback(sn); }
                let Expr gen = Expr.GenericTypeRefExpr(
                    new GenericTypeRefExpr(resolved.name, resolved.args, Optional[Expr].None(), sn.span));
                let int m = 0;
                while (m < sn.path.Length()) {
                    gen = Expr.MemberAccessExpr(new MemberAccessExpr(gen, sn.path.Get(m), sn.span));
                    m = m + 1;
                }
                return gen;
            }
            case None { }
        }

        let List[String] path = sn.scope.Clone();
        let ScopeId scope = Sc.Root();
        if (sn.scope.Length() > 0) {
            match (RealmScope(tree, sn.scope.Get(0))) {
                case None { self.ReportNoScope(path, file, sn.span); return Fallback(sn); }
                case Some(realmScope) { scope = realmScope; }
            }
        }

        // Every segment but the last may still be a scope; the last can only be the name
        let int i = 0;
        let bool walking = true;
        while (walking && i < sn.path.Length() - 1) {
            match (tree.Child(scope, sn.path.Get(i))) {
                case Some(child) { scope = child; path.Add(sn.path.Get(i)); i = i + 1; }
                case None { walking = false; }
            }
        }

        if (!self.Enclosing(scope, path, tree, from, file, sn.span)) { return Fallback(sn); }
        let String q = "";
        match (self.NameIn(scope, sn.path.Get(i), path, index, file, sn.span)) {
            case None { return Fallback(sn); }
            case Some(found) { q = found; }
        }

        let Expr e = Expr.IdentExpr(new IdentExpr(q, sn.span));
        let int m = i + 1;
        while (m < sn.path.Length()) {
            e = Expr.MemberAccessExpr(new MemberAccessExpr(e, sn.path.Get(m), sn.span));
            m = m + 1;
        }
        return e;
    }

    /*
     * ScopeFor - The scope a written path names, or None once the reason it does not has been reported
     */
    Optional[ScopeId] func ScopeFor(List[String] path, ScopeTree tree, ScopeId from, String file, TextSpan span) {
        let ScopeId scope = Sc.Root();
        let int i = 0;
        while (i < path.Length()) {
            let Optional[ScopeId] child = i == 0
                ? RealmScope(tree, path.Get(0))
                : tree.Child(scope, path.Get(i));
            match (child) {
                case Some(found) { scope = found; }
                case None {
                    self.ReportNoScope(Prefix(path, i + 1), file, span);
                    return Optional[ScopeId].None();
                }
            }
            i = i + 1;
        }
        if (self.Enclosing(scope, path, tree, from, file, span)) { return Optional.Some(scope); }
        return Optional[ScopeId].None();
    }

    /*
     * Enclosing - Checks that a written qualifier names a scope this code is inside.
     */
    bool func Enclosing(ScopeId scope, List[String] path, ScopeTree tree, ScopeId from, String file, TextSpan span) {
        if (tree.Encloses(scope, from)) { return true; }
        if (!self.badQualifier.AddNew(BadKey(file, Spell(path), ""))) { return false; }
        self.diag.Error(Codes.ScopeNotEnclosing(), file, span,
            "'" + Spell(path) + "' does not enclose this code",
            HintList.Of1("a scope qualifier reaches outward only; name an enclosing realm or process, "
                         + "or '::' for the top level"));
        return false;
    }

    /*
     * NameIn - The qualified name a scope declares, or None once the reason it declares none has been reported.
     */
    Optional[String] func NameIn(ScopeId scope, String name, List[String] path,
                                 ScopeIndex index, String file, TextSpan span) {
        if (Sc.IsRoot(scope)) {
            if (self.atRoot.Has(name)) { return Optional.Some(name); }
        } else {
            match (index.TryDeclared(scope, name)) {
                case Some(q) { return Optional.Some(q); }
                case None { }
            }
        }

        if (!self.badQualifier.AddNew(BadKey(file, Spell(path), name))) { return Optional[String].None(); }
        let String hint = Sc.IsRoot(scope)
            ? "the top level of the build declares it nowhere; check the spelling, or drop the '::'"
            : "drop the qualifier to use whatever '" + name + "' is in scope here";
        self.diag.Error(Codes.UnknownInScope(), file, span,
            Where(path) + " declares no '" + name + "'", HintList.Of1(hint));
        return Optional[String].None();
    }

    /*
     * ReportNoScope - Reports a qualifier naming a scope that does not exist in this build
     */
    void func ReportNoScope(List[String] path, String file, TextSpan span) {
        if (!self.badQualifier.AddNew(BadKey(file, Spell(path), ""))) { return; }
        self.diag.Error(Codes.ScopeNotEnclosing(), file, span, "there is no scope '" + Spell(path) + "'",
            HintList.Of1("the only realms are 'kernel' and 'userspace'; a process is named inside one"));
    }

    /*
     * IsDuplicateProcess - True for a process this binder reported as a repeat, whose declarations
     * the rewrite sweep must drop rather than emit twice
     */
    public bool func IsDuplicateProcess(ProcessDecl pd) {
        let int i = 0;
        while (i < self.duplicates.Length()) {
            if (self.duplicates.Get(i) == pd) { return true; }
            i = i + 1;
        }
        return false;
    }

    /*
     * DuplicateCount - How many processes were rejected as repeats
     */
    public int func DuplicateCount() { return self.duplicates.Length(); }
}

/*
 * NameOfRealm - The scope segment naming a realm. Matches the source keyword, so a qualified name
 * and a diagnostic read the way the user wrote it.
 */
String func NameOfRealm(Realm r) {
    if (r == Realm.Kernel) { return "kernel"; }
    if (r == Realm.User) { return "userspace"; }
    return "";
}

/*
 * RealmScope - The scope of a realm named in a qualifier. Interned, since both realms are part of
 * the language rather than of any one program.
 */
Optional[ScopeId] func RealmScope(ScopeTree tree, String name) {
    if (name == "kernel") { return Optional.Some(tree.Intern(Sc.Root(), "kernel", Realm.Kernel)); }
    if (name == "userspace") { return Optional.Some(tree.Intern(Sc.Root(), "userspace", Realm.User)); }
    return Optional[ScopeId].None();
}

/*
 * NameOfItem - The name a declaration contributes to its scope, or None for the unnamed forms
 */
Optional[String] func NameOfItem(TopLevel item) {
    match (item) {
        case ClassDecl(cd) { return Optional.Some(cd.baseName); }
        case UnionDecl(ud) { return Optional.Some(ud.baseName); }
        case EnumDecl(ed) { return Optional.Some(ed.name); }
        case NativeTypeDecl(nd) { return Optional.Some(nd.name); }
        case FuncDecl(fd) { return fd.isEntry ? Optional[String].None() : Optional.Some(fd.name); }
        case ProcessVarDecl(pv) { return Optional.Some(pv.name); }
        default { return Optional[String].None(); }
    }
}

/*
 * RootNameOfItem - The name a top-level declaration contributes at root.
 */
Optional[String] func RootNameOfItem(TopLevel item) {
    match (item) {
        case ExternFuncDecl(ef) { return Optional.Some(ef.name); }
        default { return NameOfItem(item); }
    }
}

/*
 * KindOfItem - The kind of name a declaration claims. 
 */
NameKind func KindOfItem(TopLevel item) {
    match (item) {
        case ClassDecl(cd) { return cd.genericParams.Length() > 0 ? NameKind.Generic : NameKind.Type; }
        case UnionDecl(ud) { return ud.genericParams.Length() > 0 ? NameKind.Generic : NameKind.Type; }
        case FuncDecl(fd) { return NameKind.Func; }
        case ExternFuncDecl(ef) { return NameKind.Func; }
        case ProcessVarDecl(pv) { return NameKind.State; }
        default { return NameKind.Type; }
    }
}

/*
 * IsPrivateItem - True for a declaration only its own file can see, which therefore only collides
 * there
 */
bool func IsPrivateItem(TopLevel item) {
    match (item) {
        case FuncDecl(fd) { return Mods.Has(fd.modifiers, Modifiers.Private); }
        default { return false; }
    }
}

/*
 * Describe - The word a diagnostic uses for a kind of name
 */
String func Describe(NameKind k) {
    if (k == NameKind.Generic) { return "a generic type"; }
    if (k == NameKind.Func) { return "a function"; }
    if (k == NameKind.Process) { return "a process"; }
    if (k == NameKind.State) { return "a process variable"; }
    return "a type";
}

/*
 * AnnotationsOf - The annotations a declaration carries, or none for the forms that take none.
 * Covers the unnamed forms too, so a mark on one is rejected rather than silently ignored.
 */
List[Annotation] func AnnotationsOf(TopLevel item) {
    match (item) {
        case ClassDecl(cd)      { return cd.annotations; }
        case UnionDecl(ud)      { return ud.annotations; }
        case EnumDecl(ed)       { return ed.annotations; }
        case NativeTypeDecl(nd) { return nd.annotations; }
        case FuncDecl(fd)       { return fd.annotations; }
        case ExternFuncDecl(ef) { return ef.annotations; }
        case NativeBlock(nb)    { return nb.annotations; }
        default { return new List[Annotation](); }
    }
}

/*
 * HasShadows - True when a declaration carries '@shadows'
 */
bool func HasShadows(List[Annotation] anns) {
    match (FirstShadows(anns)) {
        case Some(x) { return true; }
        case None { return false; }
    }
}

/*
 * FirstShadows - The first '@shadows' annotation in a list, or None
 */
Optional[ShadowsAnnotation] func FirstShadows(List[Annotation] anns) {
    let int i = 0;
    while (i < anns.Length()) {
        match (anns.Get(i)) {
            case ShadowsAnnotation(s) { return Optional.Some(s); }
            default { }
        }
        i = i + 1;
    }
    return Optional[ShadowsAnnotation].None();
}

/*
 * Poisoned - What a rejected qualifier leaves behind. Poison rather than the bare name, so the one
 * error already reported is not joined by a second about whatever the bare name happens to mean.
 */
NamedSpec func Poisoned(NamedSpec spec) {
    return new NamedSpec(Specs.Poison(), new List[NamedSpec](), spec.span);
}

/*
 * Fallback - A poison expression, for the same reason Poisoned exists
 */
Expr func Fallback(ScopedNameExpr sn) { return Expr.PoisonExpr(new PoisonExpr(sn.span)); }

/*
 * Owner - The readable name of a scope, for a diagnostic that names where something already exists
 */
String func Owner(ScopeTree tree, ScopeId scope) {
    let String shown = tree.Display(scope, "");
    let int end = shown.Length();
    while (end > 0 && shown.CharAt(end - 1) == '.') { end = end - 1; }
    return shown.Substring(0, end);
}

/*
 * PathsEqual - Compares two source paths the way the import graph keys them
 */
bool func PathsEqual(String a, String b) { return a.ToLower() == b.ToLower(); }

/*
 * ModuleName - A file's basename without its extension, the way a file-qualified call spells it
 */
String func ModuleName(String path) {
    let String base = BaseName(path);
    let int dot = -1;
    let int i = 0;
    while (i < base.Length()) {
        if (base.CharAt(i) == '.') { dot = i; }
        i = i + 1;
    }
    if (dot < 0) { return base; }
    return base.Substring(0, dot);
}

/*
 * Prefix - The first n segments of a path
 */
List[String] func Prefix(List[String] path, int n) {
    let List[String] r = new List[String]();
    let int i = 0;
    while (i < n && i < path.Length()) { r.Add(path.Get(i)); i = i + 1; }
    return r;
}

/*
 * Spell - A written scope path, spelled the way it is typed. The root scope is '::'.
 */
String func Spell(List[String] path) {
    if (path.Length() == 0) { return "::"; }
    return String.Join(path, ".");
}

/*
 * Where - A scope path as a diagnostic names it
 */
String func Where(List[String] path) {
    if (path.Length() == 0) { return "the top level"; }
    return "'" + Spell(path) + "'";
}

/*
 * BadKey - The (file, path, name) key the already-reported-qualifier set is indexed by
 */
String func BadKey(String file, String path, String name) {
    let String us = String.FromChar(31 as char);
    return file + us + path + us + name;
}

/*
 * RewriteThreads - Rewrites each thread's entry body, which is ordinary code running inside its
 * process
 */
List[ThreadDecl] func RewriteThreads(List[ThreadDecl] threads, SubstitutionContext sub) {
    let List[ThreadDecl] result = new List[ThreadDecl]();
    let int i = 0;
    while (i < threads.Length()) {
        let ThreadDecl t = threads.Get(i);
        i = i + 1;
        let EntryFuncDecl en = t.entryFunc;
        let EntryFuncDecl fresh = new EntryFuncDecl(en.modifiers, SubOptType(en.returnType, sub),
            SubParams(en.params, sub), SubEntryBlock(en, sub), en.span);
        result.Add(new ThreadDecl(t.name, t.mode, fresh, t.span));
    }
    return result;
}

/*
 * SubEntryBlock - Rewrites a thread entry's body with its parameters bound, so a parameter named
 * like a scoped type keeps meaning the parameter
 */
Block func SubEntryBlock(EntryFuncDecl en, SubstitutionContext sub) {
    let MethodBody body = SubBodyBound(MethodBody.BlockBody(new BlockBody(en.body)), en.params, sub);
    match (body) {
        case BlockBody(bb) { return bb.block; }
        default { return en.body; }
    }
}
