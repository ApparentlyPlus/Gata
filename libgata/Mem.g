// Mem.g — the memory engine: allocation and raw byte operations.
//
// The whole memory floor an environment must provide is two binds — _env_alloc /
// _env_free (env.g maps them to the platform's malloc/free). Everything above them
// is pure Gata: `alloc` fills the @intrinsic(alloc) role the compiler emits for
// every object allocation; Mem.Copy / Mem.StrLen are byte loops the rest of libgata
// builds on instead of a C memcpy/strlen, so they are visible to the type checker,
// ARC, and DCE rather than being a native blind spot.

@extern func _env_alloc(usize n) -> void*;
@extern func _env_free(void* p) -> void;

// Allocate `n` bytes of raw, uninitialised memory. Bound to the alloc role: the
// compiler emits a call to this for every managed-object allocation.
@intrinsic(alloc)
void* func alloc(usize n) {
    return _env_alloc(n);
}

// Release memory previously returned by `alloc`.
void func free(void* p) {
    _env_free(p);
}

module Mem {
    // Copy `n` bytes from `s` to `d` (no overlap handling).
    public void func Copy(void* d, void* s, usize n) {
        unsafe {
            let dc = d as char*;
            let sc = s as char*;
            let i = (0 as usize);
            while (i < n) {
                dc[i] = sc[i];
                i = i + (1 as usize);
            }
        }
    }

    // Length of a NUL-terminated C string (0 for null).
    public usize func StrLen(char* s) {
        if (s == null) { return (0 as usize); }
        unsafe {
            let n = (0 as usize);
            while (s[n] != '\0') { n = n + (1 as usize); }
            return n;
        }
    }

    // Set `n` bytes at `d` to `v`.
    public void func Fill(void* d, byte v, usize n) {
        unsafe {
            let dc = d as char*;
            let i = (0 as usize);
            while (i < n) { dc[i] = v as char; i = i + (1 as usize); }
        }
    }

    // Byte-wise comparison of the first `n` bytes: <0, 0, or >0.
    public int func Compare(void* a, void* b, usize n) {
        unsafe {
            let ac = a as char*;
            let bc = b as char*;
            let i = (0 as usize);
            while (i < n) {
                if (ac[i] != bc[i]) { return (ac[i] as int) - (bc[i] as int); }
                i = i + (1 as usize);
            }
        }
        return 0;
    }
}
