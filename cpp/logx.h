/*
Copyright (c) 2026, Kairav Dutta (@ka1rav6)

This is free and unencumbered software released into the public domain,
except that the above copyright notice must be retained in all copies
of this software, in source or binary form.  That's the only requirement.
*/

/*
 * logx.h -- single-header logger for C++11 and later.
 * Linux, macOS, BSD, Windows (MSVC / MinGW).
 *
 *   #include "logx.h"
 *
 *   LOGX_INFO  << "listening on port " << 8080;   // stream style
 *   LOGX_WARNF("memory at %.1f%%", 74.2);         // printf style
 *
 * Header-only and multi-file safe: the state lives in function-local statics
 * of inline functions, so every translation unit shares one copy and there is
 * nothing to add to a build file.
 *
 * Everything lives in namespace logx. The level names are mixed case
 * (logx::Level::Error) on purpose -- <windows.h> defines ERROR as a macro.
 *
 * ---------------------------------------------------------------------------
 * Compile-time options (define before including)
 * ---------------------------------------------------------------------------
 *   LOGX_COMPILE_LEVEL   discard calls below this level at compile time, e.g.
 *                        -DLOGX_COMPILE_LEVEL=::logx::Level::Warn
 *   LOGX_NO_SHORT_MACROS skip the unprefixed LOGX_* macros and keep only the
 *                        logx::* functions, if LOGX_INFO collides with yours
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

#ifndef LOGX_HPP_INCLUDED
#define LOGX_HPP_INCLUDED

#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <ctime>
#include <fstream>
#include <iostream>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#if defined(_WIN32)
  #ifndef WIN32_LEAN_AND_MEAN
  #define WIN32_LEAN_AND_MEAN
  #endif
  #ifndef NOMINMAX
  #define NOMINMAX
  #endif
  #include <io.h>
  #include <windows.h>
#else
  #include <unistd.h>
#endif

namespace logx {

enum class Level : int {
    Trace = 0,
    Info  = 1,
    Warn  = 2,
    Error = 3,
    Fatal = 4,
    Off   = 5
};

inline int levelValue(Level l) { return static_cast<int>(l); }

#ifndef LOGX_COMPILE_LEVEL
#define LOGX_COMPILE_LEVEL ::logx::Level::Trace
#endif

namespace detail {

enum class Sink { Split, Out, Err };

struct State {
    Level         level = Level::Trace;
    bool          color = false;
    Sink          sink  = Sink::Split;
    std::ofstream file;
    std::mutex    mu;
};

inline void init(State& s);

/* One State for the whole process: a function-local static inside an inline
 * function is a single object across translation units. C++11 also makes its
 * initialisation thread-safe, which is what orders init() before any use. */
inline State& state() {
    static State s;
    static const bool once = (init(s), true);
    (void)once;
    return s;
}

inline bool isTty(std::FILE* f) {
#if defined(_WIN32)
    return _isatty(_fileno(f)) != 0;
#else
    return isatty(fileno(f)) != 0;
#endif
}

inline bool iequals(const char* a, const char* b) {
    if (!a || !b) return false;
    for (; *a && *b; ++a, ++b) {
        const char ca = (*a >= 'A' && *a <= 'Z') ? static_cast<char>(*a + 32) : *a;
        const char cb = (*b >= 'A' && *b <= 'Z') ? static_cast<char>(*b + 32) : *b;
        if (ca != cb) return false;
    }
    return *a == *b;
}

inline Level parseLevel(const char* s, Level fallback) {
    if (!s || !*s) return fallback;
    if (iequals(s, "TRACE") || iequals(s, "DEBUG") || iequals(s, "ALL") || iequals(s, "0")) return Level::Trace;
    if (iequals(s, "INFO")  || iequals(s, "1")) return Level::Info;
    if (iequals(s, "WARN")  || iequals(s, "WARNING") || iequals(s, "2")) return Level::Warn;
    if (iequals(s, "ERROR") || iequals(s, "ERR") || iequals(s, "3")) return Level::Error;
    if (iequals(s, "FATAL") || iequals(s, "4")) return Level::Fatal;
    if (iequals(s, "OFF")   || iequals(s, "NONE") || iequals(s, "SILENT") || iequals(s, "5")) return Level::Off;
    return fallback;
}

/* -1 unrecognised, 0 off, 1 on */
inline int parseBool(const char* s) {
    if (!s || !*s) return -1;
    if (iequals(s, "1") || iequals(s, "true")  || iequals(s, "yes") || iequals(s, "on"))  return 1;
    if (iequals(s, "0") || iequals(s, "false") || iequals(s, "no")  || iequals(s, "off")) return 0;
    return -1;
}

inline void init(State& s) {
    s.level = parseLevel(std::getenv("LOG_LEVEL"), Level::Trace);

    const char* stream = std::getenv("LOG_STREAM");
    if (stream && iequals(stream, "stdout"))      s.sink = Sink::Out;
    else if (stream && iequals(stream, "stderr")) s.sink = Sink::Err;
    else                                          s.sink = Sink::Split;

    const int forced = parseBool(std::getenv("LOG_COLOR"));
    if (forced >= 0)                  s.color = (forced == 1);
    else if (std::getenv("NO_COLOR")) s.color = false;
    else if (s.sink == Sink::Out)     s.color = isTty(stdout);
    else if (s.sink == Sink::Err)     s.color = isTty(stderr);
    else                              s.color = isTty(stdout) && isTty(stderr);

    const char* path = std::getenv("LOG_FILE");
    if (path && *path) s.file.open(path, std::ios::app);
}

inline const char* levelName(Level l) {
    switch (l) {
        case Level::Trace: return "TRACE";
        case Level::Info:  return "INFO ";
        case Level::Warn:  return "WARN ";
        case Level::Error: return "ERROR";
        case Level::Fatal: return "FATAL";
        default:           return "?????";
    }
}

inline const char* levelColor(Level l) {
    switch (l) {
        case Level::Trace: return "\033[36m";
        case Level::Info:  return "\033[32m";
        case Level::Warn:  return "\033[33m";
        case Level::Error: return "\033[31m";
        case Level::Fatal: return "\033[35m";
        default:           return "\033[0m";
    }
}

inline const char* baseName(const char* path) {
    if (!path || !*path) return "<unknown>";
    const char* base = path;
    for (const char* p = path; *p; ++p)
        if (*p == '/' || *p == '\\') base = p + 1;
    return *base ? base : path;
}

inline std::string timestamp() {
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto ms  = duration_cast<milliseconds>(now.time_since_epoch()) % 1000;
    const std::time_t t = system_clock::to_time_t(now);

    std::tm tmv;
    std::memset(&tmv, 0, sizeof tmv);
#if defined(_WIN32)
    localtime_s(&tmv, &t);
#else
    localtime_r(&t, &tmv);
#endif

    char buf[16];
    std::snprintf(buf, sizeof buf, "%02d:%02d:%02d.%03d",
                  tmv.tm_hour, tmv.tm_min, tmv.tm_sec, static_cast<int>(ms.count()));
    return std::string(buf);
}

/* printf into a std::string, with no length cap. */
inline std::string vformat(const char* fmt, std::va_list ap) {
    if (!fmt) return std::string();
    std::va_list probe;
    va_copy(probe, ap);
    const int n = std::vsnprintf(NULL, 0, fmt, probe);
    va_end(probe);
    if (n <= 0) return std::string();
    std::vector<char> buf(static_cast<size_t>(n) + 1);
    std::vsnprintf(&buf[0], buf.size(), fmt, ap);
    return std::string(&buf[0], static_cast<size_t>(n));
}

inline void emit(Level level, const char* file, int line, const std::string& msg) {
    State& s = state();

    std::ostringstream assembled;
    assembled << '[' << timestamp() << "][" << levelName(level) << "] "
              << baseName(file) << ':' << line << " -> " << msg;
    const std::string text = assembled.str();

    {
        std::lock_guard<std::mutex> lock(s.mu);
        if (s.file.is_open()) {
            s.file << text << '\n';
            s.file.flush();
        } else {
            std::ostream& out =
                s.sink == Sink::Out ? std::cout :
                s.sink == Sink::Err ? std::cerr :
                (level >= Level::Error ? std::cerr : std::cout);
            if (s.color) out << levelColor(level) << text << "\033[0m\n";
            else         out << text << '\n';
            out.flush();
        }
    }

    if (level == Level::Fatal) std::exit(1);
}

}  // namespace detail

// ------------------------------------------------------------------- config

inline bool enabled(Level level) {
    detail::State& s = detail::state();
    std::lock_guard<std::mutex> lock(s.mu);
    return s.level < Level::Off && level >= s.level;
}

inline void setLevel(Level level) {
    detail::State& s = detail::state();
    std::lock_guard<std::mutex> lock(s.mu);
    s.level = level;
}

inline Level getLevel() {
    detail::State& s = detail::state();
    std::lock_guard<std::mutex> lock(s.mu);
    return s.level;
}

inline void setColor(bool enable) {
    detail::State& s = detail::state();
    std::lock_guard<std::mutex> lock(s.mu);
    s.color = enable;
}

/* Append log output to `path`. Returns false if the file could not be opened. */
inline bool setLogFile(const std::string& path) {
    detail::State& s = detail::state();
    std::lock_guard<std::mutex> lock(s.mu);
    if (s.file.is_open()) s.file.close();
    s.file.clear();
    s.file.open(path.c_str(), std::ios::app);
    return s.file.is_open();
}

/* Send log output back to the terminal. */
inline void setLogFile() {
    detail::State& s = detail::state();
    std::lock_guard<std::mutex> lock(s.mu);
    if (s.file.is_open()) s.file.close();
    s.file.clear();
}

inline void flush() {
    detail::State& s = detail::state();
    std::lock_guard<std::mutex> lock(s.mu);
    if (s.file.is_open()) s.file.flush();
    else { std::cout.flush(); std::cerr.flush(); }
}

// --------------------------------------------------------------- printf API

inline void vlogf(Level level, const char* file, int line, const char* fmt, std::va_list ap) {
    if (!enabled(level)) {
        /* A filtered-out Fatal still has to end the process. */
        if (level == Level::Fatal) std::exit(1);
        return;
    }
    detail::emit(level, file, line, detail::vformat(fmt, ap));
}

#if defined(__GNUC__) || defined(__clang__)
inline void logf(Level level, const char* file, int line, const char* fmt, ...)
    __attribute__((format(printf, 4, 5)));
#endif

inline void logf(Level level, const char* file, int line, const char* fmt, ...) {
    std::va_list ap;
    va_start(ap, fmt);
    vlogf(level, file, line, fmt, ap);
    va_end(ap);
}

// --------------------------------------------------------------- stream API

namespace detail {

class Stream {
public:
    Stream(Level level, const char* file, int line)
        : m_level(level), m_file(file), m_line(line), m_active(::logx::enabled(level)) {}

    ~Stream() {
        if (m_active) emit(m_level, m_file, m_line, m_buf.str());
        else if (m_level == Level::Fatal) std::exit(1);
    }

    Stream(const Stream&) = delete;
    Stream& operator=(const Stream&) = delete;

    template <typename T>
    Stream& operator<<(const T& value) {
        if (m_active) m_buf << value;
        return *this;
    }

    /* std::endl, std::hex, std::setw(...) and friends. */
    Stream& operator<<(std::ostream& (*manip)(std::ostream&)) {
        if (m_active) m_buf << manip;
        return *this;
    }

private:
    Level              m_level;
    const char*        m_file;
    int                m_line;
    bool               m_active;
    std::ostringstream m_buf;
};

}  // namespace detail
}  // namespace logx

// ------------------------------------------------------------------- macros

#define LOGX_STREAM(level) ::logx::detail::Stream((level), __FILE__, __LINE__)

#define LOGX_LOGF(level, ...)                                                    \
    do {                                                                         \
        if (::logx::levelValue(level) >= ::logx::levelValue(LOGX_COMPILE_LEVEL))  \
            ::logx::logf((level), __FILE__, __LINE__, __VA_ARGS__);               \
    } while (0)

#ifndef LOGX_NO_SHORT_MACROS

/* Stream style: LOGX_INFO << "port " << 8080; */
#define LOGX_TRACE LOGX_STREAM(::logx::Level::Trace)
#define LOGX_INFO  LOGX_STREAM(::logx::Level::Info)
#define LOGX_WARN  LOGX_STREAM(::logx::Level::Warn)
#define LOGX_ERROR LOGX_STREAM(::logx::Level::Error)
#define LOGX_FATAL LOGX_STREAM(::logx::Level::Fatal)

/* printf style: LOGX_INFOF("port %d", 8080); */
#define LOGX_TRACEF(...) LOGX_LOGF(::logx::Level::Trace, __VA_ARGS__)
#define LOGX_INFOF(...)  LOGX_LOGF(::logx::Level::Info,  __VA_ARGS__)
#define LOGX_WARNF(...)  LOGX_LOGF(::logx::Level::Warn,  __VA_ARGS__)
#define LOGX_ERRORF(...) LOGX_LOGF(::logx::Level::Error, __VA_ARGS__)
#define LOGX_FATALF(...) LOGX_LOGF(::logx::Level::Fatal, __VA_ARGS__)

#endif /* LOGX_NO_SHORT_MACROS */

#endif /* LOGX_HPP_INCLUDED */
