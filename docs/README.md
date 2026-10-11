# LogX documentation

One page per language. Each is standalone — if you only care about Go, the Go
page is all you need.

| Language | Page | File to copy |
|---|---|---|
| C | [c.md](c.md) | `c/logx.h` |
| C++ | [cpp.md](cpp.md) | `cpp/logx.h` |
| Python | [python.md](python.md) | `python/logx.py` |
| JavaScript | [javascript.md](javascript.md) | `js/logx.js` |
| TypeScript | [typescript.md](typescript.md) | `ts/logx.ts` |
| Rust | [rust.md](rust.md) | `rust/logx.rs` |
| Go | [go.md](go.md) | `go/logx.go` |
| Java | [java.md](java.md) | `java/Logx.java` |
| Zig | [zig.md](zig.md) | `zig/logx.zig` |
| Assembly | [assembly.md](assembly.md) | `asm/logx.asm` |

## Cross-cutting pages

- **[format.md](format.md)** — the output format, the levels, and the five
  environment variables, which are identical in every language.
- **[porting.md](porting.md)** — the contract a new language has to meet.
  Start here if you want to add one.

## The thirty-second version

Copy one file into your project. Then:

```c
LOGX_INFO("listening on port %d", 8080);
```

```
[14:23:01.042][INFO ] server.c:42 -> listening on port 8080
```

Timestamp, level, the real call site, and your message. `ERROR` and `FATAL` go
to stderr so stdout stays pipeable. `LOG_LEVEL=WARN` quiets it down without a
recompile, `LOG_FILE=/tmp/app.log` redirects it without a code change.

That is the whole idea. Everything else is detail.
