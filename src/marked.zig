const std = @import("std");
const fs = std.fs;
const io = std.io;
const md = @cImport({
    @cInclude("md4c-html.h");
});

pub fn callback(conv: [*c]const md.MD_CHAR, size: md.MD_SIZE, userdata: ?*anyopaque) callconv(.C) void {
    std.debug.print("{s}", .{conv[0..size]});
    //    _ = conv;
    //    _ = size;
    _ = userdata;
}

pub fn stroll(dir: []const u8) !void {
    const allocator = std.heap.page_allocator;
    var src_dir = try fs.cwd().openDir(dir, .{ .iterate = true });
    defer src_dir.close();

    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |unit| {
        if (unit.kind == .file and true) { // add check for if file is .md. reject incase filename has no extensions
            std.debug.print("{s}\n", .{unit.path});

            const fd = try fs.openFileAbsolute(unit.path, .{ .mode = .read_only });
            defer fd.close();
            try ludicrous(fd);
        }
    }
}

pub fn ludicrous(source: fs.File) !void {
    var buffboi = std.io.bufferedReader(source.reader());
    var input = buffboi.reader();
    var buffer: [2048]u8 = undefined;
    const new: ?*anyopaque = null;
    while (try input.readUntilDelimiterOrEof(&buffer, '\n')) |line| {
        const val = md.md_html(line.ptr, @intCast(line.len), callback, new, @intCast(0), md.MD_HTML_FLAG_DEBUG);
        if (val == 0) {
            continue;
        } else {
            //  std.debug.print("woo", .{});
        }
    }
}

pub fn main() !void {
    //  var source = try std.fs.cwd().openFile("test.md", .{});
    //const src_dir = "/home/vorrtt3x/dev/ludicrosity/markdwns";
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const curr = try std.os.getcwd(&buf);
    const alloc = std.heap.page_allocator;
    const src_dir = try fs.path.join(alloc, &[_][]const u8{ curr, "/markdwns/" });
    std.debug.print("{s}", .{src_dir});
    try stroll(src_dir);
    //    defer source.close();
}
