/*
 * Diagnostic.g - diagnostic model: severity, location, the code registry, and "did you mean"
 * hints
 *
 * Ports Appa/src/Diagnostics/Diagnostic.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Optional.g";
import "selfhostlib/Set.g";
import "selfhostlib/Int.g";
import "selfhostlib/Console.g";
import "src/Diagnostics/TextSpan.g";
import "src/Diagnostics/SourceText.g";

/*
 * Severity of a diagnostic, either warning or error. Warnings do not prevent compilation, but
 * errors do.
 */
enum Severity { Warning, Error }

/*
 * Where a diagnostic points. A file and the TextSpan to underline.
 */
union Loc { At(String file, TextSpan span) }

module Locs {
    public String func File(Loc l) {
        match (l) { case At(file, span) { return file; } }
    }

    public TextSpan func Span(Loc l) {
        match (l) { case At(file, span) { return span; } }
    }
}

/*
 * A diagnostic is data. It consists of a stable code, a severity, a concise message, and a
 * location. The message states the problem outright. Hints are optional, separate lines of
 * suggested fixes, rendered after the source snippet a la rustc's "= help:" lines.
 */
union Diagnostic { D(Severity severity, String code, String message, Loc loc, List[String] hints) }

module Diags {
    public Severity func Severity(Diagnostic d) {
        match (d) { case D(severity, code, message, loc, hints) { return severity; } }
    }

    public String func Code(Diagnostic d) {
        match (d) { case D(severity, code, message, loc, hints) { return code; } }
    }

    public String func Message(Diagnostic d) {
        match (d) { case D(severity, code, message, loc, hints) { return message; } }
    }

    public Loc func Loc(Diagnostic d) {
        match (d) { case D(severity, code, message, loc, hints) { return loc; } }
    }

    public List[String] func Hints(Diagnostic d) {
        match (d) { case D(severity, code, message, loc, hints) { return hints; } }
    }

    /*
     * Make - A Diagnostic with no hints (C#'s secondary constructor, defaulting Hints to [])
     */
    public Diagnostic func Make(Severity s, String code, String message, Loc loc) {
        return Diagnostic.D(s, code, message, loc, new List[String]());
    }
}

/*
 * Builders for the small literal hint lists the lexer and parser hand to Fail. C#'s ["a", "b"]
 * collection expression has no inline Gata equivalent, and every diagnostic site wants one.
 */
module HintList {
    public List[String] func Of1(String a) {
        let List[String] r = new List[String]();
        r.Add(a);
        return r;
    }

    public List[String] func Of2(String a, String b) {
        let List[String] r = HintList.Of1(a);
        r.Add(b);
        return r;
    }

    public List[String] func Of3(String a, String b, String c) {
        let List[String] r = HintList.Of2(a, b);
        r.Add(c);
        return r;
    }

    public List[String] func Of4(String a, String b, String c, String d) {
        let List[String] r = HintList.Of3(a, b, c);
        r.Add(d);
        return r;
    }
}

/*
 * A lex/parse-time failure, carried out of band.
 */
union ParseError { At(TextSpan span, String code, String message, List[String] hints) }

module PErr {

    /*
     * Nothing - The zero ParseError, for a sink that has not been written to yet
     */
    public ParseError func Nothing() {
        return ParseError.At(TS.NoneSpan(), "", "", new List[String]());
    }

    /*
     * Make - A ParseError with no hints (C#'s `hints = null` default)
     */
    public ParseError func Make(TextSpan span, String code, String message) {
        return ParseError.At(span, code, message, new List[String]());
    }

    public TextSpan func Span(ParseError e) {
        match (e) { case At(span, code, message, hints) { return span; } }
    }

    public String func Code(ParseError e) {
        match (e) { case At(span, code, message, hints) { return code; } }
    }

    public String func Message(ParseError e) {
        match (e) { case At(span, code, message, hints) { return message; } }
    }

    public List[String] func Hints(ParseError e) {
        match (e) { case At(span, code, message, hints) { return hints; } }
    }

    /*
     * ToDiagnostic - The error as a reportable Diagnostic against the file it was read from.
     * Ports Pipeline.cs's `catch (ParseException)` to `diag.Error(...)` conversion.
     */
    public Diagnostic func ToDiagnostic(ParseError e, String file) {
        match (e) {
            case At(span, code, message, hints) {
                return Diagnostic.D(Severity.Error, code, message, Loc.At(file, span), hints);
            }
        }
    }
}

/*
 * This module contains all the diagnostic codes used in the compiler. Each code is a string that
 * starts with "G" followed by a three digit number.
 */
module Codes {
    public String func File() { return "G000"; }
    public String func TopologyOutsideRealm() { return "G001"; }
    public String func MissingEntryPoint() { return "G002"; }
    public String func DuplicateName() { return "G003"; }
    public String func TypeMismatch() { return "G004"; }
    public String func UndefinedVariable() { return "G005"; }
    public String func UndefinedMethod() { return "G006"; }
    public String func UndefinedType() { return "G007"; }
    public String func WrongArgCount() { return "G008"; }
    public String func ArgTypeMismatch() { return "G009"; }
    public String func ReturnTypeMismatch() { return "G010"; }
    public String func NewOnNonClass() { return "G011"; }
    public String func IndexOnNonCollection() { return "G012"; }
    public String func StaticOnInstance() { return "G013"; }
    public String func InstanceOnStatic() { return "G014"; }
    public String func AmbiguousOverload() { return "G015"; }
    public String func NoMatchingOverload() { return "G016"; }
    public String func UnknownIntrinsic() { return "G017"; }
    public String func DuplicateIntrinsic() { return "G018"; }
    public String func MissingIntrinsic() { return "G019"; }
    public String func MissingFloorBind() { return "G020"; }
    public String func ThrowsOutsideTry() { return "G021"; }
    public String func BreakOutsideLoop() { return "G022"; }
    public String func UnusedVariable() { return "G023"; }
    public String func UnreachableCode() { return "G024"; }
    public String func EmptyBlock() { return "G025"; }
    public String func RedundantReturn() { return "G026"; }
    public String func MissingReturn() { return "G027"; }
    public String func InvalidCast() { return "G028"; }
    public String func ConditionNotBool() { return "G029"; }
    public String func CallToEntry() { return "G030"; }
    public String func PanicOutsideKernel() { return "G031"; }
    public String func NotIterable() { return "G032"; }
    public String func UnsafeRequired() { return "G033"; }
    public String func NotAnLvalue() { return "G034"; }
    public String func PrivateMember() { return "G035"; }
    public String func DiagInRelease() { return "G036"; }
    public String func RefArgMismatch() { return "G037"; }
    public String func NoIndexSetter() { return "G038"; }
    public String func NonExhaustiveMatch() { return "G039"; }
    public String func StaticOnFreeFunc() { return "G040"; }
    public String func WrongAnnotationKind() { return "G041"; }
    public String func UnknownPreambleTarget() { return "G042"; }
    public String func ThreadModeNotAllowed() { return "G043"; }
    public String func Syntax() { return "G044"; }
    public String func AssignInExpr() { return "G045"; }
    public String func UnterminatedLiteral() { return "G046"; }
    public String func BadEscape() { return "G047"; }
    public String func BadAnnotation() { return "G048"; }
    public String func BadNumber() { return "G049"; }
    public String func MissingLet() { return "G050"; }
    public String func InvalidNesting() { return "G051"; }
    public String func TrailingComma() { return "G052"; }
    public String func BadDeclHeader() { return "G053"; }
    public String func CannotInfer() { return "G054"; }
    public String func KernelBlockInHosted() { return "G055"; }
    public String func MissingRealm() { return "G056"; }
    public String func ShadowedFunction() { return "G057"; }
    public String func MissingEntry() { return "G058"; }
    public String func DuplicateEntry() { return "G059"; }
    public String func MissingProcessMode() { return "G060"; }
    public String func BadEntrySignature() { return "G061"; }
    public String func DeferTransfer() { return "G062"; }
    public String func ModuleField() { return "G063"; }
    public String func MisplacedEnvironment() { return "G064"; }
    public String func ConflictingModifiers() { return "G065"; }
    public String func BadThrowsReturnType() { return "G066"; }
    public String func LifecycleThrows() { return "G067"; }
    public String func EntryOutsideKernel() { return "G068"; }
    public String func AmbiguousCall() { return "G069"; }
    public String func ShadowedVariable() { return "G070"; }
    public String func SelfAssignment() { return "G071"; }
    public String func NoEffect() { return "G072"; }
    public String func ConstantCondition() { return "G073"; }
    public String func RedundantCast() { return "G074"; }
    public String func DivisionByZero() { return "G075"; }
    public String func UnusedParameter() { return "G076"; }
    public String func UnreachableCase() { return "G077"; }
    public String func SelfComparison() { return "G078"; }
    public String func BadShiftCount() { return "G079"; }
    public String func MissingInterpolation() { return "G080"; }
    public String func AssignOutsideCatch() { return "G081"; }
    public String func CatchHandlerNoAssign() { return "G082"; }
    public String func IdentityPayloadComparison() { return "G083"; }
    public String func ImprecisePayloadComparison() { return "G084"; }
    public String func MissingRealmKeyword() { return "G085"; }
    public String func UnknownRealm() { return "G086"; }
    public String func ScopedNameNotVisible() { return "G087"; }
    public String func UnmarkedShadow() { return "G088"; }
    public String func ScopeNotEnclosing() { return "G089"; }
    public String func UnknownInScope() { return "G090"; }
    public String func ProcessWithoutThreads() { return "G091"; }
    public String func PartialOperatorSet() { return "G092"; }
    public String func UnsafeAllocatingTemporary() { return "G093"; }
    public String func ManagedFixedArray() { return "G094"; }
    public String func MixedSignedness() { return "G095"; }
    public String func CharArithmetic() { return "G096"; }
    public String func ExplicitTypeArgs() { return "G097"; }
    public String func UseBeforeAssignment() { return "G098"; }
    public String func DiscardedRetain() { return "G099"; }
    public String func UninitialisedProcessVar() { return "G100"; }
    public String func ReferenceCycle() { return "G101"; }
    public String func CReservedCName() { return "G102"; }
}

module Suggest {

    /*
     * Closest - The candidate closest to typed by Levenshtein distance, or None if nothing is
     * close enough to plausibly be a typo of it (distance more than half of typed's length)
     */
    public Optional[String] func Closest(String typed, List[String] candidates) {
        let String best = "";
        let bool haveBest = false;
        let int bestDist = 2147483647;
        let int maxAllowed = 1 > (typed.Length() / 2) ? 1 : (typed.Length() / 2);
        let int i = 0;
        while (i < candidates.Length()) {
            let String c = candidates.Get(i);
            let int lenDiff = c.Length() - typed.Length();
            if (lenDiff < 0) { lenDiff = -lenDiff; }
            if (lenDiff <= maxAllowed) {
                let int d = Suggest.Distance(typed, c);
                if (d < bestDist) { bestDist = d; best = c; haveBest = true; }
            }
            i = i + 1;
        }
        if (haveBest && bestDist <= maxAllowed) { return Optional.Some(best); }
        return Optional.None();
    }

    /*
     * Hints - A one-element "did you mean 'X'?" hints list, or empty if nothing is close enough.
     */
    public List[String] func Hints(String typed, List[String] candidates) {
        let List[String] result = new List[String]();
        match (Suggest.Closest(typed, candidates)) {
            case Some(best) { result.Add("did you mean '" + best + "'?"); }
            case None { }
        }
        return result;
    }

    /*
     * Distance - Classic iterative Levenshtein edit distance between two strings.
     */
    private int func Distance(String a, String b) {
        let int w = b.Length() + 1;
        let List[int] prev = new List[int]();
        let List[int] cur = new List[int]();
        let int j = 0;
        while (j < w) { prev.Add(j); cur.Add(0); j = j + 1; }

        let int i = 1;
        while (i <= a.Length()) {
            cur.Set(0, i);
            let int k = 1;
            while (k < w) {
                let int cost = a.CharAt(i - 1) == b.CharAt(k - 1) ? 0 : 1;
                let int insert = cur.Get(k - 1) + 1;
                let int delete = prev.Get(k) + 1;
                let int substitute = prev.Get(k - 1) + cost;
                let int best = insert < delete ? insert : delete;
                best = best < substitute ? best : substitute;
                cur.Set(k, best);
                k = k + 1;
            }
            let List[int] tmp = prev;
            prev = cur;
            cur = tmp;
            i = i + 1;
        }
        return prev.Get(b.Length());
    }
}

/*
 * The colours diagnostics render with.
 */
module C {

    // The slots Install programs. 0, 7, 8 and 15 are left alone - they are the structural greys.
    int func SlotEmber()  { return 1; }
    int func SlotGold()   { return 2; }
    int func SlotSand()   { return 3; }
    int func SlotCyan()   { return 4; }
    int func SlotYellow() { return 5; }
    int func SlotRed()    { return 6; }

    /*
     * Install - Program the six tones, once, at startup. Skipped when neither stream is a terminal:
     * with nothing to colour there is no reason to touch a screen the compiler is not drawing on.
     */
    public void func Install() {
        if (!Console.IsTty() && !Console.IsTtyErr()) { return; }
        Console.SetPalette(C.SlotEmber(),  255, 135,  95);   // xterm 209
        Console.SetPalette(C.SlotGold(),   255, 215,  95);   // xterm 221
        Console.SetPalette(C.SlotSand(),   215, 175, 135);   // xterm 180
        Console.SetPalette(C.SlotCyan(),    95, 215, 215);   // xterm 80
        Console.SetPalette(C.SlotYellow(), 255, 175,   0);   // xterm 214
        Console.SetPalette(C.SlotRed(),    255,  95,  95);   // xterm 203
    }

    public String func NC()     { return Console.NoStyle(); }
    public String func BOLD()   { return Console.Fg(Vga.White()); }
    public String func DIM()    { return Console.Fg(Vga.DarkGray()); }

    public String func EMBER()  { return Console.Fg(Console.HasPalette() ? C.SlotEmber()  : Vga.Brown()); }
    public String func GOLD()   { return Console.Fg(Console.HasPalette() ? C.SlotGold()   : Vga.Yellow()); }
    public String func SAND()   { return Console.Fg(Console.HasPalette() ? C.SlotSand()   : Vga.Brown()); }
    public String func CYAN()   { return Console.Fg(Console.HasPalette() ? C.SlotCyan()   : Vga.LightCyan()); }
    public String func YELLOW() { return Console.Fg(Console.HasPalette() ? C.SlotYellow() : Vga.Yellow()); }
    public String func RED()    { return Console.Fg(Console.HasPalette() ? C.SlotRed()    : Vga.LightRed()); }
}

/*
 * The bag every pass reports into: the diagnostics in the order they were added, the running
 * error and warning counts, and the sources needed to render one with its snippet.
 */
class DiagnosticBag {
    SourceSet sources;
    List[Diagnostic] d;
    int errCount;
    int warnCount;

    // The generic instantiation currently being resolved, or "" outside one
    String instanceScope;
    StringSet instanceSeen;

    func _init(SourceSet sources) {
        self.sources = sources;
        self.d = new List[Diagnostic]();
        self.errCount = 0;
        self.warnCount = 0;
        self.instanceScope = "";
        self.instanceSeen = new StringSet();
    }

    /*
     * Sources - The source set diagnostics are rendered against
     */
    public SourceSet func Sources() { return self.sources; }

    /*
     * All - Every diagnostic, in the order it was added
     */
    public List[Diagnostic] func All() { return self.d; }

    public bool func HasErrors() { return self.errCount > 0; }
    public int func ErrorCount() { return self.errCount; }
    public int func WarningCount() { return self.warnCount; }
    public int func Count() { return self.d.Length(); }

    /*
     * TruncateTo - Drops every diagnostic added after the given count
     */
    public void func TruncateTo(int count) {
        if (count >= self.d.Length()) { return; }
        while (self.d.Length() > count) {
            let Diagnostic last = self.d.Last();
            if (Diags.Severity(last) == Severity.Error) { self.errCount = self.errCount - 1; }
            else { self.warnCount = self.warnCount - 1; }
            self.d.RemoveLast();
        }
    }

    /*
     * PushInstance - Marks diagnostics until the matching PopInstance as coming from one generic
     * instantiation, where the same complaint is reported once.
     */
    public String func PushInstance(String instance) {
        let String previous = self.instanceScope;
        self.instanceScope = instance;
        return previous;
    }

    /*
     * PopInstance - Restores the scope PushInstance handed back
     */
    public void func PopInstance(String previous) { self.instanceScope = previous; }

    /*
     * Error - Adds an error diagnostic. Hints are optional "= help:" lines rendered after the
     * source snippet.
     */
    public void func Error(String code, String file, TextSpan span, String message, List[String] hints) {
        if (self.instanceScope.Length() > 0) {
            let String key = self.instanceScope + "|" + code + "|" + message;
            if (!self.instanceSeen.AddNew(key)) { return; }
        }
        self.d.Add(Diagnostic.D(Severity.Error, code, message, Loc.At(file, span), hints));
        self.errCount = self.errCount + 1;
    }

    /*
     * Error - Adds an error diagnostic with no hints
     */
    public void func Error(String code, String file, TextSpan span, String message) {
        self.Error(code, file, span, message, new List[String]());
    }

    /*
     * Warn - Adds a warning diagnostic. Hints are optional "= help:" lines rendered after the
     * source snippet.
     */
    public void func Warn(String code, String file, TextSpan span, String message, List[String] hints) {
        self.d.Add(Diagnostic.D(Severity.Warning, code, message, Loc.At(file, span), hints));
        self.warnCount = self.warnCount + 1;
    }

    /*
     * Warn - Adds a warning diagnostic with no hints
     */
    public void func Warn(String code, String file, TextSpan span, String message) {
        self.Warn(code, file, span, message, new List[String]());
    }

    /*
     * LineOf - The 1-indexed line a diagnostic points at, or 0 when its file was never read or it
     * carries no span
     */
    public int func LineOf(Diagnostic dg) {
        let Loc l = Diags.Loc(dg);
        if (TS.IsNone(Locs.Span(l))) { return 0; }
        match (self.sources.Find(Locs.File(l))) {
            case Some(src) { return LC.Line(src.LineColOf(TS.Start(Locs.Span(l)))); }
            case None { return 0; }
        }
    }

    /*
     * Render - A diagnostic as a string, with source code context and ANSI colours. If the source
     * file is not available, it renders only the file name and message.
     */
    public String func Render(Diagnostic dg) {
        let String label = Diags.Severity(dg) == Severity.Error ? "error" : "warning";
        let String color = Diags.Severity(dg) == Severity.Error ? C.RED() : C.YELLOW();

        let Loc loc = Diags.Loc(dg);
        let String file = Locs.File(loc);
        let TextSpan span = Locs.Span(loc);
        let List[String] hints = Diags.Hints(dg);

        // The file name alone, from the last '/' or '\'
        let String name = BaseName(file);

        let StringBuilder sb = new StringBuilder();

        let SourceText src = null;
        match (self.sources.Find(file)) { case Some(s) { src = s; } case None { } }

        if (src == null || TS.IsNone(span)) {
            sb.Put(name).Put(": ").Put(color).Put(label).Put("[").Put(Diags.Code(dg)).Put("]")
              .Put(C.NC()).Put(": ").Put(Diags.Message(dg));
            let int i = 0;
            while (i < hints.Length()) {
                sb.Put("\n  ").Put(C.SAND()).Put("=").Put(C.NC()).Put(" ")
                  .Put(C.CYAN()).Put("help").Put(C.NC()).Put(": ").Put(hints.Get(i));
                i = i + 1;
            }
            return sb.ToString();
        }

        let LineCol lc = src.LineColOf(TS.Start(span));
        let int line = LC.Line(lc);
        let int col = LC.Col(lc);

        // Header, like "file.g:12:34: error[G001]: message"
        sb.Put(name).Put(":").Put(Int.ToString(line)).Put(":").Put(Int.ToString(col)).Put(": ")
          .Put(color).Put(label).Put("[").Put(Diags.Code(dg)).Put("]").Put(C.NC()).Put(": ")
          .Put(Diags.Message(dg)).Put("\n");

        let String tspn = src.LineTextOf(line);
        let int gutterlen = DigitCount(line);

        // Empty gutter line
        sb.Put(Spaces(gutterlen)).Put(" ").Put(C.SAND()).Put("|").Put(C.NC()).Put("\n");

        // Source line with line number and gutter
        sb.Put(C.SAND()).Put(Int.ToString(line)).Put(" |").Put(C.NC()).Put(" ").Put(tspn).Put("\n");

        // Caret underline, clamped to what is left of the line
        let int room = tspn.Length() - (col - 1);
        if (room < 0) { room = 0; }
        let int caretLen = TS.Length(span) < room ? TS.Length(span) : room;
        if (caretLen < 1) { caretLen = 1; }

        sb.Put(Spaces(gutterlen)).Put(" ").Put(C.SAND()).Put("|").Put(C.NC()).Put(" ");

        // Padding that keeps a tab in the source line lined up under the caret
        let int i2 = 0;
        while (i2 < col - 1) {
            if (i2 < tspn.Length() && tspn.CharAt(i2) == '\t') { sb.AppendChar('\t'); }
            else { sb.AppendChar(' '); }
            i2 = i2 + 1;
        }
        sb.Put(color);
        let int c2 = 0;
        while (c2 < caretLen) { sb.AppendChar('^'); c2 = c2 + 1; }
        sb.Put(C.NC());

        // Each hint as a rustc-style "= help: ..." line under a blank gutter row
        if (hints.Length() > 0) {
            sb.Put("\n").Put(Spaces(gutterlen)).Put(" ").Put(C.SAND()).Put("|").Put(C.NC());
            let int h = 0;
            while (h < hints.Length()) {
                sb.Put("\n").Put(Spaces(gutterlen)).Put(" ").Put(C.SAND()).Put("=").Put(C.NC())
                  .Put(" ").Put(C.CYAN()).Put("help").Put(C.NC()).Put(": ").Put(hints.Get(h));
                h = h + 1;
            }
        }

        return sb.ToString();
    }
}

/*
 * FileStem - The file name without its directory or extension, which is how a file is named when
 * it qualifies a call: 'util.Compute()' for src/util.g
 */
String func FileStem(String path) {
    let String name = BaseName(path);
    let int dot = name.LastIndexOf(".");
    if (dot <= 0) { return name; }
    return name.Substring(0, dot);
}

/*
 * BaseName - The file name alone, from the last '/' or '\'
 */
String func BaseName(String path) {
    let int last = -1;
    let int i = 0;
    while (i < path.Length()) {
        let char ch = path.CharAt(i);
        if (ch == '/' || ch == '\\') { last = i; }
        i = i + 1;
    }
    if (last < 0) { return path; }
    return path.Substring(last + 1, path.Length() - (last + 1));
}

/*
 * Spaces - A run of n spaces
 */
String func Spaces(int n) {
    let StringBuilder sb = new StringBuilder();
    let int i = 0;
    while (i < n) { sb.AppendChar(' '); i = i + 1; }
    return sb.ToString();
}

/*
 * DigitCount - The number of digits in a positive integer
 */
int func DigitCount(int value) {
    if (value < 0) { value = value == Int.MinValue() ? Int.MaxValue() : -value; }
    if (value < 10) { return 1; }
    if (value < 100) { return 2; }
    if (value < 1000) { return 3; }
    if (value < 10000) { return 4; }
    if (value < 100000) { return 5; }
    if (value < 1000000) { return 6; }
    if (value < 10000000) { return 7; }
    if (value < 100000000) { return 8; }
    if (value < 1000000000) { return 9; }
    return 10;
}
