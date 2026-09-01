/*
 * env.selfhost.g - A custom self hosted environment, specifically tailored to the needs of Appa. This environment
 * maximizes backwards compatibility with the C standard library, while also providing a set of additional features and utilities
 * that selfhostlib (a libgata fork) can use to provide extended support for filesystem operations and argument handling.
 */
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
    #include <unistd.h>
    #include <errno.h>
    #include <sys/ioctl.h>
    #include <sys/stat.h>
    #include <dirent.h>
    #ifdef __DJGPP__
    #include <conio.h>
    #endif
    #endif

    #include <stdlib.h>
    #include <string.h>
    #include <stdio.h>
    #include <math.h>
    #include <stddef.h>
    #include <time.h>

    #if defined(__has_include)
    #  if __has_include(<stdint.h>)
    #    define GATA_HAVE_STDINT 1
    #  endif
    #elif defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L
    #  define GATA_HAVE_STDINT 1
    #endif

    #ifdef GATA_HAVE_STDINT
    #include <stdint.h>
    #include <stdbool.h>
    #else
    #include <limits.h>
    typedef signed char    int8_t;
    typedef unsigned char  uint8_t;
    typedef short          int16_t;
    typedef unsigned short uint16_t;
    typedef int            int32_t;
    typedef unsigned int   uint32_t;
    #if LONG_MAX > 2147483647L
    typedef long               int64_t;
    typedef unsigned long      uint64_t;
    #else
    typedef long long          int64_t;
    typedef unsigned long long uint64_t;
    #endif
    typedef unsigned long uintptr_t;
    typedef long          intptr_t;
    #ifndef __cplusplus
    typedef int _gata_bool;
    #define bool  _gata_bool
    #define true  1
    #define false 0
    #endif
    #endif

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


    #ifdef GATA_HOST_WINDOWS
    static inline void _gata_win_write(DWORD which, const char* d, int n) {
        HANDLE h = GetStdHandle(which);
        DWORD put = 0;
        if (h == INVALID_HANDLE_VALUE || h == NULL) return;
        WriteFile(h, d, (DWORD)n, &put, NULL);
    }
    #endif

    #ifdef __DJGPP__
    static void _gata_dos_puts(const char* d, int n) {
        int i;
        for (i = 0; i < n; i++) {
            if (d[i] == '\n') putch('\r');
            putch(d[i]);
        }
    }
    #endif

    static inline void _env_write(const char* d, int n) {
        if (!d || n <= 0) return;
    #if defined(__DJGPP__)
        if (isatty(STDOUT_FILENO)) { _gata_dos_puts(d, n); return; }
        fwrite(d, 1, (size_t)n, stdout);
        fflush(stdout);
    #elif defined(GATA_HOST_WINDOWS)
        _gata_win_write(STD_OUTPUT_HANDLE, d, n);
    #else
        fwrite(d, 1, (size_t)n, stdout);
        fflush(stdout);
    #endif
    }

    static inline void _env_write_err(const char* d, int n) {
        if (!d || n <= 0) return;
    #if defined(__DJGPP__)
        if (isatty(STDERR_FILENO)) { _gata_dos_puts(d, n); return; }
        fwrite(d, 1, (size_t)n, stderr);
        fflush(stderr);
    #elif defined(GATA_HOST_WINDOWS)
        _gata_win_write(STD_ERROR_HANDLE, d, n);
    #else
        fwrite(d, 1, (size_t)n, stderr);
        fflush(stderr);
    #endif
    }

    static inline int _env_read(char* buf, int max) {
        (void)buf; (void)max;
        return -1;
    }

    static int _gata_attr[2];
    static unsigned char _gata_pal[16][3];
    static int _gata_pal_set[16];
    static int _gata_pal_ok = 0;

    #ifdef GATA_HOST_WINDOWS

    typedef struct {
        ULONG      cbSize;
        COORD      dwSize;
        COORD      dwCursorPosition;
        WORD       wAttributes;
        SMALL_RECT srWindow;
        COORD      dwMaximumWindowSize;
        WORD       wPopupAttributes;
        BOOL       bFullscreenSupported;
        COLORREF   ColorTable[16];
    } _GATA_CSBIEX;

    typedef BOOL (WINAPI *_GATA_GETEX)(HANDLE, _GATA_CSBIEX*);
    typedef BOOL (WINAPI *_GATA_SETEX)(HANDLE, _GATA_CSBIEX*);

    static int _gata_win_palette(void) {
        HMODULE k32;
        _GATA_GETEX getex;
        _GATA_SETEX setex;
        _GATA_CSBIEX info;
        HANDLE h;
        int i;

        k32 = GetModuleHandleA("kernel32.dll");
        if (!k32) return 0;
        getex = (_GATA_GETEX)GetProcAddress(k32, "GetConsoleScreenBufferInfoEx");
        setex = (_GATA_SETEX)GetProcAddress(k32, "SetConsoleScreenBufferInfoEx");
        if (!getex || !setex) return 0;

        h = GetStdHandle(STD_OUTPUT_HANDLE);
        if (h == INVALID_HANDLE_VALUE || h == NULL) return 0;

        memset(&info, 0, sizeof(info));
        info.cbSize = (ULONG)sizeof(info);
        if (!getex(h, &info)) return 0;
        for (i = 0; i < 16; i++) {
            if (_gata_pal_set[i]) {
                info.ColorTable[i] = (COLORREF)(((DWORD)_gata_pal[i][2] << 16) |
                                                ((DWORD)_gata_pal[i][1] << 8)  |
                                                 (DWORD)_gata_pal[i][0]);
            }
        }

        info.srWindow.Right  = (SHORT)(info.srWindow.Right + 1);
        info.srWindow.Bottom = (SHORT)(info.srWindow.Bottom + 1);
        return setex(h, &info) ? 1 : 0;
    }
    #endif


    static inline int _env_tty_palette(int index, int r, int g, int b) {
        int i = index & 0xF;
        if (r < 0) r = 0; if (r > 255) r = 255;
        if (g < 0) g = 0; if (g > 255) g = 255;
        if (b < 0) b = 0; if (b > 255) b = 255;
        _gata_pal[i][0] = (unsigned char)r;
        _gata_pal[i][1] = (unsigned char)g;
        _gata_pal[i][2] = (unsigned char)b;
        _gata_pal_set[i] = 1;

    #if defined(GATA_HOST_WINDOWS)
        _gata_pal_ok = _gata_win_palette();
    #elif defined(__DJGPP__)
        _gata_pal_ok = 0;
    #else
        _gata_pal_ok = 1;
    #endif
        _gata_attr[0] = -1;
        _gata_attr[1] = -1;
        return _gata_pal_ok;
    }

    static inline int _env_tty_haspalette(void) { return _gata_pal_ok; }

    static inline void _env_tty_palette_reset(void) {
        int i;
        for (i = 0; i < 16; i++) _gata_pal_set[i] = 0;
        _gata_pal_ok = 0;
        _gata_attr[0] = -1;
        _gata_attr[1] = -1;
    }

    static inline void _env_tty_clear(void)   { _gata_attr[0] = -1; _gata_attr[1] = -1; }
    static inline void _env_tty_cursor(int v) { (void)v; }
    static inline void _env_tty_goto(int col, int row) { (void)col; (void)row; }
    static int _gata_attr[2] = { -1, -1 };

    static inline void _gata_tty_color(int which, int fg, int bg) {
        int f = fg & 0xF, b = bg & 0xF;
        int attr = (b << 4) | f;
        if (attr == _gata_attr[which]) return;
        _gata_attr[which] = attr;
    #if defined(__DJGPP__)
        (void)which;
        textattr((unsigned char)attr);
    #elif defined(GATA_HOST_WINDOWS)
        {
            HANDLE h = GetStdHandle(which ? STD_ERROR_HANDLE : STD_OUTPUT_HANDLE);
            if (h != INVALID_HANDLE_VALUE && h != NULL) SetConsoleTextAttribute(h, (WORD)attr);
        }
    #else
        {
            static const int a[8] = { 0, 4, 2, 6, 1, 5, 3, 7 };
            FILE* out = which ? stderr : stdout;
            char fs[24], bs[24];
            if (f != 7 && _gata_pal_ok && _gata_pal_set[f])
                snprintf(fs, sizeof(fs), "38;2;%d;%d;%d", _gata_pal[f][0], _gata_pal[f][1], _gata_pal[f][2]);
            else if (f == 7)
                snprintf(fs, sizeof(fs), "39");
            else
                snprintf(fs, sizeof(fs), "%d", (f & 8) ? 90 + a[f & 7] : 30 + a[f & 7]);

            if (b != 0 && _gata_pal_ok && _gata_pal_set[b])
                snprintf(bs, sizeof(bs), "48;2;%d;%d;%d", _gata_pal[b][0], _gata_pal[b][1], _gata_pal[b][2]);
            else if (b == 0)
                snprintf(bs, sizeof(bs), "49");
            else
                snprintf(bs, sizeof(bs), "%d", (b & 8) ? 100 + a[b & 7] : 40 + a[b & 7]);

            fprintf(out, "\x1b[%s;%sm", fs, bs);
            fflush(out);
        }
    #endif
    }

    static inline void _env_tty_color(int fg, int bg)     { _gata_tty_color(0, fg, bg); }
    static inline void _env_tty_color_err(int fg, int bg) { _gata_tty_color(1, fg, bg); }


    static inline int _env_tty_isatty(void) {
    #ifdef GATA_HOST_WINDOWS
        return _isatty(_fileno(stdout)) ? 1 : 0;
    #else
        return isatty(STDOUT_FILENO) ? 1 : 0;
    #endif
    }

    static inline int _env_tty_isatty_err(void) {
    #ifdef GATA_HOST_WINDOWS
        return _isatty(_fileno(stderr)) ? 1 : 0;
    #else
        return isatty(STDERR_FILENO) ? 1 : 0;
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
    #elif defined(TIOCGWINSZ)
        {
            struct winsize ws;
            if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0) {
                if (ws.ws_col > 0) cols = (int)ws.ws_col;
                if (ws.ws_row > 0) rows = (int)ws.ws_row;
            }
        }
    #endif
        if (cols <= 0) cols = 80;
        if (rows <= 0) rows = 24;
        return ((int64_t)rows << 32) | (int64_t)(uint32_t)cols;
    }

    static inline void _env_yield(void) { }
    static inline void _env_sleep(int ms) { (void)ms; }

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
        return (int64_t)clock() * (int64_t)(1000000000L / CLOCKS_PER_SEC);
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
