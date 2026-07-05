// Map.g — hash maps.
//
//   Map[K, V]      — open-addressing hash map for value-comparable keys (primitives,
//                    pointers, or a class with `operator ==`). Reference keys without
//                    an `==` overload compare by identity — use StringMap for content-
//                    keyed strings.
//   StringMap[V]   — string-keyed map: content-hashed (FNV-1a) and content-compared.
//
// Both: linear probing, backward-shift deletion (no tombstones, so lookups stay O(1)
// amortized after removals), power-of-2 capacities indexed with a bitmask (not `%`,
// which is a division), grow/rehash at a 0.7 load factor. `Map`'s key hash runs the
// raw `(key as usize)` through a SplitMix64-style finalizer first — a bare identity
// hash clusters badly on structured keys (sequential IDs, anything sharing low bits);
// the finalizer is what every production integer hash table does instead. Same
// method set and naming on both types — the only difference is what's inside, since
// the language has no hashable/equatable trait to unify them further.

import Runtime;
import String;
import List;

usize func Mix(usize x) {
    x = (x ^ (x >> 30)) * (0xbf58476d1ce4e5b9 as usize);
    x = (x ^ (x >> 27)) * (0x94d049bb133111eb as usize);
    return x ^ (x >> 31);
}

// FNV-1a over the string's bytes. A free function (not a method on StringMap) so
// StringSet can share it too — a static method nested in a generic class gets
// re-mangled per instantiation, so there's no single callable "StringMap.Hash"
// independent of a concrete V.
usize func HashString(String key) {
    let h = 0xcbf29ce484222325 as usize;
    let n = key.Length();
    let i = 0;
    while (i < n) {
        h = h ^ ((key.CharAt(i) as usize) & (255 as usize));
        h = h * (0x100000001b3 as usize);
        i = i + 1;
    }
    return h;
}

class Map[K, V] {
    K*    keys;
    V*    vals;
    char* used;     // 0 = empty, 1 = occupied
    int   cap;
    int   count;

    func _init() {
        self.keys = null;
        self.vals = null;
        self.used = null;
        self.cap = 0;
        self.count = 0;
    }

    func _deinit() {
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { release(self.keys[i]); release(self.vals[i]); }
                i = i + 1;
            }
            if (self.keys != null) { free(self.keys); }
            if (self.vals != null) { free(self.vals); }
            if (self.used != null) { free(self.used); }
        }
    }

    public int func Length() { return self.count; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }

    public void func Reserve(int n) {
        let target = self.cap;
        if (target == 0) { target = 16; }
        while (target * 7 < n * 10) { target = target * 2; }
        if (target > self.cap) { self.Grow(target); }
    }

    // Doubles (from 16) until at least `minCap`, then re-hashes every live pair.
    void func Grow(int minCap) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 16; }
        while (nc < minCap) { nc = nc * 2; }
        unsafe {
            let nk = alloc((nc as usize) * sizeof(K)) as K*;
            let nv = alloc((nc as usize) * sizeof(V)) as V*;
            let nu = alloc(nc as usize) as char*;
            let mask = (nc - 1) as usize;
            let i = 0;
            while (i < nc) { nu[i] = 0; i = i + 1; }
            i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) {
                    let h = Mix(self.keys[i] as usize) & mask;
                    while (nu[h] != 0) { h = (h + (1 as usize)) & mask; }
                    nk[h] = self.keys[i];
                    nv[h] = self.vals[i];
                    nu[h] = 1;
                }
                i = i + 1;
            }
            if (self.keys != null) { free(self.keys); }
            if (self.vals != null) { free(self.vals); }
            if (self.used != null) { free(self.used); }
            self.keys = nk;
            self.vals = nv;
            self.used = nu;
        }
        self.cap = nc;
    }

    public void func Put(K key, V value) {
        if (self.cap == 0 || self.count * 10 >= self.cap * 7) { self.Grow(self.cap + 1); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Mix(key as usize) & mask;
            while (self.used[h] != 0) {
                if (self.keys[h] == key) {
                    release(self.vals[h]);
                    self.vals[h] = retain(value);
                    return;
                }
                h = (h + (1 as usize)) & mask;
            }
            self.keys[h] = retain(key);
            self.vals[h] = retain(value);
            self.used[h] = 1;
            self.count = self.count + 1;
        }
    }

    // Zero value if absent.
    public V func Get(K key) {
        if (self.cap == 0) { return default(V); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Mix(key as usize) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h] == key) { return retain(self.vals[h]); }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return default(V);
    }

    public throws V func GetOrThrow(K key) {
        if (self.cap > 0) {
            unsafe {
                let mask = (self.cap - 1) as usize;
                let h = Mix(key as usize) & mask;
                let start = h;
                while (self.used[h] != 0) {
                    if (self.keys[h] == key) { return retain(self.vals[h]); }
                    h = (h + (1 as usize)) & mask;
                    if (h == start) { break; }
                }
            }
        }
        throw;
    }

    operator func [](K key) -> V { return self.Get(key); }
    operator func []=(K key, V value) { self.Put(key, value); }

    public bool func Has(K key) {
        if (self.cap == 0) { return false; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Mix(key as usize) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h] == key) { return true; }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return false;
    }

    // Backward-shift clustering re-inserts any pair displaced behind the freed slot.
    public void func Remove(K key) {
        if (self.cap == 0) { return; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Mix(key as usize) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h] == key) {
                    release(self.keys[h]);
                    release(self.vals[h]);
                    self.used[h] = 0;
                    self.count = self.count - 1;
                    let j = (h + (1 as usize)) & mask;
                    while (self.used[j] != 0) {
                        let k2 = self.keys[j];
                        let v2 = self.vals[j];
                        self.used[j] = 0;
                        self.count = self.count - 1;
                        let hh = Mix(k2 as usize) & mask;
                        while (self.used[hh] != 0) { hh = (hh + (1 as usize)) & mask; }
                        self.keys[hh] = k2;
                        self.vals[hh] = v2;
                        self.used[hh] = 1;
                        self.count = self.count + 1;
                        j = (j + (1 as usize)) & mask;
                    }
                    return;
                }
                h = (h + (1 as usize)) & mask;
                if (h == start) { return; }
            }
        }
    }

    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) {
                    release(self.keys[i]);
                    release(self.vals[i]);
                    self.used[i] = 0;
                }
                i = i + 1;
            }
        }
        self.count = 0;
    }

    public List[K] func Keys() {
        let result = new List[K]();
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.keys[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    public List[V] func Values() {
        let result = new List[V]();
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.vals[i]); }
                i = i + 1;
            }
        }
        return result;
    }
}

class StringMap[V] {
    String* keys;
    V*      vals;
    char*   used;
    int     cap;
    int     count;

    func _init() {
        self.keys = null;
        self.vals = null;
        self.used = null;
        self.cap = 0;
        self.count = 0;
    }

    func _deinit() {
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { release(self.keys[i]); release(self.vals[i]); }
                i = i + 1;
            }
            if (self.keys != null) { free(self.keys); }
            if (self.vals != null) { free(self.vals); }
            if (self.used != null) { free(self.used); }
        }
    }

    public int func Length() { return self.count; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }

    public void func Reserve(int n) {
        let target = self.cap;
        if (target == 0) { target = 16; }
        while (target * 7 < n * 10) { target = target * 2; }
        if (target > self.cap) { self.Grow(target); }
    }


    void func Grow(int minCap) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 16; }
        while (nc < minCap) { nc = nc * 2; }
        unsafe {
            let nk = alloc((nc as usize) * sizeof(String)) as String*;
            let nv = alloc((nc as usize) * sizeof(V)) as V*;
            let nu = alloc(nc as usize) as char*;
            let mask = (nc - 1) as usize;
            let i = 0;
            while (i < nc) { nu[i] = 0; i = i + 1; }
            i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) {
                    let h = HashString(self.keys[i]) & mask;
                    while (nu[h] != 0) { h = (h + (1 as usize)) & mask; }
                    nk[h] = self.keys[i];
                    nv[h] = self.vals[i];
                    nu[h] = 1;
                }
                i = i + 1;
            }
            if (self.keys != null) { free(self.keys); }
            if (self.vals != null) { free(self.vals); }
            if (self.used != null) { free(self.used); }
            self.keys = nk;
            self.vals = nv;
            self.used = nu;
        }
        self.cap = nc;
    }

    // A null key is ignored.
    public void func Put(String key, V value) {
        if (key == null) { return; }
        if (self.cap == 0 || self.count * 10 >= self.cap * 7) { self.Grow(self.cap + 1); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = HashString(key) & mask;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(key)) {
                    release(self.vals[h]);
                    self.vals[h] = retain(value);
                    return;
                }
                h = (h + (1 as usize)) & mask;
            }
            self.keys[h] = retain(key);
            self.vals[h] = retain(value);
            self.used[h] = 1;
            self.count = self.count + 1;
        }
    }

    // Zero value if absent (incl. a null key).
    public V func Get(String key) {
        if (self.cap == 0 || key == null) { return default(V); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = HashString(key) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(key)) { return retain(self.vals[h]); }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return default(V);
    }

    public throws V func GetOrThrow(String key) {
        if (self.cap > 0 && key != null) {
            unsafe {
                let mask = (self.cap - 1) as usize;
                let h = HashString(key) & mask;
                let start = h;
                while (self.used[h] != 0) {
                    if (self.keys[h].Equals(key)) { return retain(self.vals[h]); }
                    h = (h + (1 as usize)) & mask;
                    if (h == start) { break; }
                }
            }
        }
        throw;
    }

    operator func [](String key) -> V { return self.Get(key); }
    operator func []=(String key, V value) { self.Put(key, value); }

    public bool func Has(String key) {
        if (self.cap == 0 || key == null) { return false; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = HashString(key) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(key)) { return true; }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return false;
    }

    public void func Remove(String key) {
        if (self.cap == 0 || key == null) { return; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = HashString(key) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(key)) {
                    release(self.keys[h]);
                    release(self.vals[h]);
                    self.used[h] = 0;
                    self.count = self.count - 1;
                    let j = (h + (1 as usize)) & mask;
                    while (self.used[j] != 0) {
                        let k2 = self.keys[j];
                        let v2 = self.vals[j];
                        self.used[j] = 0;
                        self.count = self.count - 1;
                        let hh = HashString(k2) & mask;
                        while (self.used[hh] != 0) { hh = (hh + (1 as usize)) & mask; }
                        self.keys[hh] = k2;
                        self.vals[hh] = v2;
                        self.used[hh] = 1;
                        self.count = self.count + 1;
                        j = (j + (1 as usize)) & mask;
                    }
                    return;
                }
                h = (h + (1 as usize)) & mask;
                if (h == start) { return; }
            }
        }
    }

    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) {
                    release(self.keys[i]);
                    release(self.vals[i]);
                    self.used[i] = 0;
                }
                i = i + 1;
            }
        }
        self.count = 0;
    }

    public List[String] func Keys() {
        let result = new List[String]();
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.keys[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    public List[V] func Values() {
        let result = new List[V]();
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.vals[i]); }
                i = i + 1;
            }
        }
        return result;
    }
}
