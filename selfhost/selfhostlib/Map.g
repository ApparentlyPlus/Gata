/*
 * Map.g - Hash maps: Map[K, V] (value keyed) and StringMap[V] (string keyed)
 *
 * Author: u/ApparentlyPlus
 */

import "selfhostlib/Runtime.g";
import "selfhostlib/String.g";
import "selfhostlib/List.g";
import "selfhostlib/Mem.g";
import "selfhostlib/Hash.g";
import "selfhostlib/Optional.g";

class Map[K, V] {

    // Private fields
    K* keys;
    V* vals;
    char* used; // 0 = empty, 1 = occupied
    int cap;
    int count;

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

    /*
     * Reserve - Grow so n pairs fit under the 0.7 load factor without rehashing
     */
    public void func Reserve(int n) {
        let target = self.cap;
        if (target == 0) { target = 16; }
        while (target * 7 < n * 10) { target = target * 2; }
        if (target > self.cap) { self.Grow(target); }
    }

    /*
     * Put - Insert or overwrite the value for key
     */
    public void func Put(K key, V value) {
        if (self.cap == 0) { self.Grow(1); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.Mix(key as usize) & mask;
            while (self.used[h] != 0) {
                if (self.keys[h] == key) {
                    release(self.vals[h]);
                    self.vals[h] = retain(value);
                    return;
                }
                h = (h + (1 as usize)) & mask;
            }

            if (self.count * 10 >= self.cap * 7) {
                self.Grow(self.cap + 1);
                mask = (self.cap - 1) as usize;
                h = Hash.Mix(key as usize) & mask;
                while (self.used[h] != 0) { h = (h + (1 as usize)) & mask; }
            }
            self.keys[h] = retain(key);
            self.vals[h] = retain(value);
            self.used[h] = 1;
            self.count = self.count + 1;
        }
    }

    /*
     * Slot - Index of key's pair, or -1. Every lookup below is this probe plus what it does with
     * the hit
     */
    int func Slot(K key) {
        if (self.cap == 0) { return -1; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.Mix(key as usize) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h] == key) { return h as int; }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return -1;
    }

    /*
     * Get - Value for key, or the zero value if absent
     */
    public V func Get(K key) {
        let i = self.Slot(key);
        if (i < 0) { return default(V); }
        unsafe { return retain(self.vals[i]); }
    }

    /*
     * GetOrThrow - Value for key. Throws if absent
     */
    public throws V func GetOrThrow(K key) {
        let i = self.Slot(key);
        if (i < 0) { throw; }
        unsafe { return retain(self.vals[i]); }
    }

    /*
     * Find - Some(value) for key, or None. One probe, and tells absent from a stored zero
     */
    public Optional[V] func Find(K key) {
        let i = self.Slot(key);
        if (i < 0) { return Optional.None(); }
        unsafe { return Optional.Some(retain(self.vals[i])); }
    }

    /*
     * TryGet - Value for key into out, or false if absent. One probe, not Has then Get
     */
    public bool func TryGet(K key, ref V out) {
        let i = self.Slot(key);
        if (i < 0) { return false; }
        unsafe {
            release(out);
            out = retain(self.vals[i]);
        }
        return true;
    }

    /*
     * GetOr - Value for key, or fallback if absent. Tells absent from a stored zero value
     */
    public V func GetOr(K key, V fallback) {
        let i = self.Slot(key);
        if (i < 0) { return fallback; }
        unsafe { return retain(self.vals[i]); }
    }

    public operator V func [](K key) { return self.Get(key); }
    public operator func []=(K key, V value) { self.Put(key, value); }

    /*
     * Has - True if key is present
     */
    public bool func Has(K key) { return self.Slot(key) >= 0; }

    /*
     * Remove - Delete key if present, backward-shifting any displaced pairs
     */
    public void func Remove(K key) {
        let slot = self.Slot(key);
        if (slot < 0) { return; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = slot as usize;
            release(self.keys[h]);
            release(self.vals[h]);
            self.used[h] = 0;
            self.count = self.count - 1;

            // everything after it in the run gets re-inserted, so no probe stops at the gap
            let j = (h + (1 as usize)) & mask;
            while (self.used[j] != 0) {
                let k2 = self.keys[j];
                let v2 = self.vals[j];
                self.used[j] = 0;
                self.count = self.count - 1;
                let hh = Hash.Mix(k2 as usize) & mask;
                while (self.used[hh] != 0) { hh = (hh + (1 as usize)) & mask; }
                self.keys[hh] = k2;
                self.vals[hh] = v2;
                self.used[hh] = 1;
                self.count = self.count + 1;
                j = (j + (1 as usize)) & mask;
            }
        }
    }

    /*
     * Clear - Remove all pairs, keeping the backing buffers
     */
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

    /*
     * Keys - A new List of the live keys (unspecified order)
     */
    public List[K] func Keys() {
        let result = new List[K]();
        result.Reserve(self.count);
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.keys[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    /*
     * Values - A new List of the live values (unspecified order)
     */
    public List[V] func Values() {
        let result = new List[V]();
        result.Reserve(self.count);
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.vals[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    /*
     * Grow - Double (from 16) until at least minCap, then rehash every live pair
     */
    void func Grow(int minCap) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 16; }
        while (nc < minCap) { nc = nc * 2; }
        unsafe {
            let nk = alloc((nc as usize) * sizeof(K)) as K*;
            let nv = alloc((nc as usize) * sizeof(V)) as V*;
            let nu = alloc(nc as usize) as char*;
            let mask = (nc - 1) as usize;
            Mem.Fill(nu, 0 as byte, nc as usize);
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) {
                    let h = Hash.Mix(self.keys[i] as usize) & mask;
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
}

class StringMap[V] {
    String* keys;
    V* vals;
    char* used;
    int cap;
    int count;

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

    /*
     * Reserve - Grow so n pairs fit under the 0.7 load factor without rehashing
     */
    public void func Reserve(int n) {
        let target = self.cap;
        if (target == 0) { target = 16; }
        while (target * 7 < n * 10) { target = target * 2; }
        if (target > self.cap) { self.Grow(target); }
    }

    /*
     * Put - Insert or overwrite the value for key. A null key is ignored
     */
    public void func Put(String key, V value) {
        if (key == null) { return; }
        if (self.cap == 0) { self.Grow(1); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.HashString(key) & mask;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(key)) {
                    release(self.vals[h]);
                    self.vals[h] = retain(value);
                    return;
                }
                h = (h + (1 as usize)) & mask;
            }
            
            if (self.count * 10 >= self.cap * 7) {
                self.Grow(self.cap + 1);
                mask = (self.cap - 1) as usize;
                h = Hash.HashString(key) & mask;
                while (self.used[h] != 0) { h = (h + (1 as usize)) & mask; }
            }
            self.keys[h] = retain(key);
            self.vals[h] = retain(value);
            self.used[h] = 1;
            self.count = self.count + 1;
        }
    }

    /*
     * Slot - Index of key's pair, or -1. Every lookup below is this probe plus what it does with
     * the hit
     */
    int func Slot(String key) {
        if (self.cap == 0 || key == null) { return -1; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.HashString(key) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(key)) { return h as int; }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return -1;
    }

    /*
     * Get - Value for key, or the zero value if absent (incl. a null key)
     */
    public V func Get(String key) {
        let i = self.Slot(key);
        if (i < 0) { return default(V); }
        unsafe { return retain(self.vals[i]); }
    }

    /*
     * GetOrThrow - Value for key. Throws if absent or key is null
     */
    public throws V func GetOrThrow(String key) {
        let i = self.Slot(key);
        if (i < 0) { throw; }
        unsafe { return retain(self.vals[i]); }
    }

    /*
     * Find - Some(value) for key, or None. One probe, and tells absent from a stored zero
     */
    public Optional[V] func Find(String key) {
        let i = self.Slot(key);
        if (i < 0) { return Optional.None(); }
        unsafe { return Optional.Some(retain(self.vals[i])); }
    }

    /*
     * TryGet - Value for key into out, or false if absent. One probe, not Has then Get
     */
    public bool func TryGet(String key, ref V out) {
        let i = self.Slot(key);
        if (i < 0) { return false; }
        unsafe {
            release(out);
            out = retain(self.vals[i]);
        }
        return true;
    }

    /*
     * GetOr - Value for key, or fallback if absent. Tells absent from a stored zero value
     */
    public V func GetOr(String key, V fallback) {
        let i = self.Slot(key);
        if (i < 0) { return fallback; }
        unsafe { return retain(self.vals[i]); }
    }

    public operator V func [](String key) { return self.Get(key); }
    public operator func []=(String key, V value) { self.Put(key, value); }

    /*
     * Has - True if key is present
     */
    public bool func Has(String key) { return self.Slot(key) >= 0; }

    /*
     * Remove - Delete key if present, backward-shifting any displaced pairs
     */
    public void func Remove(String key) {
        let slot = self.Slot(key);
        if (slot < 0) { return; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = slot as usize;
            release(self.keys[h]);
            release(self.vals[h]);
            self.used[h] = 0;
            self.count = self.count - 1;

            // everything after it in the run gets re-inserted, so no probe stops at the gap
            let j = (h + (1 as usize)) & mask;
            while (self.used[j] != 0) {
                let k2 = self.keys[j];
                let v2 = self.vals[j];
                self.used[j] = 0;
                self.count = self.count - 1;
                let hh = Hash.HashString(k2) & mask;
                while (self.used[hh] != 0) { hh = (hh + (1 as usize)) & mask; }
                self.keys[hh] = k2;
                self.vals[hh] = v2;
                self.used[hh] = 1;
                self.count = self.count + 1;
                j = (j + (1 as usize)) & mask;
            }
        }
    }

    /*
     * Clear - Remove all pairs, keeping the backing buffers
     */
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

    /*
     * Keys - A new List of the live keys (unspecified order)
     */
    public List[String] func Keys() {
        let result = new List[String]();
        result.Reserve(self.count);
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.keys[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    /*
     * Values - A new List of the live values (unspecified order)
     */
    public List[V] func Values() {
        let result = new List[V]();
        result.Reserve(self.count);
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.vals[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    /*
     * Grow - Double (from 16) until at least minCap, then rehash every live pair
     */
    void func Grow(int minCap) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 16; }
        while (nc < minCap) { nc = nc * 2; }
        unsafe {
            let nk = alloc((nc as usize) * sizeof(String)) as String*;
            let nv = alloc((nc as usize) * sizeof(V)) as V*;
            let nu = alloc(nc as usize) as char*;
            let mask = (nc - 1) as usize;
            Mem.Fill(nu, 0 as byte, nc as usize);
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) {
                    let h = Hash.HashString(self.keys[i]) & mask;
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
}
