/*
 * Sync.g - Thread synchronization: SpinLock and AtomicInt
 *
 * The floor for safe shared state between threads of one process. Both use
 * fields { } for a raw volatile word plus native methods over GCC's __atomic
 * builtins - pure compiler primitives, so the same body is correct in all three
 * realms (GatOS kernel, GatOS user, hosted).
 *
 * Author: u/ApparentlyPlus
 */


class SpinLock {
    fields { volatile char _lk; }

    func _init() native {
        self->_lk = 0;
    }

    /*
     * Lock - Acquire, spinning with a scheduler yield per failed attempt
     */
    public void func Lock() native {
        while (__atomic_test_and_set((void*)&self->_lk, __ATOMIC_ACQUIRE)) {
            _env_yield();
        }
    }

    /*
     * TryLock - One attempt: true if acquired, false if someone else holds it
     */
    public bool func TryLock() native {
        return !__atomic_test_and_set((void*)&self->_lk, __ATOMIC_ACQUIRE);
    }

    /*
     * Unlock - Release the lock
     */
    public void func Unlock() native {
        __atomic_clear((void*)&self->_lk, __ATOMIC_RELEASE);
    }
}

/*
 * AtomicInt - 64-bit counter with atomic, sequentially-consistent operations
 */
class AtomicInt {
    fields { volatile long long _v; }

    func _init() native {
        self->_v = 0;
    }

    public int64 func Get() native {
        return __atomic_load_n(&self->_v, __ATOMIC_SEQ_CST);
    }

    public void func Set(int64 v) native {
        __atomic_store_n(&self->_v, v, __ATOMIC_SEQ_CST);
    }

    /*
     * Add - Add delta and return the new value
     */
    public int64 func Add(int64 delta) native {
        return __atomic_add_fetch(&self->_v, delta, __ATOMIC_SEQ_CST);
    }

    public int64 func Increment() native {
        return __atomic_add_fetch(&self->_v, 1, __ATOMIC_SEQ_CST);
    }

    public int64 func Decrement() native {
        return __atomic_sub_fetch(&self->_v, 1, __ATOMIC_SEQ_CST);
    }

    /*
     * CompareExchange - If the value equals expected, set it to desired and return true
     */
    public bool func CompareExchange(int64 expected, int64 desired) native {
        long long e = expected;
        return __atomic_compare_exchange_n(&self->_v, &e, (long long)desired, 0,
                                           __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST);
    }
}
