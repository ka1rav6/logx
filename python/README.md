# LogX for Python

**One file. Zero dependencies. Copy. Paste. Log.**

`logx` is a single-file logger: levels, timestamps, the real call site, colors,
and optional file output, in about 250 lines of pure standard library.

It is one language of [LogX](https://github.com/ka1rav6/logx), which ships the
same logger for Python, JavaScript, TypeScript, C, C++, Rust, Go, Java, Zig and
x86-64 assembly.

```bash
pip install python-logx
```

Or just copy `logx.py` into your project. That works exactly the same.

## Use it

```python
from logx import trace, info, warn, error, fatal

info("listening on port %d", 8080)
warn("memory at %.1f%%", 74.2)
error("connection lost: %s", reason)
```

```
[14:23:01.042][INFO ] server.py:12 -> listening on port 8080
[14:23:01.043][WARN ] server.py:13 -> memory at 74.2%
[14:23:01.044][ERROR] server.py:14 -> connection lost: ECONNRESET
```

`ERROR` and `FATAL` go to stderr, everything else to stdout, so piping stdout
still gives you your program's real output. `fatal()` logs and then exits with
status 1.

Arguments use `%`-formatting and are applied only when the level passes the
filter, so a filtered-out call costs almost nothing. A message with no arguments
is never formatted, so `info("100% done")` needs no escaping.

## Configure it

```python
import logx

logx.set_level("WARN")              # or logx.set_level(logx.WARN)
logx.set_log_file("/tmp/app.log")   # append to a file
logx.set_log_file(None)             # back to the terminal
logx.set_color(False)               # override the TTY detection
```

| Function | Purpose |
|---|---|
| `trace() info() warn() error() fatal()` | Log at a level |
| `log(level, msg, *args, depth=2)` | Log at a level chosen at runtime |
| `set_level(level)` / `get_level()` | Read or change the threshold |
| `set_log_file(path)` | Append to a file, or `None` for the terminal |
| `set_color(enabled)` | Force color on or off |
| `flush()` | Flush pending output |

Levels are `logx.TRACE`, `INFO`, `WARN`, `ERROR`, `FATAL`, and `OFF` to silence
everything.

### Wrapping it in your own helper

`depth` controls which frame gets reported, so your wrapper can point at *its*
caller rather than at itself:

```python
def log_request(request):
    logx.log(logx.INFO, "%s %s", request.method, request.path, depth=3)
```

## Environment

Nothing to configure in code — these work out of the box, and are shared with
every other LogX language.

| Variable | Values | Default |
|---|---|---|
| `LOG_LEVEL` | `TRACE` `INFO` `WARN` `ERROR` `FATAL` `OFF`, or `0`–`5` | `TRACE` |
| `LOG_COLOR` | `1`/`true`/`yes`/`on`, or `0`/`false`/`no`/`off` | auto-detect |
| `NO_COLOR` | set to anything to disable color | unset |
| `LOG_FILE` | a path to append to instead of the terminal | unset |
| `LOG_STREAM` | `split`, `stdout`, `stderr` | `split` |

```bash
LOG_LEVEL=WARN python app.py                    # quieter
LOG_FILE=/tmp/app.log python app.py             # to a file, no code change
LOG_STREAM=stderr python app.py > results.txt   # keep stdout for real output
```

Level names are case-insensitive, and `DEBUG`, `ALL`, `WARNING`, `ERR`,
`CRITICAL`, `NONE` and `SILENT` are accepted as aliases. Color is never written
into a log file, whatever the settings say.

## What it is not

`logx` is not a replacement for `logging` or OpenTelemetry. There are no
handlers, no hierarchies, no structured output, no rotation. It is for
prototypes, CLI tools, scripts, game jams, and learning — the cases where you
want a log line without ceremony.

Requires Python 3.8 or newer. Works on Linux, macOS and Windows.

## License

BSD 2-Clause. See `LICENSE`.
