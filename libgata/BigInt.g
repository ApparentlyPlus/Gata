/*
 * BigInt.g - Arbitrary-precision signed integers
 *
 * Author: u/ApparentlyPlus
 */

import String;
import Char;
import Mem;
import Runtime;



/*
 * Thresholds at which the sub-quadratic algorithms start paying for their
 * bookkeeping, in limbs. Squaring holds out longer because its schoolbook form
 * already does half the work of a multiplication.
 */
private int func _bi_mul_karatsuba() { return 32; }
private int func _bi_sqr_karatsuba() { return 48; }

/*
 * _bi_alloc - n zeroed limbs
 */
private uint* func _bi_alloc(int n) {
    if (n < 1) { n = 1; }
    unsafe {
        let p = alloc((n as usize) * sizeof(uint)) as uint*;
        Mem.Fill(p, 0 as byte, (n as usize) * sizeof(uint));
        return p;
    }
}

/*
 * _bi_get / _bi_set - single limb access, so the class body does not need unsafe
 * just to read one
 */
private uint func _bi_get(uint* d, int i) { unsafe { return d[i]; } }
private void func _bi_set(uint* d, int i, uint v) { unsafe { d[i] = v; } }

/*
 * _bi_free - release a limb buffer
 */
private void func _bi_free(uint* d) { unsafe { if (d != null) { free(d); } } }

/*
 * _bi_copy - copy n limbs
 */
private void func _bi_copy(uint* d, uint* s, int n) {
    unsafe { Mem.Copy(d, s, (n as usize) * sizeof(uint)); }
}

/*
 * _bi_copy_at - copy n limbs from s[si..] to d[di..]
 */
private void func _bi_copy_at(uint* d, int di, uint* s, int si, int n) {
    unsafe { Mem.Copy(d + di, s + si, (n as usize) * sizeof(uint)); }
}

/*
 * _bi_clz32 - leading zero count of a limb (32 for zero)
 */
private int func _bi_clz32(uint v) {
    if (v == (0 as uint)) { return 32; }
    let n = 0;
    if ((v & (0xFFFF0000 as uint)) == (0 as uint)) { n = n + 16; v = v << 16; }
    if ((v & (0xFF000000 as uint)) == (0 as uint)) { n = n + 8;  v = v << 8;  }
    if ((v & (0xF0000000 as uint)) == (0 as uint)) { n = n + 4;  v = v << 4;  }
    if ((v & (0xC0000000 as uint)) == (0 as uint)) { n = n + 2;  v = v << 2;  }
    if ((v & (0x80000000 as uint)) == (0 as uint)) { n = n + 1; }
    return n;
}

/*
 * _bi_len - significant length of a buffer: n with the trailing zero limbs dropped
 *
 * Buffers are sized for the worst case and trimmed afterwards, so this is what
 * turns "the space the result might have needed" into "the space it used".
 */
private int func _bi_len(uint* d, int n) {
    unsafe {
        while (n > 0 && d[n - 1] == (0 as uint)) { n = n - 1; }
    }
    return n;
}

/*
 * _bi_cmp - compare two magnitudes: -1, 0 or 1
 */
private int func _bi_cmp(uint* a, int an, uint* b, int bn) {
    if (an != bn) { if (an < bn) { return -1; } return 1; }
    unsafe {
        let i = an - 1;
        while (i >= 0) {
            if (a[i] != b[i]) { if (a[i] < b[i]) { return -1; } return 1; }
            i = i - 1;
        }
    }
    return 0;
}

/*
 * _bi_add - r = a + b, an >= bn; writes an limbs and returns the carry out
 */
private uint func _bi_add(uint* r, uint* a, int an, uint* b, int bn) {
    unsafe {
        let carry = (0 as uint64);
        let i = 0;
        while (i < bn) {
            carry = carry + (a[i] as uint64) + (b[i] as uint64);
            r[i] = carry as uint;
            carry = carry >> 32;
            i = i + 1;
        }
        while (i < an) {
            carry = carry + (a[i] as uint64);
            r[i] = carry as uint;
            carry = carry >> 32;
            i = i + 1;
        }
        return carry as uint;
    }
}

/*
 * _bi_addself - a += b in place, an >= bn; the caller guarantees no carry escapes
 */
private void func _bi_addself(uint* a, int an, uint* b, int bn) {
    unsafe {
        let carry = (0 as uint64);
        let i = 0;
        while (i < bn) {
            carry = carry + (a[i] as uint64) + (b[i] as uint64);
            a[i] = carry as uint;
            carry = carry >> 32;
            i = i + 1;
        }
        while (carry != (0 as uint64) && i < an) {
            carry = carry + (a[i] as uint64);
            a[i] = carry as uint;
            carry = carry >> 32;
            i = i + 1;
        }
    }
}

/*
 * _bi_sub - r = a - b, requiring |a| >= |b|; writes an limbs
 */
private void func _bi_sub(uint* r, uint* a, int an, uint* b, int bn) {
    unsafe {
        let borrow = (0 as uint64);
        let i = 0;
        while (i < bn) {
            let d = (a[i] as uint64) - (b[i] as uint64) - borrow;
            r[i] = d as uint;
            borrow = (d >> 32) & (1 as uint64);
            i = i + 1;
        }
        while (i < an) {
            let d = (a[i] as uint64) - borrow;
            r[i] = d as uint;
            borrow = (d >> 32) & (1 as uint64);
            i = i + 1;
        }
    }
}

/*
 * _bi_muladd1 - a = a * m + add, in place; returns the carry out
 */
private uint func _bi_muladd1(uint* a, int an, uint m, uint add) {
    unsafe {
        let carry = add as uint64;
        let i = 0;
        while (i < an) {
            carry = carry + (a[i] as uint64) * (m as uint64);
            a[i] = carry as uint;
            carry = carry >> 32;
            i = i + 1;
        }
        return carry as uint;
    }
}

/*
 * _bi_submul - a -= b * m; returns the borrow out (up to a full limb wide)
 */
private uint func _bi_submul(uint* a, uint* b, int bn, uint m) {
    unsafe {
        let carry = (0 as uint64);
        let i = 0;
        while (i < bn) {
            let p = (b[i] as uint64) * (m as uint64) + carry;
            let lo = p as uint;
            carry = p >> 32;
            let orig = a[i];
            a[i] = orig - lo;
            if (orig < lo) { carry = carry + (1 as uint64); }
            i = i + 1;
        }
        return carry as uint;
    }
}

/*
 * _bi_mul_naive - schoolbook r += a * b, one row of the rhombus per limb of b
 *
 * r_ij + a_j * b_i + c <= (2^32 - 1) + (2^32 - 1)^2 + (2^32 - 1) = 2^64 - 1, so
 * the accumulator never needs a bit the uint64 does not have.
 */
private void func _bi_mul_naive(uint* r, uint* a, int an, uint* b, int bn) {
    unsafe {
        let i = 0;
        while (i < bn) {
            let carry = (0 as uint64);
            let bv = b[i] as uint64;
            let j = 0;
            while (j < an) {
                carry = carry + (r[i + j] as uint64) + (a[j] as uint64) * bv;
                r[i + j] = carry as uint;
                carry = carry >> 32;
                j = j + 1;
            }
            r[i + an] = carry as uint;
            i = i + 1;
        }
    }
}

/*
 * _bi_sqr_naive - schoolbook squaring
 */
private void func _bi_sqr_naive(uint* r, uint* a, int an) {
    unsafe {
        let i = 0;
        while (i < an) {
            let carry = (0 as uint64);
            let v = a[i] as uint64;
            let j = 0;
            while (j < i) {
                let digit1 = (r[i + j] as uint64) + carry;
                let digit2 = (a[j] as uint64) * v;
                r[i + j] = (digit1 + (digit2 << 1)) as uint;
                carry = (digit2 + (digit1 >> 1)) >> 31;
                j = j + 1;
            }
            let digits = v * v + carry;
            r[i + i] = digits as uint;
            r[i + i + 1] = (digits >> 32) as uint;
            i = i + 1;
        }
    }
}

/*
 * _bi_subcore - c -= lo, c -= hi in one pass, with ln >= hn and cn >= ln
 *
 * Karatsuba subtracts two values from the middle term, and doing it in a single
 * run costs one traversal instead of two. The carry is signed: an int64 shifted
 * right by 32 sign-extends to -1 exactly when the limb borrowed.
 */
private void func _bi_subcore(uint* c, int cn, uint* lo, int ln, uint* hi, int hn) {
    unsafe {
        let carry = (0 as int64);
        let i = 0;
        while (i < hn) {
            let d = (c[i] as int64) + carry - (lo[i] as int64) - (hi[i] as int64);
            c[i] = d as uint;
            carry = d >> 32;
            i = i + 1;
        }
        while (i < ln) {
            let d = (c[i] as int64) + carry - (lo[i] as int64);
            c[i] = d as uint;
            carry = d >> 32;
            i = i + 1;
        }
        while (carry != (0 as int64) && i < cn) {
            let d = (c[i] as int64) + carry;
            c[i] = d as uint;
            carry = d >> 32;
            i = i + 1;
        }
    }
}

/*
 * _bi_mul - r = a * b, into a zeroed buffer of an + bn limbs
 *
 * Three regimes, picked on the length of the shorter operand:
 *   schoolbook  - below the threshold, where O(n^2) with a tight loop wins
 *   right-small - b fits entirely in the low half of a, so splitting a alone
 *                 turns one lopsided product into two balanced ones
 *   Karatsuba   - both halves are worth splitting
 */
private void func _bi_mul(uint* r, uint* a, int an, uint* b, int bn) {
    unsafe {
        let xa = a; let xan = an;
        let xb = b; let xbn = bn;
        if (xan < xbn) { xa = b; xan = bn; xb = a; xbn = an; }

        if (xbn < _bi_mul_karatsuba()) { _bi_mul_naive(r, xa, xan, xb, xbn); return; }

        let n = (xan + 1) >> 1;
        if (xbn <= n) { _bi_mul_rsmall(r, xa, xan, xb, xbn, n); return; }
        _bi_mul_kara(r, xa, xan, xb, xbn, n);
    }
}

/*
 * _bi_mul_rsmall - a is split at n, b is not (it is no longer than n)
 *
 * The two partial products overlap in r[n .. n + bn), so that window is lifted
 * out before the high product overwrites it, then added back.
 */
private void func _bi_mul_rsmall(uint* r, uint* a, int an, uint* b, int bn, int n) {
    unsafe {
        _bi_mul(r, a, n, b, bn);

        let carry = _bi_alloc(bn);
        defer _bi_free(carry);
        _bi_copy(carry, r + n, bn);
        Mem.Fill(r + n, 0 as byte, (bn as usize) * sizeof(uint));

        _bi_mul(r + n, a + n, an - n, b, bn);
        _bi_addself(r + n, an + bn - n, carry, bn);
    }
}

/*
 * _bi_mul_kara - Karatsuba: three half-width products instead of four
 *
 *   a = a1<<n + a0,  b = b1<<n + b0
 *   z0 = a0*b0,  z2 = a1*b1,  z1 = (a0+a1)*(b0+b1) - z0 - z2
 *   a*b = z2<<2n + z1<<n + z0
 *
 * z0 and z2 are written straight into their final places in r, so only the
 * middle term needs scratch.
 */
private void func _bi_mul_kara(uint* r, uint* a, int an, uint* b, int bn, int n) {
    unsafe {
        _bi_mul(r, a, n, b, n);
        _bi_mul(r + n + n, a + n, an - n, b + n, bn - n);

        let foldA = _bi_alloc(n + 1);
        defer _bi_free(foldA);
        foldA[n] = _bi_add(foldA, a, n, a + n, an - n);

        let foldB = _bi_alloc(n + 1);
        defer _bi_free(foldB);
        foldB[n] = _bi_add(foldB, b, n, b + n, bn - n);

        let cn = (n + 1) << 1;
        let core = _bi_alloc(cn);
        defer _bi_free(core);
        _bi_mul(core, foldA, n + 1, foldB, n + 1);

        _bi_subcore(core, cn, r, n + n, r + n + n, an + bn - n - n);
        _bi_addself(r + n, an + bn - n, core, _bi_len(core, cn));
    }
}

/*
 * _bi_sqr - r = a * a, into a zeroed buffer of 2 * an limbs
 */
private void func _bi_sqr(uint* r, uint* a, int an) {
    unsafe {
        if (an < _bi_sqr_karatsuba()) { _bi_sqr_naive(r, a, an); return; }

        let n = an >> 1;
        _bi_sqr(r, a, n);
        _bi_sqr(r + n + n, a + n, an - n);

        let fn = an - n + 1;
        let fold = _bi_alloc(fn);
        defer _bi_free(fold);
        fold[fn - 1] = _bi_add(fold, a + n, an - n, a, n);

        let cn = fn << 1;
        let core = _bi_alloc(cn);
        defer _bi_free(core);
        _bi_sqr(core, fold, fn);

        _bi_subcore(core, cn, r + n + n, (an - n) << 1, r, n + n);
        _bi_addself(r + n, (an << 1) - n, core, _bi_len(core, cn));
    }
}

/*
 * _bi_divrem1 - q = a / d, returning a % d, for a single-limb divisor
 *
 * q may alias a: each quotient limb is written only after its dividend limb has
 * been read, so dividing in place is safe.
 */
private uint func _bi_divrem1(uint* q, uint* a, int an, uint d) {
    unsafe {
        let carry = (0 as uint64);
        let i = an - 1;
        while (i >= 0) {
            let v = (carry << 32) | (a[i] as uint64);
            if (q != null) { q[i] = (v / (d as uint64)) as uint; }
            carry = v % (d as uint64);
            i = i - 1;
        }
        return carry as uint;
    }
}

/*
 * _bi_guess_too_big - is q too large for the top three limbs of the dividend?
 *
 * Multiplies the two leading limbs of the divisor by the guess and compares
 * against the three leading limbs of the remaining dividend. Two leading limbs
 * are enough to pin the guess to within one, which is what bounds the correction
 * loop in _bi_divrem to at most two decrements.
 */
private bool func _bi_guess_too_big(uint q, uint64 valHi, uint valLo, uint divHi, uint divLo) {
    let chkHi = (divHi as uint64) * (q as uint64);
    let chkLo = (divLo as uint64) * (q as uint64);
    chkHi = chkHi + (chkLo >> 32);
    chkLo = chkLo & (0xFFFFFFFF as uint64);
    if (chkHi < valHi) { return false; }
    if (chkHi > valHi) { return true; }
    return chkLo > (valLo as uint64);
}

/*
 * _bi_divrem - grammar-school long division
 *
 * a is overwritten with the remainder; q receives qn quotient limbs (pass a null
 * q with qn 0 to compute the remainder alone). Requires an >= bn >= 2 and a
 * normalised divisor (b[bn-1] != 0).
 *
 * The divisor's top limb is shifted so its high bit is set before any guessing
 * happens, which is what makes the leading-limb quotient estimate accurate; the
 * dividend window is shifted by the same amount as it is read, so neither buffer
 * has to be normalised for real.
 */
private void func _bi_divrem(uint* a, int an, uint* b, int bn, uint* q, int qn) {
    unsafe {
        let divHi = b[bn - 1];
        let divLo = (0 as uint);
        if (bn > 1) { divLo = b[bn - 2]; }

        let shift = _bi_clz32(divHi);
        let backShift = 32 - shift;
        if (shift > 0) {
            let divNx = (0 as uint);
            if (bn > 2) { divNx = b[bn - 3]; }
            divHi = (divHi << shift) | (divLo >> backShift);
            divLo = (divLo << shift) | (divNx >> backShift);
        }

        let i = an;
        while (i >= bn) {
            let n = i - bn;

            /* the limb above the window, which the subtraction must consume exactly */
            let t = (0 as uint);
            if (i < an) { t = a[i]; }

            let valHi1 = t;
            let valHi0 = a[i - 1];
            let valLo = (0 as uint);
            if (i > 1) { valLo = a[i - 2]; }

            if (shift > 0) {
                let valNx = (0 as uint);
                if (i > 2) { valNx = a[i - 3]; }
                valHi1 = (valHi1 << shift) | (valHi0 >> backShift);
                valHi0 = (valHi0 << shift) | (valLo >> backShift);
                valLo = (valLo << shift) | (valNx >> backShift);
            }

            let valHi = ((valHi1 as uint64) << 32) | (valHi0 as uint64);

            let digit = 0xFFFFFFFF as uint;
            if (valHi1 < divHi) { digit = (valHi / (divHi as uint64)) as uint; }
            while (_bi_guess_too_big(digit, valHi, valLo, divHi, divLo)) {
                digit = digit - (1 as uint);
            }

            if (digit > (0 as uint)) {
                let borrow = _bi_submul(a + n, b, bn, digit);
                if (borrow != t) {
                    /* the guess was still exactly one too high: give the divisor back */
                    _bi_add(a + n, a + n, bn, b, bn);
                    digit = digit - (1 as uint);
                }
            }

            if (n < qn) { q[n] = digit; }
            if (i < an) { a[i] = 0 as uint; }
            i = i - 1;
        }
    }
}

/*
 * The three bitwise limb operations, named. A BigInt's bitwise operators all walk
 * two's-complement limbs the same way and differ only here, so the walk below is
 * written once and told which operation to apply.
 *
 * These are numbers rather than function values because a file-local function
 * has no address the language can hand out.
 */
private int func _bi_op_and() { return 0; }
private int func _bi_op_or()  { return 1; }
private int func _bi_op_xor() { return 2; }

/*
 * _bi_digit - value of c as a digit in the given radix, or -1
 */
private int func _bi_digit(char c, int radix) {
    let v = -1;
    if (Char.IsDigit(c)) { v = (c - '0') as int; }
    else if (Char.IsLower(c)) { v = ((c - 'a') as int) + 10; }
    else if (Char.IsUpper(c)) { v = ((c - 'A') as int) + 10; }
    if (v < 0 || v >= radix) { return -1; }
    return v;
}


/*
 * ============================================================================
 * BigInt
 * ============================================================================
 */

class BigInt {
    int   sign;   // -1, 0 or +1; 0 exactly when the value is zero
    uint* mag;    // |value| in little-endian 32-bit limbs; null when sign is 0
    int   len;    // significant limbs, so mag[len-1] is never 0; 0 when sign is 0
    int   cap;    // limbs actually allocated, which len may be shorter than

    func _init() {
        self.sign = 0;
        self.mag = null;
        self.len = 0;
        self.cap = 0;
    }

    func _deinit() { _bi_free(self.mag); }

    /*
     * Adopt - Take ownership of a limb buffer and give it a sign
     *
     * Every value in the class is built through here, which is what keeps the
     * canonical form (no leading zero limbs, sign 0 iff no limbs) an invariant
     * rather than something each operation has to remember.
     */
    static BigInt func Adopt(int sign, uint* buf, int cap) {
        let r = new BigInt();
        let n = _bi_len(buf, cap);
        if (n == 0 || sign == 0) {
            _bi_free(buf);
            return r;
        }
        r.sign = sign;
        r.mag = buf;
        r.len = n;
        r.cap = cap;
        return r;
    }

    /*
     * AdoptTwos - Take ownership of a buffer holding a two's-complement value
     *
     * The top limb decides the sign; a negative one is negated in place back
     * into magnitude form. Callers size the buffer one limb beyond the operands
     * so the sign bit is always a real limb and never an overflowed one.
     */
    static BigInt func AdoptTwos(uint* buf, int n) {
        if ((_bi_get(buf, n - 1) & (0x80000000 as uint)) == (0 as uint)) {
            return BigInt.Adopt(1, buf, n);
        }
        let borrow = 1 as uint;
        for (let int i = 0; i < n; i++) {
            let m = _bi_get(buf, i);
            _bi_set(buf, i, (~m) + borrow);
            if (m != (0 as uint)) { borrow = 0 as uint; }
        }
        return BigInt.Adopt(-1, buf, n);
    }

    /*
     * ------------------------------------------------------------------------
     * Construction
     * ------------------------------------------------------------------------
     */

    public static BigInt func Zero()     { return new BigInt(); }
    public static BigInt func One()      { return BigInt.FromInt(1); }
    public static BigInt func MinusOne() { return BigInt.FromInt(-1); }

    /*
     * FromInt - Exact value of an int
     */
    public static BigInt func FromInt(int v) {
        if (v == 0) { return new BigInt(); }
        let m = v as uint;
        let s = 1;
        if (v < 0) { m = (0 as uint) - m; s = -1; }
        let buf = _bi_alloc(1);
        _bi_set(buf, 0, m);
        return BigInt.Adopt(s, buf, 1);
    }

    /*
     * FromLong - Exact value of an int64
     */
    public static BigInt func FromLong(int64 v) {
        if (v == (0 as int64)) { return new BigInt(); }
        let m = v as uint64;
        let s = 1;
        if (v < (0 as int64)) { m = (0 as uint64) - m; s = -1; }
        return BigInt.Adopt(s, BigInt.LimbsOf(m), 2);
    }

    /*
     * FromULong - Exact value of a uint64, whose top bit is a magnitude bit here
     * rather than the sign the signed printer would read it as
     */
    public static BigInt func FromULong(uint64 v) {
        if (v == (0 as uint64)) { return new BigInt(); }
        return BigInt.Adopt(1, BigInt.LimbsOf(v), 2);
    }

    static uint* func LimbsOf(uint64 m) {
        let buf = _bi_alloc(2);
        _bi_set(buf, 0, m as uint);
        _bi_set(buf, 1, (m >> 32) as uint);
        return buf;
    }

    /*
     * Clone - A separate BigInt with the same value
     *
     * Rarely needed, since values are immutable and sharing a reference is
     * always safe; it exists for callers holding a BigInt across a boundary
     * that expects sole ownership.
     */
    public BigInt func Clone() {
        if (self.sign == 0) { return new BigInt(); }
        let buf = _bi_alloc(self.len);
        _bi_copy(buf, self.mag, self.len);
        return BigInt.Adopt(self.sign, buf, self.len);
    }

    /*
     * ------------------------------------------------------------------------
     * Inspection
     * ------------------------------------------------------------------------
     */

    /*
     * Sign - -1, 0 or 1
     */
    public int func Sign() { return self.sign; }

    public bool func IsZero()     { return self.sign == 0; }
    public bool func IsOne()      { return self.sign > 0 && self.len == 1 && _bi_get(self.mag, 0) == (1 as uint); }
    public bool func IsMinusOne() { return self.sign < 0 && self.len == 1 && _bi_get(self.mag, 0) == (1 as uint); }
    public bool func IsNegative() { return self.sign < 0; }

    /*
     * IsEven - Parity, which for a two's-complement negative is still the low
     * magnitude bit
     */
    public bool func IsEven() {
        if (self.sign == 0) { return true; }
        return (_bi_get(self.mag, 0) & (1 as uint)) == (0 as uint);
    }

    /*
     * IsPowerOfTwo - True for a positive value with exactly one bit set
     */
    public bool func IsPowerOfTwo() {
        if (self.sign <= 0) { return false; }
        for (let int i = 0; i < self.len - 1; i++) {
            if (_bi_get(self.mag, i) != (0 as uint)) { return false; }
        }
        let top = _bi_get(self.mag, self.len - 1);
        return (top & (top - (1 as uint))) == (0 as uint);
    }

    /*
     * BitLength - Bits in |value|, so 0 for zero and 1 for +/-1
     */
    public int func BitLength() {
        if (self.sign == 0) { return 0; }
        return self.len * 32 - _bi_clz32(_bi_get(self.mag, self.len - 1));
    }

    /*
     * LimbCount - 32-bit limbs in |value|
     */
    public int func LimbCount() { return self.len; }

    /*
     * TestBit - Bit i of |value|; false past the top bit and for a negative i
     *
     * This reads the MAGNITUDE, not a two's-complement view, so the bits of a
     * negative value are the bits of its absolute value. The exponent walks in
     * ModPow and Pow are what this is for.
     */
    public bool func TestBit(int i) {
        if (i < 0 || self.sign == 0) { return false; }
        let w = i / 32;
        if (w >= self.len) { return false; }
        return ((_bi_get(self.mag, w) >> (i % 32)) & (1 as uint)) != (0 as uint);
    }

    /*
     * ------------------------------------------------------------------------
     * Comparison
     * ------------------------------------------------------------------------
     */

    /*
     * CompareTo - -1, 0 or 1; a null operand compares as zero
     */
    public int func CompareTo(BigInt o) {
        if (o == null) { return self.sign; }
        if (self.sign != o.sign) { if (self.sign < o.sign) { return -1; } return 1; }
        if (self.sign == 0) { return 0; }
        let c = _bi_cmp(self.mag, self.len, o.mag, o.len);
        if (self.sign < 0) { return -c; }
        return c;
    }

    /*
     * == - Value equality. Comparing against the null LITERAL never reaches here
     * (it is a pointer check), which is what lets this body null-guard its
     * operand without recursing.
     */
    public operator bool func ==(BigInt o) {
        if (o == null) { return self.sign == 0; }
        return self.CompareTo(o) == 0;
    }

    public operator bool func < (BigInt o) { return self.CompareTo(o) <  0; }
    public operator bool func > (BigInt o) { return self.CompareTo(o) >  0; }
    public operator bool func <=(BigInt o) { return self.CompareTo(o) <= 0; }
    public operator bool func >=(BigInt o) { return self.CompareTo(o) >= 0; }

    public bool func Equals(BigInt o) { return self == o; }

    public static int func Compare(BigInt a, BigInt b) {
        if (a == null) { if (b == null) { return 0; } return -b.Sign(); }
        return a.CompareTo(b);
    }

    public static BigInt func Min(BigInt a, BigInt b) { if (BigInt.Compare(a, b) <= 0) { return a; } return b; }
    public static BigInt func Max(BigInt a, BigInt b) { if (BigInt.Compare(a, b) >= 0) { return a; } return b; }

    /*
     * ------------------------------------------------------------------------
     * Addition and subtraction
     * ------------------------------------------------------------------------
     */

    /*
     * AddMag - |a| + |b| carrying the given sign
     */
    static BigInt func AddMag(BigInt a, BigInt b, int sign) {
        let x = a;
        let y = b;
        if (x.len < y.len) { x = b; y = a; }
        let n = x.len + 1;
        let buf = _bi_alloc(n);
        _bi_set(buf, x.len, _bi_add(buf, x.mag, x.len, y.mag, y.len));
        return BigInt.Adopt(sign, buf, n);
    }

    /*
     * SubMag - |a| - |b| carrying the given sign, requiring |a| >= |b|
     */
    static BigInt func SubMag(BigInt a, BigInt b, int sign) {
        let buf = _bi_alloc(a.len);
        _bi_sub(buf, a.mag, a.len, b.mag, b.len);
        return BigInt.Adopt(sign, buf, a.len);
    }

    /*
     * + - Sum. Like signs add magnitudes; unlike signs subtract the smaller from
     * the larger and take the larger's sign.
     */
    public operator BigInt func +(BigInt o) {
        if (o == null || o.sign == 0) { return self; }
        if (self.sign == 0) { return o; }
        if (self.sign == o.sign) { return BigInt.AddMag(self, o, self.sign); }
        let c = _bi_cmp(self.mag, self.len, o.mag, o.len);
        if (c == 0) { return new BigInt(); }
        if (c > 0) { return BigInt.SubMag(self, o, self.sign); }
        return BigInt.SubMag(o, self, o.sign);
    }

    /*
     * - - Difference, which is the sum with the right operand's sign flipped
     */
    public operator BigInt func -(BigInt o) {
        if (o == null || o.sign == 0) { return self; }
        if (self.sign == 0) { return BigInt.Negate(o); }
        if (self.sign != o.sign) { return BigInt.AddMag(self, o, self.sign); }
        let c = _bi_cmp(self.mag, self.len, o.mag, o.len);
        if (c == 0) { return new BigInt(); }
        if (c > 0) { return BigInt.SubMag(self, o, self.sign); }
        return BigInt.SubMag(o, self, -o.sign);
    }

    /*
     * - - Negation
     */
    public operator BigInt func -() { return BigInt.Negate(self); }

    public static BigInt func Negate(BigInt v) {
        if (v == null || v.sign == 0) { return new BigInt(); }
        let buf = _bi_alloc(v.len);
        _bi_copy(buf, v.mag, v.len);
        return BigInt.Adopt(-v.sign, buf, v.len);
    }

    /*
     * Abs - |value|. A value that is already non-negative is returned as-is
     * rather than copied, which is safe because a BigInt never changes.
     */
    public static BigInt func Abs(BigInt v) {
        if (v == null || v.sign == 0) { return new BigInt(); }
        if (v.sign > 0) { return v; }
        return BigInt.Negate(v);
    }

    public static BigInt func Add(BigInt a, BigInt b) {
        if (a == null) {
            if (b == null) { return new BigInt(); }
            return b;
        }
        return a + b;
    }

    public static BigInt func Subtract(BigInt a, BigInt b) {
        if (a == null) { return BigInt.Negate(b); }
        return a - b;
    }

    /*
     * ------------------------------------------------------------------------
     * Multiplication
     * ------------------------------------------------------------------------
     */

    /*
     * * - Product. A value multiplied by itself takes the squaring path, which
     * is worth checking for because ModPow's inner loop is exactly that case.
     */
    public operator BigInt func *(BigInt o) {
        if (o == null || o.sign == 0 || self.sign == 0) { return new BigInt(); }
        if (self.mag == o.mag) { return self.Square(); }
        let n = self.len + o.len;
        let buf = _bi_alloc(n);
        _bi_mul(buf, self.mag, self.len, o.mag, o.len);
        return BigInt.Adopt(self.sign * o.sign, buf, n);
    }

    /*
     * Square - value * value, always non-negative
     */
    public BigInt func Square() {
        if (self.sign == 0) { return new BigInt(); }
        let n = self.len << 1;
        let buf = _bi_alloc(n);
        _bi_sqr(buf, self.mag, self.len);
        return BigInt.Adopt(1, buf, n);
    }

    public static BigInt func Multiply(BigInt a, BigInt b) {
        if (a == null || b == null) { return new BigInt(); }
        return a * b;
    }

    /*
     * ------------------------------------------------------------------------
     * Division
     *
     * Truncated, as in C and C#: the quotient rounds toward zero and the
     * remainder carries the DIVIDEND's sign, so a == (a / b) * b + a % b holds
     * for every sign combination.
     * ------------------------------------------------------------------------
     */

    /*
     * DivRem - Quotient, with the remainder written through rem
     *
     * A zero divisor yields zero for both, matching the lenient half of the
     * library's convention; DivRemOrThrow is the strict one.
     */
    public static BigInt func DivRem(BigInt a, BigInt b, ref BigInt rem) {
        rem = new BigInt();
        if (a == null || b == null || a.Sign() == 0 || b.Sign() == 0) { return new BigInt(); }
        if (_bi_cmp(a.mag, a.len, b.mag, b.len) < 0) {
            rem = a;
            return new BigInt();
        }

        let an = a.len;
        let bn = b.len;
        let qn = an - bn + 1;

        /* the dividend is consumed in place and left holding the remainder */
        let work = _bi_alloc(an);
        _bi_copy(work, a.mag, an);
        let qbuf = _bi_alloc(qn);

        if (bn == 1) {
            let r0 = _bi_divrem1(qbuf, work, an, _bi_get(b.mag, 0));
            Mem.Fill(work, 0 as byte, (an as usize) * sizeof(uint));
            _bi_set(work, 0, r0);
        } else {
            _bi_divrem(work, an, b.mag, bn, qbuf, qn);
        }

        let q = BigInt.Adopt(a.sign * b.sign, qbuf, qn);
        rem = BigInt.Adopt(a.sign, work, an);
        return q;
    }

    /*
     * Divide - Quotient alone; zero when the divisor is zero
     */
    public static BigInt func Divide(BigInt a, BigInt b) {
        let BigInt r = null;
        return BigInt.DivRem(a, b, ref r);
    }

    /*
     * Remainder - Remainder alone; zero when the divisor is zero
     */
    public static BigInt func Remainder(BigInt a, BigInt b) {
        let BigInt r = null;
        BigInt.DivRem(a, b, ref r);
        return r;
    }

    /*
     * DivRemOrThrow - Like DivRem but throws on a zero divisor, so a legitimate
     * zero quotient is distinguishable from a refused division
     */
    public static throws BigInt func DivRemOrThrow(BigInt a, BigInt b, ref BigInt rem) {
        if (b == null || b.Sign() == 0) { throw; }
        return BigInt.DivRem(a, b, ref rem);
    }

    public static throws BigInt func DivideOrThrow(BigInt a, BigInt b) {
        if (b == null || b.Sign() == 0) { throw; }
        return BigInt.Divide(a, b);
    }

    public static throws BigInt func RemainderOrThrow(BigInt a, BigInt b) {
        if (b == null || b.Sign() == 0) { throw; }
        return BigInt.Remainder(a, b);
    }

    public operator BigInt func /(BigInt o) { return BigInt.Divide(self, o); }
    public operator BigInt func %(BigInt o) { return BigInt.Remainder(self, o); }

    /*
     * ------------------------------------------------------------------------
     * Shifts
     * ------------------------------------------------------------------------
     */

    /*
     * << - Multiply by 2^shift. A negative shift reads as the opposite shift.
     */
    public operator BigInt func <<(int shift) {
        if (shift < 0) { return self >> (-shift); }
        if (shift == 0 || self.sign == 0) { return self; }

        let dsh = shift / 32;
        let bsh = shift % 32;

        let over = 0 as uint;
        if (bsh != 0) { over = _bi_get(self.mag, self.len - 1) >> (32 - bsh); }

        let n = self.len + dsh;
        if (over != (0 as uint)) { n = n + 1; }
        let buf = _bi_alloc(n);

        if (bsh == 0) {
            _bi_copy_at(buf, dsh, self.mag, 0, self.len);
        } else {
            let carry = 0 as uint;
            for (let int i = 0; i < self.len; i++) {
                let v = _bi_get(self.mag, i);
                _bi_set(buf, dsh + i, (v << bsh) | carry);
                carry = v >> (32 - bsh);
            }
            if (over != (0 as uint)) { _bi_set(buf, dsh + self.len, carry); }
        }
        return BigInt.Adopt(self.sign, buf, n);
    }

    /*
     * >> - Arithmetic shift: divide by 2^shift rounding toward NEGATIVE infinity,
     * so -1 >> 1 is -1 rather than 0.
     *
     * The magnitude is shifted as usual, then a negative value rounds away from
     * zero by one whenever any bit fell off the bottom, since floor(-m / 2^k) is
     * -ceil(m / 2^k).
     */
    public operator BigInt func >>(int shift) {
        if (shift < 0) { return self << (-shift); }
        if (shift == 0 || self.sign == 0) { return self; }

        let dsh = shift / 32;
        let bsh = shift % 32;

        if (dsh >= self.len) {
            if (self.sign < 0) { return BigInt.MinusOne(); }
            return new BigInt();
        }

        let n = self.len - dsh;
        /* one limb of headroom: rounding up can carry out of every limb at once */
        let buf = _bi_alloc(n + 1);

        if (bsh == 0) {
            _bi_copy_at(buf, 0, self.mag, dsh, n);
        } else {
            for (let int i = 0; i < n; i++) {
                let v = _bi_get(self.mag, dsh + i) >> bsh;
                if (dsh + i + 1 < self.len) { v = v | (_bi_get(self.mag, dsh + i + 1) << (32 - bsh)); }
                _bi_set(buf, i, v);
            }
        }

        if (self.sign < 0) {
            let lost = false;
            for (let int i = 0; i < dsh; i++) {
                if (_bi_get(self.mag, i) != (0 as uint)) { lost = true; }
            }
            if (bsh != 0 && (_bi_get(self.mag, dsh) << (32 - bsh)) != (0 as uint)) { lost = true; }
            if (lost) {
                let carry = 1 as uint;
                for (let int i = 0; i < n + 1; i++) {
                    if (carry == (0 as uint)) { break; }
                    let v = _bi_get(buf, i) + carry;
                    _bi_set(buf, i, v);
                    if (v != (0 as uint)) { carry = 0 as uint; }
                }
            }
        }
        return BigInt.Adopt(self.sign, buf, n + 1);
    }

    /*
     * ------------------------------------------------------------------------
     * Bitwise
     *
     * The operators behave as if the value were held in two's complement with
     * infinite sign extension, which is what makes -1 & x == x and ~x == -(x+1)
     * come out right. No temporary two's-complement buffer is built: limbs are
     * converted one at a time as the walk needs them.
     * ------------------------------------------------------------------------
     */

    /*
     * TwosLimb - Limb i of the two's-complement form of self
     *
     * borrow carries the +1 of the negation and must start at 1. It stays 1 only
     * while every limb so far has been zero, which is exactly when the increment
     * is still propagating; past the top limb the result settles at all-ones,
     * which is the sign extension.
     */
    uint func TwosLimb(int i, ref uint borrow) {
        let m = 0 as uint;
        if (i < self.len) { m = _bi_get(self.mag, i); }
        if (self.sign >= 0) { return m; }
        let t = (~m) + borrow;
        if (m != (0 as uint)) { borrow = 0 as uint; }
        return t;
    }

    /*
     * BitwiseOp - Walk both operands in two's complement, applying op limb by limb
     *
     * The result is one limb longer than the widest operand so its own sign bit
     * is a real limb; AND of two non-negatives needs only the narrower one, since
     * anything above it is zero on at least one side.
     */
    static BigInt func BitwiseOp(BigInt a, BigInt b, int op) {
        let xl = a.len; if (xl == 0) { xl = 1; }
        let yl = b.len; if (yl == 0) { yl = 1; }

        let zn = xl;
        if (op == _bi_op_and() && a.sign >= 0 && b.sign >= 0) {
            if (yl < zn) { zn = yl; }
        } else {
            if (yl > zn) { zn = yl; }
        }
        zn = zn + 1;

        let buf = _bi_alloc(zn);
        let xb = 1 as uint;
        let yb = 1 as uint;
        for (let int i = 0; i < zn; i++) {
            let xv = a.TwosLimb(i, ref xb);
            let yv = b.TwosLimb(i, ref yb);
            switch (op) {
                case 0 { _bi_set(buf, i, xv & yv); }
                case 1 { _bi_set(buf, i, xv | yv); }
                default { _bi_set(buf, i, xv ^ yv); }
            }
        }
        return BigInt.AdoptTwos(buf, zn);
    }

    public operator BigInt func &(BigInt o) {
        if (o == null) { return new BigInt(); }
        if (self.sign == 0 || o.sign == 0) { return new BigInt(); }
        return BigInt.BitwiseOp(self, o, _bi_op_and());
    }

    public operator BigInt func |(BigInt o) {
        if (o == null || o.sign == 0) { return self; }
        if (self.sign == 0) { return o; }
        return BigInt.BitwiseOp(self, o, _bi_op_or());
    }

    public operator BigInt func ^(BigInt o) {
        if (o == null || o.sign == 0) { return self; }
        if (self.sign == 0) { return o; }
        return BigInt.BitwiseOp(self, o, _bi_op_xor());
    }

    /*
     * ~ - One's complement, which in two's complement is -(value + 1)
     */
    public operator BigInt func ~() {
        let inc = self + BigInt.One();
        return BigInt.Negate(inc);
    }

    /*
     * ------------------------------------------------------------------------
     * Powers
     * ------------------------------------------------------------------------
     */

    /*
     * Pow - value raised to a non-negative exponent, by square and multiply
     *
     * A negative exponent has no integer value, so it yields zero rather than
     * pretending; use ModPow when you want a modular inverse-style result.
     */
    public static BigInt func Pow(BigInt v, int e) {
        if (e < 0) { return new BigInt(); }
        if (e == 0) { return BigInt.One(); }
        if (v == null || v.Sign() == 0) { return new BigInt(); }

        let result = BigInt.One();
        let b = v;
        let k = e;
        while (k > 0) {
            if ((k & 1) == 1) { result = result * b; }
            k = k >> 1;
            if (k > 0) { b = b.Square(); }
        }
        return result;
    }

    /*
     * ModPow - value^exponent mod modulus, by square and multiply with a
     * reduction after every step so the working values stay modulus-sized
     *
     * The magnitude is computed from |value|, and the sign is applied at the end:
     * the result is negative exactly when value is negative and the exponent is
     * odd, which is the same convention the remainder operator follows.
     *
     * A zero modulus, or a negative exponent, yields zero.
     */
    public static BigInt func ModPow(BigInt v, BigInt e, BigInt m) {
        if (m == null || m.Sign() == 0) { return new BigInt(); }
        if (e == null || e.Sign() < 0) { return new BigInt(); }

        let mm = BigInt.Abs(m);
        if (mm.IsOne()) { return new BigInt(); }
        if (e.Sign() == 0) { return BigInt.One(); }
        if (v == null || v.Sign() == 0) { return new BigInt(); }

        let neg = v.Sign() < 0 && !e.IsEven();

        let result = BigInt.One();
        let b = BigInt.Remainder(BigInt.Abs(v), mm);
        let bits = e.BitLength();

        for (let int i = 0; i < bits; i++) {
            if (e.TestBit(i)) { result = BigInt.Remainder(result * b, mm); }
            if (i + 1 < bits) { b = BigInt.Remainder(b.Square(), mm); }
        }

        if (neg) { return BigInt.Negate(result); }
        return result;
    }

    /*
     * Gcd - Greatest common divisor, always non-negative
     *
     * Plain Euclid over full-width remainders. Lehmer's algorithm would cut the
     * number of big divisions by working on the leading digits first; this does
     * not implement it.
     */
    public static BigInt func Gcd(BigInt a, BigInt b) {
        let x = BigInt.Abs(a);
        let y = BigInt.Abs(b);
        while (y.Sign() != 0) {
            let t = BigInt.Remainder(x, y);
            x = y;
            y = t;
        }
        return x;
    }

    /*
     * ------------------------------------------------------------------------
     * Conversion out
     * ------------------------------------------------------------------------
     */

    /*
     * FitsInt / FitsLong - Whether the value survives ToInt / ToLong unchanged
     */
    public bool func FitsInt() {
        if (self.sign == 0) { return true; }
        if (self.len > 1) { return false; }
        let m = _bi_get(self.mag, 0);
        if (self.sign > 0) { return m <= (0x7FFFFFFF as uint); }
        return m <= (0x80000000 as uint);
    }

    public bool func FitsLong() {
        if (self.sign == 0) { return true; }
        if (self.len > 2) { return false; }
        let m = self.ToMagnitude64();
        if (self.sign > 0) { return m <= (0x7FFFFFFFFFFFFFFF as uint64); }
        return m <= (0x8000000000000000 as uint64);
    }

    uint64 func ToMagnitude64() {
        let m = 0 as uint64;
        if (self.len > 0) { m = _bi_get(self.mag, 0) as uint64; }
        if (self.len > 1) { m = m | ((_bi_get(self.mag, 1) as uint64) << 32); }
        return m;
    }

    /*
     * ToInt / ToLong - The low bits with the sign applied, truncating silently
     * when the value does not fit (ask FitsInt / FitsLong first if that matters)
     */
    public int func ToInt() {
        if (self.sign == 0) { return 0; }
        let m = _bi_get(self.mag, 0);
        if (self.sign < 0) { return ((0 as uint) - m) as int; }
        return m as int;
    }

    public int64 func ToLong() {
        if (self.sign == 0) { return (0 as int64); }
        let m = self.ToMagnitude64();
        if (self.sign < 0) { return ((0 as uint64) - m) as int64; }
        return m as int64;
    }

    /*
     * ToString - Decimal text, with a leading - for negatives
     *
     * Digits come out nine at a time: dividing by 10^9 (the largest power of ten
     * a limb holds) means one pass over the magnitude per nine digits rather than
     * per digit.
     */
    public String func ToString() { return self.ToStringRadix(10); }

    /*
     * ToHex - Lowercase hexadecimal, prefixed with "0x", of the MAGNITUDE with a
     * leading - for negatives - not a two's-complement rendering
     */
    public String func ToHex() {
        if (self.sign == 0) { return "0x0"; }
        let body = self.ToStringRadix(16);
        if (self.sign < 0) { return "-0x" + body.Substring(1, body.Length() - 1); }
        return "0x" + body;
    }

    /*
     * ToStringRadix - Text in a radix from 2 to 36, using 0-9 then a-z
     *
     * Out-of-range radices fall back to 10.
     */
    public String func ToStringRadix(int radix) {
        if (radix < 2 || radix > 36) { radix = 10; }
        if (self.sign == 0) { return "0"; }

        /* the largest power of the radix that still fits in one limb */
        let chunkDiv = radix as uint;
        let chunkLen = 1;
        while (chunkDiv <= (0xFFFFFFFF as uint) / (radix as uint)) {
            chunkDiv = chunkDiv * (radix as uint);
            chunkLen = chunkLen + 1;
        }

        /* floor(log2(radix)) under-counts the bits a digit carries, so dividing
           by it over-counts the digits, which is the direction a buffer wants */
        let bitsPerDigit = 1;
        while ((1 << (bitsPerDigit + 1)) <= radix) { bitsPerDigit = bitsPerDigit + 1; }
        let cap = (self.BitLength() / bitsPerDigit) + 2;

        unsafe {
            let text = alloc((cap as usize) * sizeof(char)) as char*;
            defer free(text);

            let work = _bi_alloc(self.len);
            defer _bi_free(work);
            _bi_copy(work, self.mag, self.len);

            let wn = self.len;
            let pos = cap;
            while (wn > 0) {
                let rem = _bi_divrem1(work, work, wn, chunkDiv);
                wn = _bi_len(work, wn);
                let k = 0;
                while (k < chunkLen) {
                    pos = pos - 1;
                    let d = (rem % (radix as uint)) as int;
                    if (d < 10) { text[pos] = ('0' + d) as char; }
                    else { text[pos] = ('a' + d - 10) as char; }
                    rem = rem / (radix as uint);
                    k = k + 1;
                    /* stop mid-chunk only once the whole value is exhausted, so
                       interior chunks keep their leading zeros */
                    if (wn == 0 && rem == (0 as uint)) { break; }
                }
            }
            if (self.sign < 0) { pos = pos - 1; text[pos] = '-'; }
            return String.FromBuffer(text + pos, cap - pos);
        }
    }

    /*
     * ------------------------------------------------------------------------
     * Parsing
     * ------------------------------------------------------------------------
     */

    /*
     * Parse - Lenient decimal parse: skips leading whitespace, takes an optional
     * sign, stops at the first non-digit; null, empty and invalid all give zero
     * (mirrors Int.Parse)
     */
    public static BigInt func Parse(String s) { return BigInt.ParseRadix(s, 10); }

    /*
     * ParseRadix - Parse in a radix from 2 to 36, lenient in the same way
     */
    public static BigInt func ParseRadix(String s, int radix) {
        if (s == null || radix < 2 || radix > 36) { return new BigInt(); }

        let n = s.Length();
        let i = 0;
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }

        let neg = false;
        if (i < n && (s.CharAt(i) == '-' || s.CharAt(i) == '+')) {
            neg = s.CharAt(i) == '-';
            i = i + 1;
        }
        return BigInt.Accumulate(s, i, n, radix, neg);
    }

    /*
     * ParseStrict - Like Parse but throws unless the whole string is one clean
     * integer, which is what distinguishes "invalid" from a legitimate 0
     */
    public static throws BigInt func ParseStrict(String s) {
        let v = BigInt.ParseStrictRadix(s, 10);
        return v;
    }

    public static throws BigInt func ParseStrictRadix(String s, int radix) {
        if (s == null || radix < 2 || radix > 36) { throw; }

        let n = s.Length();
        let i = 0;
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }

        let neg = false;
        if (i < n && (s.CharAt(i) == '-' || s.CharAt(i) == '+')) {
            neg = s.CharAt(i) == '-';
            i = i + 1;
        }
        if (i >= n || _bi_digit(s.CharAt(i), radix) < 0) { throw; }

        let start = i;
        while (i < n && _bi_digit(s.CharAt(i), radix) >= 0) { i = i + 1; }
        let stop = i;
        while (i < n && Char.IsWhitespace(s.CharAt(i))) { i = i + 1; }
        if (i != n) { throw; }

        return BigInt.Accumulate(s, start, stop, radix, neg);
    }

    /*
     * Accumulate - Read digits from [from, to) in the radix into a magnitude
     *
     * Digits are folded a chunk at a time for the same reason ToStringRadix
     * emits them a chunk at a time: one multiply-and-add over the whole
     * magnitude per chunkLen digits instead of per digit.
     */
    static BigInt func Accumulate(String s, int from, int to, int radix, bool neg) {
        let chunkMul = radix as uint;
        let chunkLen = 1;
        while (chunkMul <= (0xFFFFFFFF as uint) / (radix as uint)) {
            chunkMul = chunkMul * (radix as uint);
            chunkLen = chunkLen + 1;
        }

        let bitsPerDigit = 1;
        while ((1 << bitsPerDigit) < radix) { bitsPerDigit = bitsPerDigit + 1; }
        let cap = ((to - from) * bitsPerDigit) / 32 + 2;

        let buf = _bi_alloc(cap);
        let len = 0;

        let i = from;
        while (i < to) {
            let mul = 1 as uint;
            let acc = 0 as uint;
            let k = 0;
            while (k < chunkLen && i < to) {
                let d = _bi_digit(s.CharAt(i), radix);
                if (d < 0) { break; }
                acc = acc * (radix as uint) + (d as uint);
                mul = mul * (radix as uint);
                i = i + 1;
                k = k + 1;
            }
            if (k == 0) { break; }

            let carry = _bi_muladd1(buf, len, mul, acc);
            if (carry != (0 as uint)) {
                _bi_set(buf, len, carry);
                len = len + 1;
            }
        }

        let sign = 1;
        if (neg) { sign = -1; }
        return BigInt.Adopt(sign, buf, cap);
    }
}
