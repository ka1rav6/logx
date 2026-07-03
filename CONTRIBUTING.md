# Contributing to LogX

Thanks for wanting to make LogX better!

## How to add a new language

LogX's whole point is being in as many languages as possible. To add one:

1. Create a file in a new `<language>/` directory.
2. Implement the **same 5 log levels**: TRACE, INFO, WARN, ERROR, FATAL.
3. Support the **same features**:
   - Timestamps in `[HH:MM:SS.mmm]` format
   - Automatic file & line capture
   - Colored output (auto TTY detection, `LOG_COLOR` env var)
   - Optional file logging via a `setLogFile`-style function
   - Thread safety (mutex/lock around writes)
   - Level filtering via `LOG_LEVEL` env var
   - FATAL exits the process
4. Follow the existing code style in that language.
5. Add a test in `test/<language>/`.
6. Add a row to the Quick Start table in `README.md`.
7. Add a row to the API Reference table.
8. Update the project structure tree in `README.md`.

## Code style

- Zero dependencies (stdlib only).
- Single file per language.
- BSD 2-Clause license header at the top.
- No comments in implementation code unless the logic is genuinely non-obvious.

## Running tests

```bash
# Python
cd test/python && python -m pytest test_logx.py

# JavaScript
cd test/js && node test.js

# TypeScript
cd test/ts && npx tsx test.ts

# C
cd test/c && gcc -std=c11 test_logx.c -o test_logx -lpthread && ./test_logx

# C++
cd test/cpp && g++ -std=c++11 test_logx.cpp -o test_logx && ./test_logx

# Rust
cd test && cargo test

# Go
cd test && go test ./...

# Java
cd test/java && javac TestLogx.java && java TestLogx

# Zig
cd test && zig test zig/test_logx.zig

# Assembly
cd test/asm && nasm -felf64 test_logx.asm -o test_logx.o && ld test_logx.o -o test_logx && ./test_logx
```

## Pull request process

1. Open an issue first to discuss the change.
2. Make your changes in a feature branch.
3. Ensure all tests pass.
4. Submit a PR with a clear description of what you changed and why.

## License

By contributing, you agree that your contributions will be licensed under the BSD 2-Clause License.
