// Copyright (c) 2026, Kairav Dutta (@ka1rav6)
//
// This is free and unencumbered software released into the public domain,
// except that the above copyright notice must be retained in all copies
// of this software, in source or binary form.  That's the only requirement.

const std = @import("std");

pub const Level = enum(u8) {
    trace = 0,
    info = 1,
    warn = 2,
    err = 3,
    fatal = 4,

    fn name(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .info => "INFO ",
            .warn => "WARN ",
            .err => "ERROR",
            .fatal => "FATAL",
        };
    }

    fn color(self: Level) []const u8 {
        return switch (self) {
            .trace => "\x1b[36m",
            .info => "\x1b[32m",
            .warn => "\x1b[33m",
            .err => "\x1b[31m",
            .fatal => "\x1b[35m",
        };
    }
};

var min_level: u8 = undefined;
var use_color: bool = undefined;
var log_file: ?std.fs.File = null;
var mutex: std.Thread.Mutex = .{};
var initialized: bool = false;

fn ensureInit() void {
    if (initialized) return;
    mutex.lock();
    defer mutex.unlock();
    if (initialized) return;

    const level_env = std.process.getEnvVarOwned(std.heap.page_allocator, "LOG_LEVEL") catch null;
    defer if (level_env) |s| std.heap.page_allocator.free(s);

    min_level = if (level_env) |s| blk: {
        if (std.mem.eql(u8, s, "TRACE")) break :blk 0;
        if (std.mem.eql(u8, s, "INFO"))  break :blk 1;
        if (std.mem.eql(u8, s, "WARN"))  break :blk 2;
        if (std.mem.eql(u8, s, "ERROR")) break :blk 3;
        if (std.mem.eql(u8, s, "FATAL")) break :blk 4;
        break :blk 0;
    } else 0;

    const color_env = std.process.getEnvVarOwned(std.heap.page_allocator, "LOG_COLOR") catch null;
    defer if (color_env) |s| std.heap.page_allocator.free(s);

    use_color = if (color_env) |s| std.mem.eql(u8, s, "1") or std.mem.eql(u8, s, "yes")
        else std.fs.File.stdout().isTty() and std.fs.File.stderr().isTty();

    initialized = true;
}

pub fn setLogFile(path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = false });
    try file.seekFromEnd(0);
    mutex.lock();
    defer mutex.unlock();
    if (log_file) |f| f.close();
    log_file = file;
}

fn timestamp(buf: []u8) []u8 {
    const now = std.time.timestamp();
    const ms = @mod(std.time.milliTimestamp(), 1000);
    const secs_of_day = @mod(@as(u64, @intCast(now)), 86400);
    const h = secs_of_day / 3600;
    const m = (secs_of_day % 3600) / 60;
    const s = secs_of_day % 60;
    return std.fmt.bufPrint(buf, "{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}", .{ h, m, s, ms }) catch unreachable;
}

pub fn log(comptime level: Level, comptime msg: []const u8, comptime src: std.builtin.SourceLocation) void {
    ensureInit();
    if (@intFromEnum(level) < min_level) return;

    var ts_buf: [16]u8 = undefined;
    const ts = timestamp(&ts_buf);

    const label = std.fmt.allocPrint(std.heap.page_allocator, "[{s}][{s}] {s}:{d} -> {s}", .{
        ts, level.name(), src.file, src.line, msg,
    }) catch return;
    defer std.heap.page_allocator.free(label);

    mutex.lock();
    defer mutex.unlock();

    if (log_file) |f| {
        _ = f.writeAll(label) catch {};
        _ = f.writeAll("\n") catch {};
    } else {
        const out: std.fs.File = if (@intFromEnum(level) >= 3) .stderr() else .stdout();
        if (use_color) {
            _ = out.writeAll(level.color()) catch {};
            _ = out.writeAll(label) catch {};
            _ = out.writeAll("\x1b[0m\n") catch {};
        } else {
            _ = out.writeAll(label) catch {};
            _ = out.writeAll("\n") catch {};
        }
    }

    if (level == .fatal) std.process.exit(1);
}
