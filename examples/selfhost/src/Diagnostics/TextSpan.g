/*
 * TextSpan.g - the (start, length) source-span value type every AST/IR node carries
 *
 * Ports Appa/src/Diagnostics/TextSpan.cs.
 */

union TextSpan { Span(int start, int length) }

/*
 * NoneSpan - The absence of a span; SpanIsNone(NoneSpan()) is true
 */
TextSpan func NoneSpan() { return TextSpan.Span(-1, 0); }

/*
 * SpanStart - The span's starting offset
 */
int func SpanStart(TextSpan s) {
    match (s) { case Span(start, length) { return start; } }
}

/*
 * SpanLength - The span's length in characters
 */
int func SpanLength(TextSpan s) {
    match (s) { case Span(start, length) { return length; } }
}

/*
 * SpanEnd - The offset one past the span's last character (SpanStart + SpanLength)
 */
int func SpanEnd(TextSpan s) {
    match (s) { case Span(start, length) { return start + length; } }
}

/*
 * SpanIsNone - True for the absent span (a negative SpanStart)
 */
bool func SpanIsNone(TextSpan s) { return SpanStart(s) < 0; }

/*
 * SpanMerge - The smallest span containing both a and b; either side alone if the other is
 * SpanIsNone
 */
TextSpan func SpanMerge(TextSpan a, TextSpan b) {
    if (SpanIsNone(a)) { return b; }
    if (SpanIsNone(b)) { return a; }
    let int ss = SpanStart(a) < SpanStart(b) ? SpanStart(a) : SpanStart(b);
    let int ee = SpanEnd(a) > SpanEnd(b) ? SpanEnd(a) : SpanEnd(b);
    return TextSpan.Span(ss, ee - ss);
}
