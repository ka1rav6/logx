# LogX for C++

Single-header logger for C++11 and later. Two call styles — stream and printf —
and no build changes even across many translation units.

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Stream style or printf style?](#stream-style-or-printf-style)
- [Compile-time options](#compile-time-options)
- [Recipes](#recipes)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| Standard | C++11 or later (tested through C++23) |
| Platforms | Linux, macOS, BSD, Windows (MSVC and MinGW) |
| Linking | Nothing. `<mutex>` may want `-pthread` on some older toolchains. |

## Install

Copy `cpp/logx.h` into your project. Header-only and multi-file safe — the
state lives in function-local statics of inline functions, so every translation
unit shares one copy with nothing to add to your build.

```bash
curl -O https://raw.githubusercontent.com/ka1rav6/logx/main/cpp/logx.h
```

## Quick start

```cpp
#include "logx.h"

int main() {
    LOGX_TRACE << "starting up";
    LOGX_INFO  << "listening on port " << 8080;
    LOGX_WARNF("memory at %.1f%%", 74.2);
    LOGX_ERROR << "connection lost";
    return 0;
}
```

```bash
c++ -std=c++11 main.cpp -o app && ./app
```

```
[14:23:01.042][TRACE] main.cpp:4 -> starting up
[14:23:01.042][INFO ] main.cpp:5 -> listening on port 8080
[14:23:01.043][WARN ] main.cpp:6 -> memory at 74.2%
[14:23:01.043][ERROR] main.cpp:7 -> connection lost
```

No init call. The first log call reads the environment and sets itself up.

## API reference

Everything lives in `namespace logx`.

### Stream macros

| Macro | Level |
|---|---|
| `LOGX_TRACE << ...` | TRACE |
| `LOGX_INFO << ...` | INFO |
| `LOGX_WARN << ...` | WARN |
| `LOGX_ERROR << ...` | ERROR |
| `LOGX_FATAL << ...` | FATAL — writes, then `std::exit(1)` |
| `LOGX_STREAM(level) << ...` | a level chosen at runtime |

The record is written when the temporary is destroyed at the end of the
statement, so one statement is one line:

```cpp
LOGX_INFO << "a=" << a << " b=" << b;     // one line
```

`std::hex`, `std::setw`, `std::setprecision` and other manipulators work:

```cpp
LOGX_INFO << "addr 0x" << std::hex << address;
```

### printf macros

| Macro | Level |
|---|---|
| `LOGX_TRACEF(fmt, ...)` | TRACE |
| `LOGX_INFOF(fmt, ...)` | INFO |
| `LOGX_WARNF(fmt, ...)` | WARN |
| `LOGX_ERRORF(fmt, ...)` | ERROR |
| `LOGX_FATALF(fmt, ...)` | FATAL |
| `LOGX_LOGF(level, fmt, ...)` | a level chosen at compile time |

```cpp
LOGX_INFOF("listening on port %d", 8080);
LOGX_WARNF("memory at %.1f%%", 74.2);
```

On GCC and Clang the format string is checked against its arguments. There is no
length cap — the message is sized exactly and heap-allocated as needed.

### Functions

```cpp
namespace logx {

enum class Level : int { Trace = 0, Info = 1, Warn = 2, Error = 3, Fatal = 4, Off = 5 };

int   levelValue(Level l);              // the underlying int

bool  enabled(Level level);             // would a message at this level be emitted?
void  setLevel(Level level);
Level getLevel();
void  setColor(bool enable);

bool  setLogFile(const std::string& path);   // false if it cannot be opened
void  setLogFile();                          // back to the terminal
void  flush();

void  logf (Level level, const char* file, int line, const char* fmt, ...);
void  vlogf(Level level, const char* file, int line, const char* fmt, std::va_list ap);

}
```

### Why `Level::Error` and not `ERROR`

`<windows.h>` defines `ERROR` as a macro. An `enum` member called `ERROR` turns
into `0 = 3` the moment someone includes a Windows header, in a wall of errors
that points at this file rather than at the real cause. Mixed-case names simply
cannot collide, which is why the test suite deliberately `#define ERROR 0`
before including the header.

### Levels and filtering

```cpp
logx::setLevel(logx::Level::Warn);
logx::setLevel(logx::Level::Off);      // silent
```

Use `logx::enabled` to skip work that is only needed for a log line:

```cpp
if (logx::enabled(logx::Level::Trace))
    LOGX_TRACE << "state: " << expensiveDump();
```

A disabled stream macro still constructs its temporary but formats nothing and
writes nothing; the guard is for your side of the `<<`.

### File output

```cpp
if (!logx::setLogFile("/tmp/app.log"))
    LOGX_WARN << "could not open the log file, staying on the terminal";

logx::setLogFile();        // back to the terminal
```

Appended, never truncated. Calling the no-argument overload closes the file.

## Stream style or printf style?

Both are first class. Pick per call site.

**Stream** when you are printing your own types, or composing from several
values:

```cpp
LOGX_INFO << "user " << user << " did " << action;
```

**printf** when you want layout control, or are porting C:

```cpp
LOGX_INFOF("%-20s %8.2f %s", name.c_str(), amount, currency);
```

One thing to watch: `operator<<` on a `std::string` works, but printf needs
`.c_str()`.

## Compile-time options

| Define | Effect |
|---|---|
| `LOGX_COMPILE_LEVEL` | Discard printf-style calls below this level at compile time |
| `LOGX_NO_SHORT_MACROS` | Do not define the `LOGX_*` macros |

### LOGX_COMPILE_LEVEL

```bash
c++ -O2 -DLOGX_COMPILE_LEVEL=::logx::Level::Warn main.cpp -o app
```

This applies to the **printf macros** (`LOGX_INFOF` and friends), which compile
to nothing below the threshold.

One sharp edge: this removes the whole call, including `LOGX_FATALF`'s
`std::exit(1)`. At `Level::Off` a `LOGX_FATALF` is nothing at all and execution
carries on past it. Runtime filtering is different — a `LOG_LEVEL=OFF` fatal
still exits 1. Do not set the compile level above `Level::Fatal`.

The stream macros are not compile-time strippable — they are expressions whose
value you append to, so there is nothing to wrap in an `if`. They still check
the level before formatting anything, so a filtered stream call costs the
construction of an unused `std::ostringstream` and no I/O. If that matters in a
hot loop, guard it:

```cpp
if (logx::enabled(logx::Level::Trace)) LOGX_TRACE << "tight loop " << i;
```

### LOGX_NO_SHORT_MACROS

If `LOGX_INFO` collides with something of yours:

```cpp
#define LOGX_NO_SHORT_MACROS
#include "logx.h"

LOGX_STREAM(::logx::Level::Info) << "still available";
::logx::logf(::logx::Level::Info, __FILE__, __LINE__, "so is this");
```

`LOGX_STREAM` and `LOGX_LOGF` are always defined; only the short names are
suppressed.

## Recipes

### Logging your own types

Give the type an `operator<<` for `std::ostream` and it works with the stream
macros for free:

```cpp
struct Point { int x, y; };

std::ostream& operator<<(std::ostream& os, const Point& p) {
    return os << '(' << p.x << ", " << p.y << ')';
}

LOGX_INFO << "clicked at " << Point{3, 4};
// -> clicked at (3, 4)
```

### Your own wrapper that reports the right line

`logf` takes the file and line explicitly, so pass them through from a macro:

```cpp
#define LOG_RESULT(r) \
    ::logx::logf(::logx::Level::Info, __FILE__, __LINE__, \
                 "%s took %lldms", (r).name.c_str(), (long long)(r).millis)
```

For a stream-style wrapper, hand out a `logx::detail::Stream`:

```cpp
#define LOG_TAGGED(tag) LOGX_INFO << "[" << (tag) << "] "

LOG_TAGGED("db") << "connected in " << ms << "ms";
// -> [db] connected in 12ms
```

### Scoped timing

```cpp
class ScopedTimer {
public:
    ScopedTimer(const char* what, const char* file, int line)
        : m_what(what), m_file(file), m_line(line),
          m_start(std::chrono::steady_clock::now()) {}

    ~ScopedTimer() {
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - m_start).count();
        ::logx::logf(::logx::Level::Trace, m_file, m_line,
                     "%s took %lldms", m_what, (long long)ms);
    }

private:
    const char* m_what;
    const char* m_file;
    int m_line;
    std::chrono::steady_clock::time_point m_start;
};

/* The two-step paste is what makes __LINE__ expand before it is glued on, so
 * two LOG_TIME uses in one scope get different variable names. */
#define LOGX_CAT_(a, b) a##b
#define LOGX_CAT(a, b) LOGX_CAT_(a, b)
#define LOG_TIME(what) \
    ScopedTimer LOGX_CAT(logx_timer_, __LINE__)((what), __FILE__, __LINE__)

void loadConfig() {
    LOG_TIME("loadConfig");
    // ...
}
```

### CMake

```cmake
add_library(logx INTERFACE)
target_include_directories(logx INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/logx)
target_compile_features(logx INTERFACE cxx_std_11)
target_link_libraries(myapp PRIVATE logx)
```

Nothing else — no `LOGX_IMPLEMENTATION` equivalent, because C++ inline
semantics already give one shared state across translation units.

## Gotchas

**`LOGX_FATAL` calls `std::exit(1)`**, not `std::terminate()` or `abort()`. No
core dump, and no stack unwinding past the current statement. It exits even when
the *runtime* level filter would have hidden the message — but not when
`LOGX_COMPILE_LEVEL` has stripped a `LOGX_FATALF` call, which removes the
`exit` along with it.

**Do not store a log macro in a variable.** The record is written by the
destructor, so the statement has to end:

```cpp
auto log = LOGX_INFO;     // does not compile: Stream is non-copyable
```

**`std::endl` inside a record does not start a new record.** It inserts a
newline into the message, which will look like a broken line in your log. One
statement, one record.

**A `std::string` needs `.c_str()` for the printf macros**, like any printf.

**The stream macros are not compile-time strippable.** See
[LOGX_COMPILE_LEVEL](#logx_compile_level).

**Namespace, not a class.** It is `logx::setLogFile(...)`, not
`Logx::setLogFile(...)`. Earlier versions used a class in the global namespace.

## Troubleshooting

**`expected identifier before numeric constant` pointing at the enum** — you
have a macro named `Trace`, `Info`, `Warn`, `Error`, `Fatal` or `Off`. The
mixed-case names avoid the common `<windows.h>` `ERROR` collision; a lowercase
or mixed-case macro of your own can still clash. `#undef` it before including.

**`LOGX_INFO` redefined, or your own `LOGX_INFO` stops working** — use
`LOGX_NO_SHORT_MACROS`.

**Logs from one `.cpp` appear and others do not** — unlike the C header, the
C++ one has a single shared state, so this is a level or stream setting, not a
linkage problem. Check `logx::getLevel()` and `LOG_STREAM`.

**No color on a terminal** — with the default `split` stream, color needs
*both* stdout and stderr to be terminals. Force it with `LOG_COLOR=1`.

**Interleaved output with `std::cout`** — LogX flushes every record, but if you
also write to `std::cout` without flushing, your own output can appear out of
order relative to the log. Use `LOG_STREAM=stderr` to separate the two streams
entirely.

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [LogX for C](c.md) — the C header also compiles as C++ if you prefer `printf`-only
- [`cpp/logx.h`](../cpp/logx.h) — the source
- [`test/cpp/test_logx.cpp`](../test/cpp/test_logx.cpp) — worked examples
