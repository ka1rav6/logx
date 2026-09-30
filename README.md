<p align="center">
  <img src="https://img.shields.io/badge/languages-10-blue?style=flat-square" alt="10 languages">
  <img src="https://img.shields.io/badge/dependencies-zero-brightgreen?style=flat-square" alt="Zero deps">
  <img src="https://img.shields.io/badge/license-BSD%202--Clause-yellow?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/setup-copy/paste-red?style=flat-square" alt="Copy paste">
  <img src="https://img.shields.io/badge/platform-linux%20%7C%20macOS%20%7C%20Windows-lightgrey?style=flat-square" alt="Platform">
</p>

<h1 align="center">LogX</h1>

<p align="center">
  <strong>One file. Ten languages. Zero dependencies.</strong><br>
  <em>Copy. Paste. Log.</em>
</p>

---

## What if logging were this easy?

```python
from logx import info, warn, error

info("listening on port %d", 8080)
warn("memory at %.1f%%", 74.2)
error("connection lost")
```

```c
LOGX_INFO("listening on port %d", 8080);
LOGX_WARN("memory at %.1f%%", 74.2);
LOGX_ERROR("connection lost");
```

```rust
logx_info!("listening on port {}", 8080);
logx_warn!("memory at {:.1}%", 74.2);
logx_error!("connection lost");
```

```js
const { info } = require('./logx');
info('listening on port %d', 8080);
```

Every one of those prints the same thing:

```
[14:23:01.042][INFO ] server.c:42 -> listening on port 8080
```

No installs. No config files. No hunting down 200 transitive deps.

---

## Table of Contents

- [Why LogX?](#why-logx)
- [Quick Start](#quick-start)
- [Per-language setup](#per-language-setup)
- [API Reference](#api-reference)
- [Environment Variables](#environment-variables)
- [Output Format](#output-format)
- [Compile-time options](#compile-time-options)
- [Per-language notes and limits](#per-language-notes-and-limits)
- [Running the tests](#running-the-tests)
- [Philosophy](#philosophy)
- [Contributing](#contributing)
- [License](#license)

---

## Why LogX?

Logging should be as easy as `print()`. But `print()` doesn't give you levels, timestamps, colors, or file output.

Most logging libraries give you all that — and also give you a headache. Setup, configuration, dependencies, framework lock-in...

LogX is the opposite. One file per language. The same API philosophy everywhere. Drop it in, include it, done.

### Why not just `print()`?

| Feature | `print()` | LogX |
|---|---|---|
| Log levels | ❌ | ✅ TRACE, INFO, WARN, ERROR, FATAL |
| Timestamps | ❌ | ✅ `[HH:MM:SS.mmm]` |
| File & line | ❌ | ✅ Automatic, from the real call site |
| Format arguments | ❌ | ✅ Native to each language |
| Colored output | ❌ | ✅ Auto TTY detection, honors `NO_COLOR` |
| File logging | ❌ | ✅ One call, or one env var |
| Errors on stderr | ❌ | ✅ So stdout stays pipeable |
| Thread safe | ❌ | ✅ Mutex-guarded, one write per record |
| Runtime filtering | ❌ | ✅ `LOG_LEVEL=WARN ./app` |
| Still one file | ✅ | ✅ |

---

## Quick Start

| Language | File | Include |
|---|---|---|
| Python | `python/logx.py` | `from logx import info` |
| JavaScript | `js/logx.js` | `const { info } = require('./logx')` |
| TypeScript | `ts/logx.ts` | `import { info } from './logx'` |
| C | `c/logx.h` | `#include "logx.h"` → `LOGX_INFO(...)` |
| C++ | `cpp/logx.h` | `#include "logx.h"` → `LOGX_INFO << ...` |
| Rust | `rust/logx.rs` | `#[macro_use] mod logx; use logx::*;` → `logx_info!(...)` |
| Go | `go/logx.go` | `import "yourmodule/logx"` → `logx.Info(...)` |
| Java | `java/Logx.java` | `Logx.info(...)` |
| Zig | `zig/logx.zig` | `@import("logx.zig")` → `logx.info(@src(), ...)` |
| Assembly | `asm/logx.asm` | `%include "logx.asm"` → `log_info("...")` |

Copy the one file for your language into your project, include it, and start logging. That is the whole install.

---

## Per-language setup

### Python

```bash
pip install python-logx      # or just copy python/logx.py
```

```python
from logx import trace, info, warn, error, fatal, set_level, set_log_file

info("hello %d", 42)
error("something broke")

set_level("WARN")                 # or set_level(logx.WARN)
set_log_file("/tmp/app.log")      # append to a file
set_log_file(None)                # back to the terminal
```

Arguments use `%`-formatting and are applied only when the level passes the filter, so a filtered-out call costs almost nothing. A message with no arguments is never `%`-formatted, so `info("100% done")` needs no escaping.

### JavaScript

```bash
npm install logx             # or just copy js/logx.js
```

```javascript
const { trace, info, warn, error, fatal, setLevel, setLogFile } = require('logx');

info('hello %d', 42);
info('object:', { a: 1 });   // objects are inspected
error('something broke');
```

`js/logx.js` is CommonJS. That is what makes `require()` work, and it also lets `import { info } from './logx.js'` work in a CommonJS package. **If your `package.json` has `"type": "module"`, save the file as `logx.cjs`** — Node then reads it as CommonJS and named imports still work:

```javascript
import { info } from './logx.cjs';
```

### TypeScript

```bash
npm install logx             # or just copy ts/logx.ts
```

```typescript
import { trace, info, warn, error, fatal, setLevel, setLogFile } from './logx';

info('hello %d', 42);
error('something broke');
```

`ts/logx.ts` has no imports at all — not even `node:fs`, which is resolved at call time and only when you ask for file logging. So it compiles and runs unchanged under CommonJS, ESM, Deno, Bun, and browser bundlers, and it needs no `@types/node`.

### C

```c
#include "logx.h"

int main(void) {
    LOGX_INFO("hello %d", 42);
    LOGX_ERROR("something broke");
    lx_set_log_file("/tmp/app.log");   // optional
}
```

```bash
cc -std=c99 main.c -o app
```

On glibc 2.34 and later `-lpthread` is not needed; on older systems add it, or build with `-DLOGX_NO_THREADS` to drop the mutex entirely.

**Multi-file programs.** By default each translation unit keeps its own copy of the logger state, so `lx_set_log_file()` in `main.c` does not affect logs from `util.c`. Two ways to get one shared configuration:

1. Configure through the environment. `LOG_LEVEL` and `LOG_FILE` are read by every unit, so they are process-wide by construction. Nothing to change.
2. Compile everything with `-DLOGX_SHARED` and add `#define LOGX_IMPLEMENTATION` above the include in exactly one `.c` file.

With GCC and Clang the format string is checked against its arguments, so a `%d` fed a string is caught at compile time.

### C++

```cpp
#include "logx.h"

int main() {
    LOGX_INFO  << "hello " << 42;      // stream style
    LOGX_INFOF("hello %d", 42);        // printf style
    logx::setLogFile("/tmp/app.log");
    logx::setLogFile();                // back to the terminal
}
```

```bash
c++ -std=c++11 main.cpp -o app
```

Everything lives in `namespace logx`, and the level names are mixed case (`logx::Level::Error`) because `<windows.h>` defines `ERROR` as a macro. The state lives in function-local statics of inline functions, so every translation unit shares one copy with nothing to add to your build.

### Rust

As one dropped-in file:

```rust
#[macro_use]
mod logx;
use logx::*;          // the macros expand to unqualified calls

fn main() {
    logx_info!("hello {}", 42);
    set_log_file("/tmp/app.log").unwrap();
}
```

Or as a dependency:

```toml
[dependencies]
logx = "1.1"
```

```rust
use logx::*;

logx_info!("hello {}", 42);
```

No dependencies — TTY detection uses `std::io::IsTerminal`, so Rust 1.70 or newer.

### Go

```bash
go get github.com/ka1rav6/logx/go
```

```go
import logx "github.com/ka1rav6/logx/go"

func main() {
    logx.Info("hello %d", 42)
    logx.Error("something broke")
    if err := logx.SetLogFile("/tmp/app.log"); err != nil {
        // ...
    }
}
```

Or copy `go/logx.go` into a `logx/` directory in your own module and import it from there.

### Java

```java
public class Main {
    public static void main(String[] args) {
        Logx.info("hello %d", 42);
        Logx.error("something broke");
        Logx.setLogFile("/tmp/app.log");   // returns false if it cannot open
    }
}
```

```bash
javac Logx.java Main.java && java Main
```

**The file must stay named `Logx.java`** — `javac` requires the file name to match the public class. If your project uses packages, add your own package line as the first line of the file and put it in the matching directory:

```java
package com.example.util;
```

### Zig

```zig
const logx = @import("logx.zig");

pub fn main() void {
    logx.info(@src(), "hello {d}", .{42});
    logx.err(@src(), "something broke", .{});
    logx.setLogFile("/tmp/app.log") catch {};
}
```

`@src()` is what supplies the file and line; Zig has no caller-location builtin that survives a function call, so it is passed in. The level is `.err` rather than `.error` because `error` is a keyword.

Supported Zig: **0.14, 0.15 and 0.16**. See [Per-language notes](#per-language-notes-and-limits).

### x86-64 Assembly (Linux, NASM)

```asm
%include "logx.asm"

section .text
global _start
_start:
    log_init                        ; must be the FIRST instruction in _start
    log_info("listening on port 8080")
    log_warn("memory is high")
    log_error("connection lost")
    log_exit 0
```

```bash
nasm -felf64 main.asm -o main.o && ld main.o -o main
```

Raw syscalls only — nothing to link. The file and line come from NASM's `__?FILE?__` and `__?LINE?__`, so they are the real call site.

`log_init` is a macro that reads the environment off the initial stack, which only works while `rsp` still points at `argc` — hence "first instruction in `_start`". Starting from `main` under libc instead? Skip it and set the state directly:

```asm
    mov byte [log_min_level], LOG_WARN
    mov byte [log_use_color], 1
```

To log a string you built at runtime:

```asm
    lea rsi, [my_buffer]
    mov rdx, my_length
    log_msg(LOG_INFO)
```

To log to a file, either define the path before including:

```asm
%define LOG_FILE_PATH "/tmp/app.log"
%include "logx.asm"
```

or call `log_set_file` with a path in `rdi`, and `log_close` to go back to the terminal.

The log macros preserve every register, including the flags, so they are safe to drop into the middle of existing code.

---

## API Reference

### Log levels

| Level | Value | Description |
|---|---|---|
| TRACE | 0 | Finest-grained diagnostic |
| INFO | 1 | General operational info |
| WARN | 2 | Something unexpected, but not fatal |
| ERROR | 3 | Runtime error or failure |
| FATAL | 4 | Unrecoverable — writes the record, then exits with status 1 |
| OFF | 5 | Silences everything (a threshold only, not something you log at) |

### Per-language API

| Language | Log calls | Set level | Set log file | Back to terminal |
|---|---|---|---|---|
| Python | `trace() info() warn() error() fatal()` | `set_level(l)` | `set_log_file(path)` | `set_log_file(None)` |
| JavaScript | `trace() info() warn() error() fatal()` | `setLevel(l)` | `setLogFile(path)` | `setLogFile(null)` |
| TypeScript | `trace() info() warn() error() fatal()` | `setLevel(l)` | `setLogFile(path)` | `setLogFile(null)` |
| C | `LOGX_TRACE() … LOGX_FATAL()` | `lx_set_level(l)` | `lx_set_log_file(path)` | `lx_set_log_file(NULL)` |
| C++ | `LOGX_INFO <<` and `LOGX_INFOF(...)` | `logx::setLevel(l)` | `logx::setLogFile(path)` | `logx::setLogFile()` |
| Rust | `logx_trace!() … logx_fatal!()` | `set_level(l)` | `set_log_file(path)` | `clear_log_file()` |
| Go | `logx.Trace() … logx.Fatal()` | `logx.SetLevel(l)` | `logx.SetLogFile(path)` | `logx.SetLogFile("")` |
| Java | `Logx.trace() … Logx.fatal()` | `Logx.setLevel(l)` | `Logx.setLogFile(path)` | `Logx.setLogFile(null)` |
| Zig | `logx.trace(@src(), …) … logx.fatal(…)` | `logx.setLevel(l)` | `logx.setLogFile(path)` | `logx.clearLogFile()` |
| Assembly | `log_trace("…") … log_fatal("…")` | `mov byte [log_min_level], …` | `log_set_file` (path in `rdi`) | `call log_close` |

Every language also has:

| Purpose | Name |
|---|---|
| Read the current threshold | `get_level` / `getLevel` / `lx_get_level` / `GetLevel` |
| Skip building an expensive message | `enabled` / `isEnabled` / `Enabled` / `logx::enabled` |
| Force color on or off | `set_color` / `setColor` / `lx_set_color` / `SetColor` |
| Parse a level name | `ParseLevel` / `parseLevel` / `LogxLevel::parse` / `Level.parse` |
| Flush pending output | `flush` / `lx_flush` |

Level setters accept either the constant or a name: `set_level("WARN")` and `set_level(WARN)` both work in Python, JS and TS.

### Reporting the right caller from your own wrapper

If you wrap these functions in a helper of your own, the reported location should still be *your* caller. C, C++, Java, JavaScript and TypeScript do this automatically — they skip frames belonging to the logger. Python and Go take an explicit argument:

```python
def my_helper(msg):
    logx.log(logx.INFO, msg, depth=3)   # report my_helper's caller
```

```go
func myHelper(msg string) {
    logx.Log(logx.INFO, 1, msg)   // 0 = myHelper's own line, 1 = its caller
}
```

---

## Environment Variables

The same five work in every language.

| Variable | Values | Default |
|---|---|---|
| `LOG_LEVEL` | `TRACE` `INFO` `WARN` `ERROR` `FATAL` `OFF`, or `0`–`5` | `TRACE` |
| `LOG_COLOR` | `1`/`true`/`yes`/`on` forces on, `0`/`false`/`no`/`off` forces off | auto-detect |
| `NO_COLOR` | set to anything to disable color ([no-color.org](https://no-color.org)) | unset |
| `LOG_FILE` | a path to append to instead of the terminal | unset |
| `LOG_STREAM` | `split`, `stdout`, `stderr` | `split` |

Level names are case-insensitive and trimmed, and `DEBUG`, `ALL`, `WARNING`, `ERR`, `CRITICAL`, `NONE` and `SILENT` are accepted as aliases.

```bash
LOG_LEVEL=WARN ./myapp                    # quieter
LOG_LEVEL=off ./myapp                     # silent
LOG_FILE=/tmp/app.log ./myapp             # to a file, no code change
LOG_STREAM=stderr ./myapp > results.txt   # keep stdout clean for real output
```

`LOG_STREAM=split` — the default — sends `ERROR` and `FATAL` to stderr and everything else to stdout. `LOG_STREAM=stderr` is the one to reach for in a CLI tool whose stdout is real output.

Color is never written to a log file, whatever the settings say.

---

## Output Format

```
[HH:MM:SS.mmm][LEVEL] filename:line -> message
```

Level names are padded to five characters so the columns line up, and the file is reduced to a base name:

```
[14:23:01.042][INFO ] server.c:42 -> listening on port 8080
[14:23:01.043][WARN ] memory.c:17 -> memory at 74.2%
[14:23:01.044][ERROR] network.c:89 -> connection lost
```

Each record is assembled first and written with a single call, so concurrent threads cannot interleave halves of a line.

---

## Compile-time options

### C (`c/logx.h`)

| Define | Effect |
|---|---|
| `LOGX_SHARED` | One shared state across translation units |
| `LOGX_IMPLEMENTATION` | Emit that shared state; exactly one `.c` file |
| `LOGX_NO_THREADS` | Drop the mutex, so no pthread and no `-lpthread` |
| `LOGX_COMPILE_LEVEL` | Discard calls below this level at compile time |
| `LOGX_DEFAULT_LEVEL` | Level used when `LOG_LEVEL` is unset |
| `LOGX_MSG_MAX` | Formatted-message buffer size (default 2048) |

```bash
cc -DLOGX_COMPILE_LEVEL=LX_WARN -O2 main.c -o app   # trace/info cost nothing
```

### C++ (`cpp/logx.h`)

| Define | Effect |
|---|---|
| `LOGX_COMPILE_LEVEL` | Discard calls below this level, e.g. `::logx::Level::Warn` |
| `LOGX_NO_SHORT_MACROS` | Skip the `LOGX_*` macros if they collide with yours |

---

## Per-language notes and limits

**Timestamps are local time** in Python, JavaScript, TypeScript, C, C++, Go and Java.

**Rust, Zig and assembly print UTC.** None of them can reach a time-zone database without a dependency — Rust's and Zig's standard libraries do not ship one, and the assembly version makes raw syscalls with no libc. Each takes a fixed offset instead:

```bash
LOG_TZ_OFFSET=+05:30 ./rust-app      # also accepts -0800 or a plain 330
```

```asm
    mov qword [log_tz_offset], 5 * 3600 + 30 * 60
```

**Zig supports 0.14 through 0.16.** Zig 0.17 reorganised the standard library — `std.fs.File` became `std.Io.File`, and every read and write now takes an `Io` parameter. `zig/logx.zig` detects that and stops with an explanation rather than failing in a dozen confusing places. Porting it is a matter of threading an `Io` through the four I/O call sites.

**Assembly is x86-64 Linux only,** and `log_init` must be the first instruction in `_start`.

**JavaScript needs a filename change for ESM packages** — see [the JavaScript section](#javascript).

**Java's default package.** `java/Logx.java` declares no package, which works for simple projects and for classes in the default package. Code inside a package cannot see it, so add your own `package` line as described [above](#java).

---

## Running the tests

```bash
make test           # every language whose toolchain is installed
make test-c         # or one at a time: test-c test-cpp test-python test-js
                    # test-ts test-go test-rust test-java test-zig test-asm
make check-all      # build the C and C++ headers in every supported mode
```

A language whose compiler is missing is reported as skipped, not as a failure, so you do not need all ten toolchains installed.

---

## Philosophy

LogX is not trying to replace OpenTelemetry. It is built for:

- Prototypes & hackathons
- CLI tools & scripts
- Game jams
- Students learning a new language
- Small-to-medium projects
- Anyone who just wants to log without ceremony

> *"If you can write print(), you already know how to use LogX."*

---

## Project Structure

```
logger/
├── asm/logx.asm          # x86-64 Assembly (Linux, NASM)
├── c/logx.h              # C99+, Linux/macOS/BSD/Windows
├── cpp/logx.h            # C++11+, Linux/macOS/BSD/Windows
├── go/logx.go            # Go 1.18+
├── java/Logx.java        # Java 8+
├── js/logx.js            # JavaScript (CommonJS)
├── python/logx.py        # Python 3.8+
├── rust/logx.rs          # Rust 1.70+
├── ts/logx.ts            # TypeScript
├── zig/logx.zig          # Zig 0.14-0.16
├── test/                 # Tests per language
├── Makefile              # make test
├── README.md
├── CONTRIBUTING.md
├── LICENSE               # BSD 2-Clause
└── .gitignore
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

BSD 2-Clause. See [LICENSE](LICENSE).
