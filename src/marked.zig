const std = @import("std");
const fs = std.fs;
const io = std.io;
const md = @cImport({
    @cInclude("md4c-html.h");
});

const callback_data = struct {
    file: fs.File,
};

const Tempdata = struct {
    start: usize,
    end: usize,
    html: []const u8,
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
// 💡 Modify templatize to loop till all param comments are identified.
pub fn templatize() !Tempdata {
    const alloc = std.heap.page_allocator;
    const template = "templates/template.html";
    const fd = fs.cwd().openFile(template, .{ .mode = .read_only }) catch |e| {
        std.log.err("{s} Can't be opened for reading", .{template});
        return e;
    };
    defer fd.close();
    const html = try fd.readToEndAlloc(alloc, 1024 * 1024);
    while (std.mem.indexOf(u8, html, "<!--")) |start_index| {
        if (std.mem.indexOf(u8, html, "-->")) |end_index| {
            //    try replace(html);
            //html = html[end_index + 3 ..];
            return Tempdata{ .end = end_index, .start = start_index, .html = html };
        } else {
            std.debug.print("Unclosed CommentLine encountered in template file", .{});
            return Tempdata{ .end = 0, .start = 0, .html = "" };
        }
    }
    return Tempdata{ .end = 0, .start = 0, .html = "" };
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
            const template = try templatize();

            if (metamatter.metadata.get("title")) |title| {
                // std.debug.print("title : {s}\n", .{title});
                _ = title;
            } else {
                std.debug.print("title key not found\n", .{});
            }
            try ludicrous(markdown[metamatter.index + 1 ..], unit.path, template);
        }
    }
}
// 💡 pass one single buffered writer instance throughout the codeflow that writes everything till the Delimiter and then writes the parsed content.
// 💡 pass the file to the callback and write to it and write once more later.
pub fn ludicrous(markdown: []const u8, src_path: []const u8, template: Tempdata) !void {
    const htmlFileName = try std.fmt.allocPrint(std.heap.page_allocator, "{s}html", .{src_path[0 .. src_path.len - 2]});
    defer std.heap.page_allocator.free(htmlFileName);
    var htmlFile = try fs.cwd().createFile(htmlFileName, .{ .truncate = false });
    defer htmlFile.close();
    _ = try htmlFile.write(template.html[0..template.start]);
    const val = md.md_html(markdown.ptr, @intCast(markdown.len), callback, &htmlFile, @intCast(0), md.MD_HTML_FLAG_DEBUG);
    _ = try htmlFile.write(template.html[template.end + 3 ..]);
    _ = val;
}

pub fn main() !void {
    var buf: [fs.MAX_PATH_BYTES]u8 = undefined;
    const curr = try std.os.getcwd(&buf);
    const alloc = std.heap.page_allocator;
    const src_dir = try fs.path.join(alloc, &[_][]const u8{ curr, "/markdwns/" });
    try stroll(src_dir);
}
