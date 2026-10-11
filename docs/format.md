# Output format, levels and environment

These are identical in all ten languages. Everything here is enforced by the
test suite, so you can rely on it when you parse log output or move between
languages.

## The record

```
[HH:MM:SS.mmm][LEVEL] filename:line -> message
```

```
[14:23:01.042][INFO ] server.c:42 -> listening on port 8080
[14:23:01.043][WARN ] memory.c:17 -> memory at 74.2%
[14:23:01.044][ERROR] network.c:89 -> connection lost
```

Details that matter if you are parsing it:

- The timestamp is always 12 characters, zero-padded: `HH:MM:SS.mmm`.
- Level names are padded to exactly 5 characters. `INFO ` and `WARN ` carry a
  trailing space; `TRACE`, `ERROR` and `FATAL` are naturally 5.
- The file is a base name. Both `/` and `\` are stripped, so a Windows path and
  a Unix path produce the same output.
- The separator is exactly ` -> ` (space, hyphen, greater-than, space).
- The message is whatever is left, and may itself contain ` -> `. Parse the
  prefix, not the message.

A regex that matches every language's output:

```
^\[\d{2}:\d{2}:\d{2}\.\d{3}\]\[(\w+ ?)\] ([^/\\:]+):(\d+) -> (.*)$
```

Each record is assembled in full and written with a single call, so concurrent
threads cannot interleave halves of a line.

## Levels

| Level | Value | Meaning |
|---|---|---|
| TRACE | 0 | Finest-grained diagnostic |
| INFO | 1 | General operational information |
| WARN | 2 | Something unexpected, but not fatal |
| ERROR | 3 | A runtime error or failure |
| FATAL | 4 | Unrecoverable — writes the record, then exits with status 1 |
| OFF | 5 | A threshold only; silences everything |

A level passes the filter when its value is `>=` the current threshold. `OFF` as
the threshold silences everything, including `FATAL` output — but `FATAL` still
exits with status 1, because swallowing a process-ending condition because of a
log setting would be worse than the lost line.

The one exception is C and C++ compile-time stripping: `LOGX_COMPILE_LEVEL`
above `FATAL` removes the call site entirely, `exit` included. See
[the C page](c.md#logx_compile_level).

`OFF` is not something you log at. Passing it to a log call is not meaningful.

### Routing

With the default `LOG_STREAM=split`, `ERROR` and `FATAL` go to stderr and
everything else goes to stdout. That way a caller can pipe your stdout and still
get your program's real output.

## Environment variables

| Variable | Values | Default |
|---|---|---|
| `LOG_LEVEL` | a level name or `0`–`5` | `TRACE` |
| `LOG_COLOR` | `1`/`true`/`yes`/`on`, or `0`/`false`/`no`/`off` | auto-detect |
| `NO_COLOR` | set to anything to disable color | unset |
| `LOG_FILE` | a path to append to instead of the terminal | unset |
| `LOG_STREAM` | `split`, `stdout`, `stderr` | `split` |

Rust, Zig and assembly also read `LOG_TZ_OFFSET`; see
[Timestamps and time zones](#timestamps-and-time-zones).

### LOG_LEVEL

Case-insensitive and trimmed. These all mean the same thing:

```bash
LOG_LEVEL=WARN    LOG_LEVEL=warn    LOG_LEVEL=" Warn "    LOG_LEVEL=2
```

Accepted aliases:

| Canonical | Also accepted |
|---|---|
| `TRACE` | `DEBUG`, `ALL`, `0` |
| `INFO` | `1` |
| `WARN` | `WARNING`, `2` |
| `ERROR` | `ERR`, `3` |
| `FATAL` | `CRITICAL`, `4` |
| `OFF` | `NONE`, `SILENT`, `5` |

An unrecognised value falls back to the default rather than erroring, so a typo
in a deployment script makes your program noisy, never broken.

### LOG_COLOR and NO_COLOR

Precedence, highest first:

1. A runtime call — `set_color()` / `setColor()` / `lx_set_color()`.
2. `LOG_COLOR`, if it holds a recognised value.
3. `NO_COLOR`, if set to anything at all (see [no-color.org](https://no-color.org)).
4. Auto-detection: color is on only when the destination is a terminal. With
   `split`, *both* stdout and stderr must be terminals, so redirecting either
   one turns color off.

**Color is never written into a log file**, whatever any of the above say. A log
file you have to strip escape codes out of is not a log file.

### LOG_FILE

```bash
LOG_FILE=/tmp/app.log ./myapp
```

Opened in append mode and never truncated, so restarting your program keeps the
history. An unwritable path leaves logging on the terminal rather than stopping
the program from starting — a logging misconfiguration should not be fatal.

### LOG_STREAM

| Value | Behaviour |
|---|---|
| `split` (default) | `ERROR` and `FATAL` to stderr, the rest to stdout |
| `stdout` | everything to stdout |
| `stderr` | everything to stderr |

`stderr` is the one to reach for in a CLI tool whose stdout is real output:

```bash
LOG_STREAM=stderr ./myapp > results.json
```

## Timestamps and time zones

Python, JavaScript, TypeScript, C, C++, Go and Java print **local time**.

Rust, Zig and assembly print **UTC**. None of them can reach a time-zone
database without taking on a dependency: Rust's and Zig's standard libraries do
not ship one, and the assembly version makes raw syscalls with no libc at all.
Rather than pretend, they accept a fixed offset.

```bash
LOG_TZ_OFFSET=+05:30 ./rust-app     # also accepts -0800, or a plain 330
```

```asm
    mov qword [log_tz_offset], 5 * 3600 + 30 * 60
```

Accepted forms: `+HH:MM`, `-HHMM`, `+H`, or a bare signed count of minutes.
Anything unparseable means UTC.

## What is the same everywhere

Every language has, under its own naming convention:

| Purpose | Names |
|---|---|
| Log at a level | `trace` `info` `warn` `error` `fatal` |
| Log at a runtime-chosen level | `log` |
| Read / change the threshold | `get_level` / `set_level` |
| Force color on or off | `set_color` |
| Append to a file | `set_log_file` |
| Back to the terminal | same call with null / empty / no argument |
| Cheap check before building a message | `enabled` |
| Parse a level name | `parse_level` |
| Flush pending output | `flush` |

The per-language pages give the exact spelling and signature.
