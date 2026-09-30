/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

/*
 * logx.h -- single-header logger for C99 and later.
 * Linux, macOS, BSD, Windows (MSVC / MinGW).
 *
 *   #include "logx.h"
 *
 *   LOGX_INFO("listening on port %d", 8080);
 *   LOGX_WARN("memory at %.1f%%", 74.2);
 *   LOGX_ERROR("connection lost");
 *
 * That is the whole setup for a single-file program.
 *
 * ---------------------------------------------------------------------------
 * Multi-file programs
 * ---------------------------------------------------------------------------
 * By default each translation unit keeps its own private copy of the logger
 * state, so lx_set_log_file() in main.c does not affect logs from util.c.
 * Two ways to get one shared configuration:
 *
 *   a) Configure through the environment. LOG_LEVEL / LOG_FILE are read by
 *      every unit, so they are process-wide by construction. Nothing to do.
 *
 *   b) Compile every file with -DLOGX_SHARED, and add
 *          #define LOGX_IMPLEMENTATION
 *      above the include in exactly one .c file. The state then lives in that
 *      file and lx_set_*() applies process-wide.
 *
 * ---------------------------------------------------------------------------
 * Compile-time options (define before including)
 * ---------------------------------------------------------------------------
 *   LOGX_SHARED           one shared state across translation units (see above)
 *   LOGX_IMPLEMENTATION   emit that shared state; exactly one .c file
 *   LOGX_NO_THREADS       drop the mutex, so no pthread and no -lpthread
 *   LOGX_COMPILE_LEVEL    discard calls below this level at compile time,
 *                         e.g. -DLOGX_COMPILE_LEVEL=LX_WARN
 *   LOGX_DEFAULT_LEVEL    level used when LOG_LEVEL is unset (default LX_TRACE)
 *   LOGX_MSG_MAX          formatted-message buffer size (default 2048)
 *
 * ---------------------------------------------------------------------------
 * Environment
 * ---------------------------------------------------------------------------
 *   LOG_LEVEL   TRACE | INFO | WARN | ERROR | FATAL | OFF   (or 0..5)
 *   LOG_COLOR   1/true/yes/on forces, 0/false/no/off disables, unset = auto
 *   NO_COLOR    set to anything to disable color (https://no-color.org)
 *   LOG_FILE    path to append to instead of writing to the terminal
 *   LOG_STREAM  split (default) | stdout | stderr
 */

#ifndef LOGX_H_INCLUDED
#define LOGX_H_INCLUDED

/* Ask for isatty/fileno/localtime_r before any system header is pulled in.
 * Skipped when the program already selected a feature set of its own, and
 * every use below is still guarded, so a strict -std=c99 build that included
 * other headers first degrades to localtime() and no TTY detection instead of
 * failing to compile. */
#if !defined(_WIN32) && !defined(_POSIX_C_SOURCE) && !defined(_XOPEN_SOURCE) \
    && !defined(_GNU_SOURCE) && !defined(_DEFAULT_SOURCE) && !defined(_BSD_SOURCE)
  #define _POSIX_C_SOURCE 200809L
#endif

#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(_WIN32)
  #ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
  #endif
  #ifndef NOMINMAX
  #define NOMINMAX
  #endif
  #include <io.h>
  #include <windows.h>
  #define LX__ISATTY(f) _isatty(_fileno(f))
#else
  #include <unistd.h>
  #if defined(_POSIX_VERSION)
    #define LX__HAVE_POSIX 1
    #define LX__ISATTY(f) isatty(fileno(f))
  #else
    #define LX__ISATTY(f) ((void)(f), 0)
  #endif
  #if !defined(LOGX_NO_THREADS)
    #include <pthread.h>
  #endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ levels */

enum {
    LX_TRACE = 0,
    LX_INFO  = 1,
    LX_WARN  = 2,
    LX_ERROR = 3,
    LX_FATAL = 4,
    LX_OFF   = 5
};

#ifndef LOGX_DEFAULT_LEVEL
#define LOGX_DEFAULT_LEVEL LX_TRACE
#endif

#ifndef LOGX_COMPILE_LEVEL
#define LOGX_COMPILE_LEVEL LX_TRACE
#endif

#ifndef LOGX_MSG_MAX
#define LOGX_MSG_MAX 2048
#endif

/* ----------------------------------------------------------- linkage setup */

#if defined(LOGX_SHARED)
  #define LX__FN
  #if defined(LOGX_IMPLEMENTATION)
    #define LX__EMIT 1
  #else
    #define LX__EMIT 0
  #endif
#else
  /* inline, not plain static: a unit that never calls lx_flush() would
   * otherwise trip -Wunused-function under -Werror. */
  #define LX__FN static inline
  #define LX__EMIT 1
#endif

/* Let the compiler type-check the format string where it knows how. */
#if defined(__GNUC__) || defined(__clang__)
  #define LX__PRINTF(f, a) __attribute__((format(printf, f, a)))
#else
  #define LX__PRINTF(f, a)
#endif

/* --------------------------------------------------------------- lock type */

#if defined(LOGX_NO_THREADS)
  typedef int lx_lock_t;
  #define LX__LOCK_INIT 0
  #define LX__LOCK(p)   ((void)(p))
  #define LX__UNLOCK(p) ((void)(p))
#elif defined(_WIN32)
  typedef SRWLOCK lx_lock_t;              /* statically initialisable, Vista+ */
  #define LX__LOCK_INIT SRWLOCK_INIT
  #define LX__LOCK(p)   AcquireSRWLockExclusive(p)
  #define LX__UNLOCK(p) ReleaseSRWLockExclusive(p)
#else
  typedef pthread_mutex_t lx_lock_t;
  #define LX__LOCK_INIT PTHREAD_MUTEX_INITIALIZER
  #define LX__LOCK(p)   pthread_mutex_lock(p)
  #define LX__UNLOCK(p) pthread_mutex_unlock(p)
#endif

/* ------------------------------------------------------------------- state */

typedef struct lx_state {
    int    ready;   /* 0 until the environment has been parsed */
    int    level;   /* lowest level that still gets emitted */
    int    color;   /* 1 = wrap terminal output in ANSI colors */
    int    stream;  /* 0 = split by level, 1 = all stdout, 2 = all stderr */
    FILE  *fp;      /* non-NULL = append here instead of the terminal */
    int    owned;   /* 1 = we opened fp and must fclose it */
} lx_state;

/* -------------------------------------------------------------- public API */

LX__FN void lx_set_level(int level);
LX__FN int  lx_get_level(void);
LX__FN int  lx_set_log_file(const char *path); /* NULL = terminal; 0 on success */
LX__FN void lx_set_color(int enabled);
LX__FN void lx_flush(void);
LX__FN void lx_vlog(int level, const char *file, int line, const char *fmt, va_list ap);
LX__FN void lx_log(int level, const char *file, int line, const char *fmt, ...) LX__PRINTF(4, 5);

/* -------------------------------------------------------------- the macros */

#define LOGX_LOG(level, ...)                                        \
    do {                                                            \
        if ((level) >= (LOGX_COMPILE_LEVEL))                        \
            lx_log((level), __FILE__, __LINE__, __VA_ARGS__);       \
    } while (0)

#define LOGX_TRACE(...) LOGX_LOG(LX_TRACE, __VA_ARGS__)
#define LOGX_INFO(...)  LOGX_LOG(LX_INFO,  __VA_ARGS__)
#define LOGX_WARN(...)  LOGX_LOG(LX_WARN,  __VA_ARGS__)
#define LOGX_ERROR(...) LOGX_LOG(LX_ERROR, __VA_ARGS__)
#define LOGX_FATAL(...) LOGX_LOG(LX_FATAL, __VA_ARGS__)

/* ============================================================ definitions */

#if LX__EMIT

/* One state object per translation unit by default, one per process under
 * LOGX_SHARED. Hiding it behind an accessor is what lets both work. */
LX__FN lx_state *lx__st(void) {
    static lx_state s;
    return &s;
}

LX__FN lx_lock_t *lx__mu(void) {
    static lx_lock_t m = LX__LOCK_INIT;
    return &m;
}

LX__FN const char *lx__level_name(int level) {
    switch (level) {
        case LX_TRACE: return "TRACE";
        case LX_INFO:  return "INFO ";
        case LX_WARN:  return "WARN ";
        case LX_ERROR: return "ERROR";
        case LX_FATAL: return "FATAL";
        default:       return "?????";
    }
}

LX__FN const char *lx__level_color(int level) {
    switch (level) {
        case LX_TRACE: return "\033[36m";
        case LX_INFO:  return "\033[32m";
        case LX_WARN:  return "\033[33m";
        case LX_ERROR: return "\033[31m";
        case LX_FATAL: return "\033[35m";
        default:       return "\033[0m";
    }
}

/* Case-insensitive compare; avoids strcasecmp/_stricmp portability noise. */
LX__FN int lx__ieq(const char *a, const char *b) {
    for (; *a && *b; a++, b++) {
        int ca = (*a >= 'A' && *a <= 'Z') ? *a + 32 : *a;
        int cb = (*b >= 'A' && *b <= 'Z') ? *b + 32 : *b;
        if (ca != cb) return 0;
    }
    return *a == *b;
}

LX__FN int lx__parse_level(const char *s, int fallback) {
    if (!s || !*s) return fallback;
    if (lx__ieq(s, "TRACE") || lx__ieq(s, "ALL")     || lx__ieq(s, "0")) return LX_TRACE;
    if (lx__ieq(s, "DEBUG"))                                            return LX_TRACE;
    if (lx__ieq(s, "INFO")  || lx__ieq(s, "1"))                         return LX_INFO;
    if (lx__ieq(s, "WARN")  || lx__ieq(s, "WARNING") || lx__ieq(s, "2")) return LX_WARN;
    if (lx__ieq(s, "ERROR") || lx__ieq(s, "ERR")     || lx__ieq(s, "3")) return LX_ERROR;
    if (lx__ieq(s, "FATAL") || lx__ieq(s, "4"))                         return LX_FATAL;
    if (lx__ieq(s, "OFF")   || lx__ieq(s, "NONE")    || lx__ieq(s, "SILENT")
                            || lx__ieq(s, "5"))                         return LX_OFF;
    return fallback;
}

/* -1 unrecognised, 0 off, 1 on */
LX__FN int lx__parse_bool(const char *s) {
    if (!s || !*s) return -1;
    if (lx__ieq(s, "1") || lx__ieq(s, "true")  || lx__ieq(s, "yes") || lx__ieq(s, "on"))  return 1;
    if (lx__ieq(s, "0") || lx__ieq(s, "false") || lx__ieq(s, "no")  || lx__ieq(s, "off")) return 0;
    return -1;
}

/* Caller holds the lock. */
LX__FN void lx__init_locked(void) {
    lx_state *st = lx__st();
    const char *env;
    int b;

    if (st->ready) return;
    st->ready = 1;

    st->level = lx__parse_level(getenv("LOG_LEVEL"), LOGX_DEFAULT_LEVEL);

    env = getenv("LOG_STREAM");
    if (env && lx__ieq(env, "stdout"))      st->stream = 1;
    else if (env && lx__ieq(env, "stderr")) st->stream = 2;
    else                                    st->stream = 0;

    b = lx__parse_bool(getenv("LOG_COLOR"));
    if (b >= 0) {
        st->color = b;
    } else if (getenv("NO_COLOR")) {
        st->color = 0;
    } else if (st->stream == 1) {
        st->color = LX__ISATTY(stdout) ? 1 : 0;
    } else if (st->stream == 2) {
        st->color = LX__ISATTY(stderr) ? 1 : 0;
    } else {
        st->color = (LX__ISATTY(stdout) && LX__ISATTY(stderr)) ? 1 : 0;
    }

    env = getenv("LOG_FILE");
    if (env && *env) {
        FILE *f = fopen(env, "a");
        if (f) { st->fp = f; st->owned = 1; }
    }
}

LX__FN void lx_set_level(int level) {
    lx_state *st = lx__st();
    LX__LOCK(lx__mu());
    lx__init_locked();
    st->level = level;
    LX__UNLOCK(lx__mu());
}

LX__FN int lx_get_level(void) {
    lx_state *st = lx__st();
    int level;
    LX__LOCK(lx__mu());
    lx__init_locked();
    level = st->level;
    LX__UNLOCK(lx__mu());
    return level;
}

LX__FN void lx_set_color(int enabled) {
    lx_state *st = lx__st();
    LX__LOCK(lx__mu());
    lx__init_locked();
    st->color = enabled ? 1 : 0;
    LX__UNLOCK(lx__mu());
}

LX__FN int lx_set_log_file(const char *path) {
    lx_state *st = lx__st();
    FILE *f = NULL;

    if (path && *path) {
        f = fopen(path, "a");
        if (!f) return -1;
    }

    LX__LOCK(lx__mu());
    lx__init_locked();
    if (st->fp && st->owned) fclose(st->fp);
    st->fp = f;
    st->owned = f ? 1 : 0;
    LX__UNLOCK(lx__mu());
    return 0;
}

LX__FN void lx_flush(void) {
    lx_state *st = lx__st();
    LX__LOCK(lx__mu());
    if (st->fp) {
        fflush(st->fp);
    } else {
        fflush(stdout);
        fflush(stderr);
    }
    LX__UNLOCK(lx__mu());
}

LX__FN const char *lx__basename(const char *path) {
    const char *p, *base;
    if (!path || !*path) return "<unknown>";
    base = path;
    for (p = path; *p; p++)
        if (*p == '/' || *p == '\\') base = p + 1;
    return *base ? base : path;
}

LX__FN void lx__timestamp(char *buf, size_t len) {
#if defined(_WIN32)
    SYSTEMTIME lt;
    GetLocalTime(&lt);
    snprintf(buf, len, "%02d:%02d:%02d.%03d",
             (int)lt.wHour, (int)lt.wMinute, (int)lt.wSecond, (int)lt.wMilliseconds);
#else
    time_t secs;
    int ms = 0;
    struct tm tmv;
    struct tm *tp;

  #if defined(CLOCK_REALTIME)
    {
        struct timespec ts;
        if (clock_gettime(CLOCK_REALTIME, &ts) == 0) {
            secs = (time_t)ts.tv_sec;
            ms   = (int)(ts.tv_nsec / 1000000L);
        } else {
            secs = time(NULL);
        }
    }
  #else
    secs = time(NULL);
  #endif

  #if defined(LX__HAVE_POSIX)
    tp = localtime_r(&secs, &tmv);
  #else
    tp = localtime(&secs);
    if (tp) { tmv = *tp; tp = &tmv; }
  #endif

    if (tp)
        snprintf(buf, len, "%02d:%02d:%02d.%03d", tp->tm_hour, tp->tm_min, tp->tm_sec, ms);
    else
        snprintf(buf, len, "--:--:--.---");
#endif
}

LX__FN void lx_vlog(int level, const char *file, int line, const char *fmt, va_list ap) {
    lx_state *st = lx__st();
    char ts[16];
    char msg[LOGX_MSG_MAX];
    int n;

    LX__LOCK(lx__mu());
    lx__init_locked();
    n = (level < st->level || st->level >= LX_OFF);
    LX__UNLOCK(lx__mu());
    if (n) return;

    n = vsnprintf(msg, sizeof msg, fmt ? fmt : "", ap);
    if (n < 0)
        msg[0] = '\0';
    else if ((size_t)n >= sizeof msg)
        memcpy(msg + sizeof msg - 4, "...", 4);

    lx__timestamp(ts, sizeof ts);

    LX__LOCK(lx__mu());
    if (st->fp) {
        fprintf(st->fp, "[%s][%s] %s:%d -> %s\n",
                ts, lx__level_name(level), lx__basename(file), line, msg);
        fflush(st->fp);
    } else {
        FILE *out;
        if (st->stream == 1)      out = stdout;
        else if (st->stream == 2) out = stderr;
        else                      out = (level >= LX_ERROR) ? stderr : stdout;

        if (st->color)
            fprintf(out, "%s[%s][%s] %s:%d -> %s\033[0m\n",
                    lx__level_color(level), ts, lx__level_name(level),
                    lx__basename(file), line, msg);
        else
            fprintf(out, "[%s][%s] %s:%d -> %s\n",
                    ts, lx__level_name(level), lx__basename(file), line, msg);
        fflush(out);
    }
    LX__UNLOCK(lx__mu());

    if (level == LX_FATAL) exit(1);
}

LX__FN void lx_log(int level, const char *file, int line, const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    lx_vlog(level, file, line, fmt, ap);
    va_end(ap);
}

#endif /* LX__EMIT */

#ifdef __cplusplus
}
#endif

#endif /* LOGX_H_INCLUDED */
