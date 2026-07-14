/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

#ifndef CLOGX_H
#define CLOGX_H

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

enum { LX_TRACE, LX_INFO, LX_WARN, LX_ERROR, LX_FATAL };

static int _lx_min_level = -1;
static int _lx_use_color = -1;
static FILE* _lx_file = NULL;

static void _lx_init(void);
static void _lx_timestamp(char* buf, size_t len);
static void _lx_lock(void);
static void _lx_unlock(void);

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

void lx_set_log_file(const char* path) {
    if (_lx_file) fclose(_lx_file);
    _lx_file = path ? fopen(path, "a") : NULL;
}

#define LOGX_TRACE(msg)  _lx_log(LX_TRACE, __FILE__, __LINE__, msg)
#define LOGX_INFO(msg)   _lx_log(LX_INFO,  __FILE__, __LINE__, msg)
#define LOGX_WARN(msg)   _lx_log(LX_WARN,  __FILE__, __LINE__, msg)
#define LOGX_ERROR(msg)  _lx_log(LX_ERROR, __FILE__, __LINE__, msg)
#define LOGX_FATAL(msg)  _lx_log(LX_FATAL, __FILE__, __LINE__, msg)

#if defined(__linux__) || defined(__APPLE__)
#include "logx_linux.c"
#elif defined(_WIN32)
#include "logx_windows.c"
#endif

#endif
