/*
 * Span.g - Span[T]: a non-owning, bounds-carrying view over a contiguous buffer
 *
 * Author: u/ApparentlyPlus
 */

import Runtime;

/*
 * A Span borrows memory it does not own: it never retains or releases what it points at, and
 * copying one is a plain (pointer, length) copy, the same cost sizeof(T*) + sizeof(int) always is.
 */
union Span[T] { View(T* ptr, int len) }

/*
 * FromRaw - A span over an existing buffer; a null pointer or a non-positive len both collapse
 * to the zero-length span, so a caller never has to special-case "the buffer might not exist".
 */
Span[T] func FromRaw[T](T* ptr, int len) {
    if (ptr == null || len <= 0) { return Span[T].View(null, 0); }
    return Span[T].View(ptr, len);
}

/*
 * Length - Element count
 */
int func Length[T](Span[T] s) {
    match (s) { case View(ptr, len) { return len; } }
}

bool func IsEmpty[T](Span[T] s) { return Length(s) == 0; }

/*
 * Raw - The raw pointer, for library code that wants to walk the buffer itself (inside unsafe)
 */
T* func Raw[T](Span[T] s) {
    match (s) { case View(ptr, len) { return ptr; } }
}

/*
 * At - Element i, or the zero value if i is out of range (mirrors List.Get's clamp-to-default)
 */
T func At[T](Span[T] s, int i) {
    match (s) {
        case View(ptr, len) {
            if (i < 0 || i >= len) { return default(T); }
            unsafe { return retain(ptr[i]); }
        }
    }
}

/*
 * Slice - The sub-span [start, start+len), clamped to this span's own bounds - never out of range
 */
Span[T] func Slice[T](Span[T] s, int start, int len) {
    match (s) {
        case View(ptr, n) {
            if (start < 0) { start = 0; }
            if (start > n) { start = n; }
            if (len < 0) { len = 0; }
            if (start + len > n) { len = n - start; }
            if (len == 0) { return Span[T].View(null, 0); }
            unsafe { return Span[T].View(&ptr[start], len); }
        }
    }
}

/*
 * Equal - Element-wise == over both spans; different lengths are never equal
 */
bool func Equal[T](Span[T] a, Span[T] b) {
    let n = Length(a);
    if (n != Length(b)) { return false; }
    if (n == 0) { return true; }
    match (a) {
        case View(pa, na) {
            match (b) {
                case View(pb, nb) {
                    unsafe {
                        let i = 0;
                        while (i < n) {
                            if (pa[i] != pb[i]) { return false; }
                            i = i + 1;
                        }
                    }
                }
            }
        }
    }
    return true;
}

/*
 * StartsWith - True if prefix occurs at the start of s (an empty prefix always matches)
 */
bool func StartsWith[T](Span[T] s, Span[T] prefix) {
    let m = Length(prefix);
    if (m > Length(s)) { return false; }
    return Equal(Slice(s, 0, m), prefix);
}
