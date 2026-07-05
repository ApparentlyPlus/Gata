// Set.g — hash sets. Same open-addressing/backward-shift/power-of-2-mask engine as
// Map.g (Set[T] reuses Map.g's `Mix` finalizer for non-string T), just without a
// stored value array — `Set[T] == Map[T, bool]` minus the wasted value array.

import Runtime;
import String;
import List;
import Map;   // Mix (SplitMix64 finalizer)

class Set[T] {
    T*    keys;
    char* used;
    int   cap;
    int   count;

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
            let nk = alloc((nc as usize) * sizeof(T)) as T*;
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

    public void func Add(T item) {
        if (self.cap == 0 || self.count * 10 >= self.cap * 7) { self.Grow(self.cap + 1); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Mix(item as usize) & mask;
            while (self.used[h] != 0) {
                if (self.keys[h] == item) { return; }
                h = (h + (1 as usize)) & mask;
            }
            self.keys[h] = retain(item);
            self.used[h] = 1;
            self.count = self.count + 1;
        }
    }

    public bool func Has(T item) {
        if (self.cap == 0) { return false; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Mix(item as usize) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h] == item) { return true; }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return false;
    }

    public void func Remove(T item) {
        if (self.cap == 0) { return; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = Mix(item as usize) & mask;
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
                        let hh = Mix(k2 as usize) & mask;
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

    public List[T] func ToList() {
        let result = new List[T]();
        unsafe {
            let i = 0;
            while (i < self.cap) {
                if (self.used[i] != 0) { result.Add(self.keys[i]); }
                i = i + 1;
            }
        }
        return result;
    }

    public Set[T] func Union(Set[T] other) {
        let result = new Set[T]();
        let mine = self.ToList();
        let theirs = other.ToList();
        for v in mine { result.Add(v); }
        for v in theirs { result.Add(v); }
        return result;
    }

    public Set[T] func Intersect(Set[T] other) {
        let result = new Set[T]();
        let mine = self.ToList();
        for v in mine {
            if (other.Has(v)) { result.Add(v); }
        }
        return result;
    }
}

class StringSet {
    String* keys;
    char*   used;
    int     cap;
    int     count;

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

    // A null item is ignored.
    public void func Add(String item) {
        if (item == null) { return; }
        if (self.cap == 0 || self.count * 10 >= self.cap * 7) { self.Grow(self.cap + 1); }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = HashString(item) & mask;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(item)) { return; }
                h = (h + (1 as usize)) & mask;
            }
            self.keys[h] = retain(item);
            self.used[h] = 1;
            self.count = self.count + 1;
        }
    }

    public bool func Has(String item) {
        if (self.cap == 0 || item == null) { return false; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = HashString(item) & mask;
            let start = h;
            while (self.used[h] != 0) {
                if (self.keys[h].Equals(item)) { return true; }
                h = (h + (1 as usize)) & mask;
                if (h == start) { break; }
            }
        }
        return false;
    }

    public void func Remove(String item) {
        if (self.cap == 0 || item == null) { return; }
        unsafe {
            let mask = (self.cap - 1) as usize;
            let h = HashString(item) & mask;
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
                        let hh = HashString(k2) & mask;
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

    public List[String] func ToList() {
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
}
