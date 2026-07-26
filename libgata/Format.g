/*
 * Format.g - Value-to-text with printf-style specs
 *
 * Author: u/ApparentlyPlus
 */

import String;

// The one general formatter. kind selects how bits is reinterpreted before snprintf:
// 0 signed (long long), 1 unsigned (unsigned long long), 2 double, 3 C string (char*).
@extern int func _env_format(char* buf, usize n, char* fmt, int kind, uint64 bits);

module Format {
    
    /*
     * Double - Default decimal text for v (the "%g" general form)
     */
    @intrinsic(stringify_float)
    public String func Double(double v) { return Double(v, "%g"); }

    /*
     * Double - Format a double with a printf float spec ("%.2f", "%e", "%12.4g"); null -> "%g"
     */
    public String func Double(double v, String spec) {
        let s = spec;
        if (s == null) { s = "%g"; }
        return run(s, 2, dbits(v));
    }

    /*
     * Int - Format a signed integer; pass the spec WITHOUT a length modifier; null -> "%d"
     */
    public String func Int(int64 v, String spec) {
        let s = spec;
        if (s == null) { s = "%d"; }
        return run(widen(s), 0, v as uint64);
    }

    /*
     * UInt - Format an unsigned integer ("%u", "%x", "%08X"); null -> "%u"
     */
    public String func UInt(uint64 v, String spec) {
        let s = spec;
        if (s == null) { s = "%u"; }
        return run(widen(s), 1, v);
    }

    /*
     * Str - Format a string with a width/precision spec; null spec -> "%s", null value -> ""
     */
    public String func Str(String v, String spec) {
        let s = spec;
        if (s == null) { s = "%s"; }
        let data = v;
        if (data == null) { data = ""; }
        unsafe { return run(s, 3, (data.CStr()) as uint64); }
    }

    /*
     * dbits - Reinterpret a double as its IEEE-754 bit pattern (the kind-2 payload)
     */
    uint64 func dbits(double v) {
        unsafe { let p = (&v) as uint64*; return *p; }
    }

    /*
     * run - snprintf bits (per kind) through spec into a fresh, exact-size buffer
     */
    String func run(String spec, int kind, uint64 bits) {
        unsafe {
            let cap = 64;
            let buf = alloc(cap as usize) as char*;
            let n = _env_format(buf, cap as usize, spec.CStr(), kind, bits);
            if (n >= cap) {
                free(buf);
                cap = n + 1;
                buf = alloc(cap as usize) as char*;
                _env_format(buf, cap as usize, spec.CStr(), kind, bits);
            }
            let r = String.FromRaw(buf);
            free(buf);
            return r;
        }
    }

    /*
     * widen - Insert the `ll` length modifier before a spec's conversion char
     */
    String func widen(String spec) {
        let n = spec.Length();
        if (n == 0) { return spec; }
        return spec.Substring(0, n - 1) + "ll" + spec.Substring(n - 1, 1);
    }
}
