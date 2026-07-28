/*
 * Set.g - Hash sets: Set[T] (value-keyed) and StringSet (string-keyed)
 *
 * Author: u/ApparentlyPlus
 */

import Runtime;
import String;
import List;
import Hash;
import Mem;

class Set[T] {
    T* keys;
    char* used;
    int cap;
    int count;

    func _init() {
        self.keys = null;
        self.used = null;
        self.cap = 0;
        self.count = 0;
    }

    func _deinit() {
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { release(self.keys[i]); }
                i = i + 1;
            }
            if (self.keys != null) { free(self.keys); }
            if (self.used != null) { free(self.used); }
        }
    }

    public int func Length() { return self.count; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }

    /*
     * Reserve - Grow so n items fit under the 0.7 load factor without rehashing
     */
    public void func Reserve(int n) {
        let target = self.cap;
        if (target == 0) { target = 16; }
        while (target * 7 < n * 10) { target = target * 2; }
        if (target > self.cap) { self.Grow(target); }
    }

    /*
     * Add - Insert item if absent (duplicates are ignored)
     */
    public void func Add(T item) { self.AddNew(item); }

    /*
     * AddNew - Insert item, returning false if it was already there; one probe, not Has then Add
     */
    public bool func AddNew(T item) {
        if (self.cap == 0 || self.count * 10 >= self.cap * 7) { self.Grow(self.cap + 1); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.Mix(item as usize) & mask;
            while (self.used[h] != 0) {
                if (self.keys[h] == item) { return false; }
                h = (h + (1 as usize)) & mask;
            }
            self.keys[h] = retain(item);
            self.used[h] = 1;
            self.count = self.count + 1;
        }
        return true;
    }

    /*
     * Has - True if item is present
     */
    public bool func Has(T item) {
        if (self.cap == 0) { return false; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.Mix(item as usize) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h] == item) { return true; }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return false;
    }

    /*
     * Remove - Delete item if present, backward-shifting the following run
     */
    public void func Remove(T item) {
        if (self.cap == 0) { return; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.Mix(item as usize) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h] == item) {
                    release(self.keys[h]);
                    self.used[h] = 0;
                    self.count = self.count - 1;
                    let j = (h + (1 as usize)) & mask;
                    while (self.used[j] != 0) {
                        let k2 = self.keys[j];
                        self.used[j] = 0;
                        self.count = self.count - 1;
                        let hh = Hash.Mix(k2 as usize) & mask;
                        while (self.used[hh] != 0) { hh = (hh + (1 as usize)) & mask; }
                        self.keys[hh] = k2;
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

    /*
     * Clear - Remove all elements, keeping the backing buffers
     */
    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { release(self.keys[i]); self.used[i] = 0; }
                i = i + 1;
            }
        }
        self.count = 0;
    }

    /*
     * ToList - Collect the elements into a new List (unspecified order)
     */
    public List[T] func ToList() {
        let result = new List[T]();
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
     * Union - A new set with every element of self and other; walks live buckets directly
     */
    public Set[T] func Union(Set[T] other) {
        let result = new Set[T]();
        result.Reserve(self.count + other.count);
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.keys[i]); }
                i = i + 1;
            }
            i = 0;
            while (i < other.cap) {
                if (other.used[i] != 0) { result.Add(other.keys[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    /*
     * Intersect - A new set with the elements present in both self and other
     */
    public Set[T] func Intersect(Set[T] other) {
        let result = new Set[T]();
        result.Reserve(self.count);
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0 && other.Has(self.keys[i])) { result.Add(self.keys[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    /*
     * + - Operator spelling of Union
     */
    public operator Set[T] func +(Set[T] other) { return self.Union(other); }

    /*
     * & - Operator spelling of Intersect
     */
    public operator Set[T] func &(Set[T] other) { return self.Intersect(other); }

    /*
     * Grow - Reallocate to >= minCap (power of two) and rehash every live key
     */
    void func Grow(int minCap) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 16; }
        while (nc < minCap) { nc = nc * 2; }
        unsafe {
            let nk = alloc((nc as usize) * sizeof(T)) as T*;
            let nu = alloc(nc as usize) as char*;
            let mask = (nc - 1) as usize;
            Mem.Fill(nu, 0 as byte, nc as usize);
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) {
                    let h = Hash.Mix(self.keys[i] as usize) & mask;
                    while (nu[h] != 0) { h = (h + (1 as usize)) & mask; }
                    nk[h] = self.keys[i];
                    nu[h] = 1;
                }
                i = i + 1;
            }
            if (self.keys != null) { free(self.keys); }
            if (self.used != null) { free(self.used); }
            self.keys = nk;
            self.used = nu;
        }
        self.cap = nc;
    }
}

class StringSet {
    String* keys;
    char* used;
    int cap;
    int count;

    func _init() {
        self.keys = null;
        self.used = null;
        self.cap = 0;
        self.count = 0;
    }

    func _deinit() {
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { release(self.keys[i]); }
                i = i + 1;
            }
            if (self.keys != null) { free(self.keys); }
            if (self.used != null) { free(self.used); }
        }
    }

    public int func Length() { return self.count; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }

    /*
     * Reserve - Grow so n items fit under the 0.7 load factor without rehashing
     */
    public void func Reserve(int n) {
        let target = self.cap;
        if (target == 0) { target = 16; }
        while (target * 7 < n * 10) { target = target * 2; }
        if (target > self.cap) { self.Grow(target); }
    }

    /*
     * Add - Insert item if absent; a null item is ignored
     */
    public void func Add(String item) { self.AddNew(item); }

    /*
     * AddNew - Insert item, returning false if it was already there (or null); one probe
     */
    public bool func AddNew(String item) {
        if (item == null) { return false; }
        if (self.cap == 0 || self.count * 10 >= self.cap * 7) { self.Grow(self.cap + 1); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.HashString(item) & mask;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(item)) { return false; }
                h = (h + (1 as usize)) & mask;
            }
            self.keys[h] = retain(item);
            self.used[h] = 1;
            self.count = self.count + 1;
        }
        return true;
    }

    /*
     * Has - True if item is present (by content)
     */
    public bool func Has(String item) {
        if (self.cap == 0 || item == null) { return false; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.HashString(item) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(item)) { return true; }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return false;
    }

    /*
     * Remove - Delete item if present, backward-shifting the following run
     */
    public void func Remove(String item) {
        if (self.cap == 0 || item == null) { return; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Hash.HashString(item) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(item)) {
                    release(self.keys[h]);
                    self.used[h] = 0;
                    self.count = self.count - 1;
                    let j = (h + (1 as usize)) & mask;
                    while (self.used[j] != 0) {
                        let k2 = self.keys[j];
                        self.used[j] = 0;
                        self.count = self.count - 1;
                        let hh = Hash.HashString(k2) & mask;
                        while (self.used[hh] != 0) { hh = (hh + (1 as usize)) & mask; }
                        self.keys[hh] = k2;
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

    /*
     * Clear - Remove all elements, keeping the backing buffers
     */
    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { release(self.keys[i]); self.used[i] = 0; }
                i = i + 1;
            }
        }
        self.count = 0;
    }

    /*
     * ToList - Collect the strings into a new List (unspecified order)
     */
    public List[String] func ToList() {
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
     * Grow - Reallocate to >= minCap (power of two) and rehash every live key
     */
    void func Grow(int minCap) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 16; }
        while (nc < minCap) { nc = nc * 2; }
        unsafe {
            let nk = alloc((nc as usize) * sizeof(String)) as String*;
            let nu = alloc(nc as usize) as char*;
            let mask = (nc - 1) as usize;
            Mem.Fill(nu, 0 as byte, nc as usize);
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) {
                    let h = Hash.HashString(self.keys[i]) & mask;
                    while (nu[h] != 0) { h = (h + (1 as usize)) & mask; }
                    nk[h] = self.keys[i];
                    nu[h] = 1;
                }
                i = i + 1;
            }
            if (self.keys != null) { free(self.keys); }
            if (self.used != null) { free(self.used); }
            self.keys = nk;
            self.used = nu;
        }
        self.cap = nc;
    }
}
