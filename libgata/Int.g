// Int.g — conversions and parsing for the integer and bool primitives.
//
//   module Int  — int <-> String, decimal/hex formatting, bounds.
//   module Long — int64 -> String.
//   module Bool — bool <-> String.
//
// Pure Gata: formatting fills a heap byte buffer (allocated through the platform
// floor) with digits inside an `unsafe` block, then wraps it as a String via the
// string_literal runtime. Parsing builds on Char.

import String;
import Char;

module Int {
    // ── Bounds ────────────────────────────────────────────────────────────────
    // Largest representable int (2^31 - 1).
    public int func MaxValue() { return 2147483647; }
    // Smallest representable int (-2^31).
    public int func MinValue() { return 0 - 2147483647 - 1; }

    // ── Formatting ────────────────────────────────────────────────────────────
    // Decimal text for `n`, with a leading '-' for negatives. Bound to the
    // stringify_int role (used when interpolating int/char/bool into strings).
    @intrinsic(stringify_int)
    public String func ToString(int n) {
        if (n == 0) { return "0"; }
        let neg = n < 0;
        let v = n;
        if (neg) { v = 0 - n; }
        unsafe {
            let buf = alloc(24 as usize) as char*;
            let i = 23;
            buf[i] = '\0';
            while (v > 0) {
                i = i - 1;
                buf[i] = ('0' + v % 10) as char;
                v = v / 10;
            }
            if (neg) { i = i - 1; buf[i] = '-'; }
            let r = String.FromRaw(buf + i);
            free(buf);
            return r;
        }
    }

    // Lowercase hexadecimal text for `n`, prefixed with "0x".
    public String func ToHex(int n) {
        if (n == 0) { return "0x0"; }
        let v = n as uint;
        unsafe {
            let buf = alloc(20 as usize) as char*;
            let i = 19;
            buf[i] = '\0';
            while (v > (0 as uint)) {
                i = i - 1;
                let d = (v & (15 as uint)) as int;
                if (d < 10) { buf[i] = ('0' + d) as char; }
                else { buf[i] = ('a' + d - 10) as char; }
                v = v >> 4;
            }
            i = i - 1; buf[i] = 'x';
            i = i - 1; buf[i] = '0';
            let r = String.FromRaw(buf + i);
            free(buf);
            return r;
        }
    }

    // ── Parsing (pure Gata) ───────────────────────────────────────────────────
    // Parse a decimal integer: skips leading whitespace, accepts an optional
    // sign, and stops at the first non-digit. Returns 0 for null/empty/invalid.
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

    // Like Parse, but rejects anything that isn't a clean (optionally
    // whitespace-padded, optionally signed) decimal integer — distinguishes
    // "invalid" from "legitimately 0", which the lenient Parse can't.
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

module Long {
    // Decimal text for a int64.
    public String func ToString(int64 n) {
        if (n == (0 as int64)) { return "0"; }
        let neg = n < (0 as int64);
        let v = n;
        if (neg) { v = (0 as int64) - n; }
        unsafe {
            let buf = alloc(24 as usize) as char*;
            let i = 23;
            buf[i] = '\0';
            while (v > (0 as int64)) {
                i = i - 1;
                buf[i] = ('0' + ((v % (10 as int64)) as int)) as char;
                v = v / (10 as int64);
            }
            if (neg) { i = i - 1; buf[i] = '-'; }
            let r = String.FromRaw(buf + i);
            free(buf);
            return r;
        }
    }

    // Returns 0 for null/empty/invalid (the fast-path default, mirrors Int.Parse).
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
        let result = (0 as int64);
        while (i < n && Char.IsDigit(s.CharAt(i))) {
            result = result * (10 as int64) + (Char.DigitValue(s.CharAt(i)) as int64);
            i = i + 1;
        }
        if (neg) { return (0 as int64) - result; }
        return result;
    }

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
        let result = (0 as int64);
        while (i < n && Char.IsDigit(s.CharAt(i))) {
            result = result * (10 as int64) + (Char.DigitValue(s.CharAt(i)) as int64);
            i = i + 1;
        }
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }
        if (i != n) { throw; }
        if (neg) { return (0 as int64) - result; }
        return result;
    }
}

module Bool {
    // "true" or "false".
    public String func ToString(bool v) {
        if (v) { return "true"; }
        return "false";
    }

    // Parse "true"/"false" (case-insensitive); anything else is false.
    public bool func Parse(String s) {
        if (s == null) { return false; }
        return s.ToLower().Equals("true");
    }
}
