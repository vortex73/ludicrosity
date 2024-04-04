const std = @import("std");
const fs = std.fs;
const io = std.io;
const md = @cImport({
    @cInclude("md4c-html.h");
});

const callback_data = struct {
    file: fs.File,
};

const Metamatter = struct {
    metadata: std.StringHashMap([]const u8),
    index: usize,
};

pub fn callback(conv: [*c]const md.MD_CHAR, size: md.MD_SIZE, userdata: ?*anyopaque) callconv(.C) void {
    const file: *callback_data = @ptrCast(@alignCast(userdata.?));
    if (file.file.write(conv[0..size])) |_| {} else |err| {
        std.log.err("File write failed {}", .{err});
    }
}
fn parseMetadata(allocator: std.mem.Allocator, content: []const u8) !Metamatter {
    var metadata = std.StringHashMap([]const u8).init(allocator);
    var index: usize = 0;
    var lines = std.mem.split(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] == '%') {
            var parts = std.mem.split(u8, line[1..], ":");
            const key = parts.next() orelse continue;
            const value = parts.next() orelse continue;
            try metadata.put(std.mem.trim(u8, key, " "), std.mem.trim(u8, value, " "));
            index += line.len + 1;
        } else {
            return Metamatter{ .metadata = metadata, .index = index };
        }
    }
    return Metamatter{ .metadata = metadata, .index = index };
}
pub fn templatize() !void {
    const alloc = std.heap.page_allocator;
    const template = "templates/template.html";
    const fd = fs.cwd().openFile(template, .{ .mode = .read_only }) catch |e| {
        std.log.err("{s} Can't be opened for reading", .{template});
        return e;
    };
    defer fd.close();
    var html = try fd.readToEndAlloc(alloc, 1024 * 1024);
    while (std.mem.indexOf(u8, html, "<!--")) |start_index| {
        if (std.mem.indexOf(u8, html, "-->")) |end_index| {
            const param = html[start_index + 4 .. end_index];
            std.debug.print("{s}\n", .{param});
            //    try replace(html);
            html = html[end_index + 3 ..];
            continue;
        } else {
            std.debug.print("Unclosed CommentLine encountered in template file", .{});
            break;
        }
    }
}

pub fn stroll(dir: []const u8) !void {
    const allocator = std.heap.page_allocator;
    var src_dir = try fs.cwd().openDir(dir, .{ .iterate = true });
    defer src_dir.close();

    var walker = try src_dir.walk(allocator);
    defer walker.deinit();
    const read_alloc = std.heap.page_allocator;

    while (try walker.next()) |unit| {
        if (unit.kind == .file) {
            const fd = src_dir.openFile(unit.path, .{ .mode = .read_only }) catch |e| {
                std.log.err("{s} Can't be opened for reading", .{unit.path});
                return e;
            };
            defer fd.close();
            const markdown = try fd.readToEndAlloc(read_alloc, 1024 * 1024);
            const metamatter = try parseMetadata(allocator, markdown);

            if (metamatter.metadata.get("title")) |title| {
                std.debug.print("title : {s}\n", .{title});
            } else {
                std.debug.print("title key not found\n", .{});
            }
            try ludicrous(markdown[metamatter.index + 1 ..], unit.path);
        }
    }
}

pub fn ludicrous(markdown: []const u8, src_path: []const u8) !void {
    const htmlFileName = try std.fmt.allocPrint(std.heap.page_allocator, "{s}html", .{src_path[0 .. src_path.len - 2]});
    defer std.heap.page_allocator.free(htmlFileName);
    var htmlFile = try fs.cwd().createFile(htmlFileName, .{});
    defer htmlFile.close();
    const val = md.md_html(markdown.ptr, @intCast(markdown.len), callback, &htmlFile, @intCast(0), md.MD_HTML_FLAG_DEBUG);
    _ = val;
}

pub fn main() !void {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const curr = try std.os.getcwd(&buf);
    const alloc = std.heap.page_allocator;
    const src_dir = try fs.path.join(alloc, &[_][]const u8{ curr, "/markdwns/" });
    try templatize();
    try stroll(src_dir);
}
