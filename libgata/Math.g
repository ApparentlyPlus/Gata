// Math.g — the floating-point math library, a pure-Gata port of fdlibm.
//
//   module Math — double-precision. Float works in any realm (GatOS handles the FPU
//   per-file, restricting SSE only in interrupt-context code), so Math is realm-free.
//
// This is a faithful translation of GatOS's ulibc/math.c (itself based on fdlibm).
// It is pure numeric policy and depends on NOTHING from the environment — so wherever
// libgata compiles, Math compiles. (Float-to-text now lives in Format.g, not here.)
// The bit-level double<->uint64 punning that fdlibm performs through a `union { double;
// uint64; }` is expressed here with the `bits` / `frombits` reinterpret helpers.
//
// Translation notes (this port predates Gata's ternary; it uses union/switch/goto
// rewrites throughout):
//   * a `dbl_cast dc` becomes a single uint64 holding the bit pattern; `dc.f` reads
//     are `frombits(u)`, `dc.f = e` is `u = bits(e)`, `dc.u` is just `u`.
//   * `a ? b : c` is rewritten into if/else; `switch` into if/else chains; the one
//     `goto recompute` (in __kernel_rem_pio2) into a `while (true)` loop.
//   * explicit `as` casts are inserted wherever C narrows implicitly, so the emitted
//     C performs the exact same conversions fdlibm relies on.

module Math {
    // ── Bit reinterpretation (the fdlibm dbl_cast union) ──────────────────────
    /// Raw IEEE-754 bits of a double.
    uint64 func bits(double x) {
        unsafe {
            let p = (&x) as uint64*;
            return *p;
        }
    }
    /// The double with the given raw IEEE-754 bit pattern.
    double func frombits(uint64 u) {
        unsafe {
            let p = (&u) as double*;
            return *p;
        }
    }

    // ── Constants (public) ────────────────────────────────────────────────────
    /// The ratio of a circle's circumference to its diameter.
    public double func Pi() { return 3.141592653589793; }
    /// Euler's number.
    public double func E()  { return 2.718281828459045; }

    // ══ Utility functions ═════════════════════════════════════════════════════
    double func fabs(double x) {
        let u = bits(x) & 0x7FFFFFFFFFFFFFFFULL;
        return frombits(u);
    }

    double func copysign(double x, double y) {
        let ux = (bits(x) & 0x7FFFFFFFFFFFFFFFULL) | (bits(y) & 0x8000000000000000ULL);
        return frombits(ux);
    }

    double func scalbn(double x, int n) {
        let u = bits(x);
        let hx = ((u >> 32) as int);
        let lx = (u as uint);
        let k = (hx & 0x7ff00000) >> 20;

        if (k == 0) {
            if ((lx | (hx & 0x7fffffff)) == 0) { return x; }
            x = x * 1.80143985094819840000e+16;
            u = bits(x);
            hx = ((u >> 32) as int);
            k = ((hx & 0x7ff00000) >> 20) - 54;
            if (n < -50000) { return 1.0e-300 * x; }
        }
        if (k == 0x7ff) { return x + x; }
        k = k + n;
        if (k > 0x7fe) { return 1.0e+300 * copysign(1.0e+300, x); }
        if (k > 0) {
            u = (u & 0x800fffffffffffffULL) | ((k as uint64) << 52);
            return frombits(u);
        }
        if (k <= -54) {
            if (n > 50000) { return 1.0e+300 * copysign(1.0e+300, x); }
            return 1.0e-300 * copysign(1.0e-300, x);
        }
        k = k + 54;
        u = (u & 0x800fffffffffffffULL) | ((k as uint64) << 52);
        return frombits(u) * 5.55111512312578270212e-17;
    }

    double func floor(double x) {
        let u = bits(x);
        let i0 = ((u >> 32) as int);
        let i1 = (u as uint);
        let j0 = ((i0 >> 20) & 0x7ff) - 0x3ff;

        if (j0 < 20) {
            if (j0 < 0) {
                if (i0 >= 0) {
                    i0 = 0;
                    i1 = (0 as uint);
                } else {
                    if (((i0 & 0x7fffffff) | (i1 as int)) != 0) {
                        i0 = (0xbff00000 as int);
                        i1 = (0 as uint);
                    }
                }
            } else {
                let i = (0x000fffff as uint) >> j0;
                if ((((i0 as uint) & i) | i1) == 0) { return x; }
                if (i0 < 0) { i0 = i0 + ((0x00100000 as int) >> j0); }
                i0 = i0 & ((~i) as int);
                i1 = (0 as uint);
            }
        } else {
            if (j0 > 51) {
                if (j0 == 0x400) { return x + x; }
                return x;
            }
            let i = (0xffffffff as uint) >> (j0 - 20);
            if ((i1 & i) == 0) { return x; }
            if (i0 < 0) {
                if (j0 == 20) {
                    i0 = i0 + 1;
                } else {
                    let j = i1 + ((1 as uint) << (52 - j0));
                    if (j < i1) { i0 = i0 + 1; }
                    i1 = j;
                }
            }
            i1 = i1 & (~i);
        }
        u = (((i0 as uint) as uint64) << 32) | (i1 as uint64);
        return frombits(u);
    }

    double func ceil(double x) {
        let u = bits(x);
        let i0 = ((u >> 32) as int);
        let i1 = (u as uint);
        let j0 = ((i0 >> 20) & 0x7ff) - 0x3ff;

        if (j0 < 20) {
            if (j0 < 0) {
                if (1.0e+300 + x > 0.0) {
                    if (i0 < 0) {
                        i0 = (0x80000000 as int);
                        i1 = (0 as uint);
                    } else {
                        if (((i0 as uint) | i1) != 0) {
                            i0 = (0x3ff00000 as int);
                            i1 = (0 as uint);
                        }
                    }
                }
            } else {
                let i = (0x000fffff as uint) >> j0;
                if ((((i0 as uint) & i) | i1) == 0) { return x; }
                if (1.0e+300 + x > 0.0) {
                    if (i0 > 0) { i0 = i0 + ((0x00100000 as int) >> j0); }
                    i0 = i0 & ((~i) as int);
                    i1 = (0 as uint);
                }
            }
        } else {
            if (j0 > 51) {
                if (j0 == 0x400) { return x + x; }
                return x;
            }
            let i = (0xffffffff as uint) >> (j0 - 20);
            if ((i1 & i) == 0) { return x; }
            if (1.0e+300 + x > 0.0) {
                if (i0 > 0) {
                    if (j0 == 20) {
                        i0 = i0 + 1;
                    } else {
                        let j = i1 + ((1 as uint) << (52 - j0));
                        if (j < i1) { i0 = i0 + 1; }
                        i1 = j;
                    }
                }
                i1 = i1 & (~i);
            }
        }
        u = (((i0 as uint) as uint64) << 32) | (i1 as uint64);
        return frombits(u);
    }

    double func trunc(double x) {
        let u = bits(x);
        let i0 = ((u >> 32) as int);
        let i1 = (u as uint);
        let j0 = ((i0 >> 20) & 0x7ff) - 0x3ff;
        let sx = ((i0 as uint) >> 31);

        if (j0 < 20) {
            if (j0 < 0) {
                if (sx != 0) { return -0.0; }
                return 0.0;
            }
            i0 = i0 & ((~((0x000fffff as uint) >> j0)) as int);
            i1 = (0 as uint);
        } else {
            if (j0 > 51) {
                if (j0 == 0x400) { return x + x; }
                return x;
            }
            i1 = i1 & (~((0xffffffff as uint) >> (j0 - 20)));
        }
        u = (((i0 as uint) as uint64) << 32) | (i1 as uint64);
        return frombits(u);
    }

    double func round(double x) {
        let u = bits(x);
        let i0 = ((u >> 32) as int);
        let i1 = (u as uint);
        let j0 = ((i0 >> 20) & 0x7ff) - 0x3ff;

        if (j0 < 20) {
            if (j0 < 0) {
                if (1.0e+300 + x > 0.0) {
                    i0 = i0 & (0x80000000 as int);
                    if (j0 == -1) { i0 = i0 | (0x3ff00000 as int); }
                    i1 = (0 as uint);
                }
            } else {
                let i = (0x000fffff as uint) >> j0;
                if ((((i0 as uint) & i) | i1) == 0) { return x; }
                if (1.0e+300 + x > 0.0) {
                    i0 = i0 + ((0x00080000 as int) >> j0);
                    i0 = i0 & ((~i) as int);
                    i1 = (0 as uint);
                }
            }
        } else {
            if (j0 > 51) {
                if (j0 == 0x400) { return x + x; }
                return x;
            }
            let i = (0xffffffff as uint) >> (j0 - 20);
            if ((i1 & i) == 0) { return x; }
            if (1.0e+300 + x > 0.0) {
                let j = i1 + ((0x80000000 as uint) >> (j0 - 20));
                if (j < i1) { i0 = i0 + 1; }
                i1 = j & (~i);
            }
        }
        u = (((i0 as uint) as uint64) << 32) | (i1 as uint64);
        return frombits(u);
    }

    // ══ Square root ═══════════════════════════════════════════════════════════
    double func sqrt(double number) {
        if (number < 0.0) { return (number - number) / (number - number); }
        if (number == 0.0) { return 0.0; }

        let i = bits(number);

        // Handle denormals by scaling
        if ((i & 0x7FF0000000000000ULL) == 0) {
            number = number * 18014398509481984.0;   // 2^54
            i = bits(number);
            i = 0x5fe6eb50c7b537a9ULL - (i >> 1);
            let y = frombits(i);
            y = y * (1.5 - (number * 0.5 * y * y));
            y = y * (1.5 - (number * 0.5 * y * y));
            y = y * (1.5 - (number * 0.5 * y * y));
            y = y * (1.5 - (number * 0.5 * y * y));
            return (number * y) * 7.450580596923828125e-09;   // 2^-27
        }

        i = 0x5fe6eb50c7b537a9ULL - (i >> 1);
        let y = frombits(i);
        y = y * (1.5 - (number * 0.5 * y * y));
        y = y * (1.5 - (number * 0.5 * y * y));
        y = y * (1.5 - (number * 0.5 * y * y));
        y = y * (1.5 - (number * 0.5 * y * y));
        return number * y;
    }

    // ── Shared fdlibm constants (kept as accessors so log/exp/log1p agree) ────
    double func k_ln2hi() { return 6.93147180369123816490e-01; }
    double func k_ln2lo() { return 1.90821492927058770002e-10; }
    double func k_lg1()   { return 6.666666666666735130e-01; }
    double func k_lg2()   { return 3.999999999940941908e-01; }
    double func k_lg3()   { return 2.857142874366239149e-01; }
    double func k_lg4()   { return 2.222219843214978396e-01; }
    double func k_lg5()   { return 1.818357216161805012e-01; }
    double func k_lg6()   { return 1.531383769920937332e-01; }
    double func k_lg7()   { return 1.479819860511658591e-01; }

    // ══ Logarithm and exponential ════════════════════════════════════════════
    double func log(double x) {
        let u = bits(x);
        let b = u;

        if ((b & 0x7FFFFFFFFFFFFFFFULL) == 0) { return -1.0 / 0.0; }
        if ((b >> 63) != 0) { return 0.0 / 0.0; }
        if ((b & 0x7FF0000000000000ULL) == 0x7FF0000000000000ULL) { return x; }

        let hx = ((b >> 32) as int);
        let k = (hx >> 20) - 1023;

        if ((hx & 0x7ff00000) == 0) {
            x = x * 18014398509481984.0;   // 2^54
            u = bits(x);
            b = u;
            hx = ((b >> 32) as int);
            k = ((hx >> 20) - 1023) - 54;
        }

        hx = hx & 0x000fffff;
        let i = (hx + 0x95f64) & 0x100000;
        u = (b & 0x000fffffffffffffULL) | (((i ^ 0x3ff00000) as uint64) << 32);
        k = k + (i >> 20);

        let f = frombits(u) - 1.0;
        let dk = (k as double);

        if ((hx + 2) < 5) {
            if (f == 0.0) { return dk * k_ln2hi() + dk * k_ln2lo(); }
            let r0 = f * f * (0.5 - 0.33333333333333333 * f);
            return dk * k_ln2hi() - ((r0 - dk * k_ln2lo()) - f);
        }

        let s = f / (2.0 + f);
        let z = s * s;
        let w = z * z;
        let t1 = w * (k_lg2() + w * (k_lg4() + w * k_lg6()));
        let t2 = z * (k_lg1() + w * (k_lg3() + w * (k_lg5() + w * k_lg7())));
        let r = t1 + t2;
        let hfsq = 0.5 * f * f;

        i = hx - 0x6147a;
        let j = 0x6b851 - hx;

        if ((i | j) > 0) {
            return dk * k_ln2hi() - ((hfsq - (s * (hfsq + r) + dk * k_ln2lo())) - f);
        }
        return dk * k_ln2hi() - ((s * (f - r) - dk * k_ln2lo()) - f);
    }

    double func exp(double x) {
        let u = bits(x);
        let hx = ((u >> 32) as uint);
        let xsb = (((hx >> 31) & 1) as int);
        hx = hx & 0x7fffffff;

        if (hx >= 0x40862E42) {
            if (hx >= 0x7ff00000) {
                let lx = ((u & 0xFFFFFFFF) as uint);
                if (((hx & 0xfffff) | lx) != 0) { return x + x; }
                if (xsb == 0) { return x; }
                return 0.0;
            }
            if (x > 7.09782712893383973096e+02) { return 1e300 * 1e300; }
            if (x < -7.45133219101941108420e+02) { return 1e-300 * 1e-300; }
        }

        let k = 0;
        let hi = 0.0;
        let lo = 0.0;
        let c = 0.0;
        let t = 0.0;

        if (hx > 0x3fd62e42) {
            if (hx < 0x3FF0A2B2) {
                let hival = k_ln2hi();
                let loval = k_ln2lo();
                if (xsb != 0) { hival = -k_ln2hi(); loval = -k_ln2lo(); }
                hi = x - hival;
                lo = loval;
                k = 1 - xsb - xsb;
            } else {
                let half = 0.5;
                if (xsb != 0) { half = -0.5; }
                k = ((1.44269504088896338700e+00 * x + half) as int);
                t = (k as double);
                hi = x - t * k_ln2hi();
                lo = t * k_ln2lo();
            }
            x = hi - lo;
        } else {
            if (hx < 0x3e300000) { return 1.0 + x; }
            k = 0;
        }

        t = x * x;
        c = x - t * (1.66666666666666019037e-01 + t * (-2.77777777770155933842e-03 + t * (6.61375632143793436117e-05 + t * (-1.65339022054652515390e-06 + t * 4.13813679705723846039e-08))));

        if (k == 0) { return 1.0 - ((x * c) / (c - 2.0) - x); }
        let y = 1.0 - ((lo - (x * c) / (2.0 - c)) - hi);

        if (k >= -1021) {
            let uy = bits(y);
            uy = uy + ((k as uint64) << 52);
            return frombits(uy);
        }
        let uz = bits(y);
        uz = uz + (((k + 1000) as uint64) << 52);
        return frombits(uz) * 9.33263618503218878990e-302;
    }

    double func expm1(double x) {
        let u = bits(x);
        let hx = ((u >> 32) as uint);
        let xsb = (hx & 0x80000000);
        let y = x;
        if (xsb != 0) { y = -x; }
        hx = hx & 0x7fffffff;

        let hi = 0.0;
        let lo = 0.0;
        let c = 0.0;
        let t = 0.0;
        let e = 0.0;
        let k = 0;

        if (hx >= 0x4043687A) {
            if (hx >= 0x40862E42) {
                if (hx >= 0x7ff00000) {
                    let lx = (u as uint);
                    if (((hx & 0xfffff) | lx) != 0) { return x + x; }
                    if (xsb == 0) { return x; }
                    return -1.0;
                }
                if (x > 7.09782712893383973096e+02) { return 1.0e+300 * 1.0e+300; }
            }
            if (xsb != 0) {
                if (x + 1.0e-300 < 0.0) { return 1.0e-300 - 1.0; }
            }
        }

        if (hx > 0x3fd62e42) {
            if (hx < 0x3FF0A2B2) {
                if (xsb == 0) {
                    hi = x - k_ln2hi();
                    lo = k_ln2lo();
                    k = 1;
                } else {
                    hi = x + k_ln2hi();
                    lo = -k_ln2lo();
                    k = -1;
                }
            } else {
                let half = 0.5;
                if (xsb != 0) { half = -0.5; }
                k = ((1.44269504088896338700e+00 * x + half) as int);
                t = (k as double);
                hi = x - t * k_ln2hi();
                lo = t * k_ln2lo();
            }
            x = hi - lo;
            c = (hi - x) - lo;
        } else {
            if (hx < 0x3c900000) {
                t = 1.0e+300 + x;
                return x - (t - (1.0e+300 + x));
            }
            k = 0;
            c = 0.0;
        }

        let hfx = 0.5 * x;
        let hxs = x * hfx;
        let r1 = 1.0 + hxs * (-3.33333333333331316428e-02 + hxs * (1.58730158725481460165e-03 + hxs * (-7.93650757867487942473e-05 + hxs * (4.00821782732936239552e-06 + hxs * -2.01099218183624371326e-07))));
        t = 3.0 - r1 * hfx;
        e = hxs * ((r1 - t) / (6.0 - x * t));

        if (k == 0) { return x - (x * e - hxs); }

        e = (x * (e - c) - c);
        e = e - hxs;

        if (k == -1) { return 0.5 * (x - e) - 0.5; }
        if (k == 1) {
            if (x < -0.25) { return -2.0 * (e - (x + 0.5)); }
            return 1.0 + 2.0 * (x - e);
        }
        if (k <= -2 || k > 56) {
            y = 1.0 - (e - x);
            let uy = bits(y);
            uy = uy + ((k as uint64) << 52);
            return frombits(uy) - 1.0;
        }

        let u2 = bits(1.0);
        if (k < 20) {
            u2 = (0x3ff00000ULL - (0x200000ULL >> k)) << 32;
            y = frombits(u2) - (e - x);
            u2 = bits(y);
            u2 = u2 + ((k as uint64) << 52);
        } else {
            u2 = (0x3ffULL - (k as uint64)) << 52;
            t = frombits(u2);
            y = x - (e + t);
            y = y + 1.0;
            u2 = bits(y);
            u2 = u2 + ((k as uint64) << 52);
        }
        return frombits(u2);
    }

    double func log1p(double x) {
        let u0 = bits(x);
        let hx_ = ((u0 >> 32) as int);
        let ax = hx_ & 0x7fffffff;

        let f = 0.0;
        let c = 0.0;
        let k = 1;
        let hu = 0;

        if (hx_ < 0x3FDA827A) {
            if (ax >= 0x3ff00000) {
                if (x == -1.0) { return -1.80143985094819840000e+16 / 0.0; }
                return (x - x) / (x - x);
            }
            if (ax < 0x3e200000) {
                if (1.80143985094819840000e+16 + x > 0.0 && ax < 0x3c900000) { return x; }
                return x - x * x * 0.5;
            }
            if (hx_ > 0 || hx_ <= (0xbfd2bec3 as int)) {
                k = 0;
                f = x;
                hu = 1;
            }
        }
        if (hx_ >= 0x7ff00000) { return x + x; }
        if (k != 0) {
            let uu = 0.0;
            if (hx_ < 0x43400000) {
                uu = 1.0 + x;
                let ub = bits(uu);
                hu = ((ub >> 32) as int);
                k = (hu >> 20) - 1023;
                if (k > 0) { c = 1.0 - (uu - x); } else { c = x - (uu - 1.0); }
                c = c / uu;
            } else {
                uu = x;
                let ub = bits(uu);
                hu = ((ub >> 32) as int);
                k = (hu >> 20) - 1023;
                c = 0.0;
            }
            hu = hu & 0x000fffff;
            if (hu < 0x6a09e) {
                let ub = bits(uu);
                ub = (ub & 0x800fffff00000000ULL) | 0x3ff0000000000000ULL;
                uu = frombits(ub);
            } else {
                k = k + 1;
                let ub = bits(uu);
                ub = (ub & 0x800fffff00000000ULL) | 0x3fe0000000000000ULL;
                uu = frombits(ub);
                hu = (0x00100000 - hu) >> 2;
            }
            f = uu - 1.0;
        }
        let hfsq = 0.5 * f * f;
        if (hu == 0) {
            if (f == 0.0) {
                if (k == 0) { return 0.0; }
                c = c + (k as double) * k_ln2lo();
                return (k as double) * k_ln2hi() + c;
            }
            let r0 = hfsq * (1.0 - 0.66666666666666666 * f);
            if (k == 0) { return f - r0; }
            return (k as double) * k_ln2hi() - ((r0 - ((k as double) * k_ln2lo() + c)) - f);
        }
        let s = f / (2.0 + f);
        let z = s * s;
        let r = z * (k_lg1() + z * (k_lg2() + z * (k_lg3() + z * (k_lg4() + z * (k_lg5() + z * (k_lg6() + z * k_lg7()))))));
        if (k == 0) { return f - (hfsq - s * (hfsq + r)); }
        return (k as double) * k_ln2hi() - ((hfsq - (s * (hfsq + r) + ((k as double) * k_ln2lo() + c))) - f);
    }

    // ══ Floating remainder ════════════════════════════════════════════════════
    double func fmod(double x, double y) {
        let ux = bits(x);
        let uy = bits(y);
        let hx = ((ux >> 32) as int);
        let lx = (ux as uint);
        let hy = ((uy >> 32) as int);
        let ly = (uy as uint);
        let sx = ((hx & 0x80000000) as int);
        hx = hx ^ sx;
        hy = hy & 0x7fffffff;

        if ((hy | (ly as int)) == 0 || hx >= 0x7ff00000 ||
            ((hy | (((ly | (0 - ly)) >> 31) as int)) > 0x7ff00000)) {
            return (x * y) / (x * y);
        }
        if (hx <= hy) {
            if (hx < hy || lx < ly) { return x; }
            if (lx == ly) { return 0.0 * x; }
        }

        let ix = 0;
        let iy = 0;
        let i = 0;
        let n = 0;

        if (hx < 0x00100000) {
            if (hx == 0) {
                ix = -1043;
                i = (lx as int);
                while (i > 0) { ix = ix - 1; i = i << 1; }
            } else {
                ix = -1022;
                i = (hx << 11);
                while (i > 0) { ix = ix - 1; i = i << 1; }
            }
        } else {
            ix = (hx >> 20) - 1023;
        }

        if (hy < 0x00100000) {
            if (hy == 0) {
                iy = -1043;
                i = (ly as int);
                while (i > 0) { iy = iy - 1; i = i << 1; }
            } else {
                iy = -1022;
                i = (hy << 11);
                while (i > 0) { iy = iy - 1; i = i << 1; }
            }
        } else {
            iy = (hy >> 20) - 1023;
        }

        if (ix >= -1022) {
            hx = 0x00100000 | (0x000fffff & hx);
        } else {
            n = -1022 - ix;
            if (n <= 31) {
                hx = (hx << n) | ((lx >> (32 - n)) as int);
                lx = lx << n;
            } else {
                hx = (lx << (n - 32)) as int;
                lx = (0 as uint);
            }
        }
        if (iy >= -1022) {
            hy = 0x00100000 | (0x000fffff & hy);
        } else {
            n = -1022 - iy;
            if (n <= 31) {
                hy = (hy << n) | ((ly >> (32 - n)) as int);
                ly = ly << n;
            } else {
                hy = (ly << (n - 32)) as int;
                ly = (0 as uint);
            }
        }

        let hz = 0;
        let lz = (0 as uint);
        n = ix - iy;
        while (n != 0) {
            n = n - 1;
            hz = hx - hy;
            lz = lx - ly;
            if (lx < ly) { hz = hz - 1; }
            if (hz < 0) {
                hx = hx + hx + ((lx >> 31) as int);
                lx = lx + lx;
            } else {
                if ((hz | (lz as int)) == 0) { return 0.0 * x; }
                hx = hz + hz + ((lz >> 31) as int);
                lx = lz + lz;
            }
        }
        hz = hx - hy;
        lz = lx - ly;
        if (lx < ly) { hz = hz - 1; }
        if (hz >= 0) {
            hx = hz;
            lx = lz;
        }

        if ((hx | (lx as int)) == 0) { return 0.0 * x; }
        while (hx < 0x00100000) {
            hx = hx + hx + ((lx >> 31) as int);
            lx = lx + lx;
            iy = iy - 1;
        }
        if (iy >= -1022) {
            hx = (hx - 0x00100000) | ((iy + 1023) << 20);
            ux = (((hx as uint) as uint64) << 32) | (lx as uint64);
        } else {
            n = -1022 - iy;
            if (n <= 20) {
                lx = (lx >> n) | (((hx as uint) << (32 - n)));
                hx = hx >> n;
            } else {
                if (n <= 31) {
                    lx = ((hx << (32 - n)) as uint) | (lx >> n);
                    hx = sx;
                } else {
                    lx = ((hx >> (n - 32)) as uint);
                    hx = sx;
                }
            }
            ux = (((hx as uint) as uint64) << 32) | (lx as uint64);
            x = frombits(ux);
            x = x * 1.0;
            ux = bits(x);
        }
        ux = ux | ((sx as uint64) << 32);
        return frombits(ux);
    }

    // ══ Power ═════════════════════════════════════════════════════════════════
    double func pow(double x, double y) {
        let z = 0.0;
        let ax = 0.0;
        let p_h = 0.0;
        let p_l = 0.0;
        let y1 = 0.0;
        let t1 = 0.0;
        let t2 = 0.0;
        let r = 0.0;
        let s = 0.0;
        let t = 0.0;
        let u = 0.0;
        let v = 0.0;
        let w = 0.0;
        let i = 0;
        let j = 0;
        let k = 0;
        let yisint = 0;
        let n = 0;

        let ux = bits(x);
        let uy = bits(y);
        let hx = ((ux >> 32) as int);
        let lx = (ux as uint);
        let hy = ((uy >> 32) as int);
        let ly = (uy as uint);
        let ix = hx & 0x7fffffff;
        let iy = hy & 0x7fffffff;

        if ((iy | (ly as int)) == 0) { return 1.0; }
        if (hx == 0x3ff00000 && lx == 0) { return 1.0; }
        if (ix > 0x7ff00000 || (ix == 0x7ff00000 && lx != 0) ||
            iy > 0x7ff00000 || (iy == 0x7ff00000 && ly != 0)) {
            return x + y;
        }

        yisint = 0;
        if (hx < 0) {
            if (iy >= 0x43400000) {
                yisint = 2;
            } else {
                if (iy >= 0x3ff00000) {
                    k = (iy >> 20) - 0x3ff;
                    if (k > 20) {
                        j = ((ly >> (52 - k)) as int);
                        if ((j << (52 - k)) == (ly as int)) { yisint = 2 - (j & 1); }
                    } else {
                        if (ly == 0) {
                            j = iy >> (20 - k);
                            if ((j << (20 - k)) == iy) { yisint = 2 - (j & 1); }
                        }
                    }
                }
            }
        }

        if (ly == 0) {
            if (iy == 0x7ff00000) {
                if (((ix - 0x3ff00000) | (lx as int)) == 0) { return y - y; }
                if (ix >= 0x3ff00000) {
                    if (hy >= 0) { return y; }
                    return 0.0;
                }
                if (hy < 0) { return -y; }
                return 0.0;
            }
            if (iy == 0x3ff00000) {
                if (hy < 0) { return 1.0 / x; }
                return x;
            }
            if (hy == 0x40000000) { return x * x; }
            if (hy == 0x3fe00000) {
                if (hx >= 0) { return sqrt(x); }
            }
        }

        ax = fabs(x);
        if (lx == 0) {
            if (ix == 0x7ff00000 || ix == 0 || ix == 0x3ff00000) {
                z = ax;
                if (hy < 0) { z = 1.0 / z; }
                if (hx < 0) {
                    if (((ix - 0x3ff00000) | yisint) == 0) {
                        z = (z - z) / (z - z);
                    } else {
                        if (yisint == 1) { z = -z; }
                    }
                }
                return z;
            }
        }

        if (((((hx as uint) >> 31) - 1) | (yisint as uint)) == 0) {
            return (x - x) / (x - x);
        }

        if (iy > 0x41e00000) {
            if (iy > 0x43f00000) {
                if (ix <= 0x3fefffff) {
                    if (hy < 0) { return 1.0e+300 * 1.0e+300; }
                    return 1.0e-300 * 1.0e-300;
                }
                if (ix >= 0x3ff00000) {
                    if (hy > 0) { return 1.0e+300 * 1.0e+300; }
                    return 1.0e-300 * 1.0e-300;
                }
            }
            if (ix < 0x3fefffff) {
                if (hy < 0) { return 1.0e+300 * 1.0e+300; }
                return 1.0e-300 * 1.0e-300;
            }
            if (ix > 0x3ff00000) {
                if (hy > 0) { return 1.0e+300 * 1.0e+300; }
                return 1.0e-300 * 1.0e-300;
            }
            t = ax - 1.0;
            w = (t * t) * (0.5 - t * (0.3333333333333333333333 - t * 0.25));
            u = 1.44269502162933349609e+00 * t;
            v = t * 1.92596299112661746887e-08 - w * 1.44269504088896338700e+00;
            t1 = u + v;
            let ut1 = bits(t1) & 0xFFFFFFFF00000000ULL;
            t1 = frombits(ut1);
            t2 = v - (t1 - u);
        } else {
            let s2 = 0.0;
            let s_h = 0.0;
            let s_l = 0.0;
            let t_h = 0.0;
            let t_l = 0.0;
            n = 0;
            if (ix < 0x00100000) {
                ax = ax * 1.80143985094819840000e+16;
                n = n - 54;
                ix = ((bits(ax) >> 32) as int);
            }
            n = n + ((ix >> 20) - 0x3ff);
            j = ix & 0x000fffff;
            ix = j | 0x3ff00000;
            if (j <= 0x3988E) {
                k = 0;
            } else {
                if (j < 0xBB67A) { k = 1; }
                else { k = 0; n = n + 1; ix = ix - 0x00100000; }
            }
            let uax = (((ix as uint) as uint64) << 32) | (lx as uint64);
            ax = frombits(uax);

            let bpk = 1.0;
            if (k != 0) { bpk = 1.5; }
            u = ax - bpk;
            v = 1.0 / (ax + bpk);
            s = u * v;
            s_h = s;
            let ush = bits(s_h) & 0xFFFFFFFF00000000ULL;
            s_h = frombits(ush);

            let uth = (((((ix >> 1) | 0x20000000) as uint) as uint64) << 32) | 0x0008000000000000ULL | ((k as uint64) << 50);
            t_h = frombits(uth);

            t_l = ax - (t_h - bpk);
            s_l = v * ((u - s_h * t_h) - s_h * t_l);
            s2 = s * s;
            r = s2 * s2 * (5.99999999999994648725e-01 + s2 * (4.28571428578550184252e-01 + s2 * (3.33333329818377432918e-01 + s2 * (2.72728123808534006489e-01 + s2 * (2.30660745775561754067e-01 + s2 * 2.06975017800338417784e-01)))));
            r = r + s_l * (s_h + s);
            s2 = s_h * s_h;
            t_h = 3.0 + s2 + r;
            let uth2 = bits(t_h) & 0xFFFFFFFF00000000ULL;
            t_h = frombits(uth2);
            t_l = r - ((t_h - 3.0) - s2);
            u = s_h * t_h;
            v = s_l * t_h + t_l * s;
            p_h = u + v;
            let uph = bits(p_h) & 0xFFFFFFFF00000000ULL;
            p_h = frombits(uph);
            p_l = v - (p_h - u);
            let z_h = 9.61796700954437255859e-01 * p_h;
            let dpl = 0.0;
            if (k != 0) { dpl = 1.35003920212974897128e-08; }
            let z_l = -7.02846165095275826516e-09 * p_h + p_l * 9.61796693925975554329e-01 + dpl;
            t = (n as double);
            let dph = 0.0;
            if (k != 0) { dph = 5.84962487220764160156e-01; }
            t1 = (((z_h + z_l) + dph) + t);
            let ut1b = bits(t1) & 0xFFFFFFFF00000000ULL;
            t1 = frombits(ut1b);
            t2 = z_l - (((t1 - t) - dph) - z_h);
        }

        s = 1.0;
        if (((((hx as uint) >> 31) - 1) | ((yisint - 1) as uint)) == 0) { s = -1.0; }

        y1 = y;
        let uy1 = bits(y1) & 0xFFFFFFFF00000000ULL;
        y1 = frombits(uy1);
        p_l = (y - y1) * t1 + y * t2;
        p_h = y1 * t1;
        z = p_l + p_h;
        let uz = bits(z);
        j = ((uz >> 32) as int);
        i = (uz as int);
        if (j >= 0x40900000) {
            if (((j - 0x40900000) | i) != 0) { return s * 1.0e+300 * 1.0e+300; }
            if (p_l + 8.0085662595372944372e-17 > z - p_h) { return s * 1.0e+300 * 1.0e+300; }
        } else {
            if ((j & 0x7fffffff) >= 0x4090cc00) {
                if (((j - 0xc090cc00) | i) != 0) { return s * 1.0e-300 * 1.0e-300; }
                if (p_l <= z - p_h) { return s * 1.0e-300 * 1.0e-300; }
            }
        }

        i = j & 0x7fffffff;
        k = (i >> 20) - 0x3ff;
        n = 0;
        if (i > 0x3fe00000) {
            n = j + (0x00100000 >> (k + 1));
            k = ((n & 0x7fffffff) >> 20) - 0x3ff;
            let ut = (((n & (~(0x000fffff >> k))) as uint) as uint64) << 32;
            t = frombits(ut);
            n = ((n & 0x000fffff) | 0x00100000) >> (20 - k);
            if (j < 0) { n = -n; }
            p_h = p_h - t;
        }
        t = p_l + p_h;
        let utt = bits(t) & 0xFFFFFFFF00000000ULL;
        t = frombits(utt);
        u = t * 6.93147182464599609375e-01;
        v = (p_l - (t - p_h)) * 6.93147180559945286227e-01 + t * (-1.90465429995776804525e-09);
        z = u + v;
        w = v - (z - u);
        t = z * z;
        t1 = z - t * (1.66666666666666019037e-01 + t * (-2.77777777770155933842e-03 + t * (6.61375632143793436117e-05 + t * (-1.65339022054652515390e-06 + t * 4.13813679705723846039e-08))));
        r = (z * t1) / (t1 - 2.0) - (w + z * w);
        z = 1.0 - (r - z);
        let uz2 = bits(z);
        j = ((uz2 >> 32) as int);
        j = j + (n << 20);
        if ((j >> 20) <= 0) {
            z = scalbn(z, n);
        } else {
            uz2 = (((j as uint) as uint64) << 32) | (uz2 & 0xFFFFFFFF);
            z = frombits(uz2);
        }
        return s * z;
    }

    // ── Constant tables (returned by value; callers fetch once) ───────────────
    [4]int func init_jk_tbl() { return [2, 3, 4, 6]; }

    [8]double func PIo2_tbl() {
        return [1.57079625129699707031e+00, 7.54978941586159635335e-08,
                5.39030252995776476554e-15, 3.28200341580791294123e-22,
                1.27065575308067607349e-29, 1.22933308981111328932e-36,
                2.73370053816464559624e-44, 2.16741683877804819444e-51];
    }

    [66]int func two_over_pi_tbl() {
        return [0xA2F983, 0x6E4E44, 0x1529FC, 0x2757D1, 0xF534DD, 0xC0DB62,
                0x95993C, 0x439041, 0xFE5163, 0xABDEBB, 0xC561B7, 0x246E3A,
                0x424DD2, 0xE00649, 0x2EEA09, 0xD1921C, 0xFE1DEB, 0x1CB129,
                0xA73EE8, 0x8235F5, 0x2EBB44, 0x84E99C, 0x7026B4, 0x5F7E41,
                0x3991D6, 0x398353, 0x39F49C, 0x845F8B, 0xBDF928, 0x3B1FF8,
                0x97FFDE, 0x05980F, 0xEF2F11, 0x8B5A0A, 0x6D1F6D, 0x367ECF,
                0x27CB09, 0xB74F46, 0x3F669E, 0x5FEA2D, 0x7527BA, 0xC7EBE5,
                0xF17B3D, 0x0739F7, 0x8A5292, 0xEA6BFB, 0x5FB11F, 0x8D5D08,
                0x560330, 0x46FC7B, 0x6BABF0, 0xCFBC20, 0x9AF436, 0x1DA9E3,
                0x91615E, 0xE61B08, 0x659985, 0x5F14A0, 0x68408D, 0xFFD880,
                0x4D7327, 0x310606, 0x1556CA, 0x73A8C9, 0x60E27B, 0xC08C6B];
    }

    [32]int func npio2_hw_tbl() {
        return [0x3FF921FB, 0x400921FB, 0x4012D97C, 0x401921FB, 0x401F6A7A, 0x4022D97C,
                0x4025FDBB, 0x402921FB, 0x402C463A, 0x402F6A7A, 0x4031475C, 0x4032D97C,
                0x40346B9C, 0x4035FDBB, 0x40378FDB, 0x403921FB, 0x403AB41B, 0x403C463A,
                0x403DD85A, 0x403F6A7A, 0x40407E4C, 0x4041475C, 0x4042106C, 0x4042D97C,
                0x4043A28C, 0x40446B9C, 0x404534AC, 0x4045FDBB, 0x4046C6CB, 0x40478FDB,
                0x404858EB, 0x404921FB];
    }

    [4]double func atanhi_tbl() {
        return [4.63647609000806093515e-01, 7.85398163397448278999e-01,
                9.82793723247329054082e-01, 1.57079632679489655800e+00];
    }
    [4]double func atanlo_tbl() {
        return [2.26987774529616870924e-17, 3.06161699786838301793e-17,
                1.39033110312309984516e-17, 6.12323399573676603587e-17];
    }
    [11]double func aT_tbl() {
        return [3.33333333333329318027e-01, -1.99999999998764832476e-01,
                1.42857142725034663711e-01, -1.11111104054623557880e-01,
                9.09088713343650656196e-02, -7.69187620504482999495e-02,
                6.66107313738753120669e-02, -5.83357013379057348645e-02,
                4.97687799461593236017e-02, -3.65315727442169155270e-02,
                1.62858201153657823623e-02];
    }
    [13]double func T_tbl() {
        return [3.33333333333334091986e-01, 1.33333333333201242699e-01,
                5.39682539762260521377e-02, 2.18694882948595424599e-02,
                8.86323982359930005737e-03, 3.59207910759131235356e-03,
                1.45620945432529025516e-03, 5.88041240820264096874e-04,
                2.46463134818469906812e-04, 7.81794442939557092300e-05,
                7.14072491382608190305e-05, -1.85586374855275456654e-05,
                2.59073051863633712884e-05];
    }

    // asin/acos polynomial coefficients (shared, so the two agree exactly).
    double func k_pS0() { return 1.66666666666666657415e-01; }
    double func k_pS1() { return -3.25565818622400915405e-01; }
    double func k_pS2() { return 2.01212532134862925881e-01; }
    double func k_pS3() { return -4.00555345006794114027e-02; }
    double func k_pS4() { return 7.91534994289814532176e-04; }
    double func k_pS5() { return 3.47933107596021167570e-05; }
    double func k_qS1() { return -2.40339491173441421878e+00; }
    double func k_qS2() { return 2.02094576023350569471e+00; }
    double func k_qS3() { return -6.88283971605453293030e-01; }
    double func k_qS4() { return 7.70381505559019352791e-02; }

    // ══ Argument reduction: x mod pi/2 ════════════════════════════════════════
    int func __kernel_rem_pio2(double* x, double* y, int e0, int nx, int prec, [66]int ipio2) {
        unsafe {
            let ijk = init_jk_tbl();
            let pio2 = PIo2_tbl();
            let [20]int iq;
            let [20]double f;
            let [20]double fq;
            let [20]double q;
            let z = 0.0;
            let fw = 0.0;
            let jz = 0; let jx = 0; let jv = 0; let jp = 0; let jk = 0;
            let carry = 0; let n = 0; let i = 0; let j = 0; let k = 0; let m = 0; let q0 = 0; let ih = 0;

            jk = ijk[prec];
            jp = jk;
            jx = nx - 1;
            jv = (e0 - 3) / 24;
            if (jv < 0) { jv = 0; }
            q0 = e0 - 24 * (jv + 1);

            j = jv - jx;
            m = jx + jk;
            i = 0;
            while (i <= m) {
                if (j < 0) { f[i] = 0.0; } else { f[i] = (ipio2[j] as double); }
                i = i + 1; j = j + 1;
            }

            i = 0;
            while (i <= jk) {
                fw = 0.0; j = 0;
                while (j <= jx) { fw = fw + x[j] * f[jx + i - j]; j = j + 1; }
                q[i] = fw;
                i = i + 1;
            }

            jz = jk;
            let again = true;
            while (again) {
                again = false;
                i = 0; j = jz; z = q[jz];
                while (j > 0) {
                    fw = (((5.96046447753906250000e-08 * z) as int) as double);
                    iq[i] = ((z - 1.67772160000000000000e+07 * fw) as int);
                    z = q[j - 1] + fw;
                    i = i + 1; j = j - 1;
                }

                z = scalbn(z, q0);
                z = z - 8.0 * floor(z * 0.125);
                n = (z as int);
                z = z - (n as double);
                ih = 0;
                if (q0 > 0) {
                    i = iq[jz - 1] >> (24 - q0);
                    n = n + i;
                    iq[jz - 1] = iq[jz - 1] - (i << (24 - q0));
                    ih = iq[jz - 1] >> (23 - q0);
                } else {
                    if (q0 == 0) { ih = iq[jz - 1] >> 23; }
                    else { if (z >= 0.5) { ih = 2; } }
                }

                if (ih > 0) {
                    n = n + 1;
                    carry = 0;
                    i = 0;
                    while (i < jz) {
                        j = iq[i];
                        if (carry == 0) {
                            if (j != 0) { carry = 1; iq[i] = 0x1000000 - j; }
                        } else {
                            iq[i] = 0xffffff - j;
                        }
                        i = i + 1;
                    }
                    if (q0 > 0) {
                        if (q0 == 1) { iq[jz - 1] = iq[jz - 1] & 0x7fffff; }
                        else { if (q0 == 2) { iq[jz - 1] = iq[jz - 1] & 0x3fffff; } }
                    }
                    if (ih == 2) {
                        z = 1.0 - z;
                        if (carry != 0) { z = z - scalbn(1.0, q0); }
                    }
                }

                if (z == 0.0) {
                    j = 0;
                    i = jz - 1;
                    while (i >= jk) { j = j | iq[i]; i = i - 1; }
                    if (j == 0) {
                        k = 1;
                        while (iq[jk - k] == 0) { k = k + 1; }
                        i = jz + 1;
                        while (i <= jz + k) {
                            f[jx + i] = (ipio2[jv + i] as double);
                            fw = 0.0; j = 0;
                            while (j <= jx) { fw = fw + x[j] * f[jx + i - j]; j = j + 1; }
                            q[i] = fw;
                            i = i + 1;
                        }
                        jz = jz + k;
                        again = true;
                    }
                }
            }

            if (z == 0.0) {
                jz = jz - 1; q0 = q0 - 24;
                while (iq[jz] == 0) { jz = jz - 1; q0 = q0 - 24; }
            } else {
                z = scalbn(z, 0 - q0);
                if (z >= 1.67772160000000000000e+07) {
                    fw = (((5.96046447753906250000e-08 * z) as int) as double);
                    iq[jz] = ((z - 1.67772160000000000000e+07 * fw) as int);
                    jz = jz + 1; q0 = q0 + 24;
                    iq[jz] = (fw as int);
                } else {
                    iq[jz] = (z as int);
                }
            }

            fw = scalbn(1.0, q0);
            i = jz;
            while (i >= 0) { q[i] = fw * (iq[i] as double); fw = fw * 5.96046447753906250000e-08; i = i - 1; }

            i = jz;
            while (i >= 0) {
                fw = 0.0; k = 0;
                while (k <= jp && k <= jz - i) { fw = fw + pio2[k] * q[i + k]; k = k + 1; }
                fq[jz - i] = fw;
                i = i - 1;
            }

            if (prec == 0) {
                fw = 0.0; i = jz;
                while (i >= 0) { fw = fw + fq[i]; i = i - 1; }
                if (ih == 0) { y[0] = fw; } else { y[0] = -fw; }
            } else {
                if (prec == 1 || prec == 2) {
                    fw = 0.0; i = jz;
                    while (i >= 0) { fw = fw + fq[i]; i = i - 1; }
                    if (ih == 0) { y[0] = fw; } else { y[0] = -fw; }
                    fw = fq[0] - fw;
                    i = 1;
                    while (i <= jz) { fw = fw + fq[i]; i = i + 1; }
                    if (ih == 0) { y[1] = fw; } else { y[1] = -fw; }
                } else {
                    i = jz;
                    while (i > 0) { fw = fq[i - 1] + fq[i]; fq[i] = fq[i] + (fq[i - 1] - fw); fq[i - 1] = fw; i = i - 1; }
                    i = jz;
                    while (i > 1) { fw = fq[i - 1] + fq[i]; fq[i] = fq[i] + (fq[i - 1] - fw); fq[i - 1] = fw; i = i - 1; }
                    fw = 0.0; i = jz;
                    while (i >= 2) { fw = fw + fq[i]; i = i - 1; }
                    if (ih == 0) { y[0] = fq[0]; y[1] = fq[1]; y[2] = fw; }
                    else { y[0] = -fq[0]; y[1] = -fq[1]; y[2] = -fw; }
                }
            }
            return n & 7;
        }
    }

    int func __ieee754_rem_pio2(double x, double* y) {
        unsafe {
            let [3]double tx;
            let nph = npio2_hw_tbl();
            let z = 0.0; let w = 0.0; let t = 0.0; let r = 0.0; let fn = 0.0;
            let e0 = 0; let i = 0; let j = 0; let nx = 0; let n = 0;
            let u = bits(x);
            let hx = ((u >> 32) as int);
            let ix = hx & 0x7fffffff;

            if (ix <= 0x3fe921fb) { y[0] = x; y[1] = 0.0; return 0; }
            if (ix < 0x4002d97c) {
                if (hx > 0) {
                    z = x - 1.57079632673412561417e+00;
                    if (ix != 0x3ff921fb) {
                        y[0] = z - 6.07710050650619224932e-11;
                        y[1] = (z - y[0]) - 6.07710050650619224932e-11;
                    } else {
                        z = z - 6.07710050630396597660e-11;
                        y[0] = z - 2.02226624879595063154e-21;
                        y[1] = (z - y[0]) - 2.02226624879595063154e-21;
                    }
                    return 1;
                } else {
                    z = x + 1.57079632673412561417e+00;
                    if (ix != 0x3ff921fb) {
                        y[0] = z + 6.07710050650619224932e-11;
                        y[1] = (z - y[0]) + 6.07710050650619224932e-11;
                    } else {
                        z = z + 6.07710050630396597660e-11;
                        y[0] = z + 2.02226624879595063154e-21;
                        y[1] = (z - y[0]) + 2.02226624879595063154e-21;
                    }
                    return -1;
                }
            }
            if (ix <= 0x413921fb) {
                t = fabs(x);
                n = ((t * 6.36619772367581382433e-01 + 0.5) as int);
                fn = (n as double);
                r = t - fn * 1.57079632673412561417e+00;
                w = fn * 6.07710050650619224932e-11;
                if (n < 32 && ix != nph[n - 1]) {
                    y[0] = r - w;
                } else {
                    j = ix >> 20;
                    y[0] = r - w;
                    let u2 = bits(y[0]);
                    i = j - (((u2 >> 32) as int) >> 20 & 0x7ff);
                    if (i > 16) {
                        t = r;
                        w = fn * 6.07710050630396597660e-11;
                        r = t - w;
                        w = fn * 2.02226624879595063154e-21 - ((t - r) - w);
                        y[0] = r - w;
                        let u3 = bits(y[0]);
                        i = j - (((u3 >> 32) as int) >> 20 & 0x7ff);
                        if (i > 49) {
                            t = r;
                            w = fn * 2.02226624871116645580e-21;
                            r = t - w;
                            w = fn * 8.47842766036889956997e-32 - ((t - r) - w);
                            y[0] = r - w;
                        }
                    }
                }
                y[1] = (r - y[0]) - w;
                if (hx < 0) { y[0] = -y[0]; y[1] = -y[1]; return 0 - n; }
                return n;
            }
            if (ix >= 0x7ff00000) { y[0] = x - x; y[1] = y[0]; return 0; }
            let u4 = bits(x);
            e0 = (ix >> 20) - 1046;
            u4 = ((((ix - (e0 << 20)) as uint) as uint64) << 32) | (u4 & 0xFFFFFFFF);
            z = frombits(u4);
            i = 0;
            while (i < 2) {
                tx[i] = ((z as int) as double);
                z = (z - tx[i]) * 1.67772160000000000000e+07;
                i = i + 1;
            }
            tx[2] = z;
            nx = 3;
            while (tx[nx - 1] == 0.0) { nx = nx - 1; }
            n = __kernel_rem_pio2(&tx[0], y, e0, nx, 2, two_over_pi_tbl());
            if (hx < 0) { y[0] = -y[0]; y[1] = -y[1]; return 0 - n; }
            return n;
        }
    }

    // ══ Kernel trig (|x| <= pi/4) ═════════════════════════════════════════════
    double func __kernel_cos(double x, double y) {
        let u = bits(x);
        let ix = ((u >> 32) as int) & 0x7fffffff;
        if (ix < 0x3e400000) {
            if ((x as int) == 0) { return 1.0; }
        }
        let z = x * x;
        let r = z * (4.16666666666666019037e-02 + z * (-1.38888888888741095749e-03 + z * (2.48015872894767294178e-05 + z * (-2.75573143513906633035e-07 + z * (2.08757232129817482790e-09 + z * -1.13596475577881948265e-11)))));
        if (ix < 0x3FD33333) {
            return 1.0 - (0.5 * z - (z * r - x * y));
        }
        let qx = 0.0;
        if (ix > 0x3fe90000) {
            qx = 0.28125;
        } else {
            let uq = (((ix - 0x00200000) as uint) as uint64) << 32;
            qx = frombits(uq);
        }
        let hz = 0.5 * z - qx;
        let a = 1.0 - qx;
        return a - (hz - (z * r - x * y));
    }

    double func __kernel_sin(double x, double y, int iy) {
        let u = bits(x);
        let ix = ((u >> 32) as int) & 0x7fffffff;
        if (ix < 0x3e400000) {
            if ((x as int) == 0) { return x; }
        }
        let z = x * x;
        let v = z * x;
        let r = 8.33333333332248946124e-03 + z * (-1.98412698298579493134e-04 + z * (2.75573137070700676789e-06 + z * (-2.50507602534068634195e-08 + z * 1.58969099521155010221e-10)));
        if (iy == 0) { return x + v * (-1.66666666666666324348e-01 + z * r); }
        return x - ((z * (0.5 * y - v * r) - y) - v * -1.66666666666666324348e-01);
    }

    double func __kernel_tan(double x, double y, int iy) {
        let tt = T_tbl();
        let u = bits(x);
        let hx = ((u >> 32) as int);
        let ix = hx & 0x7fffffff;
        let z = 0.0; let r = 0.0; let v = 0.0; let w = 0.0; let s = 0.0;

        if (ix < 0x3e300000) {
            if ((x as int) == 0) {
                if (((ix | (u as uint)) | (iy + 1)) == 0) { return 1.0 / fabs(x); }
                if (iy == 1) { return x; }
                z = x + y; w = z;
                let uz = bits(z) & 0xFFFFFFFF00000000ULL;
                z = frombits(uz);
                v = y - (z - x);
                let a = -1.0 / w;
                let t = a;
                let ut = bits(t) & 0xFFFFFFFF00000000ULL;
                t = frombits(ut);
                s = 1.0 + t * z;
                return t + a * (s + t * v);
            }
        }
        if (ix >= 0x3FE59428) {
            if (hx < 0) { x = -x; y = -y; }
            z = 7.85398163397448278999e-01 - x;
            w = 3.06161699786838301793e-17 - y;
            x = z + w;
            y = 0.0;
        }
        z = x * x;
        w = z * z;
        r = tt[1] + w * (tt[3] + w * (tt[5] + w * (tt[7] + w * (tt[9] + w * tt[11]))));
        v = z * (tt[2] + w * (tt[4] + w * (tt[6] + w * (tt[8] + w * (tt[10] + w * tt[12])))));
        s = z * x;
        r = y + z * (s * (r + v) + y);
        r = r + tt[0] * s;
        w = x + r;
        if (ix >= 0x3FE59428) {
            v = (iy as double);
            return ((1 - ((hx >> 30) & 2)) as double) * (v - 2.0 * (x - (w * w / (w + v) - r)));
        }
        if (iy == 1) { return w; }
        z = w;
        let uz = bits(z) & 0xFFFFFFFF00000000ULL;
        z = frombits(uz);
        v = r - (z - x);
        let a = -1.0 / w;
        let t = a;
        let ut = bits(t) & 0xFFFFFFFF00000000ULL;
        t = frombits(ut);
        s = 1.0 + t * z;
        return t + a * (s + t * v);
    }

    // ══ Trigonometric ═════════════════════════════════════════════════════════
    double func sin(double x) {
        let [2]double y = [0.0, 0.0];
        let z = 0.0;
        let n = 0;
        let u = bits(x);
        let ix = ((u >> 32) as int) & 0x7fffffff;
        if (ix <= 0x3fe921fb) { return __kernel_sin(x, z, 0); }
        if (ix >= 0x7ff00000) { return x - x; }
        unsafe { n = __ieee754_rem_pio2(x, &y[0]); }
        let m = n & 3;
        if (m == 0) { return __kernel_sin(y[0], y[1], 1); }
        if (m == 1) { return __kernel_cos(y[0], y[1]); }
        if (m == 2) { return -__kernel_sin(y[0], y[1], 1); }
        return -__kernel_cos(y[0], y[1]);
    }

    double func cos(double x) {
        let [2]double y = [0.0, 0.0];
        let z = 0.0;
        let n = 0;
        let u = bits(x);
        let ix = ((u >> 32) as int) & 0x7fffffff;
        if (ix <= 0x3fe921fb) { return __kernel_cos(x, z); }
        if (ix >= 0x7ff00000) { return x - x; }
        unsafe { n = __ieee754_rem_pio2(x, &y[0]); }
        let m = n & 3;
        if (m == 0) { return __kernel_cos(y[0], y[1]); }
        if (m == 1) { return -__kernel_sin(y[0], y[1], 1); }
        if (m == 2) { return -__kernel_cos(y[0], y[1]); }
        return __kernel_sin(y[0], y[1], 1);
    }

    double func tan(double x) {
        let [2]double y = [0.0, 0.0];
        let z = 0.0;
        let n = 0;
        let u = bits(x);
        let ix = ((u >> 32) as int) & 0x7fffffff;
        if (ix <= 0x3fe921fb) { return __kernel_tan(x, z, 1); }
        if (ix >= 0x7ff00000) { return x - x; }
        unsafe { n = __ieee754_rem_pio2(x, &y[0]); }
        return __kernel_tan(y[0], y[1], 1 - ((n & 1) << 1));
    }

    // ══ Inverse trigonometric ═════════════════════════════════════════════════
    double func asin(double x) {
        let u = bits(x);
        let hx = ((u >> 32) as int);
        let lx = (u as uint);
        let ix = hx & 0x7fffffff;
        let t = 0.0; let w = 0.0; let p = 0.0; let q = 0.0; let c = 0.0; let r = 0.0; let s = 0.0;
        if (ix >= 0x3ff00000) {
            if (((ix - 0x3ff00000) | (lx as int)) == 0) {
                return x * 1.57079632679489655800e+00 + x * 6.12323399573676603587e-17;
            }
            return (x - x) / (x - x);
        } else {
            if (ix < 0x3fe00000) {
                if (ix < 0x3e400000) {
                    if (1.0e+300 + x > 1.0) { return x; }
                } else {
                    t = x * x;
                    p = t * (k_pS0() + t * (k_pS1() + t * (k_pS2() + t * (k_pS3() + t * (k_pS4() + t * k_pS5())))));
                    q = 1.0 + t * (k_qS1() + t * (k_qS2() + t * (k_qS3() + t * k_qS4())));
                    w = p / q;
                    return x + x * w;
                }
            }
        }
        w = 1.0 - fabs(x);
        t = w * 0.5;
        p = t * (k_pS0() + t * (k_pS1() + t * (k_pS2() + t * (k_pS3() + t * (k_pS4() + t * k_pS5())))));
        q = 1.0 + t * (k_qS1() + t * (k_qS2() + t * (k_qS3() + t * k_qS4())));
        s = sqrt(t);
        if (ix >= 0x3FEF3333) {
            w = p / q;
            t = 1.57079632679489655800e+00 - (2.0 * (s + s * w) - 6.12323399573676603587e-17);
        } else {
            let uw = bits(s) & 0xFFFFFFFF00000000ULL;
            w = frombits(uw);
            c = (t - w * w) / (s + w);
            r = p / q;
            p = 2.0 * s * r - (6.12323399573676603587e-17 - 2.0 * c);
            q = 7.85398163397448278999e-01 - 2.0 * w;
            t = 7.85398163397448278999e-01 - (p - q);
        }
        if (hx > 0) { return t; }
        return -t;
    }

    double func acos(double x) {
        let u = bits(x);
        let hx = ((u >> 32) as int);
        let lx = (u as uint);
        let ix = hx & 0x7fffffff;
        let z = 0.0; let p = 0.0; let q = 0.0; let r = 0.0; let w = 0.0; let s = 0.0; let c = 0.0; let df = 0.0;
        if (ix >= 0x3ff00000) {
            if (((ix - 0x3ff00000) | (lx as int)) == 0) {
                if (hx > 0) { return 0.0; }
                return 3.14159265358979311600e+00 + 2.0 * 6.12323399573676603587e-17;
            }
            return (x - x) / (x - x);
        }
        if (ix < 0x3fe00000) {
            if (ix <= 0x3c600000) { return 1.57079632679489655800e+00 + 6.12323399573676603587e-17; }
            z = x * x;
            p = z * (k_pS0() + z * (k_pS1() + z * (k_pS2() + z * (k_pS3() + z * (k_pS4() + z * k_pS5())))));
            q = 1.0 + z * (k_qS1() + z * (k_qS2() + z * (k_qS3() + z * k_qS4())));
            r = p / q;
            return 1.57079632679489655800e+00 - (x - (6.12323399573676603587e-17 - x * r));
        } else {
            if (hx < 0) {
                z = (1.0 + x) * 0.5;
                p = z * (k_pS0() + z * (k_pS1() + z * (k_pS2() + z * (k_pS3() + z * (k_pS4() + z * k_pS5())))));
                q = 1.0 + z * (k_qS1() + z * (k_qS2() + z * (k_qS3() + z * k_qS4())));
                s = sqrt(z);
                r = p / q;
                w = r * s - 6.12323399573676603587e-17;
                return 3.14159265358979311600e+00 - 2.0 * (s + w);
            } else {
                z = (1.0 - x) * 0.5;
                s = sqrt(z);
                let udf = bits(s) & 0xFFFFFFFF00000000ULL;
                df = frombits(udf);
                c = (z - df * df) / (s + df);
                p = z * (k_pS0() + z * (k_pS1() + z * (k_pS2() + z * (k_pS3() + z * (k_pS4() + z * k_pS5())))));
                q = 1.0 + z * (k_qS1() + z * (k_qS2() + z * (k_qS3() + z * k_qS4())));
                r = p / q;
                w = r * s + c;
                return 2.0 * (df + w);
            }
        }
    }

    double func atan(double x) {
        let athi = atanhi_tbl();
        let atlo = atanlo_tbl();
        let aTt = aT_tbl();
        let u = bits(x);
        let hx = ((u >> 32) as int);
        let ix = hx & 0x7fffffff;
        let id = 0;
        let w = 0.0; let s1 = 0.0; let s2 = 0.0; let z = 0.0;

        if (ix >= 0x44100000) {
            if (ix > 0x7ff00000 || (ix == 0x7ff00000 && ((u as uint) != 0))) { return x + x; }
            if (hx > 0) { return athi[3] + atlo[3]; }
            return -athi[3] - atlo[3];
        }
        if (ix < 0x3fdc0000) {
            if (ix < 0x3e200000) {
                if (1.0e+300 + x > 1.0) { return x; }
            }
            id = -1;
        } else {
            x = fabs(x);
            if (ix < 0x3ff30000) {
                if (ix < 0x3fe60000) { id = 0; x = (2.0 * x - 1.0) / (2.0 + x); }
                else { id = 1; x = (x - 1.0) / (x + 1.0); }
            } else {
                if (ix < 0x40038000) { id = 2; x = (x - 1.5) / (1.0 + 1.5 * x); }
                else { id = 3; x = -1.0 / x; }
            }
        }
        z = x * x;
        w = z * z;
        s1 = z * (aTt[0] + w * (aTt[2] + w * (aTt[4] + w * (aTt[6] + w * (aTt[8] + w * aTt[10])))));
        s2 = w * (aTt[1] + w * (aTt[3] + w * (aTt[5] + w * (aTt[7] + w * aTt[9]))));
        if (id < 0) { return x - x * (s1 + s2); }
        z = athi[id] - ((x * (s1 + s2) - atlo[id]) - x);
        if (hx < 0) { return -z; }
        return z;
    }

    double func atan2(double y, double x) {
        let z = 0.0; let k = 0; let m = 0;
        let ux = bits(x);
        let uy = bits(y);
        let hx = ((ux >> 32) as int);
        let hy = ((uy >> 32) as int);
        let lx = (ux as uint);
        let ly = (uy as uint);
        let ix = hx & 0x7fffffff;
        let iy = hy & 0x7fffffff;

        if (((ix | (((lx | (0 - lx)) >> 31) as int)) > 0x7ff00000) ||
            ((iy | (((ly | (0 - ly)) >> 31) as int)) > 0x7ff00000)) {
            return x + y;
        }
        if (((hx - 0x3ff00000) | (lx as int)) == 0) { return atan(y); }
        m = ((hy >> 31) & 1) | ((hx >> 30) & 2);

        if ((iy | (ly as int)) == 0) {
            if (m == 0 || m == 1) { return y; }
            if (m == 2) { return 3.14159265358979311600e+00 + 1.0e-300; }
            return -3.14159265358979311600e+00 - 1.0e-300;
        }
        if ((ix | (lx as int)) == 0) {
            if (hy < 0) { return -1.57079632679489655800e+00 - 1.0e-300; }
            return 1.57079632679489655800e+00 + 1.0e-300;
        }
        if (ix == 0x7ff00000) {
            if (iy == 0x7ff00000) {
                if (m == 0) { return 7.85398163397448278999e-01 + 1.0e-300; }
                if (m == 1) { return -7.85398163397448278999e-01 - 1.0e-300; }
                if (m == 2) { return 3.0 * 7.85398163397448278999e-01 + 1.0e-300; }
                return -3.0 * 7.85398163397448278999e-01 - 1.0e-300;
            } else {
                if (m == 0) { return 0.0; }
                if (m == 1) { return -0.0; }
                if (m == 2) { return 3.14159265358979311600e+00 + 1.0e-300; }
                return -3.14159265358979311600e+00 - 1.0e-300;
            }
        }
        if (iy == 0x7ff00000) {
            if (hy < 0) { return -1.57079632679489655800e+00 - 1.0e-300; }
            return 1.57079632679489655800e+00 + 1.0e-300;
        }

        k = (iy - ix) >> 20;
        if (k > 60) { z = 1.57079632679489655800e+00 + 0.5 * 6.12323399573676603587e-17; }
        else {
            if (hx < 0 && k < -60) { z = 0.0; }
            else { z = atan(fabs(y / x)); }
        }
        if (m == 0) { return z; }
        if (m == 1) {
            let uz = bits(z) | 0x8000000000000000ULL;
            return frombits(uz);
        }
        if (m == 2) { return 3.14159265358979311600e+00 - (z - 1.2246467991473531772E-16); }
        return (z - 1.2246467991473531772E-16) - 3.14159265358979311600e+00;
    }

    // ══ Hyperbolic ════════════════════════════════════════════════════════════
    double func sinh(double x) {
        let u = bits(x);
        let jx = ((u >> 32) as int);
        let ix = jx & 0x7fffffff;
        let t = 0.0; let w = 0.0; let h = 0.0;
        if (ix >= 0x7ff00000) { return x + x; }
        h = 0.5;
        if (jx < 0) { h = -0.5; }
        if (ix < 0x40360000) {
            if (ix < 0x3e300000) {
                if (1.0e+300 + x > 1.0) { return x; }
            }
            t = expm1(fabs(x));
            if (ix < 0x3ff00000) { return h * (2.0 * t - t * t / (t + 1.0)); }
            return h * (t + t / (t + 1.0));
        }
        if (ix < 0x40862E42) { return h * exp(fabs(x)); }
        if (ix <= 0x408633CE) {
            w = exp(0.5 * fabs(x));
            t = h * w;
            return t * w;
        }
        return x * 1.0e+300 * 1.0e+300;
    }

    double func cosh(double x) {
        let u = bits(x);
        let ix = ((u >> 32) as int) & 0x7fffffff;
        let t = 0.0; let w = 0.0;
        if (ix >= 0x7ff00000) { return x * x; }
        if (ix < 0x3fd62e43) {
            t = expm1(fabs(x));
            w = 1.0 + t;
            if (ix < 0x3c800000) { return w; }
            return 1.0 + (t * t) / (w + w);
        }
        if (ix < 0x40360000) {
            t = exp(fabs(x));
            return 0.5 * t + 0.5 / t;
        }
        if (ix < 0x40862E42) { return 0.5 * exp(fabs(x)); }
        if (ix <= 0x408633CE) {
            w = exp(0.5 * fabs(x));
            return w * w * 0.5;
        }
        return 1.0e+300 * 1.0e+300;
    }

    double func tanh(double x) {
        let u = bits(x);
        let jx = ((u >> 32) as int);
        let ix = jx & 0x7fffffff;
        let t = 0.0; let z = 0.0;
        if (ix >= 0x7ff00000) {
            if (jx >= 0) { return 1.0 / x + 1.0; }
            return 1.0 / x - 1.0;
        }
        if (ix < 0x40360000) {
            if (ix < 0x3c800000) { return x; }
            if (ix >= 0x3ff00000) {
                t = expm1(2.0 * fabs(x));
                z = 1.0 - 2.0 / (t + 2.0);
            } else {
                t = expm1(-2.0 * fabs(x));
                z = -t / (t + 2.0);
            }
        } else {
            z = 1.0 - 1.0e-300;
        }
        if (jx >= 0) { return z; }
        return -z;
    }

    double func asinh(double x) {
        let u = bits(x);
        let hx = ((u >> 32) as int);
        let ix = hx & 0x7fffffff;
        let t = 0.0; let w = 0.0;
        if (ix >= 0x7ff00000) { return x + x; }
        if (ix < 0x3e300000) {
            if (1.0e+300 + x > 1.0) { return x; }
        }
        if (ix > 0x41b00000) {
            w = log(fabs(x)) + k_ln2hi();
        } else {
            if (ix > 0x40000000) {
                t = fabs(x);
                w = log(2.0 * t + 1.0 / (sqrt(x * x + 1.0) + t));
            } else {
                t = x * x;
                w = log1p(fabs(x) + t / (1.0 + sqrt(1.0 + t)));
            }
        }
        if (hx > 0) { return w; }
        return -w;
    }

    double func acosh(double x) {
        let u = bits(x);
        let hx = ((u >> 32) as int);
        let lx = (u as uint);
        let t = 0.0;
        if (hx < 0x3ff00000) { return (x - x) / (x - x); }
        else {
            if (hx >= 0x41b00000) {
                if (hx >= 0x7ff00000) { return x + x; }
                return log(x) + k_ln2hi();
            } else {
                if (((hx - 0x3ff00000) | (lx as int)) == 0) {
                    return 0.0;
                } else {
                    if (hx > 0x40000000) {
                        t = x * x;
                        return log(2.0 * x - 1.0 / (x + sqrt(t - 1.0)));
                    } else {
                        t = x - 1.0;
                        return log1p(t + sqrt(2.0 * t + t * t));
                    }
                }
            }
        }
    }

    double func atanh(double x) {
        let u = bits(x);
        let hx = ((u >> 32) as int);
        let lx = (u as uint);
        let ix = hx & 0x7fffffff;
        let t = 0.0;
        if ((ix | (((lx | (0 - lx)) >> 31) as int)) > 0x3ff00000) { return (x - x) / (x - x); }
        if (ix == 0x3ff00000) { return x / 0.0; }
        if (ix < 0x3e300000 && (1.0e+300 + x) > 0.0) { return x; }
        u = u & 0x7FFFFFFFFFFFFFFFULL;
        x = frombits(u);
        if (ix < 0x3fe00000) {
            t = x + x;
            t = 0.5 * log1p(t + t * x / (1.0 - x));
        } else {
            t = 0.5 * log1p((x + x) / (1.0 - x));
        }
        if (hx >= 0) { return t; }
        return -t;
    }

    // ══ Public API (thin wrappers over the fdlibm primitives) ═════════════════
    public double func Abs(double x)   { return fabs(x); }
    public double func Floor(double x) { return floor(x); }
    public double func Ceil(double x)  { return ceil(x); }
    public double func Round(double x) { return round(x); }
    public double func Trunc(double x) { return trunc(x); }
    public double func Sqrt(double x)  { return sqrt(x); }
    public double func CopySign(double x, double y) { return copysign(x, y); }
    public double func ScalbN(double x, int n)      { return scalbn(x, n); }
    public double func Log(double x)    { return log(x); }
    public double func Exp(double x)    { return exp(x); }
    public double func Log1p(double x)  { return log1p(x); }
    public double func Expm1(double x)  { return expm1(x); }
    public double func Mod(double x, double y) { return fmod(x, y); }
    public double func Pow(double b, double e)  { return pow(b, e); }
    public double func Sin(double x)  { return sin(x); }
    public double func Cos(double x)  { return cos(x); }
    public double func Tan(double x)  { return tan(x); }
    public double func Asin(double x) { return asin(x); }
    public double func Acos(double x) { return acos(x); }
    public double func Atan(double x) { return atan(x); }
    public double func Atan2(double y, double x) { return atan2(y, x); }
    public double func Sinh(double x)  { return sinh(x); }
    public double func Cosh(double x)  { return cosh(x); }
    public double func Tanh(double x)  { return tanh(x); }
    public double func Asinh(double x) { return asinh(x); }
    public double func Acosh(double x) { return acosh(x); }
    public double func Atanh(double x) { return atanh(x); }

    /// -1.0, 0.0 or 1.0 according to the sign of `x`.
    public double func Sign(double x) {
        if (x > 0.0) { return 1.0; }
        if (x < 0.0) { return -1.0; }
        return 0.0;
    }
    /// Smaller of two values.
    public double func Min(double a, double b) {
        if (a < b) { return a; }
        return b;
    }
    /// Larger of two values.
    public double func Max(double a, double b) {
        if (a > b) { return a; }
        return b;
    }
    /// Constrain `v` to the inclusive range [lo, hi].
    public double func Clamp(double v, double lo, double hi) {
        if (v < lo) { return lo; }
        if (v > hi) { return hi; }
        return v;
    }

}
