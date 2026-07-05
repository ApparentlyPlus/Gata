// Stack.g — generic LIFO stack `Stack[T]`.
//
// Same growable-buffer discipline as List. Pop/Peek return the zero value on empty
// (fast path, no branch/error machinery); PopOrThrow is the `throws` sibling for
// call sites that need to tell "empty" apart from a legitimately-zero element.

import Runtime;
import String;

class Stack[T] {
    T*  data;
    int count;
    int cap;

    func _init() {
        self.data = null;
        self.count = 0;
        self.cap = 0;
    }

    func _deinit() {
        unsafe {
            let i = 0;
            while (i < self.count) { release(self.data[i]); i = i + 1; }
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
            while (i < self.count) { nd[i] = self.data[i]; i = i + 1; }
            if (self.data != null) { free(self.data); }
            self.data = nd;
        }
        self.cap = nc;
    }

    public int func Length() { return self.count; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }
    public void func Reserve(int n) { if (n > self.cap) { self.Grow(n); } }

    public void func Push(T v) {
        if (self.count >= self.cap) { self.Grow(self.count + 1); }
        unsafe { self.data[self.count] = retain(v); }
        self.count = self.count + 1;
    }

    // Zero value if empty. Ownership transfers to the caller (no extra retain).
    public T func Pop() {
        if (self.count <= 0) { return default(T); }
        self.count = self.count - 1;
        unsafe { return self.data[self.count]; }
    }

    public throws T func PopOrThrow() {
        if (self.count <= 0) { throw; }
        self.count = self.count - 1;
        unsafe { return self.data[self.count]; }
    }

    // Zero value if empty.
    public T func Peek() {
        if (self.count > 0) {
            unsafe { return retain(self.data[self.count - 1]); }
        }
        return default(T);
    }

    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.count) { release(self.data[i]); i = i + 1; }
        }
        self.count = 0;
    }
}
