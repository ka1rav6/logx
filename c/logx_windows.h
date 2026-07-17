/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

#ifndef LOGX_WINDOWS_H
#define LOGX_WINDOWS_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <io.h>
#include <windows.h>

enum { LX_TRACE, LX_INFO, LX_WARN, LX_ERROR, LX_FATAL };

static int _lx_min_level = -1;
static int _lx_use_color = -1;
static FILE* _lx_file = NULL;
static CRITICAL_SECTION _lx_mutex;

static const char* _lx_level_str(int level) {
    switch (level) {
        case LX_TRACE: return "TRACE";
        case LX_INFO:  return "INFO ";
        case LX_WARN:  return "WARN ";
        case LX_ERROR: return "ERROR";
        case LX_FATAL: return "FATAL";
        default: return "?????";
    }
}

static const char* _lx_level_color(int level) {
    switch (level) {
        case LX_TRACE: return "\033[36m";
        case LX_INFO:  return "\033[32m";
        case LX_WARN:  return "\033[33m";
        case LX_ERROR: return "\033[31m";
        case LX_FATAL: return "\033[35m";
        default: return "\033[0m";
    }
}

static void _lx_lock(void) {
    EnterCriticalSection(&_lx_mutex);
}

static void _lx_unlock(void) {
    LeaveCriticalSection(&_lx_mutex);
}

static void _lx_init(void) {
    if (_lx_min_level != -1) return;

    InitializeCriticalSection(&_lx_mutex);

    const char* env = getenv("LOG_LEVEL");
    if (!env) _lx_min_level = LX_TRACE;
    else if (strcmp(env, "TRACE") == 0) _lx_min_level = LX_TRACE;
    else if (strcmp(env, "INFO") == 0)  _lx_min_level = LX_INFO;
    else if (strcmp(env, "WARN") == 0)  _lx_min_level = LX_WARN;
    else if (strcmp(env, "ERROR") == 0) _lx_min_level = LX_ERROR;
    else if (strcmp(env, "FATAL") == 0) _lx_min_level = LX_FATAL;
    else _lx_min_level = LX_TRACE;

    const char* col = getenv("LOG_COLOR");
    if (col) _lx_use_color = (strcmp(col, "1") == 0 || strcmp(col, "yes") == 0);
    else _lx_use_color = _isatty(_fileno(stdout)) && _isatty(_fileno(stderr));
}

static void _lx_timestamp(char* buf, size_t len) {
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    ULARGE_INTEGER li;
    li.LowPart = ft.dwLowDateTime;
    li.HighPart = ft.dwHighDateTime;
    ULONGLONG ms = li.QuadPart / 10000;
    int sec = (int)((ms / 1000) % 86400);
    int h = sec / 3600;
    int m = (sec % 3600) / 60;
    int s = sec % 60;
    int milli = (int)(ms % 1000);
    snprintf(buf, len, "%02d:%02d:%02d.%03d", h, m, s, milli);
}

static void _lx_log(int level, const char* file, int line, const char* msg) {
    _lx_init();
    if (level < _lx_min_level) return;

    char ts[32];
    _lx_timestamp(ts, sizeof(ts));

    _lx_lock();

    if (_lx_file) {
        fprintf(_lx_file, "[%s][%s] %s:%d -> %s\n",
                ts, _lx_level_str(level), file, line, msg);
        fflush(_lx_file);
    } else {
        FILE* out = (level >= LX_ERROR) ? stderr : stdout;
        if (_lx_use_color)
            fprintf(out, "%s[%s][%s] %s:%d -> %s\033[0m\n",
                    _lx_level_color(level), ts, _lx_level_str(level),
                    file, line, msg);
        else
            fprintf(out, "[%s][%s] %s:%d -> %s\n",
                    ts, _lx_level_str(level), file, line, msg);
        fflush(out);
    }

    _lx_unlock();

    if (level == LX_FATAL) exit(1);
}

static void lx_set_log_file(const char* path) {
    if (_lx_file) fclose(_lx_file);
    _lx_file = path ? fopen(path, "a") : NULL;
}

#define LOGX_TRACE(msg)  _lx_log(LX_TRACE, __FILE__, __LINE__, msg)
#define LOGX_INFO(msg)   _lx_log(LX_INFO,  __FILE__, __LINE__, msg)
#define LOGX_WARN(msg)   _lx_log(LX_WARN,  __FILE__, __LINE__, msg)
#define LOGX_ERROR(msg)  _lx_log(LX_ERROR, __FILE__, __LINE__, msg)
#define LOGX_FATAL(msg)  _lx_log(LX_FATAL, __FILE__, __LINE__, msg)

#endif
