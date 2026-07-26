/*
 * Queue.g - Generic FIFO queue Queue[T]
 *
 * Author: u/ApparentlyPlus
 */

import Runtime;
import String;
import Mem;

class Queue[T] {
    T* data;
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
            while (i < self.count) { release(self.data[(self.head + i) & (self.cap - 1)]); i = i + 1; }
            if (self.data != null) { free(self.data); }
        }
    }

    public int func Length() { return self.count; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }
    public void func Reserve(int n) { if (n > self.cap) { self.Grow(n); } }

    /*
     * Enqueue - Add v to the back
     */
    public void func Enqueue(T v) {
        if (self.count >= self.cap) { self.Grow(self.count + 1); }
        unsafe { self.data[(self.head + self.count) & (self.cap - 1)] = retain(v); }
        self.count = self.count + 1;
    }

    /*
     * Dequeue - Remove and return the front, or the zero value if empty (ownership transfers)
     */
    public T func Dequeue() {
        if (self.count <= 0) { return default(T); }
        unsafe {
            let v = self.data[self.head];
            self.head = (self.head + 1) & (self.cap - 1);
            self.count = self.count - 1;
            return v;
        }
    }

    /*
     * DequeueOrThrow - Remove and return the front; throws if empty
     */
    public throws T func DequeueOrThrow() {
        if (self.count <= 0) { throw; }
        unsafe {
            let v = self.data[self.head];
            self.head = (self.head + 1) & (self.cap - 1);
            self.count = self.count - 1;
            return v;
        }
    }

    /*
     * Peek - The front without removing it, or the zero value if empty
     */
    public T func Peek() {
        if (self.count > 0) {
            unsafe { return retain(self.data[self.head]); }
        }
        return default(T);
    }

    /*
     * Clear - Remove all elements, keeping the backing buffer
     */
    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.count) { release(self.data[(self.head + i) & (self.cap - 1)]); i = i + 1; }
        }
        self.head = 0;
        self.count = 0;
    }

    /*
     * Grow - Double capacity (from 8), unrolling the live window to start at index 0
     */
    void func Grow(int need) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 8; }
        while (nc < need) { nc = nc * 2; }
        unsafe {
            let nd = alloc((nc as usize) * sizeof(T)) as T*;
            if (self.count > 0) {
                let first = self.cap - self.head;
                if (first > self.count) { first = self.count; }
                let src = self.data as char*;
                let dst = nd as char*;
                Mem.Copy(dst, src + (self.head as usize) * sizeof(T), (first as usize) * sizeof(T));
                if (self.count > first) {
                    Mem.Copy(dst + (first as usize) * sizeof(T), src, ((self.count - first) as usize) * sizeof(T));
                }
            }
            if (self.data != null) { free(self.data); }
            self.data = nd;
        }
        self.cap = nc;
        self.head = 0;
    }
}
