const std = @import("std");
const fs = std.fs;
const io = std.io;
const md = @cImport({
    @cInclude("md4c-html.h");
});

const CONTENT = "content/";
const TEMPLATE = "./templates/template.html";

const Metamatter = struct {
    metadata: std.StringHashMap([]const u8),
    index: usize,
    tags: std.ArrayList([]const u8),
};

pub var tagmap: std.StringHashMap(std.ArrayList(std.StringHashMap([]const u8))) = undefined;

pub fn bufWriter(underlying_stream: anytype) io.BufferedWriter(1024 * 128, @TypeOf(underlying_stream)) {
    return .{ .unbuffered_writer = underlying_stream };
}

pub fn bufReader(reader: anytype) io.BufferedReader(1024 * 1024, @TypeOf(reader)) {
    return .{ .unbuffered_reader = reader };
}

pub fn collectTag(allocator: std.mem.Allocator, metamatter: Metamatter) !void {
    for (metamatter.tags.items) |tag| {
        if (tagmap.getPtr(tag)) |entry| {
            try entry.append(metamatter.metadata);
        } else {
            var newposts = std.ArrayList(std.StringHashMap([]const u8)).init(allocator);
            try newposts.append(metamatter.metadata);
            try tagmap.put(tag, newposts);
        }
    }
}
fn createTagFiles(allocator: std.mem.Allocator, dir: fs.Dir) !void {
    var hash_iter = tagmap.iterator();
    const template = dir.openFile("../templates/tag.html", .{ .mode = .read_only }) catch |err| {
        std.log.err("Unable to open template for reading. Please check permissions. {}", .{err});
        return err;
    };
    defer template.close();
    const html = try template.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(html);
    while (hash_iter.next()) |entry| {
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const file = try std.fmt.bufPrint(&buffer, "./{s}.html", .{entry.key_ptr.*});
        var fd = try dir.createFile(file, .{});
        defer fd.close();
        var writer = bufWriter(fd.writer());

        if (std.mem.indexOf(u8, html, "<!--")) |index| {
            _ = try writer.write(html[0..index]);
        }
        const value = entry.value_ptr.items;
        for (value) |item| {
            const string = try std.fmt.allocPrint(allocator, "<h2>{s}</h2>", .{item.get("title") orelse ""});
            _ = try writer.write(string);
        }
        try writer.flush();
    }
}
// The metamatter parser
fn parseMeta(allocator: std.mem.Allocator, content: []const u8) !Metamatter {
    var metadata = std.StringHashMap([]const u8).init(allocator);
    var tagList = std.ArrayList([]const u8).init(allocator);
    var index: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] == '%') {
            var parts = std.mem.splitSequence(u8, line[1..], ":");
            const key = parts.next() orelse continue;
            const val = parts.next() orelse continue;
            const key_trim = std.mem.trim(u8, key, " ");
            const val_trim = std.mem.trim(u8, val, " ");
            if (std.mem.eql(u8, key_trim, "tags")) {
                // do tags here
                var tags = std.mem.splitSequence(u8, val[0..], ",");
                while (tags.next()) |tag| {
                    try tagList.append(tag);
                }
            } else {
                try metadata.put(key_trim, val_trim);
            }
            index += line.len + 1;
        } else {
            return Metamatter{ .metadata = metadata, .tags = tagList, .index = index };
        }
    }
    return Metamatter{ .metadata = undefined, .tags = undefined, .index = 0 };
}

pub fn prepare(allocator: std.mem.Allocator, fd: fs.File, src_path: []const u8, dir: fs.Dir, html: []const u8) !void {
    const markdown = try fd.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(markdown);
    // pass the file to be parsed.
    const metamatter = try parseMeta(allocator, markdown);
    try collectTag(allocator, metamatter);
    const newFile = try std.fmt.allocPrint(allocator, "{s}html", .{src_path[0 .. src_path.len - 2]});
    defer allocator.free(newFile);
    var htmlFile = try fs.cwd().createFile(newFile, .{});
    defer htmlFile.close();
    var bufferedwriter = bufWriter(htmlFile.writer());
    // here we call ludicrous
    try parser(markdown[metamatter.index + 1 ..], &bufferedwriter, metamatter, html, dir);
    try bufferedwriter.flush();
}

pub fn stroll(allocator: std.mem.Allocator, dir: fs.Dir, html: []const u8) !void {
    var content_dir = dir.openDir("./content", .{ .iterate = true }) catch |err| {
        std.log.err("Unable to open the content directory: {}", .{err});
        return err;
    };
    const templ = try dir.openFile("./templates/tag.html", .{ .mode = .read_only });
    defer templ.close();
    var stroller = try content_dir.walk(allocator);
    defer stroller.deinit();

    while (try stroller.next()) |unit| {
        if (unit.kind == .file) {
            var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
            const path = try std.fmt.bufPrint(&buffer, "./content/{s}", .{unit.path});
            const fd = dir.openFile(path, .{ .mode = .read_only }) catch |err| {
                std.log.err("{s} can't be opened for reading. Please check file permissions.", .{unit.path});
                return err;
            };
            defer fd.close();
            try prepare(allocator, fd, unit.path, dir, html);
            // parse markdown
        }
    }
}

fn parser(markdown: []const u8, scribe: anytype, metamatter: Metamatter, html: []const u8, src_dir: fs.Dir) !void {
    const x = struct {
        fn callback(conv: [*c]const md.MD_CHAR, size: md.MD_SIZE, userdata: ?*anyopaque) callconv(.C) void {
            const file: *@TypeOf(scribe.*.writer()) = @ptrCast(@alignCast(userdata.?));
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
                _ = md.md_html(markdown.ptr, @intCast(markdown.len), x.callback, @ptrCast(@constCast(&(scribe.*.writer()))), @intCast(0), md.MD_HTML_FLAG_DEBUG);
                pointer = pointer[end_index + 3 ..];
            }
        } else {
            std.debug.print("Unclosed CommentLine encountered in template file", .{});
        }
    }
    _ = try scribe.write(pointer[0..]);
}

pub fn main() !void {
    // Literally calls the libc malloc/free
    //const allocator = std.heap.raw_c_allocator;
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = alloc.allocator();
    var src_dir = try fs.cwd().openDir(".", .{ .iterate = true });
    defer src_dir.close();
    const template = src_dir.openFile("./templates/template.html", .{ .mode = .read_only }) catch |err| {
        std.log.err("{s}: Template cannot be accessed. Please check file permissions.", .{TEMPLATE});
        return err;
    };
    defer template.close();

    std.fs.cwd().makeDir("tags") catch |e| switch (e) {
        error.PathAlreadyExists => {}, // assume it exists, try to create files or stat to figure out if it's a dir
        else => return e,
    };
    var tag_dir = try src_dir.openDir("tags", .{});
    defer tag_dir.close();
    const html = try template.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(html);
    tagmap = @TypeOf(tagmap).init(allocator);
    defer tagmap.deinit();
    try stroll(allocator, src_dir, html);
    try createTagFiles(allocator, tag_dir);
}
