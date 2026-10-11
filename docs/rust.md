# LogX for Rust

Single-file logger built on nothing but `std`. Works both as a dropped-in module
and as a crate.

- [Requirements](#requirements)
- [Install](#install)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Why `use logx::*` is required](#why-use-logx-is-required)
- [Timestamps are UTC](#timestamps-are-utc)
- [Recipes](#recipes)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Requirements

| | |
|---|---|
| Rust | 1.70 or later (for `std::io::IsTerminal`) |
| Edition | 2021 (2018 also works) |
| Dependencies | None |

## Install

### As one dropped-in file

Copy `rust/logx.rs` next to your `main.rs`:

```rust
#[macro_use]
mod logx;
use logx::*;

fn main() {
    logx_info!("listening on port {}", 8080);
}
```

`#[macro_use]` makes the `logx_*!` macros visible crate-wide. `use logx::*`
brings in the functions those macros expand to — see
[Why `use logx::*` is required](#why-use-logx-is-required).

### As a dependency

```toml
[dependencies]
logx = "1.1"
```

```rust
use logx::*;

fn main() {
    logx_info!("listening on port {}", 8080);
}
```

## Quick start

```rust
#[macro_use]
mod logx;
use logx::*;

fn main() {
    logx_trace!("starting up");
    logx_info!("listening on port {}", 8080);
    logx_warn!("memory at {:.1}%", 74.2);
    logx_error!("connection lost: {}", "ECONNRESET");
}
```

```
[08:53:01.042][TRACE] main.rs:6 -> starting up
[08:53:01.042][INFO ] main.rs:7 -> listening on port 8080
[08:53:01.043][WARN ] main.rs:8 -> memory at 74.2%
[08:53:01.043][ERROR] main.rs:9 -> connection lost: ECONNRESET
```

Formatting is `std::format!`, so everything you know works: `{}`, `{:?}`,
`{:.1}`, `{name}`, `{:>8}`, and inline captures like `logx_info!("{port}")`.

## API reference

### Macros

| Macro | Level |
|---|---|
| `logx_trace!(...)` | TRACE |
| `logx_info!(...)` | INFO |
| `logx_warn!(...)` | WARN |
| `logx_error!(...)` | ERROR |
| `logx_fatal!(...)` | FATAL — writes, then `std::process::exit(1)` |

Each takes exactly what `format!` takes.

### Level

```rust
pub enum LogxLevel {
    Trace = 0,
    Info  = 1,
    Warn  = 2,
    Error = 3,
    Fatal = 4,
    Off   = 5,     // a threshold only; silences everything
}
```

It derives `Clone`, `Copy`, `Debug`, `PartialEq`, `Eq`, `PartialOrd` and `Ord`,
so you can compare and sort levels directly.

```rust
impl LogxLevel {
    /// Case-insensitive; "0".."5" also work. Unrecognised input returns `fallback`.
    pub fn parse(text: &str, fallback: LogxLevel) -> LogxLevel;
}
```

### Functions

```rust
pub fn set_level(level: LogxLevel);
pub fn get_level() -> LogxLevel;
pub fn set_color(enabled: bool);
pub fn enabled(level: LogxLevel) -> bool;

pub fn set_log_file(path: &str) -> io::Result<()>;
pub fn clear_log_file();                    // back to the terminal
pub fn flush();

/// What the macros expand to. Call it directly to supply your own location.
pub fn logx_log(level: LogxLevel, message: &str, file: &str, line: u32);
```

### Levels and filtering

```rust
set_level(LogxLevel::Warn);
set_level(LogxLevel::Off);              // silent

if enabled(LogxLevel::Trace) {
    logx_trace!("state: {:?}", expensive_dump());
}
```

### File output

```rust
set_log_file("/tmp/app.log")?;          // io::Result
clear_log_file();                       // back to the terminal
```

Appended, never truncated. A real `io::Result`, so handle it the usual way:

```rust
if let Err(err) = set_log_file(&path) {
    logx_warn!("could not open {}: {}", path, err);
}
```

## Why `use logx::*` is required

The macros expand to **unqualified** calls:

```rust
macro_rules! logx_info {
    ($($arg:tt)*) => { logx_log(LogxLevel::Info, &format!($($arg)*), file!(), line!()) };
}
```

A `$crate::logx_log(...)` path would be the idiomatic choice, and it works
perfectly when LogX is a dependency — but it breaks the dropped-in form, because
`$crate` resolves to *your* crate root, where there is no `logx_log`. That was a
real bug: the documented `#[macro_use] mod logx;` usage failed to compile.

Unqualified names in a `macro_rules!` body resolve at the call site instead, so a
single glob import satisfies both shapes:

```rust
use logx::*;      // dropped-in module  -- resolves to the local module
use logx::*;      // crate dependency   -- resolves to the extern crate
```

If a bare `use logx::*` is too broad for your taste, import just what the macros
need:

```rust
use logx::{logx_log, LogxLevel};
```

## Timestamps are UTC

`std` ships no time-zone database, and LogX takes no dependencies, so Rust
timestamps are UTC. Set a fixed offset if you want local time:

```bash
LOG_TZ_OFFSET=+05:30 ./myapp      # also accepts -0800, or a plain 330 (minutes)
```

Zig and assembly have the same constraint for the same reason. Every other
language prints local time. See
[Timestamps and time zones](format.md#timestamps-and-time-zones).

## Recipes

### A wrapper that reports its caller

The location comes from `file!()` and `line!()`, which expand where they are
written. So a **macro** wrapper reports the call site, while a **function**
wrapper reports its own line:

```rust
macro_rules! log_request {
    ($req:expr, $status:expr) => {
        logx_info!("{} {} -> {}", $req.method, $req.path, $status)
    };
}

log_request!(req, 200);
// -> [..][INFO ] routes.rs:52 -> GET /health -> 200     <- the call site
```

```rust
fn log_request(req: &Request, status: u16) {
    logx_info!("{} {} -> {}", req.method, req.path, status);   // line 5
}

log_request(&req, 200);
// -> [..][INFO ] routes.rs:5 -> GET /health -> 200      <- inside the function
```

If you need a function and the caller's location, take it as parameters and call
`logx_log` directly:

```rust
fn log_request_at(req: &Request, status: u16, file: &str, line: u32) {
    logx_log(LogxLevel::Info,
             &format!("{} {} -> {}", req.method, req.path, status),
             file, line);
}

macro_rules! log_request {
    ($req:expr, $status:expr) => {
        log_request_at($req, $status, file!(), line!())
    };
}
```

`#[track_caller]` is the other option, though it gives you a
`std::panic::Location` rather than the `file!()`/`line!()` pair.

### Logging from submodules

`#[macro_use] mod logx;` puts the macros at the crate root, so they are visible
everywhere. Each submodule still needs the functions in scope:

```rust
// main.rs
#[macro_use]
mod logx;
mod db;

fn main() { db::connect(); }
```

```rust
// db.rs
use crate::logx::*;

pub fn connect() {
    logx_info!("connecting");
}
```

### Logging an error type

```rust
match risky() {
    Ok(value) => logx_info!("got {value}"),
    Err(err) => logx_error!("risky failed: {err}"),          // uses Display
}
```

For the full chain, `{:?}` on an `anyhow::Error` or `eyre::Report` gives the
backtrace its `Debug` impl renders:

```rust
Err(err) => logx_error!("risky failed: {err:?}"),
```

### Quieting it inside tests

Rust runs tests in threads of one process, so the level is shared. Set it once:

```rust
#[test]
fn quiet() {
    set_level(LogxLevel::Off);
    // ...
}
```

Or run with `LOG_LEVEL=OFF cargo test`. Note that `cargo test` captures stdout
by default, so logs only appear for failing tests unless you pass
`-- --nocapture`.

### Publishing the crate

`rust/Cargo.toml` already points `[lib] path` at `logx.rs`:

```bash
cd rust && cargo publish
```

## Gotchas

**`use logx::*` is not optional.** Without it the macros fail to resolve
`logx_log`. See [Why `use logx::*` is required](#why-use-logx-is-required).

**Timestamps are UTC** unless you set `LOG_TZ_OFFSET`.

**`logx_fatal!` calls `std::process::exit(1)`.** No unwinding, no `Drop`
impls, no destructors. It exits even when the level filter hid the message.

**A function wrapper reports its own line.** Use a macro, or pass
`file!()`/`line!()` explicitly.

**`#![allow(dead_code)]` is inside the file on purpose.** Dropped in as
`mod logx;`, anything your program does not call would otherwise be reported as
dead code and fail a `-D warnings` build.

**A poisoned mutex does not panic.** The internal locks use
`unwrap_or_else(|e| e.into_inner())`, so a panic in another thread while logging
cannot cascade into every later log call.

## Troubleshooting

**`cannot find function 'logx_log' in this scope`** — missing `use logx::*;`
(or `use crate::logx::*;` in a submodule).

**`cannot find macro 'logx_info' in this scope`** — the `mod logx;` declaration
needs `#[macro_use]` on it, and it must be at the crate root (`main.rs` or
`lib.rs`), not inside another module.

**`error: function 'set_color' is never used`** under `-D warnings` — you are on
a version without the `#![allow(dead_code)]` at the top of `logx.rs`. Update the
file.

**`use of unstable library feature 'is_terminal'`** — Rust older than 1.70.
Upgrade, or set `LOG_COLOR` explicitly and replace the `is_terminal()` calls.

**Timestamps are hours off** — they are UTC. Set `LOG_TZ_OFFSET`.

**No logs from `cargo test`** — stdout is captured. Use
`cargo test -- --nocapture`.

**No color in a terminal** — with the default `split` stream, color needs
*both* stdout and stderr to be terminals. Force it with `LOG_COLOR=1` or
`set_color(true)`.

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [`rust/logx.rs`](../rust/logx.rs) — the source
- [`rust/tests/integration.rs`](../rust/tests/integration.rs) — worked examples
