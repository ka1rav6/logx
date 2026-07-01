/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

#ifndef CBUGGEDD_H
#define CBUGGEDD_H

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <pthread.h>

#ifdef _WIN32
 #include <io.h>
 #include <windows.h>
 #define isatty _isatty
 #define fileno _fileno
#else
 #include <unistd.h>
#endif

enum { BD_TRACE, BD_INFO, BD_WARN, BD_ERROR, BD_FATAL };

static int _bd_min_level = -1;
static int _bd_use_color = -1;
static FILE* _bd_file = NULL;
static pthread_mutex_t _bd_mutex = PTHREAD_MUTEX_INITIALIZER;

static void _bd_init(void) {
    if (_bd_min_level != -1) return;

    const char* env = getenv("LOG_LEVEL");
    if (!env) _bd_min_level = BD_TRACE;
    else if (strcmp(env, "TRACE") == 0) _bd_min_level = BD_TRACE;
    else if (strcmp(env, "INFO") == 0)  _bd_min_level = BD_INFO;
    else if (strcmp(env, "WARN") == 0)  _bd_min_level = BD_WARN;
    else if (strcmp(env, "ERROR") == 0) _bd_min_level = BD_ERROR;
    else if (strcmp(env, "FATAL") == 0) _bd_min_level = BD_FATAL;
    else _bd_min_level = BD_TRACE;

    const char* col = getenv("LOG_COLOR");
    if (col) _bd_use_color = (strcmp(col, "1") == 0 || strcmp(col, "yes") == 0);
    else _bd_use_color = isatty(fileno(stdout)) && isatty(fileno(stderr));
}

void bd_set_log_file(const char* path) {
    if (_bd_file) fclose(_bd_file);
    _bd_file = path ? fopen(path, "a") : NULL;
}

static const char* _bd_level_str(int level) {
    switch (level) {
        case BD_TRACE: return "TRACE";
        case BD_INFO:  return "INFO ";
        case BD_WARN:  return "WARN ";
        case BD_ERROR: return "ERROR";
        case BD_FATAL: return "FATAL";
        default: return "?????";
    }
}

static const char* _bd_level_color(int level) {
    switch (level) {
        case BD_TRACE: return "\033[36m";
        case BD_INFO:  return "\033[32m";
        case BD_WARN:  return "\033[33m";
        case BD_ERROR: return "\033[31m";
        case BD_FATAL: return "\033[35m";
        default: return "\033[0m";
    }
}

static void _bd_timestamp(char* buf, size_t len) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm;
    localtime_r(&ts.tv_sec, &tm);
    int ms = ts.tv_nsec / 1000000;
    strftime(buf, len, "%H:%M:%S", &tm);
    size_t pos = strlen(buf);
    snprintf(buf + pos, len - pos, ".%03d", ms);
}

void _bd_log(int level, const char* file, int line, const char* msg) {
    _bd_init();
    if (level < _bd_min_level) return;

    char ts[32];
    _bd_timestamp(ts, sizeof(ts));

    pthread_mutex_lock(&_bd_mutex);

    if (_bd_file) {
        fprintf(_bd_file, "[%s][%s] %s:%d -> %s\n",
                ts, _bd_level_str(level), file, line, msg);
        fflush(_bd_file);
    } else {
        FILE* out = (level >= BD_ERROR) ? stderr : stdout;
        if (_bd_use_color)
            fprintf(out, "%s[%s][%s] %s:%d -> %s\033[0m\n",
                    _bd_level_color(level), ts, _bd_level_str(level),
                    file, line, msg);
        else
            fprintf(out, "[%s][%s] %s:%d -> %s\n",
                    ts, _bd_level_str(level), file, line, msg);
        fflush(out);
    }

    pthread_mutex_unlock(&_bd_mutex);

    if (level == BD_FATAL) exit(1);
}

#define BUGGED_TRACE(msg)  _bd_log(BD_TRACE, __FILE__, __LINE__, msg)
#define BUGGED_INFO(msg)   _bd_log(BD_INFO,  __FILE__, __LINE__, msg)
#define BUGGED_WARN(msg)   _bd_log(BD_WARN,  __FILE__, __LINE__, msg)
#define BUGGED_ERROR(msg)  _bd_log(BD_ERROR, __FILE__, __LINE__, msg)
#define BUGGED_FATAL(msg)  _bd_log(BD_FATAL, __FILE__, __LINE__, msg)

#endif
