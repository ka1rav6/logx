#include <unistd.h>
#include <pthread.h>

static pthread_mutex_t _lx_mutex = PTHREAD_MUTEX_INITIALIZER;

static void _lx_lock(void) {
    pthread_mutex_lock(&_lx_mutex);
}

static void _lx_unlock(void) {
    pthread_mutex_unlock(&_lx_mutex);
}

static void _lx_init(void) {
    if (_lx_min_level != -1) return;

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
    else _lx_use_color = isatty(fileno(stdout)) && isatty(fileno(stderr));
}

static void _lx_timestamp(char* buf, size_t len) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    struct tm tm;
    localtime_r(&ts.tv_sec, &tm);
    int ms = ts.tv_nsec / 1000000;
    strftime(buf, len, "%H:%M:%S", &tm);
    size_t pos = strlen(buf);
    snprintf(buf + pos, len - pos, ".%03d", ms);
}
