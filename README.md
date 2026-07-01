# Logger

A minimal, single-header C++11 logger with stream syntax, level filtering, timestamps, colors, and thread safety.

## Quick start

Drop `Logger.h` into your project, `#include` it, and start logging.

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

Compile with any C++11 compiler — no extra source files to link:

```
g++ -std=c++11 main.cpp -o app
```

## Example program

```cpp
#include "Logger.h"
#include <cmath>

double divide(double a, double b) {
    LOG_TRACE << "divide(" << a << ", " << b << ") called";
    if (b == 0.0) {
        LOG_ERROR << "division by zero, returning NaN";
        return NAN;
    }
    double result = a / b;
    LOG_INFO << a << " / " << b << " = " << result;
    return result;
}

int main() {
    LOG_INFO << "Calculator app started";

    for (int i = 5; i >= 0; --i) {
        divide(10.0, static_cast<double>(i));
    }

    LOG_WARN << "that was some risky math";
    LOG_INFO << "app shutting down";
}
```

Running it:

```
$ g++ -std=c++11 example.cpp -o example
$ ./example
[14:12:06.092][INFO ] example.cpp:16 -> Calculator app started
[14:12:06.092][TRACE] example.cpp:9 -> divide(10, 5) called
[14:12:06.092][INFO ] example.cpp:14 -> 10 / 5 = 2
[14:12:06.092][TRACE] example.cpp:9 -> divide(10, 4) called
[14:12:06.092][INFO ] example.cpp:14 -> 10 / 4 = 2.5
...
[14:12:06.092][ERROR] example.cpp:11 -> division by zero, returning NaN
[14:12:06.092][WARN ] example.cpp:24 -> that was some risky math
[14:12:06.092][INFO ] example.cpp:25 -> app shutting down

$ LOG_LEVEL=WARN ./example
[14:12:06.092][ERROR] example.cpp:11 -> division by zero, returning NaN
[14:12:06.092][WARN ] example.cpp:24 -> that was some risky math
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

Set `LOG_LEVEL` to `TRACE`, `INFO`, `WARN`, `ERROR`, or `FATAL`.
Messages below the threshold are silently discarded (the stream arguments are **not** evaluated).

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
