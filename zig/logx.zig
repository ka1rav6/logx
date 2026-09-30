// Copyright (c) 2026, Kairav Dutta (@ka1rav6)
//
// This is free and unencumbered software released into the public domain,
// except that the above copyright notice must be retained in all copies
// of this software, in source or binary form.  That's the only requirement.
//
// logx -- single-file logger for Zig.
//
//     const logx = @import("logx.zig");
//
//     logx.info(@src(), "listening on port {d}", .{8080});
//     logx.warn(@src(), "memory at {d:.1}%", .{74.2});
//     logx.err(@src(), "connection lost", .{});
//
// @src() is what supplies the file and line; Zig has no caller-location
// builtin that works through a function call, so it has to be passed in.
//
// Supported Zig: 0.14, 0.15 and 0.16 (the stable std.fs / std.io API).
// Zig 0.17 moved std.fs.File to std.Io.File and made every I/O call take an
// Io parameter; that release is detected below and reported with a clear
// message rather than a page of errors.
//
// Environment
//   LOG_LEVEL      TRACE | INFO | WARN | ERROR | FATAL | OFF   (or 0..5)
//   LOG_COLOR      1/true/yes/on forces, 0/false/no/off disables, unset = auto
//   NO_COLOR       set to anything to disable color
//   LOG_FILE       path to append to instead of writing to the terminal
//   LOG_STREAM     split (default) | stdout | stderr
//   LOG_TZ_OFFSET  +05:30, -0800, or a number of minutes. Timestamps are UTC
//                  without it: Zig's std has no time-zone database.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (@hasDecl(std, "Io") and @hasDecl(std.Io, "File")) {
        @compileError(
            "logx.zig targets Zig 0.14-0.16. This compiler has the reworked " ++
                "std.Io API (Zig 0.17+), where File lives at std.Io.File and " ++
                "every read/write takes an Io parameter. Use a 0.16 or earlier " ++
                "compiler, or port the writeAll/isTty/createFile calls in this " ++
                "file to pass an Io.",
        );
    }
}

const File = std.fs.File;

/// A logging threshold. Higher is more severe.
pub const Level = enum(u8) {
    trace = 0,
    info = 1,
    warn = 2,
    err = 3,
    fatal = 4,
    /// Silences everything.
    off = 5,

    /// Padded to a fixed width so columns line up in the output.
    fn name(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .info => "INFO ",
            .warn => "WARN ",
            .err => "ERROR",
            .fatal => "FATAL",
            .off => "OFF  ",
        };
    }

    fn color(self: Level) []const u8 {
        return switch (self) {
            .trace => "\x1b[36m",
            .info => "\x1b[32m",
            .warn => "\x1b[33m",
            .err => "\x1b[31m",
            .fatal => "\x1b[35m",
            .off => "\x1b[0m",
        };
    }

    /// Parses a level name, case-insensitively. "0".."5" work too.
    pub fn parse(text: []const u8, fallback: Level) Level {
        var buf: [16]u8 = undefined;
        if (text.len == 0 or text.len > buf.len) return fallback;
        const upper = std.ascii.upperString(&buf, text);
        if (eq(upper, "TRACE") or eq(upper, "DEBUG") or eq(upper, "ALL") or eq(upper, "0")) return .trace;
        if (eq(upper, "INFO") or eq(upper, "1")) return .info;
        if (eq(upper, "WARN") or eq(upper, "WARNING") or eq(upper, "2")) return .warn;
        if (eq(upper, "ERROR") or eq(upper, "ERR") or eq(upper, "3")) return .err;
        if (eq(upper, "FATAL") or eq(upper, "CRITICAL") or eq(upper, "4")) return .fatal;
        if (eq(upper, "OFF") or eq(upper, "NONE") or eq(upper, "SILENT") or eq(upper, "5")) return .off;
        return fallback;
    }
};

const reset = "\x1b[0m";

const Sink = enum { split, stdout, stderr };

fn eq(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

var min_level: Level = .trace;
var use_color: bool = false;
var sink: Sink = .split;
var tz_offset_secs: i64 = 0;
var log_file: ?File = null;

var mutex: std.Thread.Mutex = .{};
var init_once = std.once(initialise);

fn stdoutFile() File {
    // 0.15 moved these from std.io.getStdOut() onto File itself.
    if (comptime @hasDecl(File, "stdout")) return File.stdout();
    return std.io.getStdOut();
}

fn stderrFile() File {
    if (comptime @hasDecl(File, "stderr")) return File.stderr();
    return std.io.getStdErr();
}

/// Reads one environment variable into `buf`. Uses a caller-supplied buffer so
/// nothing here needs an allocator.
fn envVar(buf: []u8, key: []const u8) ?[]const u8 {
    var fba = std.heap.FixedBufferAllocator.init(buf);
    const value = std.process.getEnvVarOwned(fba.allocator(), key) catch return null;
    return value;
}

fn parseBool(text: []const u8) ?bool {
    var buf: [8]u8 = undefined;
    if (text.len == 0 or text.len > buf.len) return null;
    const low = std.ascii.lowerString(&buf, text);
    if (eq(low, "1") or eq(low, "true") or eq(low, "yes") or eq(low, "on")) return true;
    if (eq(low, "0") or eq(low, "false") or eq(low, "no") or eq(low, "off")) return false;
    return null;
}

/// Accepts "+05:30", "-0800", "+2", or a bare number of minutes.
fn parseTzOffset(text: []const u8) ?i64 {
    if (text.len == 0) return null;
    var sign: i64 = 1;
    var rest = text;
    if (rest[0] == '+') {
        rest = rest[1..];
    } else if (rest[0] == '-') {
        sign = -1;
        rest = rest[1..];
    }

    var digits: [8]u8 = undefined;
    var n: usize = 0;
    var has_colon = false;
    for (rest) |c| {
        if (c == ':') has_colon = true;
        if (std.ascii.isDigit(c) and n < digits.len) {
            digits[n] = c;
            n += 1;
        }
    }
    if (n == 0) return null;
    const seen = digits[0..n];

    if (has_colon or n == 4) {
        const hours = std.fmt.parseInt(i64, seen[0 .. n - 2], 10) catch return null;
        const minutes = std.fmt.parseInt(i64, seen[n - 2 ..], 10) catch return null;
        return sign * (hours * 3600 + minutes * 60);
    }
    if (n <= 2) {
        const hours = std.fmt.parseInt(i64, seen, 10) catch return null;
        return sign * hours * 3600;
    }
    // A bare minute count, e.g. LOG_TZ_OFFSET=330.
    const minutes = std.fmt.parseInt(i64, seen, 10) catch return null;
    return sign * minutes * 60;
}

fn initialise() void {
    var buf: [4096]u8 = undefined;

    if (envVar(&buf, "LOG_LEVEL")) |value| {
        min_level = Level.parse(value, .trace);
    }

    if (envVar(&buf, "LOG_STREAM")) |value| {
        var lower: [8]u8 = undefined;
        if (value.len <= lower.len) {
            const low = std.ascii.lowerString(&lower, value);
            if (eq(low, "stdout")) sink = .stdout;
            if (eq(low, "stderr")) sink = .stderr;
        }
    }

    if (envVar(&buf, "LOG_COLOR")) |value| {
        use_color = parseBool(value) orelse autoColor();
    } else if (envVar(&buf, "NO_COLOR") != null) {
        use_color = false;
    } else {
        use_color = autoColor();
    }

    if (envVar(&buf, "LOG_TZ_OFFSET")) |value| {
        tz_offset_secs = parseTzOffset(value) orelse 0;
    }

    if (envVar(&buf, "LOG_FILE")) |value| {
        if (value.len > 0) {
            // An unwritable LOG_FILE just leaves logging on the terminal.
            setLogFile(value) catch {};
        }
    }
}

fn autoColor() bool {
    return switch (sink) {
        .stdout => stdoutFile().isTty(),
        .stderr => stderrFile().isTty(),
        .split => stdoutFile().isTty() and stderrFile().isTty(),
    };
}

/// Raises or lowers the threshold at runtime.
pub fn setLevel(level: Level) void {
    init_once.call();
    mutex.lock();
    defer mutex.unlock();
    min_level = level;
}

/// The current threshold.
pub fn getLevel() Level {
    init_once.call();
    mutex.lock();
    defer mutex.unlock();
    return min_level;
}

/// Turns ANSI coloring on or off, overriding the auto-detection.
pub fn setColor(on: bool) void {
    init_once.call();
    mutex.lock();
    defer mutex.unlock();
    use_color = on;
}

/// Whether a message at `level` would be emitted.
pub fn enabled(level: Level) bool {
    init_once.call();
    mutex.lock();
    defer mutex.unlock();
    return @intFromEnum(min_level) < @intFromEnum(Level.off) and
        @intFromEnum(level) >= @intFromEnum(min_level);
}

/// Appends log output to `path`.
pub fn setLogFile(path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
    errdefer file.close();
    try file.seekFromEnd(0);

    mutex.lock();
    defer mutex.unlock();
    if (log_file) |old| old.close();
    log_file = file;
}

/// Sends log output back to the terminal.
pub fn clearLogFile() void {
    mutex.lock();
    defer mutex.unlock();
    if (log_file) |old| old.close();
    log_file = null;
}

fn timestamp(buf: []u8) []const u8 {
    const millis = std.time.milliTimestamp();
    const shifted = @divFloor(millis, 1000) + tz_offset_secs;
    const secs_of_day = @mod(shifted, 86_400);
    const ms = @mod(millis, 1000);
    return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}", .{
        @as(u64, @intCast(@divFloor(secs_of_day, 3600))),
        @as(u64, @intCast(@divFloor(@mod(secs_of_day, 3600), 60))),
        @as(u64, @intCast(@mod(secs_of_day, 60))),
        @as(u64, @intCast(ms)),
    }) catch "--:--:--.---";
}

fn baseName(path: []const u8) []const u8 {
    var start: usize = 0;
    for (path, 0..) |c, i| {
        if (c == '/' or c == '\\') start = i + 1;
    }
    return if (start < path.len) path[start..] else path;
}

/// Logs one record. `src` is `@src()` at the call site; `fmt` and `args` are
/// exactly what std.fmt takes.
pub fn log(
    level: Level,
    src: std.builtin.SourceLocation,
    comptime fmt: []const u8,
    args: anytype,
) void {
    if (!enabled(level)) {
        if (level == .fatal) std.process.exit(1);
        return;
    }

    var ts_buf: [16]u8 = undefined;
    var line_buf: [2048]u8 = undefined;

    const text = std.fmt.bufPrint(&line_buf, "[{s}][{s}] {s}:{d} -> " ++ fmt ++ "\n", .{
        timestamp(&ts_buf),
        level.name(),
        baseName(src.file),
        src.line,
    } ++ args) catch blk: {
        // The formatted message did not fit; say so rather than dropping it.
        break :blk std.fmt.bufPrint(&line_buf, "[{s}][{s}] {s}:{d} -> <message too long>\n", .{
            timestamp(&ts_buf),
            level.name(),
            baseName(src.file),
            src.line,
        }) catch "logx: message too long\n";
    };

    mutex.lock();
    if (log_file) |file| {
        file.writeAll(text) catch {};
        mutex.unlock();
    } else {
        const out = switch (sink) {
            .stdout => stdoutFile(),
            .stderr => stderrFile(),
            .split => if (@intFromEnum(level) >= @intFromEnum(Level.err)) stderrFile() else stdoutFile(),
        };
        if (use_color) {
            out.writeAll(level.color()) catch {};
            out.writeAll(text[0 .. text.len - 1]) catch {};
            out.writeAll(reset ++ "\n") catch {};
        } else {
            out.writeAll(text) catch {};
        }
        mutex.unlock();
    }

    if (level == .fatal) std.process.exit(1);
}

pub fn trace(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    log(.trace, src, fmt, args);
}

pub fn info(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    log(.info, src, fmt, args);
}

pub fn warn(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    log(.warn, src, fmt, args);
}

/// Named `err` because `error` is a Zig keyword.
pub fn err(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    log(.err, src, fmt, args);
}

/// Logs at FATAL, then exits with status 1.
pub fn fatal(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    log(.fatal, src, fmt, args);
}
