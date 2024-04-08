const std = @import("std");
const fs = std.fs;
const io = std.io;
const md = @cImport({
    @cInclude("md4c-html.h");
});

const Tempdata = struct {
    start: usize,
    end: usize,
    html: []const u8,
};

const Metamatter = struct {
    metadata: std.StringHashMapUnmanaged([]const u8),
    index: usize,
};

fn parseMetadata(allocator: std.mem.Allocator, content: []const u8) !Metamatter {
    var metadata = std.StringHashMapUnmanaged([]const u8){};
    var index: usize = 0;
    var lines = std.mem.split(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] == '%') {
            var parts = std.mem.split(u8, line[1..], ":");
            const key = parts.next() orelse continue;
            const value = parts.next() orelse continue;
            try metadata.put(allocator, std.mem.trim(u8, key, " "), std.mem.trim(u8, value, " "));
            index += line.len + 1;
        } else {
            return Metamatter{ .metadata = metadata, .index = index };
        }
    }
    return Metamatter{ .metadata = metadata, .index = index };
}
pub fn templatize(html: []const u8) !Tempdata {
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

pub fn stroll(allocator: std.mem.Allocator, dir: []const u8, tempFile: []const u8) !void {
    var src_dir = try fs.cwd().openDir(dir, .{ .iterate = true });
    defer src_dir.close();

    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    const template = try templatize(tempFile);
    while (try walker.next()) |unit| {
        if (unit.kind == .file) {
            const fd = src_dir.openFile(unit.path, .{ .mode = .read_only }) catch |e| {
                std.log.err("{s} Can't be opened for reading", .{unit.path});
                return e;
            };
            defer fd.close();
            const markdown = try fd.readToEndAlloc(allocator, 1024 * 1024);
            const metamatter = try parseMetadata(allocator, markdown);

            try createHtml(allocator, markdown, template, unit.path, metamatter);
        }
    }
}

pub fn bufwriter(underlying_stream: anytype) io.BufferedWriter(8192, @TypeOf(underlying_stream)) {
    return .{ .unbuffered_writer = underlying_stream };
}

pub fn createHtml(
    allocator: std.mem.Allocator,
    markdown: []const u8,
    template: Tempdata,
    src_path: []const u8,
    metamatter: Metamatter,
) !void {
    const htmlFileName = try std.fmt.allocPrint(allocator, "{s}html", .{src_path[0 .. src_path.len - 2]});
    var htmlFile = try fs.cwd().createFile(htmlFileName, .{});
    defer htmlFile.close();

    var bufferedwriter = bufwriter(htmlFile.writer());
    try ludicrous(markdown[metamatter.index + 1 ..], &bufferedwriter, bufferedwriter.writer(), template);
    try bufferedwriter.flush();
}
pub fn ludicrous(markdown: []const u8, scribe: anytype, writer: anytype, template: Tempdata) !void {
    const x = struct {
        fn callback(conv: [*c]const md.MD_CHAR, size: md.MD_SIZE, userdata: ?*anyopaque) callconv(.C) void {
            const file: *@TypeOf(writer) = @ptrCast(@alignCast(userdata.?));
            if (file.write(conv[0..size])) |_| {} else |err| {
                std.log.err("File write failed {}", .{err});
            }
        }
    };
    // templatize even title and other metamatter.
    _ = try scribe.write(template.html[0..template.start]);
    const val = md.md_html(markdown.ptr, @intCast(markdown.len), x.callback, @ptrCast(@constCast(&writer)), @intCast(0), md.MD_HTML_FLAG_DEBUG);
    _ = try scribe.write(template.html[template.end + 3 ..]);
    _ = val;
}

pub fn main() !void {
    //var arena_alloc = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    //defer arena_alloc.deinit();
    //const alloc = arena_alloc.allocator();
    //No Safety. CAUTION.
    const alloc = std.heap.c_allocator;
    const template = "./templates/template.html";
    const fd = fs.cwd().openFile(template, .{ .mode = .read_only }) catch |e| {
        std.log.err("{s} Can't be opened for reading", .{template});
        return e;
    };
    defer fd.close();
    const html = try fd.readToEndAlloc(alloc, 1024 * 1024);
    try stroll(alloc, "markdwns/", html);
}
