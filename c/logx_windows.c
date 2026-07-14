#include <io.h>
#include <windows.h>

static CRITICAL_SECTION _lx_mutex;

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
