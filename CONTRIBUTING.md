# Contributing to LogX

Thanks for wanting to make LogX better!

## Running tests

Everything goes through the Makefile, from the project root:

```bash
make test           # every language whose toolchain is installed
make test-c         # or one at a time: test-c test-cpp test-python test-js
                    # test-ts test-go test-rust test-java test-zig test-asm
make check-all      # build the C and C++ headers in every supported mode
make clean
```

A language whose compiler is missing is reported as skipped, not as a failure,
so you do not need all ten toolchains to work on one language.

`make check-all` is worth running after any change to `c/logx.h` or
`cpp/logx.h`: it builds them across C99/C11/C17 and C++11/14/17/20, with
`LOGX_SHARED`, `LOGX_NO_THREADS` and `LOGX_COMPILE_LEVEL`, and compiles the C
header as C++ — all with warnings as errors.

## The contract every language implements

A new language is only done when it behaves like the others. The details that
matter:

**Output format.** Exactly `[HH:MM:SS.mmm][LEVEL] filename:line -> message`.
Level names are padded to five characters (`INFO ` and `WARN ` have a trailing
space) so columns line up. The file is reduced to a base name, stripping both
`/` and `\`.

**Levels.** TRACE 0, INFO 1, WARN 2, ERROR 3, FATAL 4, and OFF 5 as a threshold
that silences everything. FATAL writes its record and then exits with status 1 —
including when it is filtered out by the level.

**Format arguments** in whatever is idiomatic for the language: `%`-style for
C, Python, Go and Java; `{}` for Rust and Zig; `util.format` placeholders for
JavaScript and TypeScript. A message with **no** arguments must be passed
through untouched, so `info("100% done")` needs no escaping. A format mismatch
should log something useful rather than throw out of a log call.

**The call site must be the caller's**, not the logger's. Where the language
allows it, skip frames belonging to the logger itself so a user's own wrapper
function still reports its caller — match on file or class name rather than
counting frames, which breaks as soon as anyone wraps you. Where it cannot be
automatic, take an explicit depth or skip argument (Python's `depth=`, Go's
`skip`) or a source location (Zig's `@src()`).

**Streams.** `ERROR` and `FATAL` to stderr, everything else to stdout, so a
caller can pipe stdout and still get their program's real output.

**Thread safety.** Assemble the whole record first and emit it with a single
write, so concurrent threads cannot interleave halves of a line.

**Color** only when writing to a terminal, and **never** into a log file
whatever the settings say.

**The five environment variables**, with identical semantics:

| Variable | Values |
|---|---|
| `LOG_LEVEL` | `TRACE` `INFO` `WARN` `ERROR` `FATAL` `OFF`, or `0`–`5` |
| `LOG_COLOR` | `1`/`true`/`yes`/`on`, or `0`/`false`/`no`/`off` |
| `NO_COLOR` | set to anything disables color |
| `LOG_FILE` | a path to append to instead of the terminal |
| `LOG_STREAM` | `split` (default), `stdout`, `stderr` |

Level names are case-insensitive and trimmed, and `DEBUG`, `ALL`, `WARNING`,
`ERR`, `CRITICAL`, `NONE` and `SILENT` are aliases. An unrecognised value falls
back to the default rather than erroring. An unwritable `LOG_FILE` must leave
logging on the terminal rather than stopping the program from starting.

**The runtime API:** setters for level, color and log file; a getter for the
level; an `enabled(level)` predicate so callers can skip building an expensive
message; and a flush.

## Adding a language

1. Create one file in a new `<language>/` directory.
2. Implement the contract above.
3. Follow the idioms of that language rather than transliterating another one.
4. Add a test under `test/<language>/` that checks the output format with a
   regex, the level filter, the call site, and that no color reaches a file.
   Look at `test/python/test_logx.py` for the shape.
5. Add a `test-<language>` target to the Makefile, including the
   `command -v` guard that turns a missing toolchain into a skip.
6. Add rows to the Quick Start and API Reference tables in `README.md`, a
   per-language setup section, and an entry in the project structure tree.
7. If the language cannot fully meet the contract, say so in
   "Per-language notes and limits" rather than leaving it for someone to
   discover. Timestamps in UTC instead of local time, for instance, or a
   supported-version range.

## Code style

- Zero dependencies. Standard library only.
- One file per language.
- BSD 2-Clause license header at the top.
- Comment the *why*, not the *what*. A comment earns its place when the reason
  for the code is not obvious from reading it — a platform quirk, a workaround,
  a non-obvious ordering constraint. Skip it otherwise.

## Pull request process

1. Open an issue first to discuss the change.
2. Make your changes in a feature branch.
3. Run `make test` (and `make check-all` for header changes).
4. Submit a PR with a clear description of what you changed and why.

## License

By contributing, you agree that your contributions will be licensed under the
BSD 2-Clause License.
