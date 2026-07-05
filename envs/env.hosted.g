// env.hosted.g — hosted (libc) environment for host builds and the ASan harness.
//
// Marked @environment: exactly one such file takes part in a build. Only @preamble(user)
// is present, so the build declares a single `user` realm and emits one libc-backed
// translation unit a host driver can call directly. Backs the runtime with the C
// standard library. The GatOS userspace syscall surface that libgata's Console/Sys
// reference is declared but unused here; it goes once dead-code elimination drops
// those unreferenced modules.
//
// The floor libgata needs is the set of _env_* binds below: alloc/free, one general
// printf-style formatter (_env_format), and the Console/Sys I/O surface. Everything
// else (memcpy, strlen, all value formatting policy, containers) is pure Gata over them.
@environment

@preamble(user) native {
    #include <stdlib.h>
    #include <string.h>
    #include <stdio.h>
    #include <math.h>
    #include <stdint.h>
    #include <stddef.h>
    #include <stdbool.h>

    static inline void* _env_alloc(size_t n) { return malloc(n); }
    static inline void  _env_free(void* p)   { free(p); }

    /* GatOS userspace surface referenced by Console/Sys (unused on the host). */
    enum { TTY_CTRL_CLEAR = 0, TTY_CTRL_CURSOR = 1, TTY_CTRL_GET_DIMS = 2, TTY_CTRL_SET_COLOR = 3 };
    uint64_t syscall_tty_ctrl();
    void     syscall_exit();
    void     syscall_sleep();
    void     syscall_yield();

    static inline int _env_format(char* buf, size_t n, char* fmt, int kind, uint64_t bits) {
        union { uint64_t u; double d; } x; x.u = bits;
        if (kind == 2) return snprintf(buf, n, fmt, x.d);
        if (kind == 1) return snprintf(buf, n, fmt, (unsigned long long)bits);
        if (kind == 3) return snprintf(buf, n, fmt, (const char*)(uintptr_t)bits);
        return snprintf(buf, n, fmt, (long long)(int64_t)bits);
    }
    static inline void  _env_write(const char* d, int n) { printf("%.*s", n, d); }
    static inline int   _env_read(char* buf, int max) {
        int i = 0, ch = -1;
        while (i < max - 1) { ch = getchar(); if (ch < 0 || ch == '\n') break; buf[i++] = (char)ch; }
        buf[i] = '\0'; return (i == 0 && ch < 0) ? -1 : i;
    }
    static inline void  _env_tty_clear(void)   { syscall_tty_ctrl(TTY_CTRL_CLEAR, 0); }
    static inline void  _env_tty_cursor(int v) { syscall_tty_ctrl(TTY_CTRL_CURSOR, v ? 1 : 0); }
    static inline long  _env_tty_dims(void)    { return (long)syscall_tty_ctrl(TTY_CTRL_GET_DIMS, 0); }
    static inline void  _env_tty_color(int fg, int bg) { syscall_tty_ctrl(TTY_CTRL_SET_COLOR, ((uint64_t)(uint8_t)bg << 8) | (uint64_t)(uint8_t)fg); }
    static inline void  _env_yield(void)       { }
    static inline void  _env_sleep(int ms)     { (void)ms; }
    static inline void  _env_exit(void)        { exit(0); }
    static inline void  _env_dbg(const char* m) { printf("[DEBUG] %s\n", m); }

    #include "gata_shared.h"
}
