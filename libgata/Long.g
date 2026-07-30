/*
 * Long.g - Conversions and parsing for the int64 primitive
 *
 * Author: u/ApparentlyPlus
 */

import String;
import Char;

module Long {

    /*
     * ToString - Decimal text for an int64 (same single-allocation shape as Int.ToString)
     */
    public String func ToString(int64 n) {
        if (n == (0 as int64)) { return "0"; }
        let neg = n < (0 as int64);
        let v = n as uint64;
        if (neg) { v = (0 as uint64) - v; }
        unsafe {
            let [24]char buf;
            let i = 24;
            while (v > (0 as uint64)) {
                i = i - 1;
                buf[i] = ('0' + ((v % (10 as uint64)) as int)) as char;
                v = v / (10 as uint64);
            }
            if (neg) { i = i - 1; buf[i] = '-'; }
            return String.FromBuffer(&buf[i], 24 - i);
        }
    }

    /*
     * Parse - Lenient decimal parse; returns 0 for null/empty/invalid (mirrors Int.Parse)
     */
    public int64 func Parse(String s) {
        if (s == null) { return (0 as int64); }
        let n = s.Length();
        let i = 0;
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }
        let neg = false;
        if (i < n && (s.CharAt(i) == '-' || s.CharAt(i) == '+')) {
            neg = s.CharAt(i) == '-';
            i = i + 1;
        }
        
        let result = (0 as uint64);
        while (i < n && Char.IsDigit(s.CharAt(i))) {
            result = result * (10 as uint64) + (Char.DigitValue(s.CharAt(i)) as uint64);
            i = i + 1;
        }
        if (neg) { return ((0 as uint64) - result) as int64; }
        return result as int64;
    }

    /*
     * ParseStrict - Like Parse but throws unless the whole string is a clean integer
     */
    public throws int64 func ParseStrict(String s) {
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
        let result = (0 as uint64);
        while (i < n && Char.IsDigit(s.CharAt(i))) {
            result = result * (10 as uint64) + (Char.DigitValue(s.CharAt(i)) as uint64);
            i = i + 1;
        }
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }
        if (i != n) { throw; }
        if (neg) { return ((0 as uint64) - result) as int64; }
        return result as int64;
    }
}
