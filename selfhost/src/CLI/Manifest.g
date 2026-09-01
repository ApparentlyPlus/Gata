/*
 * Manifest.g - the <project>.gconf reader
 *
 * Ports Appa/src/CLI/Manifest.cs, including the piece C# gets from the base library: XDocument.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Optional.g";
import "selfhostlib/File.g";
import "selfhostlib/Result.g";
import "selfhostlib/Dir.g";
import "selfhostlib/Paths.g";

enum Target { GatOS, Hosted }
enum Mode { Debug, Release }
enum OutputKind { Framebuffer, Serial }
enum Keyboard { Default, External, Hotplug }
enum CapabilityDiscovery { On, Off }

/*
 * A project's build configuration: what to build, how, and the explicitly chosen knobs.
 */
class Manifest {
    public String dir;
    public String projectName;
    public Target target;
    public Mode mode;
    public OutputKind output;
    public Keyboard keyboard;
    public CapabilityDiscovery capabilityDiscovery;

    func _init(String dir, String projectName, Target target, Mode mode, OutputKind output,
               Keyboard keyboard, CapabilityDiscovery capabilityDiscovery) {
        self.dir = dir;
        self.projectName = projectName;
        self.target = target;
        self.mode = mode;
        self.output = output;
        self.keyboard = keyboard;
        self.capabilityDiscovery = capabilityDiscovery;
    }
}

module ManifestReader {

    /*
     * Discover - The single *.gconf in a directory. None returns nothing; more than one is an
     * error, because which one was meant is not appa's guess to make.
     */
    public Result[Optional[String], String] func Discover(String dir) {
        let List[String] entries = Dir.List(dir);
        let List[String] found = new List[String]();
        let int i = 0;
        while (i < entries.Length()) {
            if (entries.Get(i).EndsWith(".gconf")) { found.Add(Paths.Join(dir, entries.Get(i))); }
            i = i + 1;
        }
        found = Paths.SortStrings(found);
        if (found.Length() == 0) { return Result.Ok(Optional[String].None()); }
        if (found.Length() > 1) {
            return Result[Optional[String], String].Err("multiple .gconf files in " + dir + "; expected exactly one");
        }
        return Result.Ok(Optional.Some(found.Get(0)));
    }

    /*
     * Load - Parses a .gconf and returns its Manifest
     */
    public Result[Manifest, String] func Load(String path) {
        let String text = "";
        match (File.Read(path)) {
            case Ok(t) { text = t; }
            case Err(msg) { return Result[Manifest, String].Err("cannot read " + Paths.FileName(path) + ": " + msg); }
        }

        let String root = ManifestReader.RootName(text);
        if (root.Length() == 0) { return Result[Manifest, String].Err(Paths.FileName(path) + " is empty"); }
        if (root != "appa") {
            return Result[Manifest, String].Err(Paths.FileName(path) + " must have an <appa> root, got <" + root + ">");
        }

        let String dir = Paths.DirName(Paths.FullPath(path));

        let Result[Target, String] tr = ManifestReader.ParseTarget(text);
        let Target target = Target.GatOS;
        match (tr) { case Ok(v) { target = v; } case Err(m) { return Result[Manifest, String].Err(m); } }

        let Result[Mode, String] mr = ManifestReader.ParseMode(text);
        let Mode mode = Mode.Debug;
        match (mr) { case Ok(v) { mode = v; } case Err(m) { return Result[Manifest, String].Err(m); } }

        let Result[OutputKind, String] our = ManifestReader.ParseOutput(text);
        let OutputKind output = OutputKind.Framebuffer;
        match (our) { case Ok(v) { output = v; } case Err(m) { return Result[Manifest, String].Err(m); } }

        let Result[Keyboard, String] kr = ManifestReader.ParseKeyboard(text);
        let Keyboard keyboard = Keyboard.Default;
        match (kr) { case Ok(v) { keyboard = v; } case Err(m) { return Result[Manifest, String].Err(m); } }

        let Result[CapabilityDiscovery, String] cr = ManifestReader.ParseCapDisc(text);
        let CapabilityDiscovery capDisc = CapabilityDiscovery.On;
        match (cr) { case Ok(v) { capDisc = v; } case Err(m) { return Result[Manifest, String].Err(m); } }

        let String name = ManifestReader.Element(text, "ProjectName");
        if (name.Length() == 0) { name = Paths.BaseName(dir); }

        return Result.Ok(new Manifest(dir, name, target, mode, output, keyboard, capDisc));
    }

    /*
     * RootName - The name of the first element, skipping comments, declarations and whitespace
     */
    public String func RootName(String text) {
        let int i = 0;
        while (i < text.Length()) {
            if (text.CharAt(i) == '<') {
                if (text.IndexOf("<!--", i) == i) {
                    let int close = text.IndexOf("-->", i);
                    if (close < 0) { return ""; }
                    i = close + 3;
                    continue;
                }
                if (i + 1 < text.Length() && (text.CharAt(i + 1) == '?' || text.CharAt(i + 1) == '!')) {
                    let int close = text.IndexOf(">", i);
                    if (close < 0) { return ""; }
                    i = close + 1;
                    continue;
                }
                let int end = i + 1;
                while (end < text.Length() && text.CharAt(end) != '>' && text.CharAt(end) != ' '
                       && text.CharAt(end) != '\n' && text.CharAt(end) != '\r' && text.CharAt(end) != '\t') {
                    end = end + 1;
                }
                return text.Substring(i + 1, end - i - 1);
            }
            i = i + 1;
        }
        return "";
    }

    /*
     * Element - The trimmed text of <tag>...</tag>, or the empty string when the element is absent.
     * Flat by construction: the format has no nesting, so the first close tag is the right one.
     */
    public String func Element(String text, String tag) {
        let String open = "<" + tag + ">";
        let String close = "</" + tag + ">";
        let int a = text.IndexOf(open);
        if (a < 0) { return ""; }
        let int b = text.IndexOf(close, a + open.Length());
        if (b < 0) { return ""; }
        return text.Substring(a + open.Length(), b - a - open.Length()).Trim();
    }

    /*
     * EnumError - The message C# builds from Enum.GetNames, spelled out per enum because Gata has
     * no reflection over enum members
     */
    String func EnumError(String v, String elementName, String names) {
        return "'" + v + "' is not a valid <" + elementName + ">; expected one of: " + names;
    }

    /*
     * The five ParseX functions below are C#'s one generic ParseEnum<T>, once per enum.
     */
    bool func LeadingDigit(String v) { return v.Length() > 0 && v.CharAt(0) >= '0' && v.CharAt(0) <= '9'; }

    Result[Target, String] func ParseTarget(String text) {
        let String v = ManifestReader.Element(text, "TargetBackend");
        if (v.Length() == 0) { return Result.Ok(Target.GatOS); }
        if (!ManifestReader.LeadingDigit(v)) {
            let String lo = v.ToLower();
            if (lo == "gatos")  { return Result.Ok(Target.GatOS); }
            if (lo == "hosted") { return Result.Ok(Target.Hosted); }
        }
        return Result[Target, String].Err(ManifestReader.EnumError(v, "TargetBackend", "GatOS, Hosted"));
    }

    Result[Mode, String] func ParseMode(String text) {
        let String v = ManifestReader.Element(text, "BuildMode");
        if (v.Length() == 0) { return Result.Ok(Mode.Debug); }
        if (!ManifestReader.LeadingDigit(v)) {
            let String lo = v.ToLower();
            if (lo == "debug")   { return Result.Ok(Mode.Debug); }
            if (lo == "release") { return Result.Ok(Mode.Release); }
        }
        return Result[Mode, String].Err(ManifestReader.EnumError(v, "BuildMode", "Debug, Release"));
    }

    Result[OutputKind, String] func ParseOutput(String text) {
        let String v = ManifestReader.Element(text, "OutputType");
        if (v.Length() == 0) { return Result.Ok(OutputKind.Framebuffer); }
        if (!ManifestReader.LeadingDigit(v)) {
            let String lo = v.ToLower();
            if (lo == "framebuffer") { return Result.Ok(OutputKind.Framebuffer); }
            if (lo == "serial")      { return Result.Ok(OutputKind.Serial); }
        }
        return Result[OutputKind, String].Err(ManifestReader.EnumError(v, "OutputType", "Framebuffer, Serial"));
    }

    Result[Keyboard, String] func ParseKeyboard(String text) {
        let String v = ManifestReader.Element(text, "KeyboardSupport");
        if (v.Length() == 0) { return Result.Ok(Keyboard.Default); }
        if (!ManifestReader.LeadingDigit(v)) {
            let String lo = v.ToLower();
            if (lo == "default")  { return Result.Ok(Keyboard.Default); }
            if (lo == "external") { return Result.Ok(Keyboard.External); }
            if (lo == "hotplug")  { return Result.Ok(Keyboard.Hotplug); }
        }
        return Result[Keyboard, String].Err(ManifestReader.EnumError(v, "KeyboardSupport", "Default, External, Hotplug"));
    }

    Result[CapabilityDiscovery, String] func ParseCapDisc(String text) {
        let String v = ManifestReader.Element(text, "CapabilityDiscovery");
        if (v.Length() == 0) { return Result.Ok(CapabilityDiscovery.On); }
        if (!ManifestReader.LeadingDigit(v)) {
            let String lo = v.ToLower();
            if (lo == "on")  { return Result.Ok(CapabilityDiscovery.On); }
            if (lo == "off") { return Result.Ok(CapabilityDiscovery.Off); }
        }
        return Result[CapabilityDiscovery, String].Err(
            ManifestReader.EnumError(v, "CapabilityDiscovery", "On, Off"));
    }

    /*
     * TargetName / ModeName - The spellings the build banner prints, matching C#'s ToString()
     */
    public String func TargetName(Target t) { return t == Target.Hosted ? "Hosted" : "GatOS"; }
    public String func ModeNameLower(Mode m) { return m == Mode.Release ? "release" : "debug"; }
}
