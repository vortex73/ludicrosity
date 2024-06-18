const std = @import("std");
const datetime = @import("datetime");
const fs = std.fs;
const io = std.io;
const md = @cImport({
    @cInclude("md4c-html.h");
});

const mem = std.mem;

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
    list: []const u8,
    index: []const u8,
    about: []const u8,
    fn deinit(self: *Layouts, allocator: std.mem.Allocator) void {
        allocator.free(self.post);
        allocator.free(self.tags);
        allocator.free(self.list);
        allocator.free(self.index);
        allocator.free(self.about);
    }
};

const TagMap = std.StringHashMap(std.ArrayList(std.StringHashMap([]const u8)));

// custom buffered writer big enough for anything.
pub fn bufWriter(underlying_stream: anytype) io.BufferedWriter(1024 * 128, @TypeOf(underlying_stream)) {
    return .{ .unbuffered_writer = underlying_stream };
}

// loads templates
// CLEAN THIS!
fn readLayouts(allocator: std.mem.Allocator, content_dir: fs.Dir) !Layouts {
    const postFile = try content_dir.openFile("../templates/post.html", .{ .mode = .read_only });
    defer postFile.close();
    const tagsFile = try content_dir.openFile("../templates/tags.html", .{ .mode = .read_only });
    defer tagsFile.close();
    const listFile = try content_dir.openFile("../templates/list.html", .{ .mode = .read_only });
    defer listFile.close();
    const indexFile = try content_dir.openFile("../templates/index.html", .{ .mode = .read_only });
    defer indexFile.close();
    const aboutFile = try content_dir.openFile("../templates/about.html", .{ .mode = .read_only });
    defer aboutFile.close();
    const post = try postFile.readToEndAlloc(allocator, 1024 * 1024);
    const about = try aboutFile.readToEndAlloc(allocator, 1024 * 1024);
    const tags = try tagsFile.readToEndAlloc(allocator, 1024 * 1024);
    const list = try listFile.readToEndAlloc(allocator, 1024 * 1024);
    const index = try indexFile.readToEndAlloc(allocator, 1024 * 1024);
    return Layouts{ .post = post, .tags = tags, .list = list, .index = index, .about = about };
}

// Parse Metamatter content
fn parseMetamatter(allocator: std.mem.Allocator, content: []const u8, path: []const u8) !Metamatter {
    var metadata = std.StringHashMap([]const u8).init(allocator);
    var tagList = std.ArrayList([]const u8).init(allocator);
    errdefer tagList.deinit();
    var index: usize = 0;
    var lines = std.mem.splitSequence(u8, content, "\n");
    const newpath = try allocator.dupe(u8, path);
    try metadata.put("path", newpath);
    while (lines.next()) |line| {
        if (line.len > 0 and line[0] == '%') {
            var parts = std.mem.splitSequence(u8, line[1..], ":");
            const key = parts.next() orelse continue;
            const val = parts.next() orelse continue;
            const key_trim = std.mem.trim(u8, key, " ");
            const val_trim = std.mem.trim(u8, val, " ");
            const key_copy = try allocator.dupe(u8, key_trim);
            const val_copy = try allocator.dupe(u8, val_trim);
            if (std.mem.eql(u8, key_copy, "tags")) {
                // do tags here
                var tags = std.mem.splitSequence(u8, val[0..], ",");
                var int: usize = 0;
                var new_tag: []const u8 = undefined;
                while (tags.next()) |tag| {
                    new_tag = std.mem.trim(u8, tag, " ");
                    const tag_copy = try allocator.dupe(u8, new_tag);
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
    return Metamatter{ .metadata = metadata, .tags = tagList, .index = 0 };
}

fn lessthanfn(context: void, lhs: Metamatter, rhs: Metamatter) bool {
    _ = context;
    const l = datetime.datetime.Date.parseIso(lhs.metadata.get("date") orelse "") catch return undefined;
    const r = datetime.datetime.Date.parseIso(rhs.metadata.get("date") orelse "") catch return undefined;
    return datetime.datetime.Date.lt(l, r);
}

fn snipp(allocator: mem.Allocator, name: []const u8, meta: Metamatter, writer: anytype) !void {
    var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const file = try std.fmt.bufPrint(&buffer, "templates/snippets/{s}.html", .{name});
    const handle = fs.cwd().openFile(file, .{ .mode = .read_only }) catch |e| {
        std.log.err("snippet type {s} not defined", .{name});
        return e;
    };
    var html = try handle.readToEndAlloc(allocator, 1024);
    while (mem.indexOf(u8, html, "<!--")) |start| {
        _ = try writer.*.write(html[0..start]);
        if (mem.indexOf(u8, html, "-->")) |end| {
            _ = try writer.write(meta.metadata.get(html[start + 4 .. end]) orelse "");
            html = html[end + 3 ..];
        }
    }
    _ = try writer.write(html[0..]);
}

fn indexify(allocator: mem.Allocator, metaList: std.ArrayList(Metamatter), layout: []const u8) !void {
    defer metaList.deinit();
    // sort
    const items = metaList.items;
    mem.sort(Metamatter, items, {}, lessthanfn);
    var file = try fs.cwd().createFile("rendered/list.html", .{});
    defer file.close();
    var writer = bufWriter(file.writer());
    defer writer.flush() catch std.log.err("Write failed to list.html", .{});
    var html = layout;
    while (mem.indexOf(u8, html, "<!--@")) |start| {
        _ = try writer.write(html[0..start]);
        if (mem.indexOf(u8, html, "@-->")) |end| {
            if (mem.eql(u8, html[start + 5 .. end], "list")) {
                for (items) |item| {
                    try snipp(allocator, html[start + 5 .. end], item, &writer);
                }
                html = html[end + 4 ..];
            }
            _ = try writer.write(html[0..]);
        }
    }
}

// Create one html file per tag
fn createTagFiles(dir: fs.Dir, html: []const u8, tagmap: *TagMap) !void {
    var hash_iter = tagmap.iterator();
    while (hash_iter.next()) |entry| {
        const path = entry.key_ptr.*;
        var buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        const file = try std.fmt.bufPrint(&buffer, "../tags/{s}.html", .{path});
        var fd = try dir.createFile(file, .{});
        defer fd.close();
        var writer = bufWriter(fd.writer());

        var pointer: []const u8 = html;
        while (mem.indexOf(u8, pointer, "<!--")) |start| {
            _ = try writer.write(pointer[0..start]);
            if (mem.indexOf(u8, pointer, "-->")) |end| {
                if (mem.eql(u8, pointer[start + 4 .. end], "title")) {
                    _ = try writer.write(entry.key_ptr.*);
                }
                if (mem.eql(u8, pointer[start + 4 .. end], "posts")) {
                    const value = entry.value_ptr.items;
                    for (value) |item| {
                        try writer.writer().print("<h2><a href=\"/rendered/{s}html\"> {s}</a></h2>", .{ item.get("path") orelse "", item.get("title") orelse "" });
                    }
                }
                pointer = pointer[end + 3 ..];
            }
        }
        _ = try writer.write(pointer);
        try writer.flush();
    }
}

// creates a new html file in the rendered dir and returns the path
fn createHtml(path: fs.Dir.Walker.Entry) !fs.File {
    var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    const filePath = try std.fmt.bufPrint(&buffer, "./rendered/{s}html", .{path.path[0 .. path.path.len - 2]});
    const htmlFile = fs.cwd().createFile(filePath, .{}) catch |e| switch (e) {
        error.FileNotFound => {
            _ = try fs.cwd().makePath(filePath[0..(filePath.len - path.basename.len)]);
            return fs.cwd().createFile(filePath, .{});
        },
        else => return e,
    };
    return htmlFile;
}

// collect tags and posts related to them
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

// Parse markdown content and write into html file
// CLEAN THIS!
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
                        const bufw = try std.fmt.bufPrint(&buff, "<li><a href=\"../tags/{s}.html\">[{s}]</a></li> ", .{ std.mem.trim(u8, tag, " "), std.mem.trim(u8, tag, " ") });
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
            std.log.err("Unclosed CommentLine encountered in template file", .{});
        }
    }
    _ = try scribe.write(pointer[0..]);
}

// Directory walker
fn stroll(allocator: std.mem.Allocator, content_dir: fs.Dir, layouts: Layouts, tagmap: *TagMap) !void {
    var markdown = std.ArrayList(u8).init(allocator);
    defer markdown.deinit();

    var metamatter: Metamatter = undefined;
    var metaList = std.ArrayList(Metamatter).init(allocator);

    var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    var stroller = try content_dir.walk(allocator);
    defer stroller.deinit();
    while (try stroller.next()) |post| {
        if (post.kind == .file) {
            std.debug.print("{s}\n", .{post.path});
            const path = try std.fmt.bufPrint(&buffer, "{s}", .{post.path});
            const fd = try content_dir.openFile(path, .{ .mode = .read_only });
            defer fd.close();

            const reader = fd.reader();
            try reader.readAllArrayList(&markdown, 0xffff_ffff);
            defer markdown.clearRetainingCapacity();

            metamatter = try parseMetamatter(allocator, markdown.items, post.path[0 .. post.path.len - 2]);
            try metaList.append(metamatter);
            var htmlFile = try createHtml(post);
            defer htmlFile.close();
            var writer = bufWriter(htmlFile.writer());
            defer writer.flush() catch std.log.err("Flush failed. Bring a plunger ;D", .{});
            // parse markdown now
            if (std.mem.eql(u8, metamatter.metadata.get("type") orelse "", "index")) {
                try parser(markdown.items[metamatter.index + 1 ..], &writer, metamatter, layouts.index);
                continue;
            }
            if (std.mem.eql(u8, metamatter.metadata.get("type") orelse "", "about")) {
                try parser(markdown.items[metamatter.index + 1 ..], &writer, metamatter, layouts.about);
                continue;
            }
            try parser(markdown.items[metamatter.index + 1 ..], &writer, metamatter, layouts.post);
            try collectTag(allocator, metamatter, tagmap);
        }
    }
    try indexify(allocator, metaList, layouts.list);
}

pub fn main() !void {
    // gpa used to detect memory leaks. Most likely temporary.
    var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 30 }){};
    const gallocator = gpa.allocator();
    // var gpa = std.heap.GeneralPurposeAllocator(.{ .stack_trace_frames = 30 }){};
    // const gallocator = gpa.allocator();
    // var logalloc = std.heap.loggingAllocator(gallocator);
    // const allocator = logalloc.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);
    var arena = std.heap.ArenaAllocator.init(gallocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // define a tagmap
    var tagmap: TagMap = undefined;

    // open cwd for the action
    var content_dir = try fs.cwd().openDir("./content", .{ .iterate = true });
    defer content_dir.close();

    // load all layouts. Hardcoded for now, prolly make it more general purpose.
    var layouts = try readLayouts(allocator, content_dir);
    defer layouts.deinit(allocator);

    // verify custom directories
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
    // maneuver to deinit contained data structures.
    defer {
        var metamatter = std.AutoHashMap(std.StringHashMap([]const u8), void).init(allocator);
        defer metamatter.deinit();
        var hashIter = tagmap.iterator();
        while (hashIter.next()) |*tag| {
            defer tag.value_ptr.deinit();
            for (tag.value_ptr.items) |*data| {
                metamatter.put(data.*, undefined) catch break;
            }
        }
        var metaIter = metamatter.iterator();
        while (metaIter.next()) |*value| {
            value.key_ptr.deinit();
        }
    }
    try stroll(allocator, content_dir, layouts, &tagmap);
    try createTagFiles(content_dir, layouts.tags, &tagmap);
}
