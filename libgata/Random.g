/*
 * Random.g - xoshiro256 PRNG, seeded through SplitMix64
 *
 * Non cryptographic (never use for keys or tokens). new Random() seeds from the
 * clock; Reseed(seed) gives a deterministic, reproducible sequence.
 *
 * Author: u/ApparentlyPlus
 */

import Time;

class Random {
    uint64 s0;
    uint64 s1;
    uint64 s2;
    uint64 s3;

    func _init() {
        self.Reseed(Time.Nanos());
    }

    /*
     * Reseed - Deterministic reset; the same seed always yields the same sequence
     */
    public void func Reseed(int64 seed) {
        let x = seed as uint64;
        self.s0 = self.Mix(ref x);
        self.s1 = self.Mix(ref x);
        self.s2 = self.Mix(ref x);
        self.s3 = self.Mix(ref x);
    }

    /*
     * Mix - One SplitMix64 step: advance x and return the mixed output
     */
    uint64 func Mix(ref uint64 x) {
        x = x + (0x9e3779b97f4a7c15 as uint64);
        let z = x;
        z = (z ^ (z >> 30)) * (0xbf58476d1ce4e5b9 as uint64);
        z = (z ^ (z >> 27)) * (0x94d049bb133111eb as uint64);
        return z ^ (z >> 31);
    }

    uint64 func Rotl(uint64 x, int k) {
        return (x << k) | (x >> (64 - k));
    }

    /*
     * NextU64 - The raw generator: 64 uniformly distributed bits (xoshiro256** step)
     */
    public uint64 func NextU64() {
        let x1 = self.s1;
        let r = self.Rotl(x1 * (5 as uint64), 7) * (9 as uint64);
        let t = x1 << 17;
        self.s2 = self.s2 ^ self.s0;
        self.s3 = self.s3 ^ x1;
        self.s1 = x1 ^ self.s2;
        self.s0 = self.s0 ^ self.s3;
        self.s2 = self.s2 ^ t;
        self.s3 = self.Rotl(self.s3, 45);
        return r;
    }

    /*
     * Next - A non-negative int, uniform in [0, 2^31)
     */
    public int func Next() {
        return (self.NextU64() >> 33) as int;
    }

    /*
     * NextRange - Uniform in [lo, hi); returns lo for an empty range
     */
    public int func NextRange(int lo, int hi) {
        if (hi <= lo) { return lo; }
        let span = (hi - lo) as uint64;
        return lo + ((self.NextU64() % span) as int);
    }

    /*
     * NextDouble - Uniform in [0.0, 1.0), with the full 53 bits a double can hold
     */
    public double func NextDouble() {
        return ((self.NextU64() >> 11) as double) / 9007199254740992.0;
    }

    public bool func NextBool() {
        return (self.NextU64() & (1 as uint64)) != (0 as uint64);
    }
}
