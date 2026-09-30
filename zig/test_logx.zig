// Tests for zig/logx.zig. Run from the project root:
//   zig test zig/test_logx.zig
//
// Needs Zig 0.14-0.16, the same range logx.zig supports.

const std = @import("std");
const logx = @import("logx.zig");
const testing = std.testing;

/// One parsed record: [HH:MM:SS.mmm][LEVEL] file:line -> message
const Record = struct {
    level: []const u8,
    file: []const u8,
    line: u32,
    message: []const u8,
};

fn parse(text: []const u8) ?Record {
    if (text.len < 16 or text[0] != '[') return null;
    if (text[3] != ':' or text[6] != ':' or text[9] != '.') return null;
    if (text[13] != ']' or text[14] != '[') return null;

    const level_end = std.mem.indexOfScalarPos(u8, text, 15, ']') orelse return null;
    const level = text[15..level_end];
    if (level.len != 5) return null;

    const rest = text[level_end + 1 ..];
    if (rest.len == 0 or rest[0] != ' ') return null;

    const arrow = std.mem.indexOf(u8, rest, " -> ") orelse return null;
    const location = rest[1..arrow];
    const colon = std.mem.lastIndexOfScalar(u8, location, ':') orelse return null;

    return .{
        .level = level,
        .file = location[0..colon],
        .line = std.fmt.parseInt(u32, location[colon + 1 ..], 10) catch return null,
        .message = rest[arrow + 4 ..],
    };
}

/// Runs `body` with output going to a temp file and returns its contents.
/// The caller owns the returned slice.
fn capture(allocator: std.mem.Allocator, comptime body: fn () void) ![]u8 {
    const path = "/tmp/logx_zig_test.log";
    std.fs.cwd().deleteFile(path) catch {};

    try logx.setLogFile(path);
    body();
    logx.clearLogFile();

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(path) catch {};

    return try file.readToEndAlloc(allocator, 64 * 1024);
}

fn emitOneOfEach() void {
    logx.trace(@src(), "trace msg", .{});
    logx.info(@src(), "port {d}", .{8080});
    logx.warn(@src(), "memory at {d:.1}%", .{74.2});
    logx.err(@src(), "lost: {s}", .{"ECONNRESET"});
}

test "format, levels and call site" {
    const allocator = testing.allocator;
    const content = try capture(allocator, emitOneOfEach);
    defer allocator.free(content);

    var lines = std.mem.tokenizeScalar(u8, content, '\n');

    const expected = [_]struct { level: []const u8, message: []const u8 }{
        .{ .level = "TRACE", .message = "trace msg" },
        .{ .level = "INFO ", .message = "port 8080" },
        .{ .level = "WARN ", .message = "memory at 74.2%" },
        .{ .level = "ERROR", .message = "lost: ECONNRESET" },
    };

    var seen: usize = 0;
    while (lines.next()) |line| : (seen += 1) {
        try testing.expect(seen < expected.len);
        const record = parse(line) orelse {
            std.debug.print("unparsed line: {s}\n", .{line});
            return error.MalformedRecord;
        };
        try testing.expectEqualStrings(expected[seen].level, record.level);
        try testing.expectEqualStrings(expected[seen].message, record.message);
        try testing.expectEqualStrings("test_logx.zig", record.file);
        try testing.expect(record.line > 0);
    }
    try testing.expectEqual(expected.len, seen);

    // Color belongs on a terminal, never in a file.
    try testing.expect(std.mem.indexOfScalar(u8, content, 0x1b) == null);
}

fn emitAcrossLevels() void {
    logx.setLevel(.warn);
    logx.trace(@src(), "hidden", .{});
    logx.info(@src(), "hidden", .{});
    logx.warn(@src(), "shown", .{});
    logx.err(@src(), "shown", .{});
    logx.setLevel(.off);
    logx.err(@src(), "silenced by off", .{});
    logx.setLevel(.trace);
}

test "level filtering" {
    const allocator = testing.allocator;
    const content = try capture(allocator, emitAcrossLevels);
    defer allocator.free(content);

    var lines = std.mem.tokenizeScalar(u8, content, '\n');
    var seen: usize = 0;
    while (lines.next()) |_| seen += 1;

    try testing.expectEqual(@as(usize, 2), seen);
    try testing.expectEqual(logx.Level.trace, logx.getLevel());
}

test "enabled" {
    logx.setLevel(.warn);
    try testing.expect(!logx.enabled(.info));
    try testing.expect(logx.enabled(.err));

    logx.setLevel(.off);
    try testing.expect(!logx.enabled(.fatal));

    logx.setLevel(.trace);
    try testing.expect(logx.enabled(.trace));
}

test "level parsing" {
    try testing.expectEqual(logx.Level.warn, logx.Level.parse("warn", .trace));
    try testing.expectEqual(logx.Level.warn, logx.Level.parse("WARNING", .trace));
    try testing.expectEqual(logx.Level.err, logx.Level.parse("3", .trace));
    try testing.expectEqual(logx.Level.off, logx.Level.parse("silent", .trace));
    try testing.expectEqual(logx.Level.trace, logx.Level.parse("DEBUG", .info));
    try testing.expectEqual(logx.Level.info, logx.Level.parse("junk", .info));
    try testing.expectEqual(logx.Level.info, logx.Level.parse("", .info));
}

// Built with a comptime loop rather than the ** operator, whose tokenisation
// differs between Zig versions.
const long_text = blk: {
    var buf: [4000]u8 = undefined;
    @memset(&buf, 'x');
    break :blk buf;
};

fn emitTooLong() void {
    logx.info(@src(), "{s}", .{&long_text});
}

test "a long message is reported rather than dropped" {
    const allocator = testing.allocator;
    const content = try capture(allocator, emitTooLong);
    defer allocator.free(content);

    try testing.expect(content.len > 0);
    try testing.expect(std.mem.indexOf(u8, content, "too long") != null);
}

test "setLogFile reports an unwritable path" {
    try testing.expectError(error.FileNotFound, logx.setLogFile("/nonexistent-dir-xyz/app.log"));
}
