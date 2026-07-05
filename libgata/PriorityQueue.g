// PriorityQueue.g — binary min-heap `PriorityQueue[T]`, ordered by `<`.
//
// Same growable-buffer discipline as List/Stack/Queue. Unlike List, this is
// inherently comparison-based — instantiating `PriorityQueue[T]` for a T without
// `<` is expected to fail to compile, the same way `BinarySearch`/`Sort` do; that's
// not a special case to guard against, it's the point.

import Runtime;
import String;

class PriorityQueue[T] {
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

    void func SiftUp(int i) {
        unsafe {
            while (i > 0) {
                let parent = (i - 1) / 2;
                if (self.data[i] < self.data[parent]) {
                    let tmp = self.data[i];
                    self.data[i] = self.data[parent];
                    self.data[parent] = tmp;
                    i = parent;
                } else { return; }
            }
        }
    }

    void func SiftDown(int i) {
        unsafe {
            while (true) {
                let l = i * 2 + 1;
                let r = i * 2 + 2;
                let smallest = i;
                if (l < self.length && self.data[l] < self.data[smallest]) { smallest = l; }
                if (r < self.length && self.data[r] < self.data[smallest]) { smallest = r; }
                if (smallest == i) { return; }
                let tmp = self.data[i];
                self.data[i] = self.data[smallest];
                self.data[smallest] = tmp;
                i = smallest;
            }
        }
    }

    public void func Push(T v) {
        if (self.length >= self.cap) { self.Grow(self.length + 1); }
        unsafe { self.data[self.length] = retain(v); }
        self.length = self.length + 1;
        self.SiftUp(self.length - 1);
    }

    // Zero value if empty. Ownership transfers to the caller (no extra retain).
    public T func Pop() {
        if (self.length <= 0) { return default(T); }
        unsafe {
            let top = self.data[0];
            self.length = self.length - 1;
            if (self.length > 0) {
                self.data[0] = self.data[self.length];
                self.SiftDown(0);
            }
            return top;
        }
    }

    public throws T func PopOrThrow() {
        if (self.length <= 0) { throw; }
        unsafe {
            let top = self.data[0];
            self.length = self.length - 1;
            if (self.length > 0) {
                self.data[0] = self.data[self.length];
                self.SiftDown(0);
            }
            return top;
        }
    }

    // Zero value if empty.
    public T func Peek() {
        if (self.length > 0) {
            unsafe { return retain(self.data[0]); }
        }
        return default(T);
    }

    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.length) { release(self.data[i]); i = i + 1; }
        }
        self.length = 0;
    }
}
