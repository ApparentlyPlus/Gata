/*
 * Mem.g - The memory engine. Allocation and raw byte operations.
 *
 * Author: u/ApparentlyPlus
 */

@intrinsic(env_alloc)
@extern void* func _env_alloc(usize n);
@extern void func _env_free(void* p);

/*
 * alloc - Allocate n bytes of raw, uninitialised memory (the alloc role)
 */
@intrinsic(alloc)
void* func alloc(usize n) {
    return _env_alloc(n);
}

/*
 * free - Release memory previously returned by alloc
 */
void func free(void* p) {
    _env_free(p);
}

/*
 * The loops below move/compare 8 bytes per iteration once both cursors reach a
 * common 8-byte alignment, with byte loops for the head, the tail, and the rare
 * case where the pointers can never align - an ~8x iteration cut on every buffer
 * op, in pure Gata `unsafe`.
 */
module Mem {
    /*
     * Copy - Copy n bytes from s to d (no overlap handling - see Move)
     */
    public void func Copy(void* d, void* s, usize n) {
        unsafe {
            let dc = d as char*;
            let sc = s as char*;
            let i = (0 as usize);
            if (((d as usize) & (7 as usize)) == ((s as usize) & (7 as usize))) {
                while (i < n && (((d as usize) + i) & (7 as usize)) != (0 as usize)) {
                    dc[i] = sc[i];
                    i = i + (1 as usize);
                }
                let words = (n - i) >> 3;
                let dw = (dc + i) as usize*;
                let sw = (sc + i) as usize*;
                let w = (0 as usize);
                while (w < words) { dw[w] = sw[w]; w = w + (1 as usize); }
                i = i + (words << 3);
            }
            while (i < n) {
                dc[i] = sc[i];
                i = i + (1 as usize);
            }
        }
    }

    /*
     * Move - Copy n bytes from s to d, tolerating overlap (copies backward when needed)
     */
    public void func Move(void* d, void* s, usize n) {
        unsafe {
            if (d == s || n == (0 as usize)) { return; }
            if ((d as usize) < (s as usize) || (d as usize) >= ((s as usize) + n)) {
                Mem.Copy(d, s, n);
                return;
            }
            let dc = d as char*;
            let sc = s as char*;
            let i = n;
            while (i > (0 as usize)) {
                i = i - (1 as usize);
                dc[i] = sc[i];
            }
        }
    }

    /*
     * StrLen - Length of a NUL-terminated C string (0 for null)
     */
    public usize func StrLen(char* s) {
        if (s == null) { return (0 as usize); }
        unsafe {
            let n = (0 as usize);
            while (s[n] != '\0') { n = n + (1 as usize); }
            return n;
        }
    }

    /*
     * Fill - Set n bytes at d to v
     */
    public void func Fill(void* d, byte v, usize n) {
        unsafe {
            let dc = d as char*;
            let word = ((v as usize) & (255 as usize)) * (0x0101010101010101 as usize);
            let i = (0 as usize);
            while (i < n && (((d as usize) + i) & (7 as usize)) != (0 as usize)) {
                dc[i] = v as char;
                i = i + (1 as usize);
            }
            let words = (n - i) >> 3;
            let dw = (dc + i) as usize*;
            let w = (0 as usize);
            while (w < words) { dw[w] = word; w = w + (1 as usize); }
            i = i + (words << 3);
            while (i < n) {
                dc[i] = v as char;
                i = i + (1 as usize);
            }
        }
    }

    /*
     * Compare - Byte-wise compare of the first n bytes: <0, 0, or >0
     *
     * Words are only used to find the first differing 8-byte chunk; the byte tail
     * then pins down the exact differing byte, so the result matches a plain scan.
     */
    public int func Compare(void* a, void* b, usize n) {
        unsafe {
            let ac = a as char*;
            let bc = b as char*;
            let i = (0 as usize);
            if (((a as usize) & (7 as usize)) == ((b as usize) & (7 as usize))) {
                while (i < n && (((a as usize) + i) & (7 as usize)) != (0 as usize)) {
                    if (ac[i] != bc[i]) { return (ac[i] as int) - (bc[i] as int); }
                    i = i + (1 as usize);
                }
                let words = (n - i) >> 3;
                let aw = (ac + i) as usize*;
                let bw = (bc + i) as usize*;
                let w = (0 as usize);
                while (w < words) {
                    if (aw[w] != bw[w]) { break; }
                    w = w + (1 as usize);
                }
                i = i + (w << 3);
            }
            while (i < n) {
                if (ac[i] != bc[i]) { return (ac[i] as int) - (bc[i] as int); }
                i = i + (1 as usize);
            }
        }
        return 0;
    }
}
