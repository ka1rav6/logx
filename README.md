# Logger

A minimal, header-friendly C++11 logger with stream syntax, level filtering, timestamps, colors, and thread safety.

## Quick start

Copy `Logger.h` and `Logger.cpp` into your project.  Compile and link `Logger.cpp` along with your other sources.

```cpp
#include "Logger.h"

int main() {
    LOG_TRACE << "starting up";
    LOG_INFO  << "user " << username << " logged in";
    LOG_WARN  << "disk at " << pct << "%";
    LOG_ERROR << "failed to open " << path;
    // LOG_FATAL << "crashing";  // calls std::terminate()
}
```

## Log levels

| Macro       | Level | Output |
|-------------|-------|--------|
| `LOG_TRACE` | 0     | stdout |
| `LOG_INFO`  | 1     | stdout |
| `LOG_WARN`  | 2     | stdout |
| `LOG_ERROR` | 3     | stderr |
| `LOG_FATAL` | 4     | stderr + terminate |

## Runtime level filtering

Set the environment variable `LOG_LEVEL` to `TRACE`, `INFO`, `WARN`, `ERROR`, or `FATAL`.
Messages below the configured level are silently discarded (the stream arguments are **not** evaluated).

```
LOG_LEVEL=WARN ./myapp
```

## Colors

Colors are enabled automatically when both `stdout` and `stderr` are terminals.
Override with the `LOG_COLOR` environment variable:

```
LOG_COLOR=0 ./myapp    # disable
LOG_COLOR=1 ./myapp    # force enable
```

| Level | Color   |
|-------|---------|
| TRACE | Cyan    |
| INFO  | Green   |
| WARN  | Yellow  |
| ERROR | Red     |
| FATAL | Magenta |

## Output format

```
[HH:MM:SS.mmm][LEVEL] filename:line -> message
```

## Thread safety

All output lines are serialized with a mutex.  The mutex is locked once, at flush time (the `LogStream` destructor), not per-`<<` call.

## Requirements

- C++11 or later
- POSIX (`unistd.h`, `localtime_r`) — easily adaptable to Windows

## License

BSD 2-Clause.  See `LICENSE`.
