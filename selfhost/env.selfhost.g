// env.selfhost.g - hosted (libc) environment for a self-hosted, single-threaded, transpile-only
// appa. Named after the project rather than "env.g" so it reads on its own; appa discovers it by
// the @environment marker below, not by filename.
//
// Scope is deliberately narrower than env.hosted.g: a batch compiler never spawns a process or a
// thread, so there is no _env_proc_create / _env_proc_hide / _env_thread_spawn here at all - no
// pthread.h, no CreateThread, no __atomic builtins, nothing that would force the toolchain to be
// GCC/Clang specifically. What's left is leaf I/O: alloc/free, one printf-style formatter, the
// Console surface, the monotonic clock, and the new File trio libselfhost's File.g binds to.
//
// Cross-platform AND Windows XP: every Windows-specific body below uses only Win32 API surface
// that has existed since Windows NT (GetStdHandle, WriteFile, SetConsoleTextAttribute,
// FillConsoleOutputCharacter/Attribute, GetConsoleCursorInfo, GetConsoleScreenBufferInfo,
// QueryPerformanceCounter, SwitchToThread, Sleep) - nothing that requires
// ENABLE_VIRTUAL_TERMINAL_PROCESSING (Windows 10 1511+ only) or any other post-XP feature. Color,
// clear and cursor visibility go through the console API directly rather than emitting ANSI/VT
// escape sequences on Windows, since an XP console has no VT100 interpreter to read them - the
// POSIX branch still emits plain ANSI, which is what every real terminal there understands.
//
// The three platform macros below - GATA_HOST_WINDOWS / GATA_HOST_MACOS / GATA_HOST_UNIX - are
// the only place a top-level #ifdef choice gets made; every function below branches on those
// three, not on its own feature-test.
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
    #include <io.h>
    #else
    #include <sched.h>
    #include <unistd.h>
    #include <errno.h>
    #include <sys/ioctl.h>
    #include <sys/stat.h>
    #include <dirent.h>
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
        SetConsoleOutputCP(CP_UTF8);
    #endif
    }

    #ifdef GATA_HOST_WINDOWS
    static inline void _gata_win_write(DWORD which, const char* d, int n) {
        HANDLE h = GetStdHandle(which);
        DWORD put = 0;
        if (h == INVALID_HANDLE_VALUE || h == NULL) return;
        WriteFile(h, d, (DWORD)n, &put, NULL);
    }
    #endif

    static inline void _env_write(const char* d, int n) {
        if (!d || n <= 0) return;
        _gata_console_init();
    #ifdef GATA_HOST_WINDOWS
        _gata_win_write(STD_OUTPUT_HANDLE, d, n);
    #else
        fwrite(d, 1, (size_t)n, stdout);
        fflush(stdout);
    #endif
    }

    static inline void _env_write_err(const char* d, int n) {
        if (!d || n <= 0) return;
        _gata_console_init();
    #ifdef GATA_HOST_WINDOWS
        _gata_win_write(STD_ERROR_HANDLE, d, n);
    #else
        fwrite(d, 1, (size_t)n, stderr);
        fflush(stderr);
    #endif
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
    #ifdef GATA_HOST_WINDOWS
        HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_SCREEN_BUFFER_INFO csbi;
        if (h != INVALID_HANDLE_VALUE && GetConsoleScreenBufferInfo(h, &csbi)) {
            DWORD cells = (DWORD)csbi.dwSize.X * (DWORD)csbi.dwSize.Y;
            DWORD written;
            COORD origin; origin.X = 0; origin.Y = 0;
            FillConsoleOutputCharacterA(h, ' ', cells, origin, &written);
            FillConsoleOutputAttribute(h, csbi.wAttributes, cells, origin, &written);
            SetConsoleCursorPosition(h, origin);
        }
    #else
        fputs("\x1b[2J\x1b[H", stdout);
        fflush(stdout);
    #endif
    }

    static inline void _env_tty_cursor(int v) {
        _gata_console_init();
    #ifdef GATA_HOST_WINDOWS
        HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE);
        CONSOLE_CURSOR_INFO info;
        if (h != INVALID_HANDLE_VALUE && GetConsoleCursorInfo(h, &info)) {
            info.bVisible = v ? TRUE : FALSE;
            SetConsoleCursorInfo(h, &info);
        }
    #else
        fputs(v ? "\x1b[?25h" : "\x1b[?25l", stdout);
        fflush(stdout);
    #endif
    }
    static inline void _env_tty_color(int fg, int bg) {
        _gata_console_init();
    #ifdef GATA_HOST_WINDOWS
        WORD attr = (WORD)(((bg & 0xF) << 4) | (fg & 0xF));
        SetConsoleTextAttribute(GetStdHandle(STD_OUTPUT_HANDLE), attr);
    #else
        static const int a[8] = { 0, 4, 2, 6, 1, 5, 3, 7 };
        int f = fg & 0xF, b = bg & 0xF;
        int fc = (f & 8) ? 90 + a[f & 7] : 30 + a[f & 7];
        int bc = (b & 8) ? 100 + a[b & 7] : 40 + a[b & 7];
        fprintf(stdout, "\x1b[%d;%dm", fc, bc);
        fflush(stdout);
    #endif
    }

    /*
     * Whether stdout is a terminal. Appa's layout depends on the answer in two places: the width
     * falls back to a fixed 80 under a pipe rather than to the window size, and the spinner does
     * not animate at all - an in-place redraw would be recorded as line noise by anything capturing
     * the output. C# gets this from Console.IsOutputRedirected; Gata gets it from here.
     */
    static inline int _env_tty_isatty(void) {
    #ifdef GATA_HOST_WINDOWS
        return _isatty(_fileno(stdout)) ? 1 : 0;
    #else
        return isatty(STDOUT_FILENO) ? 1 : 0;
    #endif
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

    static inline void _env_exit(int code) { exit(code); }
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

    static inline char* _env_readfile(const char* path, int* out_len) {
        FILE* f;
        long n;
        char* buf;
        size_t got;
        if (out_len) *out_len = 0;
        if (!path) return NULL;
        f = fopen(path, "rb");
        if (!f) return NULL;
        if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return NULL; }
        n = ftell(f);
        if (n < 0) { fclose(f); return NULL; }
        if (fseek(f, 0, SEEK_SET) != 0) { fclose(f); return NULL; }
        buf = (char*)malloc((size_t)n + 1);
        if (!buf) { fclose(f); return NULL; }
        got = (n > 0) ? fread(buf, 1, (size_t)n, f) : 0;
        fclose(f);
        buf[got] = '\0';
        if (out_len) *out_len = (int)got;
        return buf;
    }

    static inline int _env_writefile(const char* path, const char* data, int len) {
        FILE* f;
        size_t want, wrote;
        int ok;
        if (!path) return 0;
        f = fopen(path, "wb");
        if (!f) return 0;
        want = (len > 0) ? (size_t)len : 0;
        wrote = (want > 0) ? fwrite(data, 1, want, f) : 0;
        ok = (wrote == want);
        fclose(f);
        return ok;
    }

    static inline int _env_file_exists(const char* path) {
        FILE* f;
        if (!path) return 0;
        f = fopen(path, "rb");
        if (!f) return 0;
        fclose(f);
        return 1;
    }

    static char* _env_listdir(const char* path, int* out_count, int* out_total_len) {
        char* buf = NULL;
        size_t cap = 0, len = 0;
        int count = 0;
        if (out_count) *out_count = 0;
        if (out_total_len) *out_total_len = 0;
        if (!path) return NULL;
    #ifdef GATA_HOST_WINDOWS
        {
            char pattern[MAX_PATH];
            WIN32_FIND_DATAA fd;
            HANDLE h;
            size_t plen = strlen(path);
            if (plen == 0 || plen >= MAX_PATH - 3) return NULL;
            memcpy(pattern, path, plen);
            if (pattern[plen - 1] != '\\' && pattern[plen - 1] != '/') pattern[plen++] = '\\';
            pattern[plen++] = '*';
            pattern[plen] = '\0';
            h = FindFirstFileA(pattern, &fd);
            if (h == INVALID_HANDLE_VALUE) return NULL;
            do {
                const char* name = fd.cFileName;
                size_t n;
                if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) continue;
                n = strlen(name);
                if (len + n + 1 > cap) {
                    size_t ncap = cap ? cap * 2 : 256;
                    char* nb;
                    while (ncap < len + n + 1) ncap *= 2;
                    nb = (char*)realloc(buf, ncap);
                    if (!nb) { free(buf); FindClose(h); return NULL; }
                    buf = nb; cap = ncap;
                }
                memcpy(buf + len, name, n + 1);
                len += n + 1;
                count++;
            } while (FindNextFileA(h, &fd));
            FindClose(h);
        }
    #else
        {
            DIR* d = opendir(path);
            struct dirent* e;
            if (!d) return NULL;
            while ((e = readdir(d)) != NULL) {
                const char* name = e->d_name;
                size_t n;
                if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) continue;
                n = strlen(name);
                if (len + n + 1 > cap) {
                    size_t ncap = cap ? cap * 2 : 256;
                    char* nb;
                    while (ncap < len + n + 1) ncap *= 2;
                    nb = (char*)realloc(buf, ncap);
                    if (!nb) { free(buf); closedir(d); return NULL; }
                    buf = nb; cap = ncap;
                }
                memcpy(buf + len, name, n + 1);
                len += n + 1;
                count++;
            }
            closedir(d);
        }
    #endif
        if (!buf) { buf = (char*)malloc(1); if (buf) buf[0] = '\0'; }
        if (out_count) *out_count = count;
        if (out_total_len) *out_total_len = (int)len;
        return buf;
    }

    static inline int _env_mkdir(const char* path) {
        if (!path) return 0;
    #ifdef GATA_HOST_WINDOWS
        return CreateDirectoryA(path, NULL) ? 1 : 0;
    #else
        return (mkdir(path, 0755) == 0) ? 1 : 0;
    #endif
    }

    static inline int _env_is_dir(const char* path) {
        if (!path) return 0;
    #ifdef GATA_HOST_WINDOWS
        DWORD attr = GetFileAttributesA(path);
        return (attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY)) ? 1 : 0;
    #else
        struct stat st;
        return (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) ? 1 : 0;
    #endif
    }

    static inline int _env_delete_file(const char* path) {
        if (!path) return 0;
    #ifdef GATA_HOST_WINDOWS
        return DeleteFileA(path) ? 1 : 0;
    #else
        return (remove(path) == 0) ? 1 : 0;
    #endif
    }

    static inline int _env_delete_dir(const char* path) {
        if (!path) return 0;
    #ifdef GATA_HOST_WINDOWS
        return RemoveDirectoryA(path) ? 1 : 0;
    #else
        return (rmdir(path) == 0) ? 1 : 0;
    #endif
    }

    static inline char* _env_cwd(void) {
    #ifdef GATA_HOST_WINDOWS
        DWORD n = GetCurrentDirectoryA(0, NULL);
        char* buf;
        if (n == 0) return NULL;
        buf = (char*)malloc((size_t)n);
        if (!buf) return NULL;
        if (GetCurrentDirectoryA(n, buf) == 0) { free(buf); return NULL; }
        return buf;
    #else
        return getcwd(NULL, 0);
    #endif
    }

    #include "shared.h"
}
