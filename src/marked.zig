const std = @import("std");
const fs = std.fs;
const io = std.io;
const md = @cImport({
    @cInclude("md4c-html.h");
});

// Refactor: free the arraylist and hashmaps
// 15/04 : tag hashmaps printing garbage values in createtags function
// possible memory leaks
// test code to print at different locations :
// var iter = new_tagger.tagmap.iterator();
// while (iter.next()) |val| {
//     std.debug.print("{s}", .{val.key_ptr.*});
// }

const Metamatter = struct {
    metadata: std.StringHashMapUnmanaged([]const u8),
    index: usize,
    tags: std.ArrayList([]const u8),
};
const Tagger = struct {
    tagmap: std.StringHashMap(std.ArrayList([]const u8)),
};

fn parseMetadata(allocator: std.mem.Allocator, content: []const u8, taghash: *Tagger) !Metamatter {
    var metadata = std.StringHashMapUnmanaged([]const u8){};
    var tagger = std.ArrayList([]const u8).init(allocator);
    //var tagh = taghash;
    var index: usize = 0;
    var lines = std.mem.split(u8, content, "\n");
    var title: []const u8 = undefined;
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] == '%') {
            var parts = std.mem.split(u8, line[1..], ":");
            const key = parts.next() orelse continue;
            const value = parts.next() orelse continue;
            if (std.mem.eql(u8, std.mem.trim(u8, key, " "), "title")) title = value;
            if (std.mem.eql(u8, std.mem.trim(u8, key, " "), "tags")) {
                var taglist = std.mem.split(u8, value[0..], ",");
                while (true) {
                    const tag = taglist.next() orelse break;
                    try tagger.append(tag);
                    if (taghash.*.tagmap.getPtr(tag)) |post| {
                        try post.append(title);
                    } else {
                        var newposts = std.ArrayList([]const u8).init(allocator);
                        defer newposts.deinit();
                        try newposts.append(title);
                        try taghash.*.tagmap.put(tag, newposts);
                    }
                }
            } else {
                try metadata.put(allocator, std.mem.trim(u8, key, " "), std.mem.trim(u8, value, " "));
            }
            index += line.len + 1;
        } else {
            return Metamatter{ .metadata = metadata, .index = index, .tags = tagger };
        }
    }
    return Metamatter{ .metadata = metadata, .index = index, .tags = tagger };
}

pub fn stroll(allocator: std.mem.Allocator, dir: []const u8, tempFile: []const u8, tagger: *Tagger) !Tagger {
    var src_dir = try fs.cwd().openDir(dir, .{ .iterate = true });
    defer src_dir.close();

    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |unit| {
        if (unit.kind == .file) {
            const fd = src_dir.openFile(unit.path, .{ .mode = .read_only }) catch |e| {
                std.log.err("{s} Can't be opened for reading", .{unit.path});
                return e;
            };
            defer fd.close();
            const markdown = try fd.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(markdown);
            const metamatter = try parseMetadata(allocator, markdown, tagger);
            try createHtml(allocator, markdown, unit.path, metamatter, tempFile, src_dir, tagger);
        }
    }
    return tagger.*;
}

pub fn bufwriter(underlying_stream: anytype) io.BufferedWriter(1024 * 64, @TypeOf(underlying_stream)) {
    return .{ .unbuffered_writer = underlying_stream };
}

pub fn createHtml(allocator: std.mem.Allocator, markdown: []const u8, src_path: []const u8, metamatter: Metamatter, html: []const u8, src_dir: fs.Dir, tagger: *Tagger) !void {
    // refactor this
    const htmlFileName = try std.fmt.allocPrint(allocator, "{s}html", .{src_path[0 .. src_path.len - 2]});
    defer allocator.free(htmlFileName);
    var htmlFile = try fs.cwd().createFile(htmlFileName, .{});
    defer htmlFile.close();

    var bufferedwriter = bufwriter(htmlFile.writer());
    try ludicrous(allocator, markdown[metamatter.index + 1 ..], &bufferedwriter, bufferedwriter.writer(), metamatter, html, src_dir, tagger);
    try bufferedwriter.flush();
}

pub fn createTagPage(allocator: std.mem.Allocator, dir: fs.Dir, tagger: *Tagger) !void {
    var iter = tagger.*.tagmap.iterator();
    while (iter.next()) |value| {
        const key = value.key_ptr.*;
        std.debug.print("{s}", .{key});
        const fd = try std.fmt.allocPrint(allocator, "{s}.html", .{value.key_ptr.*});
        var tag_file = try dir.createFile(fd, .{});
        defer tag_file.close();
        const templ = try dir.openFile("../templates/tag.html", .{ .mode = .read_only });
        var tag_bufwrite = io.bufferedWriter(tag_file.writer());
        var temp = try templ.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(temp);
        if (std.mem.indexOf(u8, temp, "<!--")) |start| {
            _ = try tag_bufwrite.write(temp[0..start]);
            _ = try tag_bufwrite.write("Here lies the treasure");
            _ = try tag_bufwrite.write(temp[start + 11 ..]);
        }
        try tag_bufwrite.flush();
    }
}

pub fn ludicrous(allocator: std.mem.Allocator, markdown: []const u8, scribe: anytype, writer: anytype, metamatter: Metamatter, html: []const u8, src_dir: fs.Dir, tagger: *Tagger) !void {
    _ = allocator;

    _ = tagger;
    const x = struct {
        fn callback(conv: [*c]const md.MD_CHAR, size: md.MD_SIZE, userdata: ?*anyopaque) callconv(.C) void {
            const file: *@TypeOf(writer) = @ptrCast(@alignCast(userdata.?));
            if (file.write(conv[0..size])) |_| {} else |err| {
                std.log.err("File write failed {}", .{err});
            }
        }
    };
    var pointer: []const u8 = html;
    while (std.mem.indexOf(u8, pointer, "<!--")) |start_index| {
        _ = try scribe.write(pointer[0..start_index]);
        if (std.mem.indexOf(u8, pointer, "-->")) |end_index| {
            if (!std.mem.eql(u8, pointer[start_index + 4 .. end_index], "BODY")) {
                if (std.mem.eql(u8, pointer[start_index + 4 .. end_index], "tags")) {
                    var list = metamatter.tags;
                    var buff: [256]u8 = undefined;
                    _ = src_dir;
                    while (true) {
                        const tag = list.popOrNull() orelse break;
                        const bufw = try std.fmt.bufPrint(&buff, "<li><a href=\"tags/{s}\">[{s}]</a></li> ", .{ std.mem.trim(u8, tag, " "), std.mem.trim(u8, tag, " ") });
                        _ = try scribe.write(bufw);
                    }
                } else {}
                _ = try scribe.write(metamatter.metadata.get(pointer[start_index + 4 .. end_index]) orelse "");
                pointer = pointer[end_index + 3 ..];
            } else {
                _ = md.md_html(markdown.ptr, @intCast(markdown.len), x.callback, @ptrCast(@constCast(&writer)), @intCast(0), md.MD_HTML_FLAG_DEBUG);
                pointer = pointer[end_index + 3 ..];
            }
        } else {
            std.debug.print("Unclosed CommentLine encountered in template file", .{});
        }
    }
    _ = try scribe.write(pointer[0..]);
}

pub fn main() !void {
    const alloc = std.heap.raw_c_allocator;
    const template = "./templates/template.html";
    const fd = fs.cwd().openFile(template, .{ .mode = .read_only }) catch |e| {
        std.log.err("{s} Can't be opened for reading", .{template});
        return e;
    };
    defer fd.close();
    const html = try fd.readToEndAlloc(alloc, 1024 * 1024);
    var dir = fs.cwd().openDir("tags/", .{}) catch |err| {
        if (err == fs.OpenSelfExeError.FileNotFound) {
            std.debug.print("creating tags dir", .{});
            return try fs.cwd().makeDir("tags");
        } else {
            return error.Unexpected;
        }
    };
    defer dir.close();
    var tag_hashmap = std.StringHashMap(std.ArrayList([]const u8)).init(alloc);
    defer tag_hashmap.deinit();
    var tagger = Tagger{ .tagmap = tag_hashmap };
    try stroll(alloc, "markdwns/", html, &tagger);
    std.debug.print("{}", .{tagger.tagmap.count()});
    try createTagPage(alloc, dir, &tagger);
}
