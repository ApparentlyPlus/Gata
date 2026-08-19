/*
 * Diagnostic.g - diagnostic model: severity, location, the code registry, and "did you mean"
 * hints
 *
 * Ports Appa/src/Diagnostics/Diagnostic.cs.
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Optional.g";
import "src/Diagnostics/TextSpan.g";

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
     * Goes to an Error's hints parameter, not the message - it renders on its own "= help:" line
     * rather than appended to the error text.
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
     * Distance - Classic iterative Levenshtein edit distance between two strings. C#'s version
     * uses stackalloc'd Span<int> rows; Gata has no stack-scratch-buffer equivalent, so this uses
     * two List[int] rows instead - heap-allocated, same result, just not stack-allocated.
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
