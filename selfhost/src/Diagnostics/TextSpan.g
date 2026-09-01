/*
 * TextSpan.g - the (start, length) source-span value type every AST/IR node carries
 *
 * Ports Appa/src/Diagnostics/TextSpan.cs.
 */

union TextSpan { Span(int start, int length) }

module TS {

    /*
     * NoneSpan - The absence of a span; TS.IsNone(TS.NoneSpan()) is true
     */
    public TextSpan func NoneSpan() { return TextSpan.Span(-1, 0); }

    /*
     * Start - The span's starting offset
     */
    public int func Start(TextSpan s) {
        match (s) { case Span(start, length) { return start; } }
    }

    /*
     * Length - The span's length in characters
     */
    public int func Length(TextSpan s) {
        match (s) { case Span(start, length) { return length; } }
    }

    /*
     * End - The offset one past the span's last character (Start + Length)
     */
    public int func End(TextSpan s) {
        match (s) { case Span(start, length) { return start + length; } }
    }

    /*
     * IsNone - True for the absent span (a negative Start)
     */
    public bool func IsNone(TextSpan s) { return TS.Start(s) < 0; }

    /*
     * Merge - The smallest span containing both a and b; either side alone if the other is IsNone
     */
    public TextSpan func Merge(TextSpan a, TextSpan b) {
        if (TS.IsNone(a)) { return b; }
        if (TS.IsNone(b)) { return a; }
        let int ss = TS.Start(a) < TS.Start(b) ? TS.Start(a) : TS.Start(b);
        let int ee = TS.End(a) > TS.End(b) ? TS.End(a) : TS.End(b);
        return TextSpan.Span(ss, ee - ss);
    }
}
