/*
 * Stack.g - Generic LIFO stack Stack[T]
 *
 * Author: u/ApparentlyPlus
 */

import Runtime;
import String;
import Mem;

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

    public int func Length() { return self.count; }
    public bool func IsEmpty() { return self.Length() == 0; }
    public int func Capacity() { return self.cap; }
    public void func Reserve(int n) { if (n > self.cap) { self.Grow(n); } }

    /*
     * Push - Add v to the top
     */
    public void func Push(T v) {
        if (self.count >= self.cap) { self.Grow(self.count + 1); }
        unsafe { self.data[self.count] = retain(v); }
        self.count = self.count + 1;
    }

    /*
     * Pop - Remove and return the top, or the zero value if empty (ownership transfers)
     */
    public T func Pop() {
        if (self.count <= 0) { return default(T); }
        self.count = self.count - 1;
        unsafe { return self.data[self.count]; }
    }

    /*
     * PopOrThrow - Remove and return the top; throws if empty
     */
    public throws T func PopOrThrow() {
        if (self.count <= 0) { throw; }
        self.count = self.count - 1;
        unsafe { return self.data[self.count]; }
    }

    /*
     * Peek - The top without removing it, or the zero value if empty
     */
    public T func Peek() {
        if (self.count > 0) {
            unsafe { return retain(self.data[self.count - 1]); }
        }
        return default(T);
    }

    /*
     * Clear - Remove all elements, keeping the backing buffer
     */
    public void func Clear() {
        unsafe {
            let i = 0;
            while (i < self.count) { release(self.data[i]); i = i + 1; }
        }
        self.count = 0;
    }

    /*
     * Grow - Double capacity (from 8) until at least need; raw move, no retains
     */
    void func Grow(int need) {
        let nc = self.cap * 2;
        if (nc == 0) { nc = 8; }
        while (nc < need) { nc = nc * 2; }
        unsafe {
            let nd = alloc((nc as usize) * sizeof(T)) as T*;
            if (self.count > 0) { Mem.Copy(nd, self.data, (self.count as usize) * sizeof(T)); }
            if (self.data != null) { free(self.data); }
            self.data = nd;
        }
        self.cap = nc;
    }
}
