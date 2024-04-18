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

fn createHtml(path: []const u8) !fs.File {
    var buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    const filePath = try std.fmt.bufPrint(&buffer, "{s}html", .{path[0 .. path.len - 2]});
    const htmlFile = try fs.cwd().openFile(filePath, .{});
    return htmlFile;
}

fn stroll(allocator: std.mem.Allocator, arena: std.mem.Allocator, content_dir: fs.Dir, layouts: Layouts) !void {
    _ = layouts;
    var markdown = std.ArrayList(u8).init(allocator);
    defer markdown.deinit();

    var metamatter: Metamatter = undefined;

    var stroller = try content_dir.walk(allocator);
    stroller.deinit();

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
    try stroll(allocator, aAlloc, content_dir, layouts);
}
