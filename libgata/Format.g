// Format.g — value-to-text with printf-style specs.
//
// All formatting policy lives here, over the environment's ONE general delegate,
// `_env_format`. C's printf is variadic and its conversions are tied to argument
// types, which Gata cannot express directly; so each value is reinterpreted into a
// single 64-bit payload plus a `kind` tag, and the env routes it to snprintf with the
// matching argument type. One platform bind covers every conversion (%d %x %g %e %s …).
//
// Formatting goes through the platform's printf (the _env_format bind). Plain int→text
// without a spec stays in Int.g as pure Gata, needing no platform printf at all.

import String;

// The one general formatter. `kind` selects how `bits` is reinterpreted before it
// reaches snprintf: 0 signed (long long), 1 unsigned (unsigned long long), 2 double,
// 3 C string (char*).
@extern func _env_format(char* buf, usize n, char* fmt, int kind, uint64 bits) -> int;

module Format {
    // Reinterpret a double as its IEEE-754 bit pattern (the payload for kind 2).
    uint64 func dbits(double v) {
        unsafe { let p = (&v) as uint64*; return *p; }
    }

    // snprintf `bits` (interpreted per `kind`) through `spec` into a fresh buffer.
    String func run(String spec, int kind, uint64 bits) {
        unsafe {
            let buf = alloc(64 as usize) as char*;
            _env_format(buf, 64 as usize, spec.CStr(), kind, bits);
            let r = String.FromRaw(buf);
            free(buf);
            return r;
        }
    }

    // Insert the `ll` length modifier before a spec's conversion character so a
    // promoted 64-bit integer prints correctly: "%x" → "%llx", "%05d" → "%05lld".
    // (Integer specs are passed WITHOUT a length modifier; Format supplies it.)
    String func widen(String spec) {
        let n = spec.Length();
        if (n == 0) { return spec; }
        return spec.Substring(0, n - 1) + "ll" + spec.Substring(n - 1, 1);
    }

    // Default decimal text for `v` (the "%g" general form). Bound to stringify_float,
    // so interpolating a float/double routes here.
    @intrinsic(stringify_float)
    public String func Double(double v) { return Double(v, "%g"); }

    // Format a double with a printf float spec ("%.2f", "%e", "%12.4g"). Null → "%g".
    public String func Double(double v, String spec) {
        let s = spec;
        if (s == null) { s = "%g"; }
        return run(s, 2, dbits(v));
    }

    // Format a signed integer; pass the spec WITHOUT a length modifier
    // ("%d", "%x", "%05d"). Null → "%d".
    public String func Int(int64 v, String spec) {
        let s = spec;
        if (s == null) { s = "%d"; }
        return run(widen(s), 0, v as uint64);
    }

    // Format an unsigned integer ("%u", "%x", "%08X"). Null → "%u".
    public String func UInt(uint64 v, String spec) {
        let s = spec;
        if (s == null) { s = "%u"; }
        return run(widen(s), 1, v);
    }

    // Format a string with a width/precision spec ("%s", "%10s", "%-10s", "%.3s").
    // Null spec → "%s"; a null value formats as the empty string.
    public String func Str(String v, String spec) {
        let s = spec;
        if (s == null) { s = "%s"; }
        let data = v;
        if (data == null) { data = ""; }
        unsafe { return run(s, 3, (data.CStr()) as uint64); }
    }
}
