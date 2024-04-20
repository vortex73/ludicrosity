const std = @import("std");
const fs = std.fs;
const io = std.io;
const md = @cImport({
    @cInclude("md4c-html.h");
});

const Metamatter = struct {
    metadata: std.StringHashMap([]const u8),
    index: usize,
    tags: std.ArrayList([]const u8),
    fn deinit(self: *Metamatter) void {
        self.metadata.deinit();
        self.tags.deinit();
    }
};
const Layouts = struct {
    post: []const u8,
    tags: []const u8,
};

const TagMap = std.StringHashMap(std.ArrayList(std.StringHashMap([]const u8)));

pub fn bufWriter(underlying_stream: anytype) io.BufferedWriter(1024 * 128, @TypeOf(underlying_stream)) {
    return .{ .unbuffered_writer = underlying_stream };
}

fn readLayouts(allocator: std.mem.Allocator, content_dir: fs.Dir) !Layouts {
    const postFile = try content_dir.openFile("../templates/post.html", .{ .mode = .read_only });
    defer postFile.close();
    const tagsFile = try content_dir.openFile("../templates/tags.html", .{ .mode = .read_only });
    defer tagsFile.close();
    const post = try postFile.readToEndAlloc(allocator, 1024 * 1024);
    const tags = try tagsFile.readToEndAlloc(allocator, 1024 * 1024);
    return Layouts{ .post = post, .tags = tags };
}

fn parseMetamatter(allocator: std.mem.Allocator, arena: std.mem.Allocator, content: []const u8) !Metamatter {
    var metadata = std.StringHashMap([]const u8).init(allocator);
    var tagList = std.ArrayList([]const u8).init(allocator);
    errdefer tagList.deinit();
    var index: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] == '%') {
            var parts = std.mem.splitSequence(u8, line[1..], ":");
            const key = parts.next() orelse continue;
            const val = parts.next() orelse continue;
            const key_trim = std.mem.trim(u8, key, " ");
            const val_trim = std.mem.trim(u8, val, " ");
            const key_copy = try arena.dupe(u8, key_trim);
            const val_copy = try arena.dupe(u8, val_trim);
            if (std.mem.eql(u8, key_copy, "tags")) {
                // do tags here
                var tags = std.mem.splitSequence(u8, val[0..], ",");
                var int: usize = 0;
                while (tags.next()) |tag| {
                    const tag_copy = try arena.dupe(u8, tag);
                    try tagList.insert(int, tag_copy);
                    int += 1;
                }
            } else {
                try metadata.put(key_copy, val_copy);
            }
            index += line.len + 1;
        } else {
            return Metamatter{ .metadata = metadata, .tags = tagList, .index = index };
        }
    }
    return Metamatter{ .metadata = undefined, .tags = undefined, .index = 0 };
}

fn createTagFiles(allocator: std.mem.Allocator, dir: fs.Dir, html: []const u8, tagmap: *TagMap) !void {
    var hash_iter = tagmap.iterator();
    defer allocator.free(html);
    while (hash_iter.next()) |entry| {
        const path = entry.key_ptr.*;
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const file = try std.fmt.bufPrint(&buffer, "../tags/{s}.html", .{path});
        var fd = try dir.createFile(file, .{});
        defer fd.close();
        var writer = bufWriter(fd.writer());

        if (std.mem.indexOf(u8, html, "<!--")) |index| {
            _ = try writer.write(html[0..index]);
        }
        const value = entry.value_ptr.items;
        for (value) |item| {
            try writer.writer().print("<h2>{s}</h2>", .{item.get("title") orelse ""});
        }
        if (std.mem.indexOf(u8, html, "<!--")) |index| {
            _ = try writer.write(html[index + 11 ..]);
        }
        try writer.flush();
    }
}

fn createHtml(path: []const u8) !fs.File {
    var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    const filePath = try std.fmt.bufPrint(&buffer, "./rendered/{s}html", .{path[0 .. path.len - 2]});
    const htmlFile = try fs.cwd().createFile(filePath, .{});
    return htmlFile;
}

pub fn collectTag(allocator: std.mem.Allocator, metamatter: Metamatter, tagmap: *TagMap) !void {
    for (metamatter.tags.items) |tag| {
        if (tagmap.getPtr(tag)) |entry| {
            try entry.append(metamatter.metadata);
        } else {
            var newposts = std.ArrayList(std.StringHashMap([]const u8)).init(allocator);
            try newposts.append(metamatter.metadata);
            try tagmap.put(tag, newposts);
        }
    }
    metamatter.tags.deinit();
}

fn parser(markdown: []const u8, scribe: anytype, metamatter: Metamatter, html: []const u8) !void {
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
                    var buff: [4 * 1024]u8 = undefined;
                    while (true) {
                        const tag = list.popOrNull() orelse break;
                        const bufw = try std.fmt.bufPrint(&buff, "<li><a href=\"tags/{s}.html\">[{s}]</a></li> ", .{ std.mem.trim(u8, tag, " "), std.mem.trim(u8, tag, " ") });
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

fn stroll(allocator: std.mem.Allocator, arena: std.mem.Allocator, content_dir: fs.Dir, layouts: Layouts, tagmap: *TagMap) !void {
    var markdown = std.ArrayList(u8).init(allocator);
    defer markdown.deinit();

    var metamatter: Metamatter = undefined;

    var stroller = try content_dir.walk(allocator);
    defer stroller.deinit();

    var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    while (try stroller.next()) |post| {
        if (post.kind == .file) {
            const path = try std.fmt.bufPrint(&buffer, "{s}", .{post.path});
            const fd = try content_dir.openFile(path, .{ .mode = .read_only });
            defer fd.close();

            const reader = fd.reader();
            try reader.readAllArrayList(&markdown, 0xffff_ffff);
            defer markdown.clearRetainingCapacity();

            metamatter = try parseMetamatter(allocator, arena, markdown.items);
            var htmlFile = try createHtml(post.path);
            defer htmlFile.close();
            var writer = bufWriter(htmlFile.writer());
            defer writer.flush() catch std.log.err("Flush failed. Bring a plunger ;D", .{});
            // parse markdown now
            try parser(markdown.items[metamatter.index + 1 ..], &writer, metamatter, layouts.post);
            try collectTag(allocator, metamatter, tagmap);
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 30 }){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const aAlloc = arena.allocator();

    // define a tagmap
    var tagmap: TagMap = undefined;

    // open cwd for the action
    var content_dir = try fs.cwd().openDir("./content", .{ .iterate = true });
    defer content_dir.close();

    const layouts = try readLayouts(allocator, content_dir);
    defer allocator.free(layouts.post);

    // verify tags directory
    fs.cwd().makeDir("tags") catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };
    fs.cwd().makeDir("rendered") catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => return e,
    };

    tagmap = TagMap.init(allocator);
    defer tagmap.deinit();
    var hashIter = tagmap.iterator();
    try stroll(allocator, aAlloc, content_dir, layouts, &tagmap);
    defer {
        while (hashIter.next()) |*tag| {
            defer tag.value_ptr.deinit();
            const value = tag.value_ptr.items;
            for (value) |*item| {
                item.deinit();
            }
        }
    }
    try createTagFiles(allocator, content_dir, layouts.tags, &tagmap);
}
