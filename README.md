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

## Documentation

**One page per language, each standalone.** If you only care about Go, the Go
page is all you need.

| Language | Docs | File to copy | Package |
|---|---|---|---|
| C | **[docs/c.md](docs/c.md)** | `c/logx.h` | — |
| C++ | **[docs/cpp.md](docs/cpp.md)** | `cpp/logx.h` | — |
| Python | **[docs/python.md](docs/python.md)** | `python/logx.py` | `pip install python-logx` |
| JavaScript | **[docs/javascript.md](docs/javascript.md)** | `js/logx.js` | `npm install logx` |
| TypeScript | **[docs/typescript.md](docs/typescript.md)** | `ts/logx.ts` | `npm install logx` |
| Rust | **[docs/rust.md](docs/rust.md)** | `rust/logx.rs` | `logx = "1.1"` |
| Go | **[docs/go.md](docs/go.md)** | `go/logx.go` | `go get github.com/ka1rav6/logx/go` |
| Java | **[docs/java.md](docs/java.md)** | `java/Logx.java` | — |
| Zig | **[docs/zig.md](docs/zig.md)** | `zig/logx.zig` | — |
| Assembly | **[docs/assembly.md](docs/assembly.md)** | `asm/logx.asm` | — |

Plus two cross-cutting pages:

- **[docs/format.md](docs/format.md)** — the output format, the levels, and the
  five environment variables, which are identical everywhere.
- **[docs/porting.md](docs/porting.md)** — the contract a new language has to
  meet.

---

## Why LogX?

Logging should be as easy as `print()`. But `print()` doesn't give you levels,
timestamps, colors, or file output.

Most logging libraries give you all that — and also give you a headache. Setup,
configuration, dependencies, framework lock-in...

LogX is the opposite. One file per language. The same API philosophy everywhere.
Drop it in, include it, done.

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

## Quick start

Copy the one file for your language into your project, include it, and start
logging. That is the whole install.

```c
#include "logx.h"

int main(void) {
    LOGX_INFO("listening on port %d", 8080);
}
```

```bash
cc -std=c99 main.c -o app && ./app
```

```
[14:23:01.042][INFO ] main.c:4 -> listening on port 8080
```

No init call, no logger object, no configuration file. The first log call reads
the environment and sets itself up.

Your language's page in the table above has the equivalent, plus its full API.

---

## Output format

```
[HH:MM:SS.mmm][LEVEL] filename:line -> message
```

Level names are padded to five characters so columns line up, and the file is
reduced to a base name:

```
[14:23:01.042][INFO ] server.c:42 -> listening on port 8080
[14:23:01.043][WARN ] memory.c:17 -> memory at 74.2%
[14:23:01.044][ERROR] network.c:89 -> connection lost
```

Each record is assembled in full and written with a single call, so concurrent
threads cannot interleave halves of a line.

Details, including a regex that parses it, are in
[docs/format.md](docs/format.md).

---

## Log levels

| Level | Value | Description |
|---|---|---|
| TRACE | 0 | Finest-grained diagnostic |
| INFO | 1 | General operational info |
| WARN | 2 | Something unexpected, but not fatal |
| ERROR | 3 | Runtime error or failure |
| FATAL | 4 | Unrecoverable — writes the record, then exits with status 1 |
| OFF | 5 | Silences everything (a threshold only, not something you log at) |

With the default stream setting, `ERROR` and `FATAL` go to stderr and everything
else to stdout.

---

## Environment variables

The same five work in every language, with no code changes.

| Variable | Values | Default |
|---|---|---|
| `LOG_LEVEL` | a level name, or `0`–`5` | `TRACE` |
| `LOG_COLOR` | `1`/`true`/`yes`/`on` forces on, `0`/`false`/`no`/`off` forces off | auto-detect |
| `NO_COLOR` | set to anything to disable color ([no-color.org](https://no-color.org)) | unset |
| `LOG_FILE` | a path to append to instead of the terminal | unset |
| `LOG_STREAM` | `split`, `stdout`, `stderr` | `split` |

```bash
LOG_LEVEL=WARN ./myapp                    # quieter
LOG_LEVEL=off ./myapp                     # silent
LOG_FILE=/tmp/app.log ./myapp             # to a file, no code change
LOG_STREAM=stderr ./myapp > results.txt   # keep stdout clean for real output
```

Names are case-insensitive and trimmed, and `DEBUG`, `ALL`, `WARNING`, `ERR`,
`CRITICAL`, `NONE` and `SILENT` are accepted as aliases. An unrecognised value
falls back to the default rather than erroring, so a typo in a deployment script
makes your program noisy, never broken.

Color is never written into a log file, whatever the settings say.

---

## The API, across all ten

Each language spells these its own way; the per-language pages give exact
signatures.

| Purpose | Names |
|---|---|
| Log at a level | `trace` `info` `warn` `error` `fatal` |
| Log at a runtime-chosen level | `log` |
| Read / change the threshold | `get_level` / `set_level` |
| Force color on or off | `set_color` |
| Append to a file | `set_log_file` |
| Back to the terminal | the same call with null / empty / no argument |
| Cheap check before building a message | `enabled` |
| Parse a level name | `parse_level` |
| Flush pending output | `flush` |

### Reporting the right caller from your own wrapper

Worth knowing before you build a logging helper, because it differs by language.

| Language | A wrapper of yours reports | How to get the call site |
|---|---|---|
| C, C++ | the call site | pass `__FILE__`/`__LINE__` to `lx_log` / `logx::logf` from a macro |
| Rust | the call site, from a `macro_rules!` wrapper | use a macro, or pass `file!()`/`line!()` to `logx_log` |
| Assembly | the call site | the log macros expand where you write them |
| Python | your wrapper's own line | pass `depth=3` |
| Go | your wrapper's own line | pass `skip: 1` |
| Zig | wherever you point it | forward a `@src()` |
| **JavaScript, TypeScript, Java** | **your wrapper's own line** | **not expressible** — see below |

JavaScript, TypeScript and Java find the location by skipping stack frames that
belong to the logger and reporting the first one that does not — which is your
wrapper. That is usually what you want from a dedicated logging helper, since it
identifies which helper produced the line. But there is no depth or skip
parameter in those three, so if you need the original call site, pass it in the
message yourself.

---

## Per-language notes and limits

**Timestamps are local time** in Python, JavaScript, TypeScript, C, C++, Go and
Java.

**Rust, Zig and assembly print UTC.** None of them can reach a time-zone
database without a dependency — Rust's and Zig's standard libraries do not ship
one, and the assembly version makes raw syscalls with no libc. Each takes a
fixed offset instead:

```bash
LOG_TZ_OFFSET=+05:30 ./rust-app      # also accepts -0800 or a plain 330
```

**Zig supports 0.14 through 0.16.** Zig 0.17 reorganised the standard library;
`zig/logx.zig` detects that and stops with an explanation rather than failing in
a dozen confusing places. See [docs/zig.md](docs/zig.md).

**Assembly is x86-64 Linux only,** and `log_init` must be the first instruction
in `_start`.

**JavaScript needs a filename change for ESM packages.** `js/logx.js` is
CommonJS; in a `"type": "module"` package, save it as `logx.cjs`. Installing
from npm avoids this. See [docs/javascript.md](docs/javascript.md).

**Java's file must stay named `Logx.java`,** and it declares no package. Code
inside a package needs a `package` line added to the file. See
[docs/java.md](docs/java.md).

**C keeps per-translation-unit state by default.** Configure through the
environment, or build with `-DLOGX_SHARED`. See [docs/c.md](docs/c.md).

---

## Running the tests

```bash
make test           # every language whose toolchain is installed
make test-c         # or one at a time: test-c test-cpp test-python test-js
                    # test-ts test-go test-rust test-java test-zig test-asm
make check-all      # build the C and C++ headers in every supported mode
```

A language whose compiler is missing is reported as skipped, not as a failure,
so you do not need all ten toolchains installed.

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

## Project structure

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
├── docs/                 # One page per language
├── test/                 # Tests per language
├── Makefile              # make test
├── README.md
├── CONTRIBUTING.md
├── LICENSE               # BSD 2-Clause
└── .gitignore
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the process, and
[docs/porting.md](docs/porting.md) for the contract a new language has to meet.

---

## License

BSD 2-Clause. See [LICENSE](LICENSE).
