// env.hosted.g - hosted (libc) environment for host builds and the ASan harness.
//
// Marked @environment: exactly one such file takes part in a build. Only @preamble(user)
// is present, so the build declares a single `user` realm and emits one libc-backed
// translation unit a host driver can call directly.
//
// The floor libgata needs is the set of _env_* binds below: alloc/free, one general
// printf-style formatter (_env_format), the Console/Sys I/O surface, the monotonic
// clock, and the process/thread trio. Everything else (memcpy, strlen, all value
// formatting policy, containers) is pure Gata over them.
//
// Portable across Linux, macOS and Windows. Everything platform-specific is behind
// GATA_HOST_WINDOWS / GATA_HOST_MACOS / GATA_HOST_UNIX below, and the three of them
// are the only place an #ifdef appears.
//
// Compiler: GCC or Clang. libgata's Sync module is built on the __atomic builtins,
// so on Windows this means MinGW-w64 or clang, not MSVC.
//
// `_env_panic` is deliberately absent: `panic` is kernel-only, and a hosted build has
// no kernel realm to write one in.
@environment

@preamble(user) native {
    #if defined(_WIN32) || defined(_WIN64)
    #define GATA_HOST_WINDOWS 1
    #elif defined(__APPLE__)
    #define GATA_HOST_MACOS 1
    #define GATA_HOST_UNIX  1
    #else
    #define GATA_HOST_UNIX  1
    #endif
    #if defined(GATA_HOST_UNIX) && !defined(GATA_HOST_MACOS)
    #ifndef _POSIX_C_SOURCE
    #define _POSIX_C_SOURCE 200809L
    #endif
    #endif
    #ifdef GATA_HOST_WINDOWS
    #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
    #endif
    #ifndef NOMINMAX
    #define NOMINMAX
    #endif
    #ifndef _CRT_SECURE_NO_WARNINGS
    #define _CRT_SECURE_NO_WARNINGS
    #endif
    #include <windows.h>
    #ifndef ENABLE_VIRTUAL_TERMINAL_PROCESSING
    #define ENABLE_VIRTUAL_TERMINAL_PROCESSING 0x0004
    #endif
    #else
    #include <pthread.h>
    #include <sched.h>
    #include <unistd.h>
    #include <errno.h>
    #include <sys/ioctl.h>
    #endif

    #include <stdlib.h>
    #include <string.h>
    #include <stdio.h>
    #include <math.h>
    #include <stdint.h>
    #include <stddef.h>
    #include <stdbool.h>
    #include <time.h>

    int gata_argc = 0;
    char** gata_argv = 0;

    static inline int _env_argc(void) { return gata_argc; }
    static inline char* _env_argv(int i) {
        return (i >= 0 && i < gata_argc) ? gata_argv[i] : NULL;
    }

    static inline void* _env_alloc(size_t n) { return malloc(n); }
    static inline void  _env_free(void* p)   { free(p); }
    static inline int _env_format(char* buf, size_t n, char* fmt, int kind, uint64_t bits) {
        union { uint64_t u; double d; } x; x.u = bits;
        if (kind == 2) return snprintf(buf, n, fmt, x.d);
        if (kind == 1) return snprintf(buf, n, fmt, (unsigned long long)bits);
        if (kind == 3) return snprintf(buf, n, fmt, (const char*)(uintptr_t)bits);
        return snprintf(buf, n, fmt, (long long)(int64_t)bits);
    }
    static void _gata_console_init(void) {
        static int done = 0;
        if (done) return;
        done = 1;
    #ifdef GATA_HOST_WINDOWS
        HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
        DWORD mode = 0;
        if (h != INVALID_HANDLE_VALUE && GetConsoleMode(h, &mode)) {
            SetConsoleMode(h, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
        }
        SetConsoleOutputCP(CP_UTF8);
    #endif
    }

    static inline void _env_write(const char* d, int n) {
        if (!d || n <= 0) return;
        _gata_console_init();
        fwrite(d, 1, (size_t)n, stdout);
        fflush(stdout);
    }

    static inline int _env_read(char* buf, int max) {
        int i = 0, ch = -1;
        if (max <= 0) return -1;
        while (i < max - 1) { ch = getchar(); if (ch < 0 || ch == '\n') break; buf[i++] = (char)ch; }
        buf[i] = '\0';
        return (i == 0 && ch < 0) ? -1 : i;
    }

    static inline void _env_tty_clear(void) {
        _gata_console_init();
        fputs("\x1b[2J\x1b[H", stdout);
        fflush(stdout);
    }

    static inline void _env_tty_cursor(int v) {
        _gata_console_init();
        fputs(v ? "\x1b[?25h" : "\x1b[?25l", stdout);
        fflush(stdout);
    }

    static inline void _env_tty_color(int fg, int bg) {
        static const int a[8] = { 0, 4, 2, 6, 1, 5, 3, 7 };
        int f = fg & 0xF, b = bg & 0xF;
        int fc = (f & 8) ? 90 + a[f & 7] : 30 + a[f & 7];
        int bc = (b & 8) ? 100 + a[b & 7] : 40 + a[b & 7];
        _gata_console_init();
        fprintf(stdout, "\x1b[%d;%dm", fc, bc);
        fflush(stdout);
    }

    static inline int64_t _env_tty_dims(void) {
        int cols = 80, rows = 24;
    #ifdef GATA_HOST_WINDOWS
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &csbi)) {
            cols = (int)(csbi.srWindow.Right - csbi.srWindow.Left + 1);
            rows = (int)(csbi.srWindow.Bottom - csbi.srWindow.Top + 1);
        }
    #else
        struct winsize ws;
        if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
            if (ws.ws_col > 0) cols = (int)ws.ws_col;
            if (ws.ws_row > 0) rows = (int)ws.ws_row;
        }
    #endif
        if (cols <= 0) cols = 80;
        if (rows <= 0) rows = 24;
        return ((int64_t)rows << 32) | (int64_t)(uint32_t)cols;
    }

    static inline void _env_yield(void) {
    #ifdef GATA_HOST_WINDOWS
        SwitchToThread();
    #else
        sched_yield();
    #endif
    }

    static inline void _env_sleep(int ms) {
        if (ms < 0) ms = 0;
    #ifdef GATA_HOST_WINDOWS
        Sleep((DWORD)ms);
    #else
        struct timespec req, rem;
        req.tv_sec  = (time_t)(ms / 1000);
        req.tv_nsec = (long)(ms % 1000) * 1000000L;
        while (nanosleep(&req, &rem) != 0 && errno == EINTR) req = rem;
    #endif
    }

    static inline void _env_exit(void)     { exit(0); }
    static inline void _env_shutdown(void) { exit(0); }
    static inline void _env_reboot(void)   { exit(0); }
    static inline void _env_dbg(const char* m) { printf("[DEBUG] %s\n", m); }

    static inline int64_t _env_time_ns(void) {
    #ifdef GATA_HOST_WINDOWS
        static LARGE_INTEGER freq;
        static int have_freq = 0;
        LARGE_INTEGER now;
        if (!have_freq) { QueryPerformanceFrequency(&freq); have_freq = 1; }
        if (freq.QuadPart <= 0) return 0;
        QueryPerformanceCounter(&now);
        return (int64_t)((now.QuadPart / freq.QuadPart) * 1000000000LL
             + ((now.QuadPart % freq.QuadPart) * 1000000000LL) / freq.QuadPart);
    #elif defined(CLOCK_MONOTONIC)
        struct timespec ts;
        if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
        return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
    #else
        struct timespec ts;
        if (timespec_get(&ts, TIME_UTC) != TIME_UTC) return 0;
        return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
    #endif
    }
    
    #define GATA_HOST_MAX_THREADS 64

    typedef struct gata_host_proc { char name[64]; int hidden; } gata_host_proc;
    typedef struct gata_host_thunk { void (*entry)(void*); void* arg; } gata_host_thunk;

    #ifdef GATA_HOST_WINDOWS
    static HANDLE gata_host_thread[GATA_HOST_MAX_THREADS];
    #else
    static pthread_t gata_host_thread[GATA_HOST_MAX_THREADS];
    #endif
    static int gata_host_live[GATA_HOST_MAX_THREADS];
    static int gata_host_count = 0;
    static int gata_host_hooked = 0;

    static void gata_host_join_all(void) {
        int n = __atomic_load_n(&gata_host_count, __ATOMIC_ACQUIRE);
        int i;
        if (n > GATA_HOST_MAX_THREADS) n = GATA_HOST_MAX_THREADS;
        for (i = 0; i < n; i++) {
            if (!__atomic_load_n(&gata_host_live[i], __ATOMIC_ACQUIRE)) continue;
    #ifdef GATA_HOST_WINDOWS
            WaitForSingleObject(gata_host_thread[i], INFINITE);
            CloseHandle(gata_host_thread[i]);
    #else
            pthread_join(gata_host_thread[i], NULL);
    #endif
            __atomic_store_n(&gata_host_live[i], 0, __ATOMIC_RELEASE);
        }
    }

    #ifdef GATA_HOST_WINDOWS
    static DWORD WINAPI gata_host_trampoline(LPVOID raw) {
        gata_host_thunk t = *(gata_host_thunk*)raw;
        free(raw);
        t.entry(t.arg);
        return 0;
    }
    #else
    static void* gata_host_trampoline(void* raw) {
        gata_host_thunk t = *(gata_host_thunk*)raw;
        free(raw);
        t.entry(t.arg);
        return NULL;
    }
    #endif

    void* _env_proc_create(const char* name) {
        gata_host_proc* p = (gata_host_proc*)calloc(1, sizeof(gata_host_proc));
        if (!p) return NULL;
        if (name) {
            size_t n = strlen(name);
            if (n > sizeof(p->name) - 1) n = sizeof(p->name) - 1;
            memcpy(p->name, name, n);
            p->name[n] = '\0';
        }
        return p;
    }

    /* One stdout, so hiding is recorded rather than enforced. */
    void _env_proc_hide(void* proc) {
        gata_host_proc* p = (gata_host_proc*)proc;
        if (p) p->hidden = 1;
    }

    void _env_thread_spawn(void* proc, const char* name, void (*entry)(void*), int is_user) {
        gata_host_thunk* t;
        int slot;
        (void)proc; (void)name; (void)is_user;
        if (!entry) return;

        if (__atomic_exchange_n(&gata_host_hooked, 1, __ATOMIC_ACQ_REL) == 0) {
            atexit(gata_host_join_all);
        }

        slot = __atomic_fetch_add(&gata_host_count, 1, __ATOMIC_ACQ_REL);
        if (slot >= GATA_HOST_MAX_THREADS) return;

        t = (gata_host_thunk*)malloc(sizeof(gata_host_thunk));
        if (!t) return;
        t->entry = entry;
        t->arg = NULL;

    #ifdef GATA_HOST_WINDOWS
        gata_host_thread[slot] = CreateThread(NULL, 0, gata_host_trampoline, t, 0, NULL);
        if (gata_host_thread[slot] == NULL) { free(t); return; }
    #else
        if (pthread_create(&gata_host_thread[slot], NULL, gata_host_trampoline, t) != 0) {
            free(t);
            return;
        }
    #endif
        __atomic_store_n(&gata_host_live[slot], 1, __ATOMIC_RELEASE);
    }

    #include "shared.h"
}
