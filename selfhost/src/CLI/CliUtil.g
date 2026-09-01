/*
 * CliUtil.g - input resolution, output writing, and the fatal-error exit
 *
 * Ports Appa/src/CLI/CliUtil.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Map.g";
import "selfhostlib/Optional.g";
import "selfhostlib/File.g";
import "selfhostlib/Dir.g";
import "selfhostlib/Sys.g";
import "src/Backend/Layout.g";
import "src/CLI/AppaConsts.g";
import "src/CLI/Fmt.g";
import "src/CLI/Manifest.g";
import "selfhostlib/Paths.g";
import "src/CLI/Pipeline.g";

/*
 * What ResolveInputs worked out. C# returns a five-tuple; this is the same thing with names.
 */
class ResolvedInputs {
    public Optional[Manifest] manifest;
    public String envPath;
    public String entryPath;
    public String projectRoot;
    public String stdlibDir;
    func _init(Optional[Manifest] manifest, String envPath, String entryPath, String projectRoot,
               String stdlibDir) {
        self.manifest = manifest;
        self.envPath = envPath;
        self.entryPath = entryPath;
        self.projectRoot = projectRoot;
        self.stdlibDir = stdlibDir;
    }
}

module Cli {

    /*
     * TranspileDir - Where a non-image build writes its C, relative to the project root
     */
    public String func TranspileDir() { return "transpilation"; }

    /*
     * GeneratedDirs - The project-root directories a build owns end to end, and so the ones
     * `appa clean` removes.
     */
    public List[String] func GeneratedDirs() {
        let List[String] r = new List[String]();
        r.Add(Cli.TranspileDir());
        return r;
    }

    /*
     * Fail - A fatal configuration error, then exit 1. Every caller treats this as not returning.
     */
    public void func Fail(String message) {
        Log.Error(message);
        Sys.Exit(1);
    }

    public void func FailHint(String message, String hint) {
        Log.ErrorHint(message, hint);
        Sys.Exit(1);
    }

    /*
     * ResolveInputs - Works out the environment file, entry file, project root and libgata
     * directory for a build or check
     */
    public ResolvedInputs func ResolveInputs(Optional[String] manifestArg, Optional[String] envOverride,
                                             Optional[String] entryOverride, Optional[String] stdlibOverride,
                                             bool loose, String manifestHint, String looseHint) {
        let Optional[Manifest] manifest = Optional[Manifest].None();

        if (!loose) {
            let Optional[String] manifestPath = Optional[String].None();
            match (manifestArg) {
                case None {
                    match (ManifestReader.Discover(Dir.Cwd())) {
                        case Ok(p) { manifestPath = p; }
                        case Err(msg) { Cli.Fail(msg); }
                    }
                }
                case Some(arg) {
                    if (!Dir.IsDir(arg) && !File.Exists(arg)) {
                        Cli.FailHint("'" + arg + "' does not exist",
                                     "the argument is a project directory, or the path to its .gconf");
                    }
                    if (Dir.IsDir(arg)) {
                        match (ManifestReader.Discover(arg)) {
                            case Ok(p) { manifestPath = p; }
                            case Err(msg) { Cli.Fail(msg); }
                        }
                    } else {
                        manifestPath = Optional.Some(arg);
                    }
                }
            }
            match (manifestPath) {
                case Some(p) {
                    match (ManifestReader.Load(p)) {
                        case Ok(mf) { manifest = Optional.Some(mf); }
                        case Err(msg) { Cli.Fail(msg); }
                    }
                }
                case None { }
            }
            if (!IsSome(manifest)) { Cli.FailNoManifest(envOverride, entryOverride, manifestHint); }
        } else {
            match (manifestArg) {
                case Some(arg) {
                    Log.Warn("project argument '" + arg + "' is ignored with " + looseHint +
                             " (loose-file mode discovers nothing from a project)");
                }
                case None { }
            }
        }

        let List[String] unreadableEnvs = new List[String]();
        let Optional[String] envPath = envOverride;
        if (!IsSome(envPath)) {
            match (manifest) {
                case Some(mf) { envPath = Pipeline.DiscoverEnv(mf.dir, unreadableEnvs); }
                case None { }
            }
        }
        let Optional[String] entryPath = entryOverride;
        if (!IsSome(entryPath)) {
            match (manifest) {
                case Some(mf) { entryPath = Pipeline.DiscoverEntry(mf.dir); }
                case None { }
            }
        }

        if (!IsSome(envPath)) {
            if (unreadableEnvs.Length() > 0) {
                Cli.FailHint("no environment found - mark one project file @environment, or pass --env",
                    "could not parse " + String.Join(unreadableEnvs, ", ") +
                    "; if the environment is declared there, fix the syntax error first");
            }
            Cli.Fail("no environment found - mark one project file @environment, or pass --env");
        }
        if (!IsSome(entryPath)) { Cli.Fail("no entry point - expected src/main.g, or pass --entry"); }

        let String env = OrEmptyStr(envPath);
        let String entryFile = OrEmptyStr(entryPath);

        let String projectRoot = Paths.DirName(Paths.FullPath(entryFile));
        match (manifest) { case Some(mf) { projectRoot = mf.dir; } case None { } }

        let Optional[String] stdlibDir = stdlibOverride;
        if (!IsSome(stdlibDir)) { stdlibDir = Pipeline.FindLibgata(); }
        if (!IsSome(stdlibDir)) {
            Cli.Fail("cannot find libgata - pass --stdlib <dir>");
        }

        if (!File.Exists(env))       { Cli.Fail("file not found: " + env); }
        if (!File.Exists(entryFile)) { Cli.Fail("file not found: " + entryFile); }

        return new ResolvedInputs(manifest, env, entryFile, projectRoot, OrEmptyStr(stdlibDir));
    }

    /*
     * FailNoManifest - Reports that no project was found, naming what is actually missing
     */
    public void func FailNoManifest(Optional[String] envOverride, Optional[String] entryOverride,
                                    String manifestHint) {
        let bool hasEnv = IsSome(envOverride);
        let bool hasEntry = IsSome(entryOverride);
        if (hasEnv != hasEntry) {
            let String had = hasEnv ? "--env" : "--entry";
            let String missing = hasEnv ? "--entry" : "--env";
            Cli.FailHint(had + " was given without " + missing,
                "building without a .gconf needs both, so the environment and the entry point are " +
                "each chosen explicitly - add " + missing + " <file>, or drop " + had +
                " and build a project");
        }
        if (hasEnv) {
            Cli.FailHint("--env and --entry need '--pure-transpile' to build without a .gconf",
                "use '" + manifestHint + "' to emit C from loose files, or run this in a project directory");
        }
        Cli.Fail("no <project>.gconf found - add one to the project directory, or use " + manifestHint);
    }

    /*
     * WriteOutputs - Every output file into a directory, creating it if it is not there
     */
    public void func WriteOutputs(List[OutputFile] files, String dir) {
        Paths.MakeDirs(dir);
        let int i = 0;
        while (i < files.Length()) {
            let OutputFile f = files.Get(i);
            if (!File.Write(Paths.Join(dir, f.name), f.content)) {
                Cli.Fail("could not write " + Paths.Join(dir, f.name));
            }
            i = i + 1;
        }
    }

    /*
     * WriteSourcemap - The dense-to-readable name map as sourcemap.json, keys in ordinal order so
     * the file is stable across runs
     */
    public void func WriteSourcemap(StringMap[String] map, String dir) {
        if (map.Length() == 0) { return; }
        Paths.MakeDirs(dir);
        let List[String] keys = Paths.SortStrings(map.Keys());
        let StringBuilder sb = new StringBuilder();
        sb.Append("{\n");
        let int i = 0;
        while (i < keys.Length()) {
            sb.Append("  \"");
            sb.Append(keys.Get(i));
            sb.Append("\": \"");
            sb.Append(map.Get(keys.Get(i)));
            sb.Append("\"");
            if (i < keys.Length() - 1) { sb.Append(","); }
            sb.Append("\n");
            i = i + 1;
        }
        sb.Append("}\n");
        File.Write(Paths.Join(dir, "sourcemap.json"), sb.ToString());
    }
}

/*
 * OrEmptyStr - An optional string, or "". IsSome already lives in Optional.g, so only this one is
 * new here.
 */
String func OrEmptyStr(Optional[String] o) {
    match (o) { case Some(x) { return x; } case None { return ""; } }
}
