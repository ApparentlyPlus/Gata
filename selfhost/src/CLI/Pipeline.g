/*
 * Pipeline.g - project discovery, the front-end driver, and every whole-build validation
 *
 * Ports Appa/src/CLI/Pipeline.cs.
 *
 * BuildModule here is the same loop the C# one runs, including the monomorphization rounds: the
 * front end re-runs while resolution keeps discovering new generic instantiations, capped so an
 * infinite family becomes the resolver's diagnostic rather than a hang.
 *
 * NOT PORTED: WarnReferenceCycles. It is a warning, and the one place the port would have to invent
 * behaviour - C# locates the cycle at a class DECLARATION by walking the parsed AST a second time,
 * and the pass runs only when nothing else failed. Left out deliberately rather than approximated,
 * because a G101 pointing at the wrong line is worse than no G101; the check is still performed by
 * the C# compiler, and by appa itself over this port's own source. See the note in Program.g.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "selfhostlib/File.g";
import "selfhostlib/Dir.g";
import "selfhostlib/Sys.g";
import "src/Diagnostics/TextSpan.g";
import "src/Diagnostics/Diagnostic.g";
import "src/Diagnostics/SourceText.g";
import "src/Syntax/Ast.g";
import "src/Syntax/Lexer.g";
import "src/Syntax/Parser.g";
import "src/IR/Ir.g";
import "src/Semantics/ScopeBinder.g";
import "src/Semantics/Monomorphizer.g";
import "src/Semantics/SymbolCollector.g";
import "src/Semantics/TypeResolver.g";
import "src/Lowering/Desugar.g";
import "src/Lowering/CapabilityScan.g";
import "src/Lowering/Dce.g";
import "src/Lowering/Densifier.g";
import "src/Lowering/Ownership.g";
import "src/Lowering/IrWalker.g";
import "src/Backend/Mangler.g";
import "src/Backend/Layout.g";
import "src/CLI/AppaConsts.g";
import "src/CLI/Fmt.g";
import "src/CLI/Manifest.g";
import "selfhostlib/Paths.g";
import "src/CLI/Spin.g";

/*
 * Everything Transpile produced: the parsed programs in dependency order, every path it tried, the
 * import graph, and the bag the whole run reports into.
 */
class TranspileResult {
    public List[ProgramFile] programs;
    public List[String] attempted;
    public StringMap[List[String]] imports;
    public DiagnosticBag diag;
    public SourceSet sources;
    func _init(List[ProgramFile] programs, List[String] attempted, StringMap[List[String]] imports,
               DiagnosticBag diag, SourceSet sources) {
        self.programs = programs;
        self.attempted = attempted;
        self.imports = imports;
        self.diag = diag;
        self.sources = sources;
    }
}

/*
 * What BuildModule produced: the lowered module, its name sourcemap, the scanned capabilities, and
 * the type table and mangler the backend needs to keep asking questions with.
 */
class BuiltModule {
    public IrModule mod;
    public StringMap[String] sourcemap;
    public CapabilityScan caps;
    public IrTypeTable t;
    public Mangler mangler;
    func _init(IrModule mod, StringMap[String] sourcemap, CapabilityScan caps, IrTypeTable t,
               Mangler mangler) {
        self.mod = mod;
        self.sourcemap = sourcemap;
        self.caps = caps;
        self.t = t;
        self.mangler = mangler;
    }
}

module Pipeline {

    /*
     * ProjectWide - Stands in for a file path on diagnostics belonging to the build as a whole
     * rather than to any one source file. Without it the header renders as a bare ": error[...]".
     */
    String func ProjectWide() { return "<project>"; }

    /*
     * MaxMonomorphizationRounds - How many times the front end may re-run to create generic
     * instantiations discovered during resolution. Each round can only ADD instantiations, and a
     * program needing more than a couple of levels is asking for an infinite family; the cap turns
     * that into the resolver's diagnostic rather than a hang.
     */
    int func MaxMonomorphizationRounds() { return 6; }

    // --- Project discovery -------------------------------------------------------------------

    /*
     * DiscoverEnv - The project file marked @environment. Parses the top-level *.g files in
     * ordinal order and returns the first one carrying the marker; a file that will not parse is
     * recorded rather than reported, because the real diagnostic belongs to the build.
     */
    public Optional[String] func DiscoverEnv(String projectRoot, List[String] unreadable) {
        let List[String] files = Paths.ListWithExt(projectRoot, ".g");
        let int i = 0;
        while (i < files.Length()) {
            let String f = files.Get(i);
            let bool ok = false;
            match (File.Read(f)) {
                case Err(msg) { unreadable.Add(Paths.FileName(f)); }
                case Ok(src) {
                    let Lexer lx = new Lexer(src);
                    let List[Token] toks = lx.Tokenize() catch {
                        unreadable.Add(Paths.FileName(f));
                        assign new List[Token]();
                    };
                    if (toks.Length() > 0) {
                        let Parser ps = new Parser(toks, new Mangler());
                        let Program prog = ps.ParseProgram() catch {
                            unreadable.Add(Paths.FileName(f));
                            assign new Program(new List[TopLevel]());
                        };
                        let int k = 0;
                        while (k < prog.items.Length()) {
                            match (prog.items.Get(k)) {
                                case EnvironmentDecl(x) { ok = true; }
                                default { }
                            }
                            k = k + 1;
                        }
                    }
                }
            }
            if (ok) { return Optional.Some(Paths.FullPath(f)); }
            i = i + 1;
        }
        return Optional[String].None();
    }

    /*
     * DiscoverEntry - The entry point, by the src/main.g convention
     */
    public Optional[String] func DiscoverEntry(String projectRoot) {
        let String p = Paths.Join3(projectRoot, "src", "main.g");
        if (File.Exists(p)) { return Optional.Some(Paths.FullPath(p)); }
        return Optional[String].None();
    }

    /*
     * FindLibgata - The libgata directory from an appa install.
     *
     * The C# compiler resolves this through AppaPaths, which is built out of the platform's
     * local-share directory and the SUDO_USER dance. This port has no such table (see the note in
     * AppaConsts.g), so it looks where the install puts it relative to the process cwd and
     * otherwise says so; --stdlib <dir> is the supported answer either way.
     */
    public Optional[String] func FindLibgata() {
        let List[String] candidates = new List[String]();
        candidates.Add("selfhostlib");
        candidates.Add("libgata");
        candidates.Add(Paths.Join(Dir.Cwd(), "selfhostlib"));
        candidates.Add(Paths.Join(Dir.Cwd(), "libgata"));
        let int i = 0;
        while (i < candidates.Length()) {
            let String c = candidates.Get(i);
            if (Dir.IsDir(c) && Paths.ListWithExt(c, ".g").Length() > 0) {
                return Optional.Some(Paths.FullPath(c));
            }
            i = i + 1;
        }
        return Optional[String].None();
    }

    /*
     * ResolveLibgata - An unquoted library import name to a path inside the libgata directory
     */
    public String func ResolveLibgata(String name, String libgataDir, String fromFile,
                                      DiagnosticBag diag, TextSpan span) {
        let String candidate = Paths.Join(libgataDir, name + ".g");
        if (File.Exists(candidate)) { return candidate; }
        diag.Error(Codes.File(), fromFile, span,
                   "cannot find library module '" + name + "' (" + name + ".g) in " + libgataDir);
        return "";
    }

    // --- Build pipeline ----------------------------------------------------------------------

    /*
     * Transpile - Parses the entry files and follows their imports transitively, returning the
     * parsed programs in dependency order along with the per-file import graph
     */
    public TranspileResult func Transpile(List[String] inputFiles, String projectRoot, String libgataDir) {
        let SourceSet sources = new SourceSet();
        let DiagnosticBag diag = new DiagnosticBag(sources);
        let List[ProgramFile] ordered = new List[ProgramFile]();
        let List[String] attempted = new List[String]();
        let StringMap[List[String]] imports = new StringMap[List[String]]();
        let StringSet visited = new StringSet();

        let List[String] work = new List[String]();
        let int f = 0;
        while (f < inputFiles.Length()) { work.Add(Paths.FullPath(inputFiles.Get(f))); f = f + 1; }

        let int i = 0;
        while (i < work.Length()) {
            Pipeline.ResolveOne(work.Get(i), projectRoot, libgataDir, sources, diag, ordered,
                                attempted, imports, visited);
            i = i + 1;
        }
        return new TranspileResult(ordered, attempted, imports, diag, sources);
    }

    /*
     * ResolveOne - Parses one file and recurses into its imports.
     *
     * C# writes this as a local function closing over every accumulator; with no closures they are
     * parameters. The recursion order is what puts the programs in dependency order, so it is a
     * depth-first walk here exactly as it is there.
     */
    void func ResolveOne(String path, String projectRoot, String libgataDir, SourceSet sources,
                         DiagnosticBag diag, List[ProgramFile] ordered, List[String] attempted,
                         StringMap[List[String]] imports, StringSet visited) {
        if (!visited.AddNew(path)) { return; }

        if (!File.Exists(path)) {
            diag.Error(Codes.File(), path, TS.NoneSpan(), "file not found: '" + path + "'");
            attempted.Add(path);
            return;
        }

        let String src = "";
        match (File.Read(path)) {
            case Ok(text) { src = text; }
            case Err(msg) {
                diag.Error(Codes.File(), path, TS.NoneSpan(), "cannot read '" + path + "': " + msg);
                attempted.Add(path);
                return;
            }
        }
        sources.Add(path, src);

        let bool parsed = false;
        let Program prog = new Program(new List[TopLevel]());
        let Lexer lx = new Lexer(src);
        let List[Token] toks = lx.Tokenize() catch {
            diag.Error(PErr.Code(lx.lastErr), path, PErr.Span(lx.lastErr), PErr.Message(lx.lastErr));
            assign new List[Token]();
        };
        if (toks.Length() > 0) {
            // The env/entry parse only needs an AST, so a throwaway mangler is right here; the
            // one the pipeline threads is created in BuildModule and used from there on.
            let Parser ps = new Parser(toks, new Mangler());
            prog = ps.ParseProgram() catch {
                diag.Error(PErr.Code(ps.lastErr), path, PErr.Span(ps.lastErr), PErr.Message(ps.lastErr));
                assign new Program(new List[TopLevel]());
            };
            parsed = true;
        }

        let List[String] edges = new List[String]();
        if (parsed) {
            let int k = 0;
            while (k < prog.items.Length()) {
                match (prog.items.Get(k)) {
                    case ImportDecl(imp) {
                        let String resolved = imp.isPath
                            ? Paths.Join(projectRoot, imp.name)
                            : Pipeline.ResolveLibgata(imp.name, libgataDir, path, diag, imp.span);
                        if (resolved.Length() > 0) {
                            resolved = Paths.FullPath(resolved);
                            edges.Add(resolved);
                            Pipeline.ResolveOne(resolved, projectRoot, libgataDir, sources, diag,
                                                ordered, attempted, imports, visited);
                        }
                    }
                    default { }
                }
                k = k + 1;
            }
        }
        imports.Put(path, edges);
        if (parsed) { ordered.Add(new ProgramFile(path, prog)); }
        attempted.Add(path);
    }

    /*
     * VisibleModules - For each file, the set of files whose top-level names it may reference:
     * itself plus the transitive closure of its imports
     */
    public StringMap[StringSet] func VisibleModules(StringMap[List[String]] imports) {
        let StringMap[StringSet] visible = new StringMap[StringSet]();
        let List[String] files = imports.Keys();
        let int i = 0;
        while (i < files.Length()) {
            let String file = files.Get(i);
            let StringSet seen = new StringSet();
            seen.AddNew(file);
            let List[String] stack = new List[String]();
            stack.Add(file);
            while (stack.Length() > 0) {
                let String top = stack.Get(stack.Length() - 1);
                stack.RemoveLast();
                match (imports.Find(top)) {
                    case Some(deps) {
                        let int d = 0;
                        while (d < deps.Length()) {
                            if (seen.AddNew(deps.Get(d))) { stack.Add(deps.Get(d)); }
                            d = d + 1;
                        }
                    }
                    case None { }
                }
            }
            visible.Put(file, seen);
            i = i + 1;
        }
        return visible;
    }

    /*
     * BuildModule - The whole front end and lowering chain, re-running while resolution keeps
     * discovering generic instantiations
     */
    public BuiltModule func BuildModule(List[ProgramFile] programs, StringMap[StringSet] visible,
                                        Mode mode, DiagnosticBag diag) {
        let List[ProgramFile] pristine = new List[ProgramFile]();
        let int p = 0;
        while (p < programs.Length()) { pristine.Add(programs.Get(p)); p = p + 1; }

        let Mangler mangler = new Mangler();
        let List[GenericSeed] seeds = new List[GenericSeed]();
        let StringSet seeded = new StringSet();
        let int mark = diag.Count();

        let IrModule mod = null;
        let CollectionResult collected = null;
        let IrTypeTable typeTable = null;

        let int round = 0;
        while (true) {
            programs.Clear();
            let int q = 0;
            while (q < pristine.Length()) { programs.Add(pristine.Get(q)); q = q + 1; }
            diag.TruncateTo(mark);

            mangler.BeginRound();
            let ScopeBinder binder = new ScopeBinder(diag, mangler);
            binder.Bind(programs, visible);

            let Monomorphizer mono = new Monomorphizer(diag, mangler);
            let StringMap[String] genericRequestFile = mono.Process(programs, seeds);

            let SymbolCollector sc = new SymbolCollector(diag, mangler);
            collected = sc.Collect(programs);

            let StringMap[StringSet] seedScopes = new StringMap[StringSet]();
            let int s = 0;
            while (s < seeds.Length()) {
                let StringSet sc2 = new StringSet();
                let int sz = 0;
                while (sz < seeds.Get(s).scope.Length()) { sc2.AddNew(seeds.Get(s).scope.Get(sz)); sz = sz + 1; }
                seedScopes.Put(seeds.Get(s).Key(mangler), sc2);
                s = s + 1;
            }

            let TypeResolver tr = new TypeResolver(collected.sym, collected.hasInit,
                collected.preDefinedStructs, collected.opaqueFieldClasses, visible,
                genericRequestFile, seedScopes, mode == Mode.Release, diag, mangler);
            mod = tr.Resolve(programs);
            typeTable = tr.t;

            if (round >= Pipeline.MaxMonomorphizationRounds()) { break; }
            let int before = seeds.Length();
            let List[GenericSeed] pend = tr.pendingInstances;
            let int pi = 0;
            while (pi < pend.Length()) {
                if (seeded.AddNew(pend.Get(pi).Key(mangler))) { seeds.Add(pend.Get(pi)); }
                pi = pi + 1;
            }
            if (seeds.Length() == before) { break; }
            round = round + 1;
        }

        Pipeline.ValidateCNames(mod, mangler, diag);
        if (diag.HasErrors()) {
            return new BuiltModule(mod, new StringMap[String](), new CapabilityScan(mod),
                                   typeTable, mangler);
        }

        let Desugar dg = new Desugar(collected.sym, diag, mangler, typeTable);
        dg.Run(mod);

        let CapabilityScan caps = new CapabilityScan(mod);
        caps.Run();

        let Dce dce = new Dce(mod);
        dce.Run();

        let Densifier dn = new Densifier(mod, mangler);
        let StringMap[String] sourcemap = dn.Run();

        let Ownership own = new Ownership(mod, typeTable, mangler);
        own.Run();

        return new BuiltModule(mod, sourcemap, caps, typeTable, mangler);
    }

    // --- Whole-build validation ---------------------------------------------------------------

    /*
     * ValidateEnvironment - Exactly one @environment file takes part in the build
     */
    public void func ValidateEnvironment(List[ProgramFile] programs, DiagnosticBag diag) {
        let List[String] envFiles = new List[String]();
        let List[TextSpan] envSpans = new List[TextSpan]();
        let int i = 0;
        while (i < programs.Length()) {
            let ProgramFile pf = programs.Get(i);
            let int k = 0;
            while (k < pf.prog.items.Length()) {
                match (pf.prog.items.Get(k)) {
                    case EnvironmentDecl(e) { envFiles.Add(pf.path); envSpans.Add(e.span); }
                    default { }
                }
                k = k + 1;
            }
            i = i + 1;
        }

        if (envFiles.Length() == 0) {
            let List[String] hints = new List[String]();
            hints.Add("exactly one .g file in the build must be marked '@environment'; pass it with --env, or put it in the project directory");
            diag.Error(Codes.File(), Pipeline.ProjectWide(), TS.NoneSpan(),
                            "no @environment file in the build", hints);
            return;
        }
        let int j = 1;
        while (j < envFiles.Length()) {
            diag.Error(Codes.File(), envFiles.Get(j), envSpans.Get(j),
                       "multiple @environment files; exactly one is allowed");
            j = j + 1;
        }
    }

    /*
     * ValidateFloor - Every _env_* bind the lowered IR reaches is defined by the active
     * environment's @preamble. Turns a missing-bind LINK error into a diagnostic that names the
     * environment as the incomplete thing, which is what it is.
     */
    public void func ValidateFloor(IrModule mod, DiagnosticBag diag) {
        let EnvProbe probe = new EnvProbe(mod.symbols);
        probe.Run(mod);

        if (mod.processes.Length() > 0) {
            probe.refs.AddNew(mod.symbols.FloorName(Roles.EnvProcCreate()));
            probe.refs.AddNew(mod.symbols.FloorName(Roles.EnvThreadSpawn()));
            let int p = 0;
            while (p < mod.processes.Length()) {
                if (mod.processes.Get(p).mode == "background") {
                    probe.refs.AddNew(mod.symbols.FloorName(Roles.EnvProcHide()));
                }
                p = p + 1;
            }
        }
        if (probe.refs.Length() == 0) { return; }

        let StringBuilder pre = new StringBuilder();
        let int n = 0;
        while (n < mod.nativeBlocks.Length()) {
            let IrNativeBlock nb = mod.nativeBlocks.Get(n);
            if (nb.section == NativeSection.Preamble) {
                if (pre.Length() > 0) { pre.Append("\n"); }
                pre.Append(nb.c);
            }
            n = n + 1;
        }
        let String env = NativeC.Mask(pre.ToString());

        let List[String] names = Paths.SortStrings(probe.refs.ToList());
        let int i = 0;
        while (i < names.Length()) {
            let String name = names.Get(i);
            if (!Pipeline.ContainsWholeWord(env, name)) {
                diag.Error(Codes.MissingFloorBind(), "<environment>", TS.NoneSpan(),
                    "the active environment's @preamble provides no definition of '" + name +
                    "'; add one (the environment file, not your Gata source, is incomplete)");
            }
            i = i + 1;
        }
    }

    /*
     * ArcRoles - The reference-counting runtime as ONE contract, not five knobs
     */
    List[String] func ArcRoles() {
        let List[String] r = new List[String]();
        r.Add(Roles.Alloc());
        r.Add(Roles.Retain());
        r.Add(Roles.Release());
        r.Add(Roles.ObjHeader());
        r.Add(Roles.ObjInit());
        return r;
    }

    /*
     * ValidateIntrinsics - The standard library has to bind the whole ARC contract whenever a
     * reference-counted class survives to codegen. Here rather than in BuildModule, which runs over
     * stdlib-free input where an unbound role means only "no standard library".
     */
    public void func ValidateIntrinsics(IrModule mod, DiagnosticBag diag) {
        let bool needsArc = false;
        let int c = 0;
        while (c < mod.classes.Length()) {
            if (!mod.classes.Get(c).isModule) { needsArc = true; }
            c = c + 1;
        }
        if (!needsArc) { return; }

        let List[String] roles = Pipeline.ArcRoles();
        let List[String] missing = new List[String]();
        let int i = 0;
        while (i < roles.Length()) {
            match (mod.symbols.IntrinsicOrNull(roles.Get(i))) {
                case None { missing.Add("@intrinsic(" + roles.Get(i) + ")"); }
                case Some(x) { }
            }
            i = i + 1;
        }
        if (missing.Length() == 0) { return; }

        let bool none = missing.Length() == roles.Length();
        let String missingText = String.Join(missing, ", ");

        let List[String] all = new List[String]();
        let int j = 0;
        while (j < roles.Length()) { all.Add("@intrinsic(" + roles.Get(j) + ")"); j = j + 1; }

        let List[String] hints = new List[String]();
        hints.Add("reference counting needs the whole set: " + String.Join(all, ", "));
        if (none) {
            hints.Add("nothing in the build provides them - import a libgata module (any of them pulls in 'Mem'), or drop the class if this file is meant to stand alone");
        } else {
            hints.Add("the standard library is incomplete, not your program; check libgata's Runtime.g and Mem.g");
        }

        let String msg = none
            ? ("this build declares a class, but nothing in it binds " + missingText)
            : ("the standard library binds no " + missingText);
        diag.Error(Codes.MissingIntrinsic(), "<runtime>", TS.NoneSpan(), msg, hints);
    }

    /*
     * ValidateCNames - Two declarations that would be emitted under one C name. Every readable
     * mangling joins its parts with '_', which is also legal inside each part, so 'class A_B { M }'
     * and 'class A { B_M }' both spell 'gata_A_B_M'. Caught here rather than left to the C compiler,
     * which would report it against generated names the author never wrote.
     */
    public void func ValidateCNames(IrModule mod, Mangler mangler, DiagnosticBag diag) {
        let StringMap[String] seen = new StringMap[String]();

        let int c = 0;
        while (c < mod.classes.Length()) {
            let IrClass cls = mod.classes.Get(c);
            let String owner = mangler.DisplayName(cls.name);
            Pipeline.Claim(seen, diag, cls.cName, "type '" + owner + "'");
            let int m = 0;
            while (m < cls.methods.Length()) {
                Pipeline.Claim(seen, diag, cls.methods.Get(m).cName,
                               "method '" + owner + "." + cls.methods.Get(m).name + "'");
                m = m + 1;
            }
            let int o = 0;
            while (o < cls.operators.Length()) {
                Pipeline.Claim(seen, diag, cls.operators.Get(o).cName,
                               "operator '" + owner + "." + cls.operators.Get(o).op + "'");
                o = o + 1;
            }
            c = c + 1;
        }

        let int e = 0;
        while (e < mod.enums.Length()) {
            let IrEnum en = mod.enums.Get(e);
            let String shown = mangler.DisplayName(en.name);
            Pipeline.Claim(seen, diag, en.cName, "enum '" + shown + "'");
            let int k = 0;
            while (k < en.members.Length()) {
                Pipeline.Claim(seen, diag, mangler.EnumMember(en.name, en.members.Get(k).name),
                               "enum member '" + shown + "." + en.members.Get(k).name + "'");
                k = k + 1;
            }
            e = e + 1;
        }

        let int u = 0;
        while (u < mod.unions.Length()) {
            Pipeline.Claim(seen, diag, mod.unions.Get(u).cName,
                           "union '" + mangler.DisplayName(mod.unions.Get(u).name) + "'");
            u = u + 1;
        }
        let int nt = 0;
        while (nt < mod.nativeTypes.Length()) {
            Pipeline.Claim(seen, diag, mod.nativeTypes.Get(nt).cName,
                           "native type '" + mangler.DisplayName(mod.nativeTypes.Get(nt).name) + "'");
            nt = nt + 1;
        }
        let int f = 0;
        while (f < mod.freeFunctions.Length()) {
            let IrFunction fn = mod.freeFunctions.Get(f);
            Pipeline.Claim(seen, diag, fn.cName,
                fn.isEntry ? "the entry point" : ("function '" + mangler.DisplayName(fn.name) + "'"));
            f = f + 1;
        }
        let int fp = 0;
        while (fp < mod.funcPtrTypes.Length()) {
            Pipeline.Claim(seen, diag, mangler.CType(mod.funcPtrTypes.Get(fp)),
                           "the function type '" + Types.MangledName(mod.funcPtrTypes.Get(fp)) + "'");
            fp = fp + 1;
        }
        let int ar = 0;
        while (ar < mod.arrayTypes.Length()) {
            Pipeline.Claim(seen, diag, mangler.CType(mod.arrayTypes.Get(ar)),
                           "the array type '" + Types.MangledName(mod.arrayTypes.Get(ar)) + "'");
            ar = ar + 1;
        }

        Pipeline.Claim(seen, diag, Layout.LauncherName(), "the generated process launcher");

        let List[Symbol] externs = mod.symbols.Externs();
        let int x = 0;
        while (x < externs.Length()) {
            let Symbol sym = externs.Get(x);
            Pipeline.Claim(seen, diag, sym.cName, "'@extern' declaration of '" + sym.name + "'");
            if (Mangle.IsCReserved(sym.cName)) {
                let List[String] hints = new List[String]();
                hints.Add("rename the declaration; an '@extern' name is emitted verbatim so the linker can find it, and so cannot be a C keyword or standard macro");
                diag.Error(Codes.CReservedCName(), "<runtime>", TS.NoneSpan(),
                    "'@extern' declaration of '" + sym.name + "' is emitted as the C name '" +
                    sym.cName + "', which C reserves", hints);
            }
            x = x + 1;
        }

        let int p = 0;
        while (p < mod.processes.Length()) {
            let IrProcess proc = mod.processes.Get(p);
            let String inRealm = "userspace";
            match (proc.stateInit) {
                case Some(si) { if (si.vis == Visibility.Kernel) { inRealm = "kernel"; } }
                case None { }
            }
            let int v = 0;
            while (v < proc.state.Length()) {
                Pipeline.Claim(seen, diag, proc.state.Get(v).cName,
                    "process variable '" + inRealm + "." + proc.name + "." + proc.state.Get(v).name + "'");
                v = v + 1;
            }
            match (proc.stateInit) {
                case Some(si) {
                    Pipeline.Claim(seen, diag, si.cName,
                                   "the initialiser generated for '" + inRealm + "." + proc.name + "'");
                    Pipeline.Claim(seen, diag, si.cName + "_gate",
                                   "the state gate generated for '" + inRealm + "." + proc.name + "'");
                    Pipeline.Claim(seen, diag, si.cName + "_enter",
                                   "the state entry generated for '" + inRealm + "." + proc.name + "'");
                }
                case None { }
            }
            let int th = 0;
            while (th < proc.threads.Length()) {
                let IrThread t = proc.threads.Get(th);
                match (t.entryFunc) {
                    case Some(ef) {
                        let String r2 = ef.vis == Visibility.Kernel ? "kernel" : "userspace";
                        Pipeline.Claim(seen, diag, ef.cName,
                                       "thread '" + r2 + "." + proc.name + "." + t.name + "'");
                    }
                    case None { }
                }
                th = th + 1;
            }
            p = p + 1;
        }
    }

    /*
     * Claim - Records one C name against what declared it, reporting the second claimant
     */
    void func Claim(StringMap[String] seen, DiagnosticBag diag, String cname, String what) {
        if (cname.Length() == 0) { return; }
        match (seen.Find(cname)) {
            case None { seen.Put(cname, what); }
            case Some(prev) {
                if (prev != what) {
                    let List[String] hints = new List[String]();
                    hints.Add("rename one of them; a readable C name joins its parts with '_', which two differently split names can spell the same way");
                    diag.Error(Codes.DuplicateName(), "<runtime>", TS.NoneSpan(),
                        what + " and " + prev + " are both emitted as the C name '" + cname + "'", hints);
                }
            }
        }
    }

    /*
     * ContainsWholeWord - Whether text contains a name as a whole C identifier rather than as a
     * substring of a longer one
     */
    public bool func ContainsWholeWord(String text, String name) {
        let int from = 0;
        while (true) {
            let int at = text.IndexOf(name, from);
            if (at < 0) { return false; }
            let bool beforeOk = at == 0 || !Pipeline.IsIdentChar(text.CharAt(at - 1));
            let bool afterOk = at + name.Length() >= text.Length()
                               || !Pipeline.IsIdentChar(text.CharAt(at + name.Length()));
            if (beforeOk && afterOk) { return true; }
            from = at + 1;
        }
    }

    bool func IsIdentChar(char c) {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
    }

    /*
     * IsLibrary - Whether a path lies inside the standard library, which is code the author cannot
     * edit. An empty libgataDir treats every file as theirs.
     */
    public bool func IsLibrary(String path, String libgataDir) {
        if (libgataDir.Length() == 0) { return false; }
        return Paths.IsUnder(path, libgataDir);
    }

    /*
     * CountSummary - An error/warning count as the summary line appa prints
     */
    public String func CountSummary(int errors, int warnings) {
        let String e = errors > 0
            ? (Int.ToString(errors) + " error" + (errors == 1 ? "" : "s")) : "";
        let String w = warnings > 0
            ? (Int.ToString(warnings) + " warning" + (warnings == 1 ? "" : "s")) : "";
        if (e.Length() > 0 && w.Length() > 0) { return e + ", " + w; }
        return e + w;
    }

    /*
     * ValidateStructure - Realm structure against the target.
     *
     * A realm is ONE namespace however many blocks open it, in however many files, so what is
     * counted here is entry points rather than blocks - the rule the reference states in 1.3 and
     * the reason this is a whole-build check rather than a per-file one.
     */
    public void func ValidateStructure(List[ProgramFile] programs, Target target, DiagnosticBag diag) {
        let List[String] kernelFiles = new List[String]();
        let List[TextSpan] kernelSpans = new List[TextSpan]();
        let List[String] userFiles = new List[String]();
        let List[TextSpan] userSpans = new List[TextSpan]();
        let List[ContextDecl] userDecls = new List[ContextDecl]();

        let int i = 0;
        while (i < programs.Length()) {
            let ProgramFile pf = programs.Get(i);
            let int k = 0;
            while (k < pf.prog.items.Length()) {
                match (pf.prog.items.Get(k)) {
                    case ContextDecl(c) {
                        if (c.kind == Realm.Kernel) { kernelFiles.Add(pf.path); kernelSpans.Add(c.span); }
                        else { userFiles.Add(pf.path); userSpans.Add(c.span); userDecls.Add(c); }
                    }
                    default { }
                }
                k = k + 1;
            }
            i = i + 1;
        }

        // A process with no threads would be created and never do anything.
        let int p = 0;
        while (p < programs.Length()) {
            let ProgramFile pf = programs.Get(p);
            let int k = 0;
            while (k < pf.prog.items.Length()) {
                match (pf.prog.items.Get(k)) {
                    case ContextDecl(ctx) {
                        let int n = 0;
                        while (n < ctx.items.Length()) {
                            match (ctx.items.Get(n)) {
                                case ProcessDecl(pd) {
                                    if (pd.threads.Length() == 0 && !Pipeline.Reported(diag, pf.path, pd.span)) {
                                        let List[String] hints = new List[String]();
                                        hints.Add("a process runs only through its threads, so this one would be created and never do anything");
                                        hints.Add("give it one: 'thread Worker { entry func Run() { } }', or remove '" + pd.name + "'");
                                        diag.Error(Codes.ProcessWithoutThreads(), pf.path, pd.span,
                                                   "process '" + pd.name + "' declares no threads", hints);
                                    }
                                }
                                default { }
                            }
                            n = n + 1;
                        }
                    }
                    default { }
                }
                k = k + 1;
            }
            p = p + 1;
        }

        if (target == Target.Hosted) {
            let int kb = 0;
            while (kb < kernelFiles.Length()) {
                diag.Error(Codes.KernelBlockInHosted(), kernelFiles.Get(kb), kernelSpans.Get(kb),
                           "a 'realm kernel { }' block is not allowed in a Hosted build");
                kb = kb + 1;
            }

            if (userDecls.Length() == 0) {
                let List[String] hints = new List[String]();
                hints.Add("wrap the entry point in 'realm userspace { entry func Main() { ... } }'");
                diag.Error(Codes.MissingRealm(), Pipeline.ProjectWide(), TS.NoneSpan(),
                    "no 'realm userspace { }' block found in any .g file, but a Hosted build needs one", hints);
                return;
            }

            let List[String] entryFiles = new List[String]();
            let List[TextSpan] entrySpans = new List[TextSpan]();
            let int u = 0;
            while (u < userDecls.Length()) {
                let ContextDecl ud = userDecls.Get(u);
                let int n = 0;
                while (n < ud.items.Length()) {
                    match (ud.items.Get(n)) {
                        case FuncDecl(ef) {
                            if (ef.isEntry) { entryFiles.Add(userFiles.Get(u)); entrySpans.Add(ef.span); }
                        }
                        default { }
                    }
                    n = n + 1;
                }
                u = u + 1;
            }

            if (entryFiles.Length() == 0) {
                diag.Error(Codes.MissingEntry(), userFiles.Get(0), userSpans.Get(0),
                           "the 'realm userspace { }' block declares no 'entry func'");
                return;
            }
            let int e = 1;
            while (e < entryFiles.Length()) {
                diag.Error(Codes.DuplicateEntry(), entryFiles.Get(e), entrySpans.Get(e),
                           "the userspace realm declares more than one 'entry func'");
                e = e + 1;
            }
            return;
        }

        // GatOS from here: the kernel realm holds the entry point, and userspace entry points are
        // the threads of a process.
        let List[String] kEntryFiles = new List[String]();
        let List[TextSpan] kEntrySpans = new List[TextSpan]();
        let int q = 0;
        while (q < programs.Length()) {
            let ProgramFile pf = programs.Get(q);
            let int k = 0;
            while (k < pf.prog.items.Length()) {
                match (pf.prog.items.Get(k)) {
                    case ContextDecl(c) {
                        let int n = 0;
                        while (n < c.items.Length()) {
                            match (c.items.Get(n)) {
                                case FuncDecl(ef) {
                                    if (ef.isEntry) {
                                        if (c.kind == Realm.Kernel) {
                                            kEntryFiles.Add(pf.path);
                                            kEntrySpans.Add(ef.span);
                                        } else {
                                            diag.Error(Codes.EntryOutsideKernel(), pf.path, ef.span,
                                                "an 'entry func' inside a 'realm userspace { }' block is only valid in a Hosted build; " +
                                                "in a GatOS build, userspace entry points are the threads of a 'process'");
                                        }
                                    }
                                }
                                default { }
                            }
                            n = n + 1;
                        }
                    }
                    case FuncDecl(tef) {
                        if (tef.isEntry) {
                            let List[String] hints = new List[String]();
                            hints.Add("move it inside the 'realm kernel { }' block, or drop 'entry'");
                            diag.Error(Codes.EntryOutsideKernel(), pf.path, tef.span,
                                "'" + tef.name + "' is declared 'entry' outside any realm block", hints);
                        }
                    }
                    default { }
                }
                k = k + 1;
            }
            q = q + 1;
        }

        if (kernelFiles.Length() == 0) {
            let List[String] hints = new List[String]();
            hints.Add("a GatOS build boots into the kernel realm: add 'realm kernel { entry func Main() { ... } }'");
            diag.Error(Codes.MissingEntryPoint(), Pipeline.ProjectWide(), TS.NoneSpan(),
                       "no 'realm kernel { }' entry point found in any .g file", hints);
            return;
        }

        if (kEntryFiles.Length() == 0) {
            diag.Error(Codes.MissingEntryPoint(), kernelFiles.Get(0), kernelSpans.Get(0),
                       "the 'realm kernel { }' block declares no 'entry func'");
            return;
        }
        let int d = 1;
        while (d < kEntryFiles.Length()) {
            diag.Error(Codes.DuplicateEntry(), kEntryFiles.Get(d), kEntrySpans.Get(d),
                       "the kernel realm declares more than one 'entry func'");
            d = d + 1;
        }
    }

    /*
     * Reported - True when something has already been reported at exactly this declaration
     */
    bool func Reported(DiagnosticBag diag, String file, TextSpan span) {
        let int i = 0;
        while (i < diag.Count()) {
            let Diagnostic d = diag.All().Get(i);
            if (Diags.Severity(d) == Severity.Error
                && TS.Start(Locs.Span(Diags.Loc(d))) == TS.Start(span)
                && TS.Length(Locs.Span(Diags.Loc(d))) == TS.Length(span)
                && Locs.File(Diags.Loc(d)).ToLower() == file.ToLower()) {
                return true;
            }
            i = i + 1;
        }
        return false;
    }
}

/*
 * EnvProbe - Collects every _env_* name the lowered IR actually reaches, so ValidateFloor can ask
 * the environment for exactly those and no more.
 *
 * C# subclasses IrRewriter and overrides two methods; the port has no inheritance, so it is an
 * IrWalk state class with two free-function hooks - the shape IrWalker.g exists for.
 */
class EnvProbe {
    public StringSet refs;
    public SymbolTable sym;
    func _init(SymbolTable sym) {
        self.refs = new StringSet();
        self.sym = sym;
    }

    /*
     * Run - Every body in the module
     */
    public void func Run(IrModule m) {
        let IrWalk[EnvProbe] w = new IrWalk[EnvProbe](self, ProbeStmt, ProbeExpr);
        let int c = 0;
        while (c < m.classes.Length()) {
            let IrClass cls = m.classes.Get(c);
            let int i = 0;
            while (i < cls.methods.Length()) {
                match (cls.methods.Get(i).body) {
                    case Some(b) { w.WalkStmt(IrStmt.IrBlock(b)); }
                    case None { }
                }
                i = i + 1;
            }
            let int o = 0;
            while (o < cls.operators.Length()) {
                match (cls.operators.Get(o).body) {
                    case Some(b) { w.WalkStmt(IrStmt.IrBlock(b)); }
                    case None { }
                }
                o = o + 1;
            }
            c = c + 1;
        }
        let int f = 0;
        while (f < m.freeFunctions.Length()) {
            match (m.freeFunctions.Get(f).body) {
                case Some(b) { w.WalkStmt(IrStmt.IrBlock(b)); }
                case None { }
            }
            f = f + 1;
        }
    }
}

/*
 * ProbeExpr - The _env_* names named by a static call
 */
bool func ProbeExpr(IrWalk[EnvProbe] w, IrExpr e) {
    match (e) {
        case IrStaticCall(sc) { if (sc.cName.StartsWith("_env_")) { w.state.refs.AddNew(sc.cName); } }
        default { }
    }
    return true;
}

/*
 * ProbeStmt - debug and panic reach the floor through their BOUND names, never a hardcoded literal
 */
bool func ProbeStmt(IrWalk[EnvProbe] w, IrStmt s) {
    match (s) {
        case IrDebug(x) { w.state.refs.AddNew(w.state.sym.FloorName(Roles.EnvDebug())); }
        case IrPanic(x) { w.state.refs.AddNew(w.state.sym.FloorName(Roles.EnvPanic())); }
        default { }
    }
    return true;
}
