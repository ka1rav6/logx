# LogX for Zig

Single-file logger using nothing but `std`. No allocator in the logging path.

- [Supported Zig versions](#supported-zig-versions)
- [Install](#install)
- [Quick start](#quick-start)
- [API reference](#api-reference)
- [Why `@src()`](#why-src)
- [Timestamps are UTC](#timestamps-are-utc)
- [Recipes](#recipes)
- [Gotchas](#gotchas)
- [Troubleshooting](#troubleshooting)

## Supported Zig versions

**Zig 0.14, 0.15 and 0.16.**

Zig 0.17 reorganised the standard library: `std.fs.File` became `std.Io.File`,
every read and write now takes an `Io` parameter, and `std.Thread.Mutex`,
`std.once`, `std.time.milliTimestamp` and `std.process.getEnvVarOwned` all
moved or were removed. Rather than silently miscompile, `logx.zig` detects that
and stops with an explanation:

```
logx.zig:37:9: error: logx.zig targets Zig 0.14-0.16. This compiler has the
reworked std.Io API (Zig 0.17+), where File lives at std.Io.File and every
read/write takes an Io parameter. Use a 0.16 or earlier compiler, or port the
writeAll/isTty/createFile calls in this file to pass an Io.
```

Porting it is a contained job: four I/O call sites (`writeAll`, `isTty`,
`createFile`, `close`) need an `Io` threaded through, and the three relocated
`std` helpers need their new paths. `std.Options.debug_io` is the `Io` instance
to use when you have no other.

Zig's standard library is still moving, which is why this file tracks released
versions rather than nightly.

## Install

Copy `zig/logx.zig` next to the file that imports it:

```zig
const logx = @import("logx.zig");
```

With a `build.zig` you can also make it a module, so every file gets it by name
rather than by relative path:

```zig
// build.zig
const logx = b.createModule(.{ .root_source_file = b.path("src/logx.zig") });

const exe = b.addExecutable(.{
    .name = "myapp",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("logx", logx);
```

```zig
const logx = @import("logx");    // no relative path
```

## Quick start

```zig
const logx = @import("logx.zig");

pub fn main() void {
    logx.trace(@src(), "starting up", .{});
    logx.info(@src(), "listening on port {d}", .{8080});
    logx.warn(@src(), "memory at {d:.1}%", .{74.2});
    logx.err(@src(), "connection lost: {s}", .{"ECONNRESET"});
}
```

```
[08:53:01.042][TRACE] main.zig:4 -> starting up
[08:53:01.042][INFO ] main.zig:5 -> listening on port 8080
[08:53:01.043][WARN ] main.zig:6 -> memory at 74.2%
[08:53:01.043][ERROR] main.zig:7 -> connection lost: ECONNRESET
```

Formatting is `std.fmt`, so `{d}`, `{s}`, `{any}`, `{d:.1}`, `{x}` and the rest
all work. Pass `.{}` when there are no arguments.

## API reference

### Log functions

```zig
pub fn trace(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void
pub fn info (src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void
pub fn warn (src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void
pub fn err  (src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void
pub fn fatal(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void

pub fn log(level: Level, src: std.builtin.SourceLocation,
           comptime fmt: []const u8, args: anytype) void
```

`err`, not `error` — `error` is a Zig keyword.

`fatal` writes the record and then calls `std.process.exit(1)`.

### Level

```zig
pub const Level = enum(u8) {
    trace = 0,
    info  = 1,
    warn  = 2,
    err   = 3,
    fatal = 4,
    off   = 5,     // a threshold only; silences everything

    /// Case-insensitive; "0".."5" also work. Unrecognised input returns `fallback`.
    pub fn parse(text: []const u8, fallback: Level) Level
};
```

### Configuration

```zig
pub fn setLevel(level: Level) void
pub fn getLevel() Level
pub fn setColor(on: bool) void
pub fn enabled(level: Level) bool
pub fn setLogFile(path: []const u8) !void
pub fn clearLogFile() void
```

```zig
logx.setLevel(.warn);
logx.setLevel(.off);                   // silent

if (logx.enabled(.trace)) {
    logx.trace(@src(), "state: {any}", .{state});
}
```

### File output

```zig
try logx.setLogFile("/tmp/app.log");
logx.clearLogFile();                   // back to the terminal
```

It returns an error union, so handle it however suits you:

```zig
logx.setLogFile(path) catch |e| {
    logx.warn(@src(), "could not open {s}: {s}", .{ path, @errorName(e) });
};
```

Appended, never truncated.

## Why `@src()`

Zig has no caller-location builtin that survives a function call. `@src()`
evaluates where it is *written*, so it has to be written at your call site and
passed in. That is the whole reason the first parameter exists.

The upside is that it makes the location explicit and controllable — forward a
`src` through your own helper and the record points wherever you want:

```zig
fn logRequest(src: std.builtin.SourceLocation, method: []const u8, status: u16) void {
    logx.info(src, "{s} -> {d}", .{ method, status });
}

logRequest(@src(), "GET", 200);     // reports this line
```

A macro-free language cannot do this implicitly, and a hidden
`std.builtin.SourceLocation` parameter would be worse than an explicit one.

## Timestamps are UTC

Zig's standard library ships no time-zone database, and LogX takes no
dependencies, so timestamps are UTC. Set a fixed offset for local time:

```bash
LOG_TZ_OFFSET=+05:30 ./myapp     # also accepts -0800, or a plain 330 (minutes)
```

Rust and assembly have the same constraint for the same reason. See
[Timestamps and time zones](format.md#timestamps-and-time-zones).

## Recipes

### Forwarding the call site through a helper

```zig
const Level = logx.Level;

fn logDb(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    logx.log(.info, src, "[db] " ++ fmt, args);
}

logDb(@src(), "connected in {d}ms", .{12});
// -> [db] connected in 12ms, reported at the call site
```

`fmt` is `comptime`, so `"[db] " ++ fmt` is a compile-time concatenation with
no runtime cost.

### A level from your own configuration

```zig
const level = logx.Level.parse(config.log_level, .info);
logx.setLevel(level);
```

### Logging an error

```zig
risky() catch |e| {
    logx.err(@src(), "risky failed: {s}", .{@errorName(e)});
};
```

`@errorName` gives the error's name as a string. For an error union you want to
propagate as well:

```zig
const value = risky() catch |e| {
    logx.err(@src(), "risky failed: {s}", .{@errorName(e)});
    return e;
};
```

### Quieting it inside tests

```zig
test "quiet" {
    logx.setLevel(.off);
    defer logx.setLevel(.trace);
    // ...
}
```

Zig runs tests in one process, so the level is shared — restore it with
`defer` to avoid affecting later tests.

### Capturing output in a test

Point it at a temp file, which is what the test suite does:

```zig
fn capture(allocator: std.mem.Allocator, comptime body: fn () void) ![]u8 {
    const path = "/tmp/logx_test.log";
    std.fs.cwd().deleteFile(path) catch {};

    try logx.setLogFile(path);
    body();
    logx.clearLogFile();

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(path) catch {};

    return try file.readToEndAlloc(allocator, 64 * 1024);
}
```

## Gotchas

**Zig 0.17+ is rejected on purpose.** See
[Supported Zig versions](#supported-zig-versions).

**It is `err`, not `error`.** `error` is a keyword.

**Pass `.{}` for no arguments.** `logx.info(@src(), "plain", .{})`, not
`logx.info(@src(), "plain")`.

**`fmt` is `comptime`.** A runtime-built format string will not compile. Build
the *message* at runtime instead and log it with `"{s}"`.

**Messages are capped at 2048 bytes.** The record is assembled in a stack
buffer with no allocator. A longer message is replaced with
`<message too long>` rather than being truncated mid-way or silently dropped —
so you see that something was lost.

**Timestamps are UTC** unless you set `LOG_TZ_OFFSET`.

**`fatal` calls `std.process.exit(1)`.** No `defer` blocks run after it. It
exits even when the level filter hid the message.

**`setLogFile` returns an error union.** `try` it, or `catch` it.

## Troubleshooting

**`logx.zig targets Zig 0.14-0.16`** — you are on 0.17 or a nightly. Use a
released 0.16 or earlier compiler, or port the four I/O call sites.

**`expected 3 argument(s), found 2`** — you left off the `.{}` argument tuple.

**`no member named 'error' in 'Level'`** — it is `.err`.

**`unable to resolve comptime value` on your format string** — `fmt` has to be
comptime-known. Format the message separately and log it with `"{s}"`.

**`<message too long>` in the output** — over 2048 bytes. Log less, or split
it across records.

**Timestamps are hours off** — they are UTC. Set `LOG_TZ_OFFSET`.

**No color in a terminal** — with the default `split` stream, color needs
*both* stdout and stderr to be TTYs. Force it with `LOG_COLOR=1` or
`logx.setColor(true)`.

## See also

- [Output format, levels and environment](format.md) — shared across all languages
- [`zig/logx.zig`](../zig/logx.zig) — the source
- [`zig/test_logx.zig`](../zig/test_logx.zig) — worked examples
