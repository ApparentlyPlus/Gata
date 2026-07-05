// String.g — the String type and StringBuilder.
//
// String owns `char* data; usize length;`. A "..." literal is a STATIC String built
// by GATA_STRLIT at the bottom of this file (no allocation); everything else that
// builds a String goes through the platform allocator. All public methods are
// null/bounds safe. Comparison operators are built on CompareTo so String slots
// into the duck-typed generic algorithms in Algorithms.g (Sort/Min/Max/...).

import Runtime;
import Char;
import Mem;
import List;

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

    // The raw NUL-terminated buffer, for the few platform calls (printf-style
    // formatting, the write syscall) that need a real char* rather than going
    // through CharAt/Substring. `data` itself stays private.
    public char* func CStr() { return self.data; }

    public char func CharAt(int i) {
        if (i < 0 || i >= self.Length()) { return '\0'; }
        unsafe { return self.data[i]; }
    }

    public bool func Equals(String other) {
        if (other == null) { return false; }
        if (self.Length() != other.Length()) { return false; }
        let i = 0;
        while (i < self.Length()) {
            if (self.CharAt(i) != other.CharAt(i)) { return false; }
            i = i + 1;
        }
        return true;
    }

    public int func CompareTo(String other) {
        if (other == null) { return 1; }
        let n = self.Length();
        let m = other.Length();
        let i = 0;
        while (i < n && i < m) {
            let a = self.CharAt(i) as int;
            let b = other.CharAt(i) as int;
            if (a != b) { return a - b; }
            i = i + 1;
        }
        return n - m;
    }

    operator func <  (String other) -> bool { return self.CompareTo(other) < 0; }
    operator func >  (String other) -> bool { return self.CompareTo(other) > 0; }
    operator func <= (String other) -> bool { return self.CompareTo(other) <= 0; }
    operator func >= (String other) -> bool { return self.CompareTo(other) >= 0; }

    public bool func StartsWith(String prefix) {
        if (prefix == null) { return false; }
        let m = prefix.Length();
        if (m > self.Length()) { return false; }
        let i = 0;
        while (i < m) {
            if (self.CharAt(i) != prefix.CharAt(i)) { return false; }
            i = i + 1;
        }
        return true;
    }

    public bool func EndsWith(String suffix) {
        if (suffix == null) { return false; }
        let n = self.Length();
        let m = suffix.Length();
        if (m > n) { return false; }
        let i = 0;
        while (i < m) {
            if (self.CharAt(n - m + i) != suffix.CharAt(i)) { return false; }
            i = i + 1;
        }
        return true;
    }

    public int func IndexOfChar(char c) {
        let i = 0;
        while (i < self.Length()) {
            if (self.CharAt(i) == c) { return i; }
            i = i + 1;
        }
        return -1;
    }

    // First index of `sub` at or after `from`, or -1. Empty `sub` matches at `from`.
    public int func IndexOf(String sub, int from) {
        if (sub == null) { return -1; }
        if (from < 0) { from = 0; }
        let n = self.Length();
        let m = sub.Length();
        if (m == 0) { return from <= n ? from : -1; }
        if (from > n - m) { return -1; }
        let i = from;
        while (i <= n - m) {
            let j = 0;
            while (j < m && self.CharAt(i + j) == sub.CharAt(j)) { j = j + 1; }
            if (j == m) { return i; }
            i = i + 1;
        }
        return -1;
    }

    public int func IndexOf(String sub) { return self.IndexOf(sub, 0); }

    public int func LastIndexOf(String sub) {
        if (sub == null) { return -1; }
        let n = self.Length();
        let m = sub.Length();
        if (m == 0) { return n; }
        if (m > n) { return -1; }
        let i = n - m;
        while (i >= 0) {
            let j = 0;
            while (j < m && self.CharAt(i + j) == sub.CharAt(j)) { j = j + 1; }
            if (j == m) { return i; }
            i = i - 1;
        }
        return -1;
    }

    public bool func Contains(String sub) { return self.IndexOf(sub) >= 0; }

    // `len` characters starting at `start`; indices are clamped, never out of bounds.
    public String func Substring(int start, int len) {
        if (start < 0) { start = 0; }
        if (len < 0) { len = 0; }
        let slen = self.length as int;
        if (start > slen) { start = slen; }
        if (start + len > slen) { len = slen - start; }
        let r = new String();
        unsafe {
            r.data = alloc((len + 1) as usize) as char*;
            let i = 0;
            while (i < len) {
                r.data[i] = self.data[start + i];
                i = i + 1;
            }
            r.data[len] = '\0';
        }
        r.length = len as usize;
        return r;
    }

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

    public String func Trim() {
        let n = self.Length();
        let start = 0;
        while (start < n && Char.IsWhitespace(self.CharAt(start))) { start = start + 1; }
        let end = n;
        while (end > start && Char.IsWhitespace(self.CharAt(end - 1))) { end = end - 1; }
        return self.Substring(start, end - start);
    }

    // Split on every occurrence of `sep`. A null/empty `sep` returns `[self]`.
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

    public String func PadLeft(int width, char pad) {
        let n = self.Length();
        if (n >= width) { return self; }
        let sb = new StringBuilder();
        let i = n;
        while (i < width) { sb.AppendChar(pad); i = i + 1; }
        sb.Append(self);
        return sb.ToString();
    }

    public String func PadRight(int width, char pad) {
        let n = self.Length();
        if (n >= width) { return self; }
        let sb = new StringBuilder();
        sb.Append(self);
        let i = n;
        while (i < width) { sb.AppendChar(pad); i = i + 1; }
        return sb.ToString();
    }

    public String func Repeat(int n) {
        if (n <= 0) { return ""; }
        let sb = new StringBuilder();
        let i = 0;
        while (i < n) { sb.Append(self); i = i + 1; }
        return sb.ToString();
    }

    // Backs `+` and string interpolation (the non-String side is stringified first
    // by the front-end, so this always receives two Strings).
    operator func +(String other) -> String {
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

    // The runtime path for wrapping a computed (non-literal) char* buffer into a heap
    // String — copies the bytes, so unlike a "..." literal this always allocates. A
    // static method (not a free function) because it pokes `data`/`length` directly,
    // which are private now that fields default to class-internal access.
    public static String func FromRaw(char* raw) {
        let n = 0;
        if (raw != null) { unsafe { n = Mem.StrLen(raw) as int; } }
        return String.FromBuffer(raw, n);
    }

    // Like FromRaw, but for a buffer that is not (or may not be) NUL-terminated and
    // whose length is already known — e.g. StringBuilder's backing array, which
    // tracks length separately rather than relying on a terminator.
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
}

// Growable text buffer for hot-loop string building — a chain of `+` is O(n^2)
// (each concat allocates a fresh buffer), this amortizes to O(n).
class StringBuilder {
    char* data;
    int length;
    int cap;

    func _init() { self.data = null; self.length = 0; self.cap = 0; }
    func _deinit() { if (self.data != null) { free(self.data); } }

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

    public int func Length() { return self.length; }
    public int func Capacity() { return self.cap; }
    public void func Reserve(int n) { if (n > self.cap) { self.Grow(n); } }
    public void func Clear() { self.length = 0; }

    public void func AppendChar(char c) {
        if (self.length + 1 > self.cap) { self.Grow(self.length + 1); }
        unsafe { self.data[self.length] = c; }
        self.length = self.length + 1;
    }

    public void func Append(String s) {
        if (s == null) { return; }
        let n = s.Length();
        if (n == 0) { return; }
        if (self.length + n > self.cap) { self.Grow(self.length + n); }
        unsafe {
            let i = 0;
            while (i < n) { self.data[self.length + i] = s.CharAt(i); i = i + 1; }
        }
        self.length = self.length + n;
    }

    public String func ToString() {
        unsafe { return String.FromBuffer(self.data, self.length); }
    }
}

// The compiler emits GATA_STRLIT("...") for every "..." literal: a STATIC String
// (GATA_OBJ_STATIC gives it the sentinel refcount, so ARC leaves it alone) with no
// heap allocation — a program built only from string literals needs no allocator.
native {
    #define GATA_STRLIT(T, lit) (__extension__({ \
        static const char _gsb[] = lit; \
        static T _gss = { GATA_OBJ_STATIC, (char*)_gsb, sizeof(_gsb) - 1 }; \
        &_gss; \
    }))
}

