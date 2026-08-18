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
 * Word blitting - the 8-bytes-at-a-time inner loops, in C rather than Gata.
 */
native {
    #if defined(__GNUC__) || defined(__clang__)
    typedef uint64_t __attribute__((__may_alias__)) gata_word;
    #else
    /* No may_alias: fall back to a character type, which aliases by definition. The
       copy stays correct, it just loses the width. */
    typedef unsigned char gata_word;
    #endif
    #define GATA_WORD_STRIDE (sizeof(gata_word) == 8 ? 1u : 8u)
}

/*
 * _mem_copy_words - copy `words` 8-byte words from s to d
 */
private void func _mem_copy_words(void* d, void* s, usize words) native {
    gata_word* dw = (gata_word*)d;
    const gata_word* sw = (const gata_word*)s;
    size_t n = words * GATA_WORD_STRIDE;
    for (size_t w = 0; w < n; w++) dw[w] = sw[w];
}

/*
 * _mem_fill_words - write `word` into `words` 8-byte words at d
 */
private void func _mem_fill_words(void* d, usize word, usize words) native {
    gata_word* dw = (gata_word*)d;
    if (sizeof(gata_word) == 8) {
        for (size_t w = 0; w < words; w++) dw[w] = (gata_word)word;
    } else {
        unsigned char* b = (unsigned char*)d;
        for (size_t k = 0; k < words * 8u; k++) b[k] = (unsigned char)(word & 0xFFu);
    }
}

/*
 * _mem_diff_word - index of the first of `words` 8-byte words that differs, or `words`
 */
private usize func _mem_diff_word(void* a, void* b, usize words) native {
    const gata_word* aw = (const gata_word*)a;
    const gata_word* bw = (const gata_word*)b;
    if (sizeof(gata_word) != 8) {
        const unsigned char* ab = (const unsigned char*)a;
        const unsigned char* bb = (const unsigned char*)b;
        for (size_t w = 0; w < words; w++)
            for (size_t k = 0; k < 8u; k++)
                if (ab[w * 8u + k] != bb[w * 8u + k]) return w;
        return words;
    }
    size_t w = 0;
    while (w < words && aw[w] == bw[w]) w++;
    return w;
}

/*
 * The loops below move/compare 8 bytes per iteration once both cursors reach a
 * common 8-byte alignment, with byte loops for the head, the tail, and the rare
 * case where the pointers can never align - an ~8x iteration cut on every buffer
 * op. The word step itself is _mem_*_words above; everything else is pure Gata.
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
                _mem_copy_words(dc + i, sc + i, words);
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
            _mem_fill_words(dc + i, word, words);
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
                let w = _mem_diff_word(ac + i, bc + i, words);
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
