/*
 * NetRandom.g - .NET's seeded System.Random, reproduced exactly
 *
 * The Knuth subtractive generator .NET Core routes `new Random(seed)` to (Net5CompatSeedImpl),
 * inherited unchanged from .NET Framework and kept bit-compatible on purpose: a 56-entry lag table,
 * two rolling indices 21 apart, and a subtract-with-borrow step modulo int.MaxValue.
 *
 * It lives here rather than beside its one caller because it is a general-purpose deterministic
 * generator, and because reproducing a specific platform's PRNG is a library concern - anything
 * that has to agree with a .NET-produced sequence wants exactly this, not a better generator.
 *
 * Next(max) is `(int)(InternalSample() * (1.0 / int.MaxValue) * max)` - a double multiply, NOT an
 * integer modulo. The two disagree, and the double is the one .NET does.
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/List.g";

class NetRandom {
    // 56 entries, index 0 unused - the original is a 1-based table and the arithmetic below relies
    // on that, so the slot is kept rather than shifting every index by one.
    List[int] seedArray;
    int inext;
    int inextp;

    func _init(int seed) {
        self.seedArray = new List[int]();
        let int z = 0;
        while (z < 56) { self.seedArray.Add(0); z = z + 1; }

        // int.MinValue has no positive counterpart, so .NET pins it to int.MaxValue rather than
        // letting Math.Abs overflow.
        let int subtraction = seed == (0 - 2147483647 - 1) ? 2147483647 : (seed < 0 ? (0 - seed) : seed);
        let int mj = 161803398 - subtraction;
        self.seedArray.Set(55, mj);
        let int mk = 1;

        let int ii = 0;
        let int i = 1;
        while (i < 55) {
            ii = ii + 21;
            if (ii >= 55) { ii = ii - 55; }
            self.seedArray.Set(ii, mk);
            mk = mj - mk;
            if (mk < 0) { mk = mk + 2147483647; }
            mj = self.seedArray.Get(ii);
            i = i + 1;
        }

        let int k = 1;
        while (k < 5) {
            let int j = 1;
            while (j < 56) {
                let int n = j + 30;
                if (n >= 55) { n = n - 55; }
                let int v = self.seedArray.Get(j) - self.seedArray.Get(1 + n);
                if (v < 0) { v = v + 2147483647; }
                self.seedArray.Set(j, v);
                j = j + 1;
            }
            k = k + 1;
        }

        self.inext = 0;
        self.inextp = 21;
    }

    /*
     * InternalSample - One subtract-with-borrow step over the lag table
     */
    int func InternalSample() {
        let int locINext = self.inext;
        let int locINextp = self.inextp;

        locINext = locINext + 1;
        if (locINext >= 56) { locINext = 1; }
        locINextp = locINextp + 1;
        if (locINextp >= 56) { locINextp = 1; }

        let int retVal = self.seedArray.Get(locINext) - self.seedArray.Get(locINextp);
        if (retVal == 2147483647) { retVal = retVal - 1; }
        if (retVal < 0) { retVal = retVal + 2147483647; }

        self.seedArray.Set(locINext, retVal);
        self.inext = locINext;
        self.inextp = locINextp;
        return retVal;
    }

    /*
     * Sample - The sample as a double in [0,1). The division is what .NET does and it is not
     * interchangeable with an integer modulo: for a given sample the two pick different buckets.
     */
    double func Sample() {
        return (self.InternalSample() as double) * (1.0 / 2147483647.0);
    }

    /*
     * Next - A value in [0, maxValue)
     */
    public int func Next(int maxValue) {
        return (self.Sample() * (maxValue as double)) as int;
    }
}
