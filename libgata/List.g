// List.g — generic growable array `List[T]`.
//
// The monomorphizer stamps List_int, List_String, ... per instantiation used. The
// backing buffer is a raw `T*` poked inside `unsafe`, where ARC steps aside and
// element lifetimes are managed by hand (retain on store, release on overwrite/
// remove/clear/dealloc — a no-op for value T). `==` (IndexOf/Contains) is value
// equality for primitive T, identity for reference T — Gata has no per-type
// comparator. `for x in list` works because of Length()/Get(int); `list[i]` because
// of the declared `operator []`/`[]=` below — two separate, independent opt-ins.

import Runtime;
import String;

class List[T] {
    T*  data;
    int length;
    int cap;

    func _init() {
        self.data = null;
        self.length = 0;
        self.cap = 0;
    }

    func _deinit() {
        unsafe {
            let i = 0;
            while (i < self.length) { release(self.data[i]); i = i + 1; }
            if (self.data != null) { free(self.data); }
        }
    }

    // Doubles capacity (from 8) until at least `need`; raw move, no retains (the
    // pointer relocates, ownership doesn't change).
    void func Grow(int need) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 8; }
        while (nc < need) { nc = nc * 2; }
        unsafe {
            let nd = alloc((nc as usize) * sizeof(T)) as T*;
            let i = 0;
            while (i < self.length) { nd[i] = self.data[i]; i = i + 1; }
            if (self.data != null) { free(self.data); }
            self.data = nd;
        }
        self.cap = nc;
    }

    public int func Length() { return self.length; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }
    public void func Reserve(int n) { if (n > self.cap) { self.Grow(n); } }

    // Zero value if `i` is out of range.
    public T func Get(int i) {
        if (i >= 0 && i < self.length) {
            unsafe { return retain(self.data[i]); }
        }
        return default(T);
    }

    // No-op if `i` is out of range.
    public void func Set(int i, T v) {
        if (i >= 0 && i < self.length) {
            unsafe {
                release(self.data[i]);
                self.data[i] = retain(v);
            }
        }
    }

    operator func [](int i) -> T { return self.Get(i); }
    operator func []=(int i, T v) { self.Set(i, v); }

    public T func First() { return self.Get(0); }
    public T func Last() { return self.Get(self.Length() - 1); }

    public void func Add(T v) {
        if (self.length >= self.cap) { self.Grow(self.length + 1); }
        unsafe { self.data[self.length] = retain(v); }
        self.length = self.length + 1;
    }

    // `i` is clamped to [0, length].
    public void func Insert(int i, T v) {
        if (i < 0) { i = 0; }
        if (i > self.length) { i = self.length; }
        if (self.length >= self.cap) { self.Grow(self.length + 1); }
        unsafe {
            let j = self.length;
            while (j > i) { self.data[j] = self.data[j - 1]; j = j - 1; }
            self.data[i] = retain(v);
        }
        self.length = self.length + 1;
    }

    // No-op if `i` is out of range.
    public void func RemoveAt(int i) {
        if (i < 0 || i >= self.length) { return; }
        unsafe {
            release(self.data[i]);
            let j = i;
            while (j < self.length - 1) { self.data[j] = self.data[j + 1]; j = j + 1; }
        }
        self.length = self.length - 1;
    }

    // No-op if empty.
    public void func RemoveLast() {
        if (self.length > 0) {
            unsafe { release(self.data[self.length - 1]); }
            self.length = self.length - 1;
        }
    }

    public void func Reverse() {
        let a = 0;
        let b = self.length - 1;
        unsafe {
            while (a < b) {
                let t = self.data[a];
                self.data[a] = self.data[b];
                self.data[b] = t;
                a = a + 1;
                b = b - 1;
            }
        }
    }

    // Keeps the backing buffer.
    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.length) { release(self.data[i]); i = i + 1; }
        }
        self.length = 0;
    }

    public int func IndexOf(T v) {
        unsafe {
            let i = 0;
            while (i < self.length) {
                if (self.data[i] == v) { return i; }
                i = i + 1;
            }
        }
        return -1;
    }

    public bool func Contains(T v) { return self.IndexOf(v) >= 0; }
}
