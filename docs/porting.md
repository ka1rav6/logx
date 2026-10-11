# Porting LogX to a new language

A new language is done when it behaves like the other ten. This page is the
contract; [CONTRIBUTING.md](../CONTRIBUTING.md) has the process around it.

Everything here is checked by the test suite in the existing languages, so you
can read any of them as a reference implementation. The shortest are
[`python/logx.py`](../python/logx.py) and [`js/logx.js`](../js/logx.js).

## The output

Exactly:

```
[HH:MM:SS.mmm][LEVEL] filename:line -> message
```

- Timestamp always 12 characters, zero-padded.
- Level padded to exactly 5 characters — `INFO ` and `WARN ` get a trailing
  space.
- The file reduced to a base name, stripping both `/` and `\`.
- The separator is exactly ` -> `.

This regex has to match every line you emit:

```
^\[\d{2}:\d{2}:\d{2}\.\d{3}\]\[(\w+ ?)\] ([^/\\:]+):(\d+) -> (.*)$
```

## The levels

TRACE 0, INFO 1, WARN 2, ERROR 3, FATAL 4, and OFF 5 as a threshold that
silences everything.

A level passes when its value is `>=` the threshold.

**FATAL writes its record and then exits with status 1** — including when the
level filter hid the message. A logging setting must not be able to turn a
process-ending condition into a no-op. This is easy to get wrong: the filtered
branch needs its own `exit`, not just an early return. C shipped without it for
a while and was the only language of the ten that returned normally from a
silenced `FATAL`.

A compile-time strip (C's and C++'s `LOGX_COMPILE_LEVEL`) is allowed to remove
the call entirely, exit included, because at that point there is no call left to
have semantics.

## Formatting

Use whatever is idiomatic: `%`-style for C, Python, Go and Java; `{}` for Rust
and Zig; `util.format` placeholders for JavaScript and TypeScript.

Two rules:

1. **A message with no arguments is passed through untouched**, so
   `info("100% done")` needs no escaping. C is the only exception, because
   everything there goes through `printf` whether you like it or not — and that
   exception is documented rather than hidden.
2. **A format mismatch logs something useful rather than throwing.** A broken
   log statement must not take down the request that hit it. Python appends the
   argument tuple; Java appends `Arrays.toString(args)`.

Formatting should happen *after* the level check, so a filtered call does no
work.

## The call site

The reported location must be the **caller's**, never a line inside the logger.

Two ways to get there, and which one you use depends on the language:

**Expand at the call site.** C, C++, Rust and assembly capture the location
with macros, so it is correct by construction and a macro wrapper of the user's
own works too.

**Skip frames at runtime.** JavaScript, TypeScript and Java walk the stack and
report the first frame that is not the logger's. Match on file or class name —
**do not count frames**, which breaks the moment anybody wraps you, and breaks
differently under `async`.

Where neither is possible, take the location as a parameter: Python's `depth=`,
Go's `skip`, Zig's `@src()`.

Be honest about the limit. Frame skipping reports the user's *wrapper*, not the
wrapper's caller, and the per-language docs say so rather than implying
otherwise.

## Streams

`ERROR` and `FATAL` to stderr, everything else to stdout. A caller has to be
able to pipe stdout and still get the program's real output.

`LOG_STREAM` overrides this with `stdout` or `stderr`.

## Thread safety

Assemble the complete record first, then emit it with **a single write**. Two
threads must never interleave halves of a line, and a color escape from one
record must never wrap the text of another.

Hold the lock for the write, not for the formatting, if you can manage it
without a second buffer.

## Color

Only when the destination is a terminal, and **never into a file**, whatever
any setting says. A log file you have to strip escape codes out of is not a log
file.

Precedence: a runtime `set_color` call, then `LOG_COLOR`, then `NO_COLOR`, then
auto-detection. With `split`, auto-detection requires *both* stdout and stderr
to be terminals.

The five colors, for consistency:

| Level | Escape |
|---|---|
| TRACE | `\033[36m` cyan |
| INFO | `\033[32m` green |
| WARN | `\033[33m` yellow |
| ERROR | `\033[31m` red |
| FATAL | `\033[35m` magenta |

Reset with `\033[0m`.

## The environment

| Variable | Values |
|---|---|
| `LOG_LEVEL` | a level name or `0`–`5` |
| `LOG_COLOR` | `1`/`true`/`yes`/`on`, or `0`/`false`/`no`/`off` |
| `NO_COLOR` | set to anything disables color |
| `LOG_FILE` | a path to append to |
| `LOG_STREAM` | `split` (default), `stdout`, `stderr` |

Level names are case-insensitive and trimmed, with `DEBUG`, `ALL`, `WARNING`,
`ERR`, `CRITICAL`, `NONE` and `SILENT` as aliases.

**An unrecognised value falls back to the default rather than erroring.** A typo
in a deployment script should make the program noisy, never broken.

**An unwritable `LOG_FILE` leaves logging on the terminal** rather than
stopping the program from starting.

If your language's standard library has no time-zone database, print UTC and
read `LOG_TZ_OFFSET` (`+HH:MM`, `-HHMM`, or a signed count of minutes), as Rust,
Zig and assembly do. Do not take a dependency to get local time.

## The runtime API

| Purpose | Required |
|---|---|
| Log at a level | `trace` `info` `warn` `error` `fatal` |
| Log at a runtime-chosen level | `log` |
| Read / change the threshold | `get_level` / `set_level` |
| Force color | `set_color` |
| Append to a file | `set_log_file` |
| Back to the terminal | the same call with null / empty / no argument |
| Cheap pre-check | `enabled` |
| Parse a level name | `parse_level` |
| Flush | `flush` |

Spell them the way your language spells things — `SetLogFile` in Go,
`setLogFile` in Java, `set_log_file` in Python.

`enabled` and `parse_level` can be left out where they make no sense: C has no
`lx_enabled` because the level check is already the first thing `lx_log` does
and the formatting happens inside the call.

Failure reporting should match local convention: a `bool` in Java and C++, an
`error` in Go, an `io::Result` in Rust, a raised `OSError` in Python, a
negative errno in assembly.

## Single file

One file, no dependencies beyond the standard library, with the BSD 2-Clause
header at the top.

If the language cannot meet some part of the contract, **say so in the
per-language documentation** rather than leaving it to be discovered: UTC
timestamps, a supported-version range, a filename constraint, a module-format
caveat. Every existing language has a "Gotchas" section for exactly this.

## Tests

Add `test/<language>/` covering at least:

- the output format, checked with the regex above
- format arguments, including a no-argument message containing a literal `%`
- level filtering, including `OFF`
- the reported call site being the test file
- no color escapes in a file
- `set_log_file` reporting an unwritable path

Then a `test-<language>` target in the [Makefile](../Makefile), with the
`command -v` guard that turns a missing toolchain into a skip rather than a
failure:

```make
test-mylang:
	@command -v mylangc >/dev/null 2>&1 || { echo "SKIP: mylangc not found"; exit 0; }
	@mylangc test/mylang/test_logx.ml && ./a.out
```

The `test` target greps for `SKIP:` to decide, so that exact prefix matters.

## Documentation

Add `docs/<language>.md` following the shape the others use: Requirements,
Install, Quick start, API reference, Recipes, Gotchas, Troubleshooting. Then add
rows to [`docs/README.md`](README.md) and the tables in the top-level
[README](../README.md).

Verify every example you write by actually compiling and running it. Several
bugs in this project were found that way — a documented recipe that did not
work was how the Go `skip` semantics and the C++ token-pasting problem both came
to light.
