# LogX for Python

Single-file logger for Python 3.8+. About 250 lines of pure standard library.

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Formatting](#formatting)
- [Recipes](#recipes)
- [logx or the stdlib logging module?](#logx-or-the-stdlib-logging-module)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| Python | 3.8 or later |
| Platforms | Linux, macOS, Windows |
| Dependencies | None |

## Install

```bash
pip install python-logx
```

Or copy `python/logx.py` next to your code. Both work identically; the package
is just the same single file.

## Quick start

```python
from logx import trace, info, warn, error

trace("starting up")
info("listening on port %d", 8080)
warn("memory at %.1f%%", 74.2)
error("connection lost: %s", reason)
```

```
[14:23:01.042][TRACE] server.py:3 -> starting up
[14:23:01.042][INFO ] server.py:4 -> listening on port 8080
[14:23:01.043][WARN ] server.py:5 -> memory at 74.2%
[14:23:01.043][ERROR] server.py:6 -> connection lost: ECONNRESET
```

Nothing to configure and no logger object to create. The module reads the
environment on import.

## API reference

### Log functions

```python
trace(msg, *args, depth=3)
info (msg, *args, depth=3)
warn (msg, *args, depth=3)
error(msg, *args, depth=3)
fatal(msg, *args, depth=3)      # logs, then sys.exit(1)

log(level, msg, *args, depth=2) # a level chosen at runtime
```

`msg` is a `%`-style format string, `args` are its arguments, and `depth`
controls which stack frame is reported — see
[Wrapping it in your own helper](#wrapping-it-in-your-own-helper).

`msg` does not have to be a string; anything else is passed through `str()`.

### Configuration

```python
set_level(level)      # a constant or a name: set_level("WARN") or set_level(logx.WARN)
get_level() -> int
set_color(enabled)    # override the TTY detection
set_log_file(path)    # append to a file; None goes back to the terminal
flush()
```

### Levels

```python
logx.TRACE   # 0
logx.INFO    # 1
logx.WARN    # 2
logx.ERROR   # 3
logx.FATAL   # 4
logx.OFF     # 5  -- a threshold only; silences everything
```

```python
import logx

logx.set_level("WARN")          # names are case-insensitive, 0-5 also work
logx.set_level(logx.OFF)        # silent
```

There is no `enabled()` in the Python version — see
[Skipping expensive arguments](#skipping-expensive-arguments).

### File output

```python
logx.set_log_file("/tmp/app.log")
logx.set_log_file(None)          # back to the terminal
```

Opened in append mode with UTF-8 encoding. The previous file is closed for you.
Unlike the other languages, this raises `OSError` if the path cannot be opened,
because that is what a Python caller expects:

```python
try:
    logx.set_log_file(path)
except OSError as exc:
    logx.warn("could not open %s: %s", path, exc)
```

## Formatting

Arguments use `%`-formatting, and are applied **only when the level passes the
filter**. A filtered-out call does no formatting at all, so leaving `trace()`
calls in hot code is cheap.

```python
info("port %d", 8080)                  # port 8080
info("memory at %.1f%%", 74.2)         # memory at 74.2%
info("user %s did %s", name, action)
```

A message with **no** arguments is never formatted, so a literal `%` needs no
escaping:

```python
info("100% done")                      # 100% done
```

A format mismatch logs the pieces instead of raising. A broken log statement
should not take your program down:

```python
info("expected two: %d %d", 1)
# -> expected two: %d %d (1,)
```

Non-string messages go through `str()`:

```python
info({"a": 1})                         # {'a': 1}
info(some_exception)                   # whatever str() gives
```

## Recipes

### Wrapping it in your own helper

The `depth` argument says which frame to report. The default for `trace()` and
friends is 3, which means "my caller". From inside your own wrapper you want one
more:

```python
import logx

def log_request(request):
    logx.log(logx.INFO, "%s %s -> %d",
             request.method, request.path, request.status, depth=3)
```

```
[14:23:01.044][INFO ] views.py:52 -> GET /health -> 200
```

`views.py:52` is the line that called `log_request`, not the line inside it.

Counting frames: `depth=1` is `log` itself, `2` is whoever called `log`
(the default), `3` is one further out, and so on.

### Skipping expensive arguments

Formatting is already lazy, but the arguments themselves are evaluated at the
call site. For something genuinely expensive, check the level first:

```python
if logx.get_level() <= logx.TRACE:
    logx.trace("state: %s", expensive_dump())
```

### Logging exceptions with a traceback

```python
import traceback

try:
    risky()
except Exception:
    logx.error("risky() failed:\n%s", traceback.format_exc())
```

### A per-module prefix

```python
import logx

def tagged(tag):
    def emit(msg, *args):
        logx.log(logx.INFO, "[%s] " + msg, tag, *args, depth=3)
    return emit

log = tagged("db")
log("connected in %dms", 12)
# -> [db] connected in 12ms
```

### Quieting it inside tests

```python
import logx, pytest

@pytest.fixture(autouse=True)
def quiet_logs():
    previous = logx.get_level()
    logx.set_level(logx.OFF)
    yield
    logx.set_level(previous)
```

Or set `LOG_LEVEL=OFF` in your test runner's environment.

### Capturing output in a test

`logx` writes to `sys.stdout` and `sys.stderr` by name on every call, so
pytest's `capsys` and `unittest`'s `redirect_stdout` both work:

```python
def test_logs_the_port(capsys):
    logx.info("listening on port %d", 8080)
    assert "listening on port 8080" in capsys.readouterr().out
```

For the file path instead:

```python
def test_file_output(tmp_path):
    path = tmp_path / "app.log"
    logx.set_log_file(str(path))
    logx.info("hello")
    logx.set_log_file(None)
    assert "hello" in path.read_text()
```

## logx or the stdlib logging module?

`logging` is the right answer when you need handlers, per-logger hierarchies,
filters, rotation, structured output, or integration with a framework that
already configures it. It is in the standard library and it is good.

`logx` is the right answer when you want a log line with a timestamp and a call
site and you do not want to think about it. No `basicConfig`, no handler, no
`getLogger(__name__)`, and the file-and-line is on by default rather than a
format-string option you have to remember.

They coexist fine — `logx` touches nothing in `logging`.

## Gotchas

**`fatal()` raises `SystemExit`.** It calls `sys.exit(1)`, so `finally` blocks
and context managers still run, and a bare `except:` will swallow it. That is
deliberately more Pythonic than `os._exit`, but it does mean
`except Exception` is safe while `except BaseException` is not.

**`depth` is off by one from the outside.** `trace()`/`info()`/etc. default to
`depth=3`; `log()` defaults to `depth=2`. If you wrap `log()`, pass `depth=3`.

**Arguments are not lazy, formatting is.** `info("x %s", f())` always calls
`f()`.

**Levels are read at import.** `LOG_LEVEL` is parsed when the module is first
imported. Changing `os.environ["LOG_LEVEL"]` afterwards does nothing; use
`set_level()`.

**`set_log_file` raises on a bad path**, unlike the other languages which
return a failure value. `LOG_FILE` pointing at an unwritable path does *not*
raise — it is swallowed at import so a misconfigured environment cannot stop
your program from starting.

## Troubleshooting

**`ModuleNotFoundError: No module named 'logx'`** — the file is not on
`sys.path`. Either `pip install python-logx`, or put `logx.py` next to the
script that imports it.

**Every line says `<string>:1` or the wrong file** — something is wrapping the
log functions. Pass a `depth` that accounts for your wrapper.

**No color in a terminal** — with the default `split` stream, color needs
*both* `sys.stdout` and `sys.stderr` to be TTYs. Running under pytest, a
Jupyter kernel, or any captured-output harness turns it off. Force it with
`LOG_COLOR=1` or `logx.set_color(True)`.

**Nothing is logged at all** — check `logx.get_level()`; `LOG_LEVEL=OFF` or a
`set_level(logx.OFF)` somewhere will silence everything.

**Output appears out of order relative to `print()`** — `logx` flushes every
record and `print` does not always. Use `LOG_STREAM=stderr` to separate them.

**`pytest` shows nothing** — pytest captures output and only shows it for
failing tests. Use `-s` to see it live.

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [`python/logx.py`](../python/logx.py) — the source
- [`python/README.md`](../python/README.md) — the PyPI page
- [`test/python/test_logx.py`](../test/python/test_logx.py) — worked examples
