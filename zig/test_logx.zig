const std = @import("std");
const logx = @import("logx.zig");

fn testBasicOutput() !void {
    const tmp_path = "/tmp/logx_zig_test.txt";
    _ = std.fs.cwd().deleteFile(tmp_path) catch {};

    try logx.setLogFile(tmp_path);
    logx.log(.trace, "trace msg", @src());
    logx.log(.info, "info msg", @src());
    logx.log(.warn, "warn msg", @src());
    logx.log(logx.Level.err, "error msg", @src());

    const file = try std.fs.cwd().openFile(tmp_path, .{});
    defer file.close();
    defer std.fs.cwd().deleteFile(tmp_path) catch {};

    const content = try file.readToEndAlloc(std.heap.page_allocator, 4096);
    defer std.heap.page_allocator.free(content);
    const s = std.mem.sliceTo(content, 0);

    try std.testing.expect(std.mem.containsAtLeast(u8, s, 1, "trace msg"));
    try std.testing.expect(std.mem.containsAtLeast(u8, s, 1, "TRACE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, s, 1, "info msg"));
    try std.testing.expect(std.mem.containsAtLeast(u8, s, 1, "INFO "));
    try std.testing.expect(std.mem.containsAtLeast(u8, s, 1, "warn msg"));
    try std.testing.expect(std.mem.containsAtLeast(u8, s, 1, "WARN "));
    try std.testing.expect(std.mem.containsAtLeast(u8, s, 1, "error msg"));
    try std.testing.expect(std.mem.containsAtLeast(u8, s, 1, "ERROR"));
}

test "basic output" {
    try testBasicOutput();
}
