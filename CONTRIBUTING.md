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

## Adding a language

The behaviour every language has to implement — output format, levels,
formatting rules, call-site reporting, streams, thread safety, color,
environment variables, the runtime API — is written up in
**[docs/porting.md](docs/porting.md)**. Read that first; it is the actual
contract, and it explains the reasoning behind the parts that look arbitrary.

Then:

1. Create one file in a new `<language>/` directory.
2. Implement the contract, following the idioms of that language rather than
   transliterating another one.
3. Add a test under `test/<language>/`. `test/python/test_logx.py` is a good
   shape to copy.
4. Add a `test-<language>` target to the Makefile, including the `command -v`
   guard that turns a missing toolchain into a skip.
5. Write `docs/<language>.md`, following the shape the existing pages use.
6. Add rows to the tables in [`README.md`](README.md) and
   [`docs/README.md`](docs/README.md), and an entry in the project structure
   tree.
7. If the language cannot fully meet the contract, say so in that page's
   "Gotchas" section rather than leaving it to be discovered. UTC timestamps
   instead of local time, a supported-version range, a filename constraint — all
   of those are already documented for the languages they affect.

## Changing an existing language

If you change behaviour in one language, check whether the same change belongs
in the other nine. The point of the project is that they agree.

Anything in [docs/format.md](docs/format.md) is a cross-language promise. If you
need to change one of those, change all ten and the tests together.

## Documentation

**Verify every example you write by compiling and running it.** Not by reading
it back.

This is not boilerplate advice — several real bugs were found exactly that way
while the docs were being written:

- A documented Go helper used `skip: 2` where `1` was correct, so the example
  reported the wrong line.
- A documented C++ scoped-timer macro used `logx_timer_##__LINE__`, which does
  not expand `__LINE__`, so two timers in one scope collided.
- The README claimed JavaScript, TypeScript and Java wrappers report their
  caller. They report the wrapper's own line. The claim had been carried in the
  README for a while before anybody ran it.

A doc example that does not compile is worse than no example.

## Code style

- Zero dependencies. Standard library only.
- One file per language.
- BSD 2-Clause header at the top.
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
