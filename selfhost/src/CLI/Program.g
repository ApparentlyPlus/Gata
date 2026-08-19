/*
 * Program.g - the appa command line: dispatch, the build and check commands, and the help
 *
 * Ports Appa/src/CLI/Program.cs.
 *
 * WHAT THIS COMPILER DOES AND DOES NOT DO
 *
 * Every command appa has is accepted here and spelled the same way, but three of them cannot be
 * carried out by a transpile-only compiler, and each says so rather than pretending:
 *
 *   appa install / appa update   need HTTPS, a GitHub release download, zip extraction, PATH
 *                                editing and privilege elevation. None of that is in the floor.
 *   appa run                     needs to spawn QEMU. There is no process-spawn bind.
 *   appa build on a GatOS target needs to spawn the cross-gcc, grub-mkrescue and xorriso. Same.
 *   appa new                     needs the installed env.GatOS.g that `appa install` puts in
 *                                place, so it depends on the first one.
 *
 * These are the boundaries selfhost.txt section 4 drew, and they are floor gaps rather than
 * language or compiler gaps: each one is a process-spawn or a network bind away. What IS here is
 * the whole transpile path - `appa build` on a Hosted project, `appa build --pure-transpile`,
 * `appa check`, `appa clean`, `--version` and `--help` - which is the part that makes the compiler
 * self-hosting.
 *
 * NOT PORTED for the same reason: Templates (the `appa new` file contents), GatosFlags (the cross-
 * compiler flag sets), and the Installer/Toolchain/GitHubDirDownloader files wholesale.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Set.g";
import "selfhostlib/Optional.g";
import "selfhostlib/File.g";
import "selfhostlib/Dir.g";
import "selfhostlib/Sys.g";
import "selfhostlib/Args.g";
import "selfhostlib/Console.g";
import "src/Diagnostics/Diagnostic.g";
import "src/IR/Ir.g";
import "src/Backend/Emitter.g";
import "src/Backend/Layout.g";
import "src/CLI/AppaConsts.g";
import "src/CLI/Banner.g";
import "src/CLI/CliUtil.g";
import "src/CLI/Fmt.g";
import "src/CLI/Manifest.g";
import "selfhostlib/Paths.g";
import "src/CLI/Pipeline.g";
import "src/CLI/Spin.g";

/*
 * What RunFrontEnd produced, plus the bag every command reports from.
 */
class FrontEndRun {
    public IrModule mod;
    public StringMap[String] sourcemap;
    public CapabilityScan caps;
    public DiagnosticBag diag;
    public IrTypeTable t;
    public Mangler mangler;
    func _init(IrModule mod, StringMap[String] sourcemap, CapabilityScan caps, DiagnosticBag diag,
               IrTypeTable t, Mangler mangler) {
        self.mod = mod;
        self.sourcemap = sourcemap;
        self.caps = caps;
        self.diag = diag;
        self.t = t;
        self.mangler = mangler;
    }
}

module AppaCli {

    /*
     * Main - The dispatch in Program.cs's top-level statements, argument for argument
     */
    public void func Main() {
        if (Args.Argc() <= 1) { AppaCli.PrintHelp(); return; }
        let String cmd = Args.Arg(1);
        let List[String] rest = AppaCli.Rest(2);

        if (cmd == "install" || cmd == "update") { AppaCli.RunUnsupportedSetup(cmd); return; }
        if (cmd == "new")   { AppaCli.RunNew(rest); return; }
        if (cmd == "clean") { AppaCli.RunClean(rest); return; }
        if (cmd == "build") { AppaCli.RunBuild(rest, false); return; }
        if (cmd == "run")   { AppaCli.RunBuild(rest, true); return; }
        if (cmd == "check") { AppaCli.RunCheck(rest); return; }
        if (cmd == "help" || cmd == "--help" || cmd == "-h") { AppaCli.PrintHelp(); return; }
        if (cmd == "version" || cmd == "--version" || cmd == "-v") {
            Console.PrintLine("Appa " + AppaVersion.Current());
            return;
        }

        if (cmd == "setup") {
            Log.ErrorHint("unknown command 'setup'", "'appa setup' is now 'appa install'");
            Sys.Exit(1);
        }
        match (Suggest.Closest(cmd, AppaCli.Commands())) {
            case Some(near) { Log.ErrorHint("unknown command '" + cmd + "'", "did you mean 'appa " + near + "'?"); }
            case None { Log.ErrorHint("unknown command '" + cmd + "'", "run 'appa --help' for the list of commands"); }
        }
        Sys.Exit(1);
    }

    /*
     * Rest - The arguments after index i, as a list
     */
    List[String] func Rest(int i) {
        let List[String] r = new List[String]();
        let int k = i;
        while (k < Args.Argc()) { r.Add(Args.Arg(k)); k = k + 1; }
        return r;
    }

    /*
     * Commands - Every command name, in the order the help lists them. Also what a mistyped command
     * is matched against, so the two can never drift apart.
     */
    List[String] func Commands() {
        let List[String] r = new List[String]();
        r.Add("install"); r.Add("update"); r.Add("new");
        r.Add("check"); r.Add("build"); r.Add("run"); r.Add("clean");
        return r;
    }

    // --- The commands this compiler cannot carry out -----------------------------------------

    /*
     * RunUnsupportedSetup - install and update, which need the network and the filesystem
     * privileges a transpile-only compiler has no binds for
     */
    void func RunUnsupportedSetup(String cmd) {
        Log.ErrorHint("'appa " + cmd + "' is not available in the self-hosted compiler",
            "it downloads the GatOS toolchain bundle over HTTPS, extracts it, and edits PATH - " +
            "none of which the environment floor binds. Use the C# appa for this step, or point " +
            "this one at an existing install with '--stdlib <dir>'.");
        Sys.Exit(1);
    }

    /*
     * RunNew - Scaffolding a project, which copies env.GatOS.g out of the directory `appa install`
     * creates
     */
    void func RunNew(List[String] _args) {
        Log.ErrorHint("'appa new' is not available in the self-hosted compiler",
            "it seeds a project from the environment file 'appa install' puts in the install root, " +
            "and this compiler cannot run 'appa install'. Copy an existing project's env.g and " +
            ".gconf, or scaffold with the C# appa.");
        Sys.Exit(1);
    }

    // --- appa clean ---------------------------------------------------------------------------

    /*
     * RunClean - Removes the directories a build writes into the project root, leaving sources and
     * the .gconf untouched
     */
    void func RunClean(List[String] args) {
        let Optional[String] dirArg = Optional[String].None();
        let int i = 0;
        while (i < args.Length()) {
            if (args.Get(i).StartsWith("--")) { Cli.Fail("unknown option '" + args.Get(i) + "'"); }
            else { dirArg = Optional.Some(args.Get(i)); }
            i = i + 1;
        }

        let String rawDir = ".";
        match (dirArg) { case Some(d) { rawDir = d; } case None { } }
        let String projectRoot = Paths.FullPath(rawDir);
        if (!Dir.IsDir(projectRoot)) { Cli.Fail("'" + rawDir + "' does not exist"); }

        let Optional[String] manifestPath = Optional[String].None();
        match (ManifestReader.Discover(projectRoot)) {
            case Ok(p) { manifestPath = p; }
            case Err(msg) { Cli.Fail(msg); }
        }
        let String mp = "";
        match (manifestPath) {
            case Some(p) { mp = p; }
            case None {
                Cli.FailHint("no <project>.gconf found in " + projectRoot,
                             "clean only removes build output from a project directory");
            }
        }

        Console.PrintLine("");
        Console.PrintLine(C.EMBER() + "Cleaning" + C.NC() + " " + Paths.FileNameNoExt(mp) + " " +
                          C.DIM() + "(" + projectRoot + ")" + C.NC());
        Console.PrintLine("");

        let int removed = 0;
        let List[String] gen = Cli.GeneratedDirs();
        let int g = 0;
        while (g < gen.Length()) {
            let String name = gen.Get(g);
            let String path = Paths.Join(projectRoot, name);
            if (Dir.IsDir(path)) {
                let int64 t0 = Spin.Now();
                if (!Dir.DeleteRecursive(path)) {
                    Cli.Fail("could not remove " + name + Paths.Sep());
                }
                Out.Step("removed " + name + Paths.Sep(), Spin.Now() - t0);
                removed = removed + 1;
            }
            g = g + 1;
        }

        if (removed == 0) {
            Out.Note(C.DIM() + "nothing to remove - the project is already clean" + C.NC());
        } else {
            Console.PrintLine("");
            Console.PrintLine(C.EMBER() + "✓" + C.NC() + " " + C.BOLD() + "Clean" + C.NC());
        }
        Console.PrintLine("");
    }

    // --- appa build / appa run ----------------------------------------------------------------

    /*
     * RunBuild - Parses the build arguments, runs the front end, and either writes the emitted C or
     * says why an image cannot be produced here
     */
    void func RunBuild(List[String] args, bool doRun) {
        let Optional[String] manifestArg = Optional[String].None();
        let Optional[String] envOverride = Optional[String].None();
        let Optional[String] entryOverride = Optional[String].None();
        let Optional[String] stdlibOverride = Optional[String].None();
        let bool warnAsError = false;
        let bool pureTranspile = false;
        let bool emitSourcemap = false;

        let int i = 0;
        while (i < args.Length()) {
            let String a = args.Get(i);
            if (a == "--env" && i + 1 < args.Length())         { i = i + 1; envOverride = Optional.Some(args.Get(i)); }
            else { if (a == "--entry" && i + 1 < args.Length())  { i = i + 1; entryOverride = Optional.Some(args.Get(i)); }
            else { if (a == "--stdlib" && i + 1 < args.Length()) { i = i + 1; stdlibOverride = Optional.Some(args.Get(i)); }
            else { if (a == "--werror")          { warnAsError = true; }
            else { if (a == "--pure-transpile")  { pureTranspile = true; }
            else { if (a == "--emit-sourcemap")  { emitSourcemap = true; }
            else { if (a == "headless" || a == "--headless")   { AppaCli.RunOnly(a, doRun); }
            else { if (a.StartsWith("timeout=") || a.StartsWith("--timeout=")) { AppaCli.RunOnly(a, doRun); }
            else { if (a.StartsWith("--")) { Cli.Fail("unknown option '" + a + "'"); }
            else { manifestArg = Optional.Some(a); } } } } } } } } }
            i = i + 1;
        }

        let bool looseTranspile = pureTranspile && IsSome(envOverride) && IsSome(entryOverride);
        let ResolvedInputs inputs = Cli.ResolveInputs(manifestArg, envOverride, entryOverride,
            stdlibOverride, looseTranspile,
            "--pure-transpile --env <file> --entry <file>", "--pure-transpile --env --entry");

        match (inputs.manifest) {
            case Some(mf) {
                Console.PrintLine(C.EMBER() + "Building" + C.NC() + " " + mf.projectName + " " +
                    C.DIM() + "(" + ManifestReader.TargetName(mf.target) + ", " +
                    ManifestReader.ModeNameLower(mf.mode) + ")" + C.NC());
            }
            case None {
                Console.PrintLine(C.EMBER() + "Building" + C.NC() + " " + C.DIM() + "(--pure-transpile)" + C.NC());
            }
        }
        Console.PrintLine("");

        let FrontEndRun fe = AppaCli.RunFrontEnd(inputs, warnAsError);

        let Emitter em = new Emitter(fe.mod, fe.diag, fe.t, fe.mangler);
        let List[OutputFile] output = Layout.Compose(em.Build(), fe.mod.symbols);

        if (fe.diag.HasErrors()) {
            let int d = 0;
            while (d < fe.diag.Count()) {
                let Diagnostic dg = fe.diag.All().Get(d);
                if (Diags.Severity(dg) == Severity.Error) { Console.PrintLineErr(fe.diag.Render(dg)); }
                d = d + 1;
            }
            Sys.Exit(1);
        }

        // An image build needs the cross toolchain; this compiler stops at the C either way, and
        // says so rather than silently producing a different artifact from the one asked for.
        let bool wantsIso = false;
        match (inputs.manifest) {
            case Some(mf) { wantsIso = !pureTranspile && mf.target == Target.GatOS; }
            case None { }
        }
        if (wantsIso) {
            Log.ErrorHint("this build targets GatOS, which needs the cross toolchain to produce an ISO",
                "the self-hosted compiler transpiles and stops - it has no bind for spawning " +
                "x86_64-elf-gcc, grub-mkrescue or xorriso. Add '--pure-transpile' to emit the C " +
                "here, set <TargetBackend>Hosted</TargetBackend>, or run the image build with the " +
                "C# appa.");
            Sys.Exit(1);
        }
        if (doRun) {
            Log.Warn("'appa run' only launches a GatOS image; there is nothing to boot here (this build just writes C)");
        }

        let String outDir = Paths.Join(inputs.projectRoot, Cli.TranspileDir());
        Cli.WriteOutputs(output, outDir);
        if (emitSourcemap) { Cli.WriteSourcemap(fe.sourcemap, outDir); }
        Console.PrintLine("");
        Console.PrintLine(C.EMBER() + "✓" + C.NC() + " " + C.BOLD() + "Finished" + C.NC() + " " +
                          C.DIM() + "→" + C.NC() + " " + outDir + Paths.Sep());
        let int f = 0;
        while (f < output.Length()) {
            Out.Child(C.DIM() + Paths.Join(Cli.TranspileDir(), output.Get(f).name) + C.NC());
            f = f + 1;
        }
    }

    /*
     * RunOnly - An option that only means something for `appa run`
     */
    void func RunOnly(String opt, bool doRun) {
        if (!doRun) {
            Cli.FailHint("'" + opt + "' only applies to 'appa run'",
                         "use 'appa run' to build the ISO and launch it");
        }
        Log.Warn("'" + opt + "' is accepted but has no effect: this compiler cannot launch QEMU");
    }

    // --- appa check ---------------------------------------------------------------------------

    /*
     * RunCheck - The front end only, reporting diagnostics without ever reaching emission
     */
    void func RunCheck(List[String] args) {
        let Optional[String] manifestArg = Optional[String].None();
        let Optional[String] envOverride = Optional[String].None();
        let Optional[String] entryOverride = Optional[String].None();
        let Optional[String] stdlibOverride = Optional[String].None();
        let bool warnAsError = false;

        let int i = 0;
        while (i < args.Length()) {
            let String a = args.Get(i);
            if (a == "--env" && i + 1 < args.Length())          { i = i + 1; envOverride = Optional.Some(args.Get(i)); }
            else { if (a == "--entry" && i + 1 < args.Length())  { i = i + 1; entryOverride = Optional.Some(args.Get(i)); }
            else { if (a == "--stdlib" && i + 1 < args.Length()) { i = i + 1; stdlibOverride = Optional.Some(args.Get(i)); }
            else { if (a == "--werror") { warnAsError = true; }
            else { if (a.StartsWith("--")) { Cli.Fail("unknown option '" + a + "'"); }
            else { manifestArg = Optional.Some(a); } } } } }
            i = i + 1;
        }

        let bool loose = IsSome(envOverride) && IsSome(entryOverride);
        let ResolvedInputs inputs = Cli.ResolveInputs(manifestArg, envOverride, entryOverride,
            stdlibOverride, loose, "--env <file> --entry <file>", "--env --entry");

        match (inputs.manifest) {
            case Some(mf) {
                Console.PrintLine(C.EMBER() + "Checking" + C.NC() + " " + mf.projectName + " " +
                    C.DIM() + "(" + ManifestReader.TargetName(mf.target) + ", " +
                    ManifestReader.ModeNameLower(mf.mode) + ")" + C.NC());
            }
            case None {
                Console.PrintLine(C.EMBER() + "Checking" + C.NC() + " " + C.DIM() + "(--env/--entry)" + C.NC());
            }
        }
        Console.PrintLine("");

        AppaCli.RunFrontEnd(inputs, warnAsError);
    }

    /*
     * RunFrontEnd - Every front-end stage `appa build` and `appa check` share: parse, lower,
     * validate the environment, the floor, the intrinsics and the structure, then report
     */
    FrontEndRun func RunFrontEnd(ResolvedInputs inputs, bool warnAsError) {
        let List[String] inputFiles = new List[String]();
        inputFiles.Add(Paths.FullPath(inputs.envPath));
        inputFiles.Add(Paths.FullPath(inputs.entryPath));

        let TranspileResult tr = Pipeline.Transpile(inputFiles, inputs.projectRoot, inputs.stdlibDir);
        let DiagnosticBag diag = tr.diag;
        let bool loaded = !diag.HasErrors();
        let int afterLoad = diag.Count();

        let StringMap[StringSet] visible = Pipeline.VisibleModules(tr.imports);
        let Mode mode = Mode.Debug;
        match (inputs.manifest) { case Some(mf) { mode = mf.mode; } case None { } }

        let BuiltModule built = Pipeline.BuildModule(tr.programs, visible, mode, diag);

        if (!loaded) {
            diag.TruncateTo(afterLoad);
            AppaCli.ReportGataFiles(tr.attempted, diag, warnAsError, inputs.stdlibDir);
            return new FrontEndRun(built.mod, built.sourcemap, built.caps, diag, built.t, built.mangler);
        }

        let Target target = built.mod.HasKernelRealm() ? Target.GatOS : Target.Hosted;
        match (inputs.manifest) { case Some(mf) { target = mf.target; } case None { } }

        Pipeline.ValidateEnvironment(tr.programs, diag);
        Pipeline.ValidateFloor(built.mod, diag);
        Pipeline.ValidateIntrinsics(built.mod, diag);
        Pipeline.ValidateStructure(tr.programs, target, diag);

        match (inputs.manifest) {
            case Some(mf) {
                if (mf.target == Target.Hosted && built.mod.HasKernelRealm()) {
                    diag.Error(Codes.KernelBlockInHosted(), "<environment>", TS.NoneSpan(),
                        "the active environment declares a kernel preamble, which is not allowed for a Hosted build");
                }
            }
            case None { }
        }

        AppaCli.ReportGataFiles(tr.attempted, diag, warnAsError, inputs.stdlibDir);
        return new FrontEndRun(built.mod, built.sourcemap, built.caps, diag, built.t, built.mangler);
    }

    /*
     * ReportGataFiles - The per-file pass/fail report, exiting on the first failing file and
     * preferring one the author wrote: dependency order puts the library first, and an error there
     * is nearly always a symptom of something in the program.
     */
    void func ReportGataFiles(List[String] attempted, DiagnosticBag diag, bool warnAsError,
                              String libgataDir) {
        let StringSet known = new StringSet();
        let int k = 0;
        while (k < attempted.Length()) { known.AddNew(attempted.Get(k)); k = k + 1; }
        let bool tty = Spin.IsTty();
        let int64 t0 = Spin.Now();

        // Pick the file to report from before walking, preferring the author's own.
        let Optional[String] reportFrom = Optional[String].None();
        let int i = 0;
        while (i < attempted.Length()) {
            let String path = attempted.Get(i);
            if (AppaCli.Failing(diag, path, warnAsError, libgataDir)) {
                if (!IsSome(reportFrom)) { reportFrom = Optional.Some(path); }
                if (!Pipeline.IsLibrary(path, libgataDir)) {
                    reportFrom = Optional.Some(path);
                    i = attempted.Length();
                }
            }
            i = i + 1;
        }
        match (reportFrom) {
            case Some(path) {
                let List[Diagnostic] shown = new List[Diagnostic];
                let int d = 0;
                while (d < diag.Count()) {
                    let Diagnostic dg = diag.All().Get(d);
                    if (AppaCli.SameFile(Locs.File(Diags.Loc(dg)), path)) {
                        let Severity sv = Diags.Severity(dg);
                        if (sv == Severity.Error || (warnAsError && sv == Severity.Warning)) { shown.Add(dg); }
                    }
                    d = d + 1;
                }
                AppaCli.FailWith(shown, diag, warnAsError, tty);
            }
            case None { }
        }

        let int n = 0;
        while (n < attempted.Length()) {
            let String path = attempted.Get(n);
            n = n + 1;
            let List[Diagnostic] warnings = new List[Diagnostic];
            if (!Pipeline.IsLibrary(path, libgataDir)) {
                let int d = 0;
                while (d < diag.Count()) {
                    let Diagnostic dg = diag.All().Get(d);
                    if (AppaCli.SameFile(Locs.File(Diags.Loc(dg)), path)
                        && Diags.Severity(dg) == Severity.Warning) { warnings.Add(dg); }
                    d = d + 1;
                }
            }
            if (tty) {
                Out.Redraw("  " + C.DIM() + "⠿ Checking [" + Int.ToString(n) + "/" +
                           Int.ToString(attempted.Length()) + "] " + Paths.FileName(path) + C.NC());
            }
            if (warnings.Length() > 0) {
                if (tty) { Out.ClearRedraw(); }
                let int w = 0;
                while (w < warnings.Length()) { Console.PrintLine(diag.Render(warnings.Get(w))); w = w + 1; }
            }
        }

        // Diagnostics that belong to no file in the build - the whole-build ones.
        let List[Diagnostic] orphanErrors = new List[Diagnostic];
        let List[Diagnostic] orphanWarnings = new List[Diagnostic];
        let int o = 0;
        while (o < diag.Count()) {
            let Diagnostic dg = diag.All().Get(o);
            if (!known.Has(Locs.File(Diags.Loc(dg)))) {
                if (Diags.Severity(dg) == Severity.Error) { orphanErrors.Add(dg); }
                if (Diags.Severity(dg) == Severity.Warning) { orphanWarnings.Add(dg); }
            }
            o = o + 1;
        }

        if (orphanErrors.Length() > 0 || (warnAsError && orphanWarnings.Length() > 0)) {
            let List[Diagnostic] both = new List[Diagnostic];
            let int a = 0;
            while (a < orphanErrors.Length()) { both.Add(orphanErrors.Get(a)); a = a + 1; }
            let int b = 0;
            while (b < orphanWarnings.Length()) { both.Add(orphanWarnings.Get(b)); b = b + 1; }
            AppaCli.FailWith(both, diag, warnAsError, tty);
        }

        // FailWith exits, so this runs only when the build is allowed to continue.
        if (orphanWarnings.Length() > 0) {
            if (tty) { Out.ClearRedraw(); }
            let int w = 0;
            while (w < orphanWarnings.Length()) {
                Console.PrintLine(diag.Render(orphanWarnings.Get(w)));
                w = w + 1;
            }
        }

        if (tty) { Out.ClearRedraw(); }
        Spin.Done("Checked " + Int.ToString(attempted.Length()) + " file" +
                  (attempted.Length() == 1 ? "" : "s"), Spin.Now() - t0);
    }

    /*
     * SameFile - Path comparison, case-insensitive to match C#'s OrdinalIgnoreCase
     */
    bool func SameFile(String a, String b) { return a.ToLower() == b.ToLower(); }

    /*
     * Failing - Whether a file has anything that stops the build
     */
    bool func Failing(DiagnosticBag diag, String path, bool warnAsError, String libgataDir) {
        let bool err = false;
        let bool warn = false;
        let int d = 0;
        while (d < diag.Count()) {
            let Diagnostic dg = diag.All().Get(d);
            if (AppaCli.SameFile(Locs.File(Diags.Loc(dg)), path)) {
                if (Diags.Severity(dg) == Severity.Error) { err = true; }
                if (Diags.Severity(dg) == Severity.Warning) { warn = true; }
            }
            d = d + 1;
        }
        return err || (warnAsError && warn && !Pipeline.IsLibrary(path, libgataDir));
    }

    /*
     * FailWith - Renders a failing file's diagnostics in line order, prints the count summary, and
     * exits 1
     */
    void func FailWith(List[Diagnostic] ds, DiagnosticBag diag, bool warnAsError, bool tty) {
        if (tty) { Out.ClearRedraw(); }
        let List[Diagnostic] list = AppaCli.SortByLine(ds, diag);
        let int i = 0;
        while (i < list.Length()) { Console.PrintLineErr(diag.Render(list.Get(i))); i = i + 1; }
        Console.PrintLineErr("");

        let int errs = 0;
        let int warns = 0;
        let int j = 0;
        while (j < list.Length()) {
            if (Diags.Severity(list.Get(j)) == Severity.Error) { errs = errs + 1; }
            if (Diags.Severity(list.Get(j)) == Severity.Warning) { warns = warns + 1; }
            j = j + 1;
        }
        let String tail = (errs == 0 && warns > 0 && warnAsError) ? " (--werror: treated as errors)" : "";
        Console.PrintLineErr(Pipeline.CountSummary(errs, warns) + tail);
        Sys.Exit(1);
    }

    /*
     * SortByLine - A stable insertion sort on the rendered line number, matching C#'s OrderBy
     */
    List[Diagnostic] func SortByLine(List[Diagnostic] ds, DiagnosticBag diag) {
        let List[Diagnostic] out = new List[Diagnostic];
        let int i = 0;
        while (i < ds.Length()) {
            let Diagnostic d = ds.Get(i);
            let int line = diag.LineOf(d);
            let int at = out.Length();
            let int k = 0;
            while (k < out.Length()) {
                if (diag.LineOf(out.Get(k)) > line) { at = k; k = out.Length(); }
                k = k + 1;
            }
            out.Insert(at, d);
            i = i + 1;
        }
        return out;
    }

    // --- Help ---------------------------------------------------------------------------------

    /*
     * PrintHelp - The top-level usage: commands, options, examples. The text is data, laid out by
     * Fmt against the real terminal width - no line here is wrapped or padded by hand.
     */
    public void func PrintHelp() {
        Banner.Print("");
        Fmt.Para(C.DIM() + "The Gata language compiler for GatOS. Invoked as " + C.NC() + "appa" +
                 C.DIM() + "." + C.NC(), Fmt.Indent());

        Fmt.Section("Commands");
        let List[String] cl = new List[String]();
        let List[String] cr = new List[String]();
        cl.Add("appa install");         cr.Add("Install the GatOS toolchain, template, and libgata");
        cl.Add("appa update");          cr.Add("Re-download the GatOS bundle and self-update Appa");
        cl.Add("appa new <name>");      cr.Add("Create a GatOS project");
        cl.Add("appa check [project]"); cr.Add("Lex, parse, and type-check only - reports errors, emits nothing");
        cl.Add("appa build [project]"); cr.Add("Build the project described by its .gconf into an ISO");
        cl.Add("appa run [project]");   cr.Add("Build the ISO, then launch it in QEMU");
        cl.Add("appa clean [project]"); cr.Add("Remove " + String.Join(Cli.GeneratedDirs(), "/, ") + "/");
        cl.Add("appa --version / -v");  cr.Add("Print the Appa version");
        Fmt.Table(cl, cr, Fmt.Indent());
        Console.PrintLine("");
        Fmt.Para(C.DIM() + "A project argument is a directory or a path to its .gconf; the default is the current directory." + C.NC(), Fmt.Indent());

        Fmt.Section("Install options");
        let List[String] il = new List[String]();
        let List[String] ir = new List[String]();
        il.Add("--with-path"); ir.Add("Add Appa to PATH without asking - re-runs elevated if it has to");
        il.Add("--no-path");   ir.Add("Install without touching PATH, and without asking");
        il.Add("--force");     ir.Add("Overwrite an existing install without confirming");
        Fmt.Table(il, ir, Fmt.Indent());

        Fmt.SectionNote("Run options", "(on top of every build option below)");
        let List[String] rl = new List[String]();
        let List[String] rr = new List[String]();
        rl.Add("headless");     rr.Add("No QEMU window - serial only");
        rl.Add("timeout=<Xs>"); rr.Add("Kill the guest after a duration (30s, 5m, 1h)");
        Fmt.Table(rl, rr, Fmt.Indent());

        Fmt.SectionNote("Build options", "(also accepted by run and check)");
        let List[String] bl = new List[String]();
        let List[String] br = new List[String]();
        bl.Add("--stdlib <dir>");   br.Add("Override the libgata directory");
        bl.Add("--werror");         br.Add("Treat warnings as errors");
        bl.Add("--env <env.g>");    br.Add("Environment file, overriding discovery");
        bl.Add("--entry <file.g>"); br.Add("Entry source, overriding discovery");
        bl.Add("--emit-sourcemap"); br.Add("Write sourcemap.json (dense name -> readable name)");
        bl.Add("--pure-transpile"); br.Add("Emit C and stop, with no .gconf at all - needs --env and --entry (build only; check never emits, so it takes --env/--entry on their own)");
        Fmt.Table(bl, br, Fmt.Indent());
        Console.PrintLine("");
        Fmt.Para(C.DIM() + "A project build discovers its own environment (the @environment file in the project directory) and entry (src/main.g), so --env and --entry are only for loose files." + C.NC(), Fmt.Indent());

        Fmt.Section("Examples");
        let List[String] el = new List[String]();
        let List[String] er = new List[String]();
        el.Add("appa install");                                                er.Add("");
        el.Add("appa new myos && cd myos && appa run");                         er.Add("");
        el.Add("appa run headless timeout=30s");                                er.Add("");
        el.Add("appa build --pure-transpile --env env.g --entry src/main.g");   er.Add("");
        el.Add("appa check myos --werror");                                     er.Add("");
        el.Add("appa clean");                                                   er.Add("");
        Fmt.Table(el, er, Fmt.Indent());
        Console.PrintLine("");

        // The one place this compiler tells you it is not the C# one. Kept at the end so it reads
        // as a footnote rather than as the headline; the commands above are all accepted, and the
        // three that cannot be carried out say so when you run them.
        Fmt.Section("Note");
        Fmt.Para(C.DIM() + "This is the self-hosted Appa, written in Gata. It transpiles: 'build' on a Hosted project, 'build --pure-transpile', 'check' and 'clean' all work. 'install', 'update', 'new', 'run', and an ISO build need process spawning and network access that the environment floor does not bind - each says so if you run it." + C.NC(), Fmt.Indent());
        Console.PrintLine("");
    }
}
