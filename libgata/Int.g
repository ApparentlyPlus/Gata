/*
 * Int.g - Conversions and parsing for the int primitive
 *
 * Author: u/ApparentlyPlus
 */

import String;
import Char;

module Int {

    /*
     * MaxValue - Largest representable int (2^31 - 1)
     */
    public int func MaxValue() { return 2147483647; }

    /*
     * MinValue - Smallest representable int (-2^31)
     */
    public int func MinValue() { return 0 - 2147483647 - 1; }

    /*
     * ToString - Decimal text for n, with a leading - for negatives
     */
    @intrinsic(stringify_int)
    public String func ToString(int n) {
        if (n == 0) { return "0"; }
        let neg = n < 0;
        let v = n;
        if (neg) { v = 0 - n; }
        unsafe {
            let [24]char buf;
            let i = 24;
            while (v > 0) {
                i = i - 1;
                buf[i] = ('0' + v % 10) as char;
                v = v / 10;
            }
            if (neg) { i = i - 1; buf[i] = '-'; }
            return String.FromBuffer(&buf[i], 24 - i);
        }
    }

    /*
     * ToHex - Lowercase hexadecimal text for n, prefixed with "0x"
     */
    public String func ToHex(int n) {
        if (n == 0) { return "0x0"; }
        let v = n as uint;
        unsafe {
            let [20]char buf;
            let i = 20;
            while (v > (0 as uint)) {
                i = i - 1;
                let d = (v & (15 as uint)) as int;
                if (d < 10) { buf[i] = ('0' + d) as char; }
                else { buf[i] = ('a' + d - 10) as char; }
                v = v >> 4;
            }
            i = i - 1; buf[i] = 'x';
            i = i - 1; buf[i] = '0';
            return String.FromBuffer(&buf[i], 20 - i);
        }
    }

    /*
     * Parse - Lenient decimal parse: skips whitespace, optional sign, stops at first
     * non-digit; returns 0 for null/empty/invalid
     */
    public int func Parse(String s) {
        if (s == null) { return 0; }
        let n = s.Length();
        let i = 0;
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }
        let neg = false;
        if (i < n && (s.CharAt(i) == '-' || s.CharAt(i) == '+')) {
            neg = s.CharAt(i) == '-';
            i = i + 1;
        }
        let result = 0;
        while (i < n && Char.IsDigit(s.CharAt(i))) {
            result = result * 10 + Char.DigitValue(s.CharAt(i));
            i = i + 1;
        }
        if (neg) { return 0 - result; }
        return result;
    }

    /*
     * ParseStrict - Like Parse but throws unless the whole string is a clean integer
     * (distinguishes "invalid" from a legitimate 0)
     */
    public throws int func ParseStrict(String s) {
        if (s == null) { throw; }
        let n = s.Length();
        let i = 0;
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }
        let neg = false;
        if (i < n && (s.CharAt(i) == '-' || s.CharAt(i) == '+')) {
            neg = s.CharAt(i) == '-';
            i = i + 1;
        }
        if (i >= n || !Char.IsDigit(s.CharAt(i))) { throw; }
        let result = 0;
        while (i < n && Char.IsDigit(s.CharAt(i))) {
            result = result * 10 + Char.DigitValue(s.CharAt(i));
            i = i + 1;
        }
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }
        if (i != n) { throw; }
        if (neg) { return 0 - result; }
        return result;
    }
}
