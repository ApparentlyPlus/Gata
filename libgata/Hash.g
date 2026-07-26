/*
 * Hash.g - Hashing primitives shared by the hash-table containers
 *
 * Map/StringMap and Set/StringSet all call Hash.Mix/Hash.HashString rather than an
 * unqualified global, so the finalizer and string hash live in one place.
 *
 * Author: u/ApparentlyPlus
 */

import String;

module Hash {
    
    /*
     * Mix - SplitMix64-style finalizer that decorrelates structured integer keys
     */
    public usize func Mix(usize x) {
        x = (x ^ (x >> 30)) * (0xbf58476d1ce4e5b9 as usize);
        x = (x ^ (x >> 27)) * (0x94d049bb133111eb as usize);
        return x ^ (x >> 31);
    }

    /*
     * HashString - FNV-1a over a string's raw bytes (one up-front bounds check)
     *
     * Lives here, not as a StringMap method, so StringSet can share it - a static
     * method nested in a generic class re-mangles per instantiation.
     */
    public usize func HashString(String key) {
        let h = 0xcbf29ce484222325 as usize;
        let n = key.Length();
        unsafe {
            let d = key.CStr();
            let i = 0;
            while (i < n) {
                h = h ^ ((d[i] as usize) & (255 as usize));
                h = h * (0x100000001b3 as usize);
                i = i + 1;
            }
        }
        return h;
    }
}
