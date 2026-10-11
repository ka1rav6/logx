# LogX for C

Single-header logger for C99 and later. One file, no dependencies, nothing to
link on a modern libc.

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Multi-file programs](#multi-file-programs)
- [Compile-time options](#compile-time-options)
- [Recipes](#recipes)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| Standard | C99 or later. Also compiles as C++. |
| Platforms | Linux, macOS, BSD, Windows (MSVC and MinGW) |
| Linking | Nothing on glibc 2.34+, macOS or Windows. `-lpthread` on older glibc, or build with `-DLOGX_NO_THREADS`. |

## Install

Copy `c/logx.h` into your project. That is the install.

```bash
curl -O https://raw.githubusercontent.com/ka1rav6/logx/main/c/logx.h
```

## Quick start

```c
#include "logx.h"

int main(void) {
    LOGX_TRACE("starting up");
    LOGX_INFO("listening on port %d", 8080);
    LOGX_WARN("memory at %.1f%%", 74.2);
    LOGX_ERROR("connection lost: %s", "ECONNRESET");
    return 0;
}
```

```bash
cc -std=c99 main.c -o app && ./app
```

```
[14:23:01.042][TRACE] main.c:4 -> starting up
[14:23:01.042][INFO ] main.c:5 -> listening on port 8080
[14:23:01.043][WARN ] main.c:6 -> memory at 74.2%
[14:23:01.043][ERROR] main.c:7 -> connection lost: ECONNRESET
```

There is no init call and nothing to configure. The first log call reads the
environment and sets itself up.

## API reference

### Macros

| Macro | Level |
|---|---|
| `LOGX_TRACE(fmt, ...)` | TRACE |
| `LOGX_INFO(fmt, ...)` | INFO |
| `LOGX_WARN(fmt, ...)` | WARN |
| `LOGX_ERROR(fmt, ...)` | ERROR |
| `LOGX_FATAL(fmt, ...)` | FATAL — writes, then `exit(1)` |
| `LOGX_LOG(level, fmt, ...)` | a level chosen at compile time |

`fmt` is an ordinary `printf` format string and the arguments are ordinary
`printf` arguments. The format string is required; the arguments are optional.

```c
LOGX_INFO("plain message");              /* fine */
LOGX_INFO("port %d", 8080);              /* fine */
LOGX_INFO("literal 100%% done");         /* prints: literal 100% done */
```

Because it goes through `printf`, a literal `%` has to be written `%%` even
when there are no arguments. C is the only LogX language where that is true —
the rest skip formatting entirely when you pass no arguments.

On GCC and Clang the format string is checked against its arguments, so a
mismatch is caught at compile time rather than becoming a runtime surprise:

```c
LOGX_INFO("%d", "not a number");
/* warning: format '%d' expects argument of type 'int', but argument 5
   has type 'char *' [-Wformat=] */
```

That is a warning by default and an error under `-Werror`.

### Functions

```c
void lx_set_level(int level);
int  lx_get_level(void);
int  lx_set_log_file(const char *path);   /* 0 on success, -1 if it cannot open */
void lx_set_color(int enabled);
void lx_flush(void);

void lx_log (int level, const char *file, int line, const char *fmt, ...);
void lx_vlog(int level, const char *file, int line, const char *fmt, va_list ap);
```

### Levels

```c
enum { LX_TRACE = 0, LX_INFO = 1, LX_WARN = 2, LX_ERROR = 3, LX_FATAL = 4, LX_OFF = 5 };
```

```c
lx_set_level(LX_WARN);     /* TRACE and INFO now cost a compare and a return */
lx_set_level(LX_OFF);      /* silent */
```

There is no `lx_enabled()`. The level check is already the first thing
`lx_log` does, and because the message is formatted inside the call, a filtered
call never formats anything. If you need to skip expensive *argument*
evaluation, compare against `lx_get_level()` yourself:

```c
if (lx_get_level() <= LX_TRACE)
    LOGX_TRACE("state dump: %s", expensive_serialise(obj));
```

### File output

```c
if (lx_set_log_file("/tmp/app.log") != 0)
    LOGX_WARN("could not open the log file, staying on the terminal");

lx_set_log_file(NULL);     /* back to the terminal */
```

Opened in append mode. The previous file, if any, is closed for you.

## Multi-file programs

By default **each translation unit gets its own copy of the logger state**. That
is what makes the header safe to include anywhere with no build changes, but it
means a programmatic setting does not cross a `.c` boundary:

```c
/* main.c */
lx_set_log_file("/tmp/app.log");
LOGX_INFO("this line goes to the file");
util_work();                       /* logs from util.c still go to the terminal */
```

Pick whichever fix suits you.

### Option 1: configure through the environment

`LOG_LEVEL`, `LOG_FILE`, `LOG_COLOR` and `LOG_STREAM` are read by every unit
independently, so they are process-wide by construction. Nothing to change in
the code:

```bash
LOG_FILE=/tmp/app.log ./app
```

Each unit opens its own handle to the path in append mode, which is fine —
appends are atomic enough for whole lines and every record is flushed.

This is the right answer most of the time.

### Option 2: one shared state

Compile everything with `-DLOGX_SHARED`, and add `LOGX_IMPLEMENTATION` in
exactly one file:

```c
/* logx_impl.c -- the whole file */
#define LOGX_IMPLEMENTATION
#include "logx.h"
```

```bash
cc -std=c99 -DLOGX_SHARED main.c util.c logx_impl.c -o app
```

Now `lx_set_log_file()` and `lx_set_level()` apply process-wide.

`LOGX_SHARED` must be defined for *every* translation unit — put it in your
build flags, not in a single source file — and `LOGX_IMPLEMENTATION` in exactly
one. Two of them gives you duplicate symbols at link time; none gives you
undefined symbols.

## Compile-time options

Define these before the include, or on the command line.

| Define | Effect |
|---|---|
| `LOGX_SHARED` | One shared state across translation units |
| `LOGX_IMPLEMENTATION` | Emit that shared state; exactly one `.c` file |
| `LOGX_NO_THREADS` | Drop the mutex, so no pthread and no `-lpthread` |
| `LOGX_COMPILE_LEVEL` | Discard calls below this level at compile time |
| `LOGX_DEFAULT_LEVEL` | Threshold when `LOG_LEVEL` is unset (default `LX_TRACE`) |
| `LOGX_MSG_MAX` | Formatted-message buffer size (default 2048) |

### LOGX_COMPILE_LEVEL

`lx_set_level()` filters at runtime, which still costs a call. `LOGX_COMPILE_LEVEL`
removes the call site entirely:

```bash
cc -O2 -DLOGX_COMPILE_LEVEL=LX_WARN main.c -o app
```

Now `LOGX_TRACE(...)` and `LOGX_INFO(...)` compile to nothing. Useful for a
release build that keeps its trace logging in the source.

The arguments are still type-checked, so a stripped call cannot rot. They are
*not* evaluated, so do not put side effects in a log call — which was true
anyway.

One sharp edge: `LOGX_COMPILE_LEVEL` removes the whole call, including
`LOGX_FATAL`'s `exit(1)`. At `-DLOGX_COMPILE_LEVEL=LX_OFF` a `LOGX_FATAL` is
not a silent log, it is nothing at all, and execution carries on past it.
Runtime filtering is different — a `LOG_LEVEL=OFF` FATAL still exits 1. Do not
set the compile level above `LX_FATAL`.

### LOGX_NO_THREADS

Single-threaded program, or a platform with no pthreads:

```bash
cc -std=c99 -DLOGX_NO_THREADS main.c -o app
```

The lock becomes a no-op. Everything else is unchanged.

### LOGX_MSG_MAX

A formatted message is built in a fixed stack buffer. Longer messages are
truncated with a trailing `...` rather than being dropped or heap-allocated.
Raise it if you log long strings:

```bash
cc -DLOGX_MSG_MAX=16384 main.c -o app
```

## Recipes

### Your own wrapper that reports the right line

`lx_log` takes the file and line explicitly, which is what lets a wrapper point
at its own caller. Pass `__FILE__` and `__LINE__` through from a macro:

```c
/* Logs a message plus the current errno. */
#define LOG_ERRNO(fmt, ...) \
    lx_log(LX_ERROR, __FILE__, __LINE__, fmt ": %s", __VA_ARGS__, strerror(errno))

...
LOG_ERRNO("could not open %s", path);
```

```
[14:23:01.044][ERROR] io.c:88 -> could not open /etc/shadow: Permission denied
```

A wrapper *function* cannot do this — by the time it runs, `__FILE__` and
`__LINE__` are its own. Take them as parameters if you need one:

```c
void log_request(const char *file, int line, const Request *r) {
    lx_log(LX_INFO, file, line, "%s %s -> %d", r->method, r->path, r->status);
}
#define LOG_REQUEST(r) log_request(__FILE__, __LINE__, (r))
```

### A variadic function of your own

`lx_vlog` takes a `va_list`, so you can forward from your own variadic function:

```c
void audit(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    lx_vlog(LX_INFO, __FILE__, __LINE__, fmt, ap);
    va_end(ap);
}
```

As written, that reports the line inside `audit` — `__FILE__` and `__LINE__`
expand where they are written. To report `audit`'s caller instead, take the
location as parameters and wrap it in a macro, as above.

### Logging to a file and the terminal at once

LogX writes to one destination. For both, let the shell do it:

```bash
LOG_STREAM=stdout ./app | tee /tmp/app.log
```

### CMake

```cmake
add_library(logx INTERFACE)
target_include_directories(logx INTERFACE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/logx)

# Only if you want one shared state across translation units:
# target_compile_definitions(logx INTERFACE LOGX_SHARED)

target_link_libraries(myapp PRIVATE logx)
```

With `LOGX_SHARED`, remember the one file that defines `LOGX_IMPLEMENTATION`.

### Meson

```meson
logx = declare_dependency(include_directories: include_directories('third_party/logx'))
executable('myapp', 'main.c', dependencies: [logx])
```

## Gotchas

**A literal `%` needs `%%`.** Everything goes through `printf`, including
messages with no arguments.

**`LOGX_FATAL` does not return.** It calls `exit(1)`, so `atexit` handlers run
but the rest of your function does not. It exits even when the *runtime* level
filter would have hidden the message — but not when `LOGX_COMPILE_LEVEL` has
stripped the call, which removes the `exit` along with it.

**Per-translation-unit state by default.** See
[Multi-file programs](#multi-file-programs).

**`exit(1)`, not `abort()`.** No core dump. If you want one, log at `LX_ERROR`
and call `abort()` yourself.

**Do not put side effects in a log call.** With `LOGX_COMPILE_LEVEL` the
arguments are not evaluated.

**MSVC does not check format strings.** The `__attribute__((format))` hint is
GCC and Clang only. MSVC compiles the header fine; it just will not catch a
mismatched `%d`.

## Troubleshooting

**`implicit declaration of function 'isatty'`** — something else included a
system header in strict-ANSI mode before `logx.h` got a chance to ask for the
POSIX declarations. Harmless: the header detects this and falls back to
`localtime()` with no TTY detection, so color defaults off and `LOG_COLOR=1`
still works. To get auto-detection back, include `logx.h` first, or compile with
`-std=gnu99` or `-D_POSIX_C_SOURCE=200809L`.

**`undefined reference to lx_log`** — you compiled with `-DLOGX_SHARED` but no
translation unit defines `LOGX_IMPLEMENTATION`.

**`multiple definition of lx_log`** — more than one file defines
`LOGX_IMPLEMENTATION`. Exactly one.

**`undefined reference to pthread_mutex_lock`** — glibc older than 2.34. Add
`-lpthread`, or `-DLOGX_NO_THREADS` if you are single-threaded.

**No color on a terminal** — with the default `split` stream, color needs
*both* stdout and stderr to be terminals. Redirecting either turns it off.
Force it with `LOG_COLOR=1`.

**Log file has no lines after a crash** — every record is flushed as it is
written, so this is not buffering. Check the level and that
`lx_set_log_file` returned 0.

**Lines from one `.c` file go to the terminal while others go to the file** —
per-TU state. See [Multi-file programs](#multi-file-programs).

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [`c/logx.h`](../c/logx.h) — the source, with the same notes in its header comment
- [`test/c/test_logx.c`](../test/c/test_logx.c) — worked examples of every feature
