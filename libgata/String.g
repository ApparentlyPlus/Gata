/*
 * String.g - The String type and StringBuilder
 *
 * Author: u/ApparentlyPlus
 */

import Runtime;
import Char;
import Mem;
import List;
import Int; // Int.ToString backs the `as String` operator below
import Long; // Long.ToString backs `int64 as String`
import Format; // Format.Double backs `v as String` for double

/*
 * @builtin(String) lets the compiler resolve String as a first class type from this
 * declaration instead of hardcoding the name.
 */
@builtin(String)
class String {
    char* data;
    usize length;

    func _init() {
        self.data = null;
        self.length = (0 as usize);
    }

    func _deinit() {
        if (self.data != null) { free(self.data); }
    }

    public int func Length() { return self.length as int; }
    public bool func IsEmpty() { return self.Length() == 0; }

    /*
     * CStr - The raw NUL-terminated buffer, for platform calls that need a char*
     */
    public char* func CStr() { return self.data; }

    public char func CharAt(int i) {
        if (i < 0 || i >= self.Length()) { return '\0'; }
        unsafe { return self.data[i]; }
    }

    /*
     * [] - Read-only `str[i]` sugar for CharAt
     *
     * There is deliberately no operator[]=: a "..." literal is a single STATIC String
     * instance, so every variable holding it aliases the same buffer - in-place
     * mutation would corrupt every alias. Build text with StringBuilder instead.
     */
    public operator char func [](int i) { return self.CharAt(i); }

    /*
     * == - Content equality: compares characters, never buffer identity
     *
     * A comparison against the null LITERAL is compiled by appa as a pointer check
     * and never reaches this operator - which is what lets this body null-guard its
     * own operand without recursing.
     */
    public operator bool func ==(String other) {
        if (other == null) { return false; }
        if (self.length != other.length) { return false; }
        unsafe { return Mem.Compare(self.data, other.data, self.length) == 0; }
    }

    public bool func Equals(String other) { return self == other; }

    /*
     * CompareTo - Lexicographic order: <0, 0, or >0 (null sorts first)
     */
    public int func CompareTo(String other) {
        if (other == null) { return 1; }
        let n = self.Length();
        let m = other.Length();
        let k = n < m ? n : m;
        unsafe {
            let c = Mem.Compare(self.data, other.data, k as usize);
            if (c != 0) { return c; }
        }
        return n - m;
    }

    public operator bool func < (String other) { return self.CompareTo(other) < 0; }
    public operator bool func > (String other) { return self.CompareTo(other) > 0; }
    public operator bool func <= (String other) { return self.CompareTo(other) <= 0; }
    public operator bool func >= (String other) { return self.CompareTo(other) >= 0; }

    /*
     * StartsWith - True if this string begins with prefix
     */
    public bool func StartsWith(String prefix) {
        if (prefix == null) { return false; }
        let m = prefix.Length();
        if (m > self.Length()) { return false; }
        unsafe { return Mem.Compare(self.data, prefix.data, m as usize) == 0; }
    }

    /*
     * EndsWith - True if this string ends with suffix
     */
    public bool func EndsWith(String suffix) {
        if (suffix == null) { return false; }
        let n = self.Length();
        let m = suffix.Length();
        if (m > n) { return false; }
        unsafe { return Mem.Compare(self.data + (n - m), suffix.data, m as usize) == 0; }
    }

    /*
     * IndexOfChar - First index of c, or -1 if absent
     */
    public int func IndexOfChar(char c) {
        let n = self.Length();
        unsafe {
            let d = self.data;
            let i = 0;
            while (i < n) {
                if (d[i] == c) { return i; }
                i = i + 1;
            }
        }
        return -1;
    }

    /*
     * IndexOf - First index of sub at or after `from`, or -1 (empty sub matches at from)
     *
     * Scans for the first character before comparing the rest, so mismatches cost one
     * comparison instead of a call per character.
     */
    public int func IndexOf(String sub, int from) {
        if (sub == null) { return -1; }
        if (from < 0) { from = 0; }
        let n = self.Length();
        let m = sub.Length();
        if (m == 0) { return from <= n ? from : -1; }
        if (from > n - m) { return -1; }
        unsafe {
            let d = self.data;
            let p = sub.data;
            let first = p[0];
            let i = from;
            while (i <= n - m) {
                if (d[i] == first) {
                    let j = 1;
                    while (j < m && d[i + j] == p[j]) { j = j + 1; }
                    if (j == m) { return i; }
                }
                i = i + 1;
            }
        }
        return -1;
    }

    public int func IndexOf(String sub) { return self.IndexOf(sub, 0); }

    /*
     * LastIndexOf - Last index of sub, or -1 if absent
     */
    public int func LastIndexOf(String sub) {
        if (sub == null) { return -1; }
        let n = self.Length();
        let m = sub.Length();
        if (m == 0) { return n; }
        if (m > n) { return -1; }
        unsafe {
            let d = self.data;
            let p = sub.data;
            let i = n - m;
            while (i >= 0) {
                let j = 0;
                while (j < m && d[i + j] == p[j]) { j = j + 1; }
                if (j == m) { return i; }
                i = i - 1;
            }
        }
        return -1;
    }

    public bool func Contains(String sub) { return self.IndexOf(sub) >= 0; }

    /*
     * Substring - len characters starting at start; indices are clamped, never out of bounds
     */
    public String func Substring(int start, int len) {
        if (start < 0) { start = 0; }
        if (len < 0) { len = 0; }
        let slen = self.length as int;
        if (start > slen) { start = slen; }
        if (start + len > slen) { len = slen - start; }
        let r = new String();
        unsafe {
            r.data = alloc((len + 1) as usize) as char*;
            if (len > 0) { Mem.Copy(r.data, self.data + start, len as usize); }
            r.data[len] = '\0';
        }
        r.length = len as usize;
        return r;
    }

    /*
     * ToUpper - A new string with ASCII letters uppercased
     */
    public String func ToUpper() {
        let n = self.length as int;
        let r = new String();
        unsafe {
            r.data = alloc((n + 1) as usize) as char*;
            let i = 0;
            while (i < n) {
                let c = self.data[i];
                if (c >= 'a' && c <= 'z') { r.data[i] = (c - 32) as char; }
                else { r.data[i] = c; }
                i = i + 1;
            }
            r.data[n] = '\0';
        }
        r.length = n as usize;
        return r;
    }

    /*
     * ToLower - A new string with ASCII letters lowercased
     */
    public String func ToLower() {
        let n = self.length as int;
        let r = new String();
        unsafe {
            r.data = alloc((n + 1) as usize) as char*;
            let i = 0;
            while (i < n) {
                let c = self.data[i];
                if (c >= 'A' && c <= 'Z') { r.data[i] = (c + 32) as char; }
                else { r.data[i] = c; }
                i = i + 1;
            }
            r.data[n] = '\0';
        }
        r.length = n as usize;
        return r;
    }

    /*
     * Trim - A new string with leading and trailing whitespace removed
     */
    public String func Trim() {
        let n = self.Length();
        let start = 0;
        while (start < n && Char.IsWhitespace(self.CharAt(start))) { start = start + 1; }
        let end = n;
        while (end > start && Char.IsWhitespace(self.CharAt(end - 1))) { end = end - 1; }
        return self.Substring(start, end - start);
    }

    /*
     * Split - Split on every occurrence of sep; a null/empty sep returns [self]
     */
    public List[String] func Split(String sep) {
        let result = new List[String]();
        if (sep == null || sep.Length() == 0 || self.Length() == 0) {
            result.Add(self);
            return result;
        }
        let start = 0;
        let idx = self.IndexOf(sep, start);
        while (idx >= 0) {
            result.Add(self.Substring(start, idx - start));
            start = idx + sep.Length();
            idx = self.IndexOf(sep, start);
        }
        result.Add(self.Substring(start, self.Length() - start));
        return result;
    }

    /*
     * Join - Concatenate parts with sep between them
     */
    public static String func Join(List[String] parts, String sep) {
        let sb = new StringBuilder();
        let n = parts.Length();
        let i = 0;
        while (i < n) {
            if (i > 0 && sep != null) { sb.Append(sep); }
            sb.Append(parts.Get(i));
            i = i + 1;
        }
        return sb.ToString();
    }

    /*
     * Replace - A new string with every occurrence of oldVal replaced by newVal
     */
    public String func Replace(String oldVal, String newVal) {
        if (oldVal == null || oldVal.Length() == 0) { return self; }
        let sb = new StringBuilder();
        let start = 0;
        let idx = self.IndexOf(oldVal, start);
        while (idx >= 0) {
            sb.Append(self.Substring(start, idx - start));
            if (newVal != null) { sb.Append(newVal); }
            start = idx + oldVal.Length();
            idx = self.IndexOf(oldVal, start);
        }
        sb.Append(self.Substring(start, self.Length() - start));
        return sb.ToString();
    }

    /*
     * PadLeft - Left-pad with pad up to width (returns self if already wide enough)
     */
    public String func PadLeft(int width, char pad) {
        let n = self.Length();
        if (n >= width) { return self; }
        let sb = new StringBuilder();
        let i = n;
        while (i < width) { sb.AppendChar(pad); i = i + 1; }
        sb.Append(self);
        return sb.ToString();
    }

    /*
     * PadRight - Right-pad with pad up to width (returns self if already wide enough)
     */
    public String func PadRight(int width, char pad) {
        let n = self.Length();
        if (n >= width) { return self; }
        let sb = new StringBuilder();
        sb.Append(self);
        let i = n;
        while (i < width) { sb.AppendChar(pad); i = i + 1; }
        return sb.ToString();
    }

    /*
     * Repeat - This string concatenated with itself n times ("" for n <= 0)
     */
    public String func Repeat(int n) {
        if (n <= 0) { return ""; }
        let sb = new StringBuilder();
        let i = 0;
        while (i < n) { sb.Append(self); i = i + 1; }
        return sb.ToString();
    }

    /*
     * + - Concatenation, backing `+` and interpolation (both sides are Strings here)
     */
    public operator String func +(String other) {
        let r = new String();
        unsafe {
            let la = 0;
            let lb = 0;
            if (self != null)  { la = self.length as int; }
            if (other != null) { lb = other.length as int; }
            let total = la + lb;
            r.length = total as usize;
            r.data = alloc((total + 1) as usize) as char*;
            if (la > 0) { Mem.Copy(r.data, self.data, la as usize); }
            if (lb > 0) { Mem.Copy(r.data + la, other.data, lb as usize); }
            r.data[total] = '\0';
        }
        return r;
    }

    public String func Concat(String other) { return self + other; }
    public String func ToString() { return self; }

    /*
     * FromChar - A one-character string (the stringify_char role)
     *
     * Interpolating/concatenating a char routes here, not stringify_int, so it prints
     * the character rather than its codepoint. Lives here because it pokes the private
     * data/length directly.
     */
    @intrinsic(stringify_char)
    public static String func FromChar(char c) {
        let r = new String();
        unsafe {
            r.data = alloc((2) as usize) as char*;
            r.data[0] = c;
            r.data[1] = '\0';
        }
        r.length = (1) as usize;
        return r;
    }

    /*
     * FromRaw - Wrap a computed NUL-terminated char* into a heap String (copies the bytes)
     */
    public static String func FromRaw(char* raw) {
        let n = 0;
        if (raw != null) { unsafe { n = Mem.StrLen(raw) as int; } }
        return String.FromBuffer(raw, n);
    }

    /*
     * FromBuffer - Like FromRaw but for a buffer of known length, not NUL-terminated
     */
    public static String func FromBuffer(char* raw, int len) {
        let r = new String();
        unsafe {
            r.length = len as usize;
            r.data = alloc((len + 1) as usize) as char*;
            if (raw != null && len > 0) { Mem.Copy(r.data, raw, len as usize); }
            r.data[len] = '\0';
        }
        return r;
    }

    public operator String func as(char c) { return String.FromChar(c); }
    public operator String func as(char* raw) { return String.FromRaw(raw); }
    public operator String func as(int n)    { return Int.ToString(n); }
    public operator String func as(int64 n)  { return Long.ToString(n); }
    public operator String func as(double v) { return Format.Double(v); }
    public operator String func as(bool b)   { return b ? "true" : "false"; }
}


@builtin(StringBuilder)
class StringBuilder {
    char* data;
    int length;
    int cap;

    func _init() { self.data = null; self.length = 0; self.cap = 0; }
    func _deinit() { if (self.data != null) { free(self.data); } }

    public int func Length() { return self.length; }
    public int func Capacity() { return self.cap; }
    public void func Reserve(int n) { if (n > self.cap) { self.Grow(n); } }
    public void func Clear() { self.length = 0; }

    /*
     * AppendChar - Append a single character
     */
    public void func AppendChar(char c) {
        if (self.length + 1 > self.cap) { self.Grow(self.length + 1); }
        unsafe { self.data[self.length] = c; }
        self.length = self.length + 1;
    }

    /*
     * Append - Append a string (null and empty are no-ops)
     */
    public void func Append(String s) {
        if (s == null) { return; }
        let n = s.Length();
        if (n == 0) { return; }
        if (self.length + n > self.cap) { self.Grow(self.length + n); }
        unsafe { Mem.Copy(self.data + self.length, s.CStr(), n as usize); }
        self.length = self.length + n;
    }

    /*
     * Put - Chainable Append: returns self so appends compose (the lowering's shape)
     */
    public StringBuilder func Put(String s) {
        self.Append(s);
        return self;
    }

    /*
     * ToString - Snapshot the buffer into a new String
     */
    public String func ToString() {
        unsafe { return String.FromBuffer(self.data, self.length); }
    }

    /*
     * Grow - Double capacity (from 16) until at least need
     */
    void func Grow(int need) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 16; }
        while (nc < need) { nc = nc * 2; }
        unsafe {
            let nd = alloc(nc as usize) as char*;
            if (self.data != null) { Mem.Copy(nd, self.data, self.length as usize); free(self.data); }
            self.data = nd;
        }
        self.cap = nc;
    }
}

/*
 * The compiler emits GATA_STRLIT("...") for every "..." literal: a STATIC String
 * (GATA_OBJ_STATIC gives it the sentinel refcount, so ARC leaves it alone) with no
 * heap allocation - a program built only from string literals needs no allocator.
 */
native {
    #define GATA_STRLIT(T, lit) (__extension__({ \
        static const char _gsb[] = lit; \
        static T _gss = { GATA_OBJ_STATIC, (char*)_gsb, sizeof(_gsb) - 1 }; \
        &_gss; \
    }))
}
