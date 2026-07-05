// Queue.g — generic FIFO queue `Queue[T]`.
//
// Growable circular buffer: O(1) Enqueue/Dequeue, no element shifting. On growth
// the live elements are unrolled into a fresh buffer starting at index 0. Dequeue/
// Peek return the zero value on empty; DequeueOrThrow is the `throws` sibling.

import Runtime;
import String;

class Queue[T] {
    T*  data;
    int head;
    int count;
    int cap;

    func _init() {
        self.data = null;
        self.head = 0;
        self.count = 0;
        self.cap = 0;
    }

    func _deinit() {
        unsafe {
            let i = 0;
            while (i < self.count) { release(self.data[(self.head + i) % self.cap]); i = i + 1; }
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
            while (i < self.count) { nd[i] = self.data[(self.head + i) % self.cap]; i = i + 1; }
            if (self.data != null) { free(self.data); }
            self.data = nd;
        }
        self.cap = nc;
        self.head = 0;
    }

    public int func Length() { return self.count; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }
    public void func Reserve(int n) { if (n > self.cap) { self.Grow(n); } }

    public void func Enqueue(T v) {
        if (self.count >= self.cap) { self.Grow(self.count + 1); }
        unsafe { self.data[(self.head + self.count) % self.cap] = retain(v); }
        self.count = self.count + 1;
    }

    // Zero value if empty. Ownership transfers to the caller (no extra retain).
    public T func Dequeue() {
        if (self.count <= 0) { return default(T); }
        unsafe {
            let v = self.data[self.head];
            self.head = (self.head + 1) % self.cap;
            self.count = self.count - 1;
            return v;
        }
    }

    public throws T func DequeueOrThrow() {
        if (self.count <= 0) { throw; }
        unsafe {
            let v = self.data[self.head];
            self.head = (self.head + 1) % self.cap;
            self.count = self.count - 1;
            return v;
        }
    }

    // Zero value if empty.
    public T func Peek() {
        if (self.count > 0) {
            unsafe { return retain(self.data[self.head]); }
        }
        return default(T);
    }

    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.count) { release(self.data[(self.head + i) % self.cap]); i = i + 1; }
        }
        self.head = 0;
        self.count = 0;
    }
}
