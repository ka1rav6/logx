# LogX for Go

Single-file logger with no dependencies outside the standard library.

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [The `skip` parameter](#the-skip-parameter)
- [Recipes](#recipes)
- [logx or log/slog?](#logx-or-logslog)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| Go | 1.18 or later (for `any`) |
| Platforms | Everywhere Go runs |
| Dependencies | None |

## Install

### As a module

```bash
go get github.com/ka1rav6/logx/go
```

```go
import logx "github.com/ka1rav6/logx/go"
```

The import path ends in `go` because that is the directory inside the
multi-language repository, so give it the `logx` alias.

### As one dropped-in file

Copy `go/logx.go` into a `logx/` directory inside your own module:

```
myapp/
├── go.mod          // module example.com/myapp
├── main.go
└── logx/
    └── logx.go     // package logx
```

```go
import "example.com/myapp/logx"
```

No alias needed this way, since the directory is already called `logx`.

## Quick start

```go
package main

import logx "github.com/ka1rav6/logx/go"

func main() {
    logx.Trace("starting up")
    logx.Info("listening on port %d", 8080)
    logx.Warn("memory at %.1f%%", 74.2)
    logx.Error("connection lost: %s", "ECONNRESET")
}
```

```
[14:23:01.042][TRACE] main.go:6 -> starting up
[14:23:01.042][INFO ] main.go:7 -> listening on port 8080
[14:23:01.043][WARN ] main.go:8 -> memory at 74.2%
[14:23:01.043][ERROR] main.go:9 -> connection lost: ECONNRESET
```

Formatting is `fmt.Sprintf`, and is applied **only when there are arguments** —
so `logx.Info("100% done")` needs no escaping.

## API reference

### Log functions

```go
func Trace(msg string, args ...any)
func Info (msg string, args ...any)
func Warn (msg string, args ...any)
func Error(msg string, args ...any)
func Fatal(msg string, args ...any)   // logs, then os.Exit(1)

func Log(level Level, skip int, msg string, args ...any)
```

### Level

```go
type Level int

const (
    TRACE Level = 0
    INFO  Level = 1
    WARN  Level = 2
    ERROR Level = 3
    FATAL Level = 4
    OFF   Level = 5   // a threshold only; silences everything
)

func (l Level) String() string      // "TRACE", "INFO", ... "OFF", "UNKNOWN"
```

`Level` implements `fmt.Stringer`, so `%v` and `%s` print the name:

```go
logx.Info("threshold is %v", logx.GetLevel())   // threshold is TRACE
```

Note `String()` returns the *unpadded* name. The padding in the output column
is applied separately, so `WARN.String()` is `"WARN"`, not `"WARN "`.

### Configuration

```go
func SetLevel(level Level)
func GetLevel() Level
func SetColor(enabled bool)
func Enabled(level Level) bool
func SetLogFile(path string) error    // "" goes back to the terminal
func ParseLevel(s string, fallback Level) Level
```

### Levels and filtering

```go
logx.SetLevel(logx.WARN)
logx.SetLevel(logx.OFF)               // silent

if logx.Enabled(logx.TRACE) {
    logx.Trace("state: %s", expensiveDump())
}
```

`ParseLevel` is exported so you can accept a level from your own config:

```go
level := logx.ParseLevel(cfg.LogLevel, logx.INFO)   // unrecognised -> INFO
logx.SetLevel(level)
```

### File output

```go
if err := logx.SetLogFile("/tmp/app.log"); err != nil {
    logx.Warn("could not open the log file: %v", err)
}

logx.SetLogFile("")                   // back to the terminal
```

Opened with `O_APPEND|O_CREATE|O_WRONLY` and mode `0644`. The previous file is
closed, and `SetLogFile` returns the close error if there is one.

## The `skip` parameter

`Log` takes a stack-frame count, which is what lets a helper of yours report
*its* caller instead of itself.

| `skip` | Reports |
|---|---|
| `0` | the line where `Log` is called |
| `1` | that function's caller |
| `2` | one further out |

The convenience functions pass `skip: 1`, which is why `logx.Info(...)` reports
your line rather than a line inside `logx.go`.

```go
func logRequest(r *http.Request, status int) {
    logx.Log(logx.INFO, 1, "%s %s -> %d", r.Method, r.URL.Path, status)
}
```

```
[14:23:01.044][INFO ] routes.go:52 -> GET /health -> 200
```

`routes.go:52` is the line that called `logRequest`. Use `skip: 0` if you would
rather see the line inside the helper.

Overshooting walks off the top of your stack and reports a runtime internal like
`proc.go:271`, which is a useful signal that the number is wrong.

## Recipes

### HTTP middleware

```go
func logging(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}

        next.ServeHTTP(rec, r)

        level := logx.INFO
        if rec.status >= 500 {
            level = logx.ERROR
        }
        logx.Log(level, 0, "%s %s -> %d (%v)",
            r.Method, r.URL.Path, rec.status, time.Since(start).Round(time.Millisecond))
    })
}

type statusRecorder struct {
    http.ResponseWriter
    status int
}

func (r *statusRecorder) WriteHeader(code int) {
    r.status = code
    r.ResponseWriter.WriteHeader(code)
}
```

`skip: 0` here because the interesting location *is* the middleware.

### A package-level prefix

```go
package db

import logx "github.com/ka1rav6/logx/go"

func logf(level logx.Level, msg string, args ...any) {
    logx.Log(level, 1, "[db] "+msg, args...)
}

func Connect() {
    logf(logx.INFO, "connected in %dms", 12)    // line 10: reported here
}
```

```
[14:23:01.044][INFO ] db.go:10 -> [db] connected in 12ms
```

`skip: 1` means "my caller", and from inside `logf` that is `Connect`. Bump it
to `2` if you would rather see whoever called `Connect`.

### Logging an error

```go
if err := doWork(); err != nil {
    logx.Error("doWork failed: %v", err)
}
```

`%v` uses the error's `Error()` string; `%+v` gives the extra detail that
wrapped errors and `github.com/pkg/errors` values render.

### Quieting it inside tests

```go
func TestMain(m *testing.M) {
    logx.SetLevel(logx.OFF)
    os.Exit(m.Run())
}
```

Or `LOG_LEVEL=OFF go test ./...`.

### Capturing output in a test

The simplest approach, and what the test suite does, is to point it at a file:

```go
func capture(t *testing.T, fn func()) []string {
    t.Helper()
    path := filepath.Join(t.TempDir(), "logx.log")
    if err := logx.SetLogFile(path); err != nil {
        t.Fatal(err)
    }
    fn()
    if err := logx.SetLogFile(""); err != nil {
        t.Fatal(err)
    }
    data, err := os.ReadFile(path)
    if err != nil {
        t.Fatal(err)
    }
    return strings.Split(strings.TrimRight(string(data), "\n"), "\n")
}
```

Reassigning `os.Stdout` also works, but a temp file is simpler and does not
race with other tests.

## logx or log/slog?

`log/slog` is the right answer when you want structured, machine-parsed logs:
levelled key-value attributes, handler composition, `context` propagation, JSON
output. It is in the standard library since Go 1.21 and it is good.

`logx` is the right answer when you want a readable line with a timestamp and a
call site, with no handler to construct and no `slog.New(slog.NewTextHandler(...))`
to remember. The file and line are on by default rather than
`AddSource: true`, and `LOG_LEVEL` works without wiring up a `LevelVar`.

They coexist fine — `logx` touches nothing in `log` or `log/slog`.

## Gotchas

**`Fatal` calls `os.Exit(1)`.** Deferred functions do not run. It exits even
when the level filter hid the message.

**`skip` is easy to get wrong by one.** The convenience functions use `1`.
Inside your own helper, `1` reports your helper's caller and `0` reports your
helper. See [The `skip` parameter](#the-skip-parameter).

**Formatting only happens when you pass arguments.** `Info("50%")` prints
`50%`; `Info("50%%", nil)` would print `50%` too, but through `Sprintf`. Keep
literal messages argument-free.

**`go vet` will check your format strings** for the convenience functions,
since their signature matches the `(string, ...any)` printf shape. It cannot
check `Log`, whose format string is not the first argument.

**TTY detection uses `os.ModeCharDevice`.** That is right on Unix and on
Windows consoles, but a Cygwin or MSYS pseudo-terminal looks like a pipe, so
color is off there. Force it with `LOG_COLOR=1`.

**The import path ends in `/go`.** Alias it: `import logx "github.com/ka1rav6/logx/go"`.

## Troubleshooting

**`package github.com/ka1rav6/logx/go is not in GOROOT`** — run
`go get github.com/ka1rav6/logx/go`, or use the dropped-in-file layout and
import your own module path.

**`logx.Info undefined`** — you imported the directory without the alias, so
the package is bound to whatever Go inferred. Add `logx "…/logx/go"`.

**Every line reports `logx.go`** — you called `Log` with `skip: 0` from inside
`logx` itself, or you are on an old copy. The convenience functions use `1`.

**Lines report `proc.go` or `asm_amd64.s`** — `skip` is too large; it walked
off the top of your stack.

**`imported and not used: "strconv"`** — an old copy of `logx.go` that did not
compile at all. Update the file.

**No color in a terminal** — with the default `split` stream, color needs
*both* stdout and stderr to be character devices. Force it with `LOG_COLOR=1`
or `logx.SetColor(true)`.

**No logs from `go test`** — Go captures test output; use `go test -v`.

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [`go/logx.go`](../go/logx.go) — the source
- [`go/logx_test.go`](../go/logx_test.go) — worked examples
