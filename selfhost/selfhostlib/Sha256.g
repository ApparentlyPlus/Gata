/*
 * Sha256.g - SHA-256 (FIPS 180-4), incremental
 *
 * Eight working variables, sixty-four rounds, the standard round constants. Incremental because the
 * inputs worth hashing are large enough that materialising them a second time to hash them is the
 * expensive part.
 *
 * All arithmetic is on `uint`, which wraps at 32 bits exactly as the specification wants.
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/String.g";
import "selfhostlib/List.g";

class Sha256 {
    List[uint] h;
    List[uint] k;

    // The 64-byte block under construction, and how much of it is filled
    List[uint] buf;
    int bufLen;

    // Total message length in BYTES, needed for the length suffix
    int64 total;

    func _init() {
        self.h = new List[uint]();
        self.h.Add(0x6a09e667 as uint); self.h.Add(0xbb67ae85 as uint);
        self.h.Add(0x3c6ef372 as uint); self.h.Add(0xa54ff53a as uint);
        self.h.Add(0x510e527f as uint); self.h.Add(0x9b05688c as uint);
        self.h.Add(0x1f83d9ab as uint); self.h.Add(0x5be0cd19 as uint);

        self.k = new List[uint]();
        self.InitK();

        self.buf = new List[uint]();
        let int i = 0;
        while (i < 64) { self.buf.Add(0 as uint); i = i + 1; }
        self.bufLen = 0;
        self.total = 0 as int64;
    }

    /*
     * InitK - The sixty-four round constants: the first thirty-two bits of the fractional parts of
     * the cube roots of the first sixty-four primes
     */
    void func InitK() {
        self.k.Add(0x428a2f98 as uint); self.k.Add(0x71374491 as uint); self.k.Add(0xb5c0fbcf as uint); self.k.Add(0xe9b5dba5 as uint);
        self.k.Add(0x3956c25b as uint); self.k.Add(0x59f111f1 as uint); self.k.Add(0x923f82a4 as uint); self.k.Add(0xab1c5ed5 as uint);
        self.k.Add(0xd807aa98 as uint); self.k.Add(0x12835b01 as uint); self.k.Add(0x243185be as uint); self.k.Add(0x550c7dc3 as uint);
        self.k.Add(0x72be5d74 as uint); self.k.Add(0x80deb1fe as uint); self.k.Add(0x9bdc06a7 as uint); self.k.Add(0xc19bf174 as uint);
        self.k.Add(0xe49b69c1 as uint); self.k.Add(0xefbe4786 as uint); self.k.Add(0x0fc19dc6 as uint); self.k.Add(0x240ca1cc as uint);
        self.k.Add(0x2de92c6f as uint); self.k.Add(0x4a7484aa as uint); self.k.Add(0x5cb0a9dc as uint); self.k.Add(0x76f988da as uint);
        self.k.Add(0x983e5152 as uint); self.k.Add(0xa831c66d as uint); self.k.Add(0xb00327c8 as uint); self.k.Add(0xbf597fc7 as uint);
        self.k.Add(0xc6e00bf3 as uint); self.k.Add(0xd5a79147 as uint); self.k.Add(0x06ca6351 as uint); self.k.Add(0x14292967 as uint);
        self.k.Add(0x27b70a85 as uint); self.k.Add(0x2e1b2138 as uint); self.k.Add(0x4d2c6dfc as uint); self.k.Add(0x53380d13 as uint);
        self.k.Add(0x650a7354 as uint); self.k.Add(0x766a0abb as uint); self.k.Add(0x81c2c92e as uint); self.k.Add(0x92722c85 as uint);
        self.k.Add(0xa2bfe8a1 as uint); self.k.Add(0xa81a664b as uint); self.k.Add(0xc24b8b70 as uint); self.k.Add(0xc76c51a3 as uint);
        self.k.Add(0xd192e819 as uint); self.k.Add(0xd6990624 as uint); self.k.Add(0xf40e3585 as uint); self.k.Add(0x106aa070 as uint);
        self.k.Add(0x19a4c116 as uint); self.k.Add(0x1e376c08 as uint); self.k.Add(0x2748774c as uint); self.k.Add(0x34b0bcb5 as uint);
        self.k.Add(0x391c0cb3 as uint); self.k.Add(0x4ed8aa4a as uint); self.k.Add(0x5b9cca4f as uint); self.k.Add(0x682e6ff3 as uint);
        self.k.Add(0x748f82ee as uint); self.k.Add(0x78a5636f as uint); self.k.Add(0x84c87814 as uint); self.k.Add(0x8cc70208 as uint);
        self.k.Add(0x90befffa as uint); self.k.Add(0xa4506ceb as uint); self.k.Add(0xbef9a3f7 as uint); self.k.Add(0xc67178f2 as uint);
    }

    static uint func Rotr(uint x, int n) {
        return (x >> n) | (x << (32 - n));
    }

    /*
     * Append - Feeds one section's bytes. A Gata String is raw bytes already, which is what the C#
     * side hashes too (it encodes each section as UTF-8 before feeding it).
     */
    public void func Append(String s) {
        let int n = s.Length();
        let int i = 0;
        while (i < n) {
            self.buf.Set(self.bufLen, (s.CharAt(i) as uint) & (255 as uint));
            self.bufLen = self.bufLen + 1;
            self.total = self.total + (1 as int64);
            if (self.bufLen == 64) { self.Compress(); self.bufLen = 0; }
            i = i + 1;
        }
    }

    /*
     * Compress - One 64-byte block through the round function
     */
    void func Compress() {
        let List[uint] w = new List[uint]();
        let int i = 0;
        while (i < 64) { w.Add(0 as uint); i = i + 1; }

        let int t = 0;
        while (t < 16) {
            let int b = t * 4;
            w.Set(t, (self.buf.Get(b) << 24) | (self.buf.Get(b + 1) << 16)
                   | (self.buf.Get(b + 2) << 8) | self.buf.Get(b + 3));
            t = t + 1;
        }
        let int u = 16;
        while (u < 64) {
            let uint s0 = Sha256.Rotr(w.Get(u - 15), 7) ^ Sha256.Rotr(w.Get(u - 15), 18) ^ (w.Get(u - 15) >> 3);
            let uint s1 = Sha256.Rotr(w.Get(u - 2), 17) ^ Sha256.Rotr(w.Get(u - 2), 19) ^ (w.Get(u - 2) >> 10);
            w.Set(u, w.Get(u - 16) + s0 + w.Get(u - 7) + s1);
            u = u + 1;
        }

        let uint a = self.h.Get(0);
        let uint b = self.h.Get(1);
        let uint c = self.h.Get(2);
        let uint d = self.h.Get(3);
        let uint e = self.h.Get(4);
        let uint f = self.h.Get(5);
        let uint g = self.h.Get(6);
        let uint hh = self.h.Get(7);

        let int r = 0;
        while (r < 64) {
            let uint S1 = Sha256.Rotr(e, 6) ^ Sha256.Rotr(e, 11) ^ Sha256.Rotr(e, 25);
            let uint ch = (e & f) ^ ((~e) & g);
            let uint temp1 = hh + S1 + ch + self.k.Get(r) + w.Get(r);
            let uint S0 = Sha256.Rotr(a, 2) ^ Sha256.Rotr(a, 13) ^ Sha256.Rotr(a, 22);
            let uint maj = (a & b) ^ (a & c) ^ (b & c);
            let uint temp2 = S0 + maj;

            hh = g;
            g = f;
            f = e;
            e = d + temp1;
            d = c;
            c = b;
            b = a;
            a = temp1 + temp2;
            r = r + 1;
        }

        self.h.Set(0, self.h.Get(0) + a);
        self.h.Set(1, self.h.Get(1) + b);
        self.h.Set(2, self.h.Get(2) + c);
        self.h.Set(3, self.h.Get(3) + d);
        self.h.Set(4, self.h.Get(4) + e);
        self.h.Set(5, self.h.Get(5) + f);
        self.h.Set(6, self.h.Get(6) + g);
        self.h.Set(7, self.h.Get(7) + hh);
    }

    /*
     * Digest - Pads, appends the bit length, and returns the 32 digest bytes
     */
    public List[uint] func Digest() {
        let int64 bitLen = self.total * (8 as int64);

        self.buf.Set(self.bufLen, 0x80 as uint);
        self.bufLen = self.bufLen + 1;
        if (self.bufLen > 56) {
            while (self.bufLen < 64) { self.buf.Set(self.bufLen, 0 as uint); self.bufLen = self.bufLen + 1; }
            self.Compress();
            self.bufLen = 0;
        }
        while (self.bufLen < 56) { self.buf.Set(self.bufLen, 0 as uint); self.bufLen = self.bufLen + 1; }

        let int i = 0;
        while (i < 8) {
            let int shift = (7 - i) * 8;
            self.buf.Set(56 + i, ((bitLen >> shift) as uint) & (255 as uint));
            i = i + 1;
        }
        self.Compress();
        self.bufLen = 0;

        let List[uint] outBytes = new List[uint]();
        let int j = 0;
        while (j < 8) {
            let uint v = self.h.Get(j);
            outBytes.Add((v >> 24) & (255 as uint));
            outBytes.Add((v >> 16) & (255 as uint));
            outBytes.Add((v >> 8) & (255 as uint));
            outBytes.Add(v & (255 as uint));
            j = j + 1;
        }
        return outBytes;
    }

    /*
     * SeedFromDigest - BitConverter.ToInt32 over the first four digest bytes: little-endian, and
     * reinterpreted as signed, which is what .NET does and what Random's constructor then takes
     */
    public static int func SeedFromDigest(List[uint] d) {
        let uint v = d.Get(0) | (d.Get(1) << 8) | (d.Get(2) << 16) | (d.Get(3) << 24);
        return v as int;
    }
}
