/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

#ifndef CLOGGER_H
#define CLOGGER_H

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

enum { CL_TRACE, CL_INFO, CL_WARN, CL_ERROR, CL_FATAL };

static int _cl_min_level = -1;
static int _cl_use_color = -1;
static FILE* _cl_file = NULL;
static pthread_mutex_t _cl_mutex = PTHREAD_MUTEX_INITIALIZER;

static void _cl_init(void) {
    if (_cl_min_level != -1) return;

    const char* env = getenv("LOG_LEVEL");
    if (!env) _cl_min_level = CL_TRACE;
    else if (strcmp(env, "TRACE") == 0) _cl_min_level = CL_TRACE;
    else if (strcmp(env, "INFO") == 0)  _cl_min_level = CL_INFO;
    else if (strcmp(env, "WARN") == 0)  _cl_min_level = CL_WARN;
    else if (strcmp(env, "ERROR") == 0) _cl_min_level = CL_ERROR;
    else if (strcmp(env, "FATAL") == 0) _cl_min_level = CL_FATAL;
    else _cl_min_level = CL_TRACE;

    const char* col = getenv("LOG_COLOR");
    if (col) _cl_use_color = (strcmp(col, "1") == 0 || strcmp(col, "yes") == 0);
    else _cl_use_color = isatty(fileno(stdout)) && isatty(fileno(stderr));
}

void cl_set_log_file(const char* path) {
    if (_cl_file) fclose(_cl_file);
    _cl_file = path ? fopen(path, "a") : NULL;
}

static const char* _cl_level_str(int level) {
    switch (level) {
        case CL_TRACE: return "TRACE";
        case CL_INFO:  return "INFO ";
        case CL_WARN:  return "WARN ";
        case CL_ERROR: return "ERROR";
        case CL_FATAL: return "FATAL";
        default: return "?????";
    }
}

static const char* _cl_level_color(int level) {
    switch (level) {
        case CL_TRACE: return "\033[36m";
        case CL_INFO:  return "\033[32m";
        case CL_WARN:  return "\033[33m";
        case CL_ERROR: return "\033[31m";
        case CL_FATAL: return "\033[35m";
        default: return "\033[0m";
    }
}

static void _cl_timestamp(char* buf, size_t len) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm;
    localtime_r(&ts.tv_sec, &tm);
    int ms = ts.tv_nsec / 1000000;
    strftime(buf, len, "%H:%M:%S", &tm);
    size_t pos = strlen(buf);
    snprintf(buf + pos, len - pos, ".%03d", ms);
}

void _cl_log(int level, const char* file, int line, const char* msg) {
    _cl_init();
    if (level < _cl_min_level) return;

    char ts[32];
    _cl_timestamp(ts, sizeof(ts));

    pthread_mutex_lock(&_cl_mutex);

    if (_cl_file) {
        fprintf(_cl_file, "[%s][%s] %s:%d -> %s\n",
                ts, _cl_level_str(level), file, line, msg);
        fflush(_cl_file);
    } else {
        FILE* out = (level >= CL_ERROR) ? stderr : stdout;
        if (_cl_use_color)
            fprintf(out, "%s[%s][%s] %s:%d -> %s\033[0m\n",
                    _cl_level_color(level), ts, _cl_level_str(level),
                    file, line, msg);
        else
            fprintf(out, "[%s][%s] %s:%d -> %s\n",
                    ts, _cl_level_str(level), file, line, msg);
        fflush(out);
    }

    pthread_mutex_unlock(&_cl_mutex);

    if (level == CL_FATAL) exit(1);
}

#define LOG_TRACE(msg)  _cl_log(CL_TRACE, __FILE__, __LINE__, msg)
#define LOG_INFO(msg)   _cl_log(CL_INFO,  __FILE__, __LINE__, msg)
#define LOG_WARN(msg)   _cl_log(CL_WARN,  __FILE__, __LINE__, msg)
#define LOG_ERROR(msg)  _cl_log(CL_ERROR, __FILE__, __LINE__, msg)
#define LOG_FATAL(msg)  _cl_log(CL_FATAL, __FILE__, __LINE__, msg)

#endif
