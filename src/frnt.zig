const std = @import("std");

pub const FrontMatter = struct {
    title: []const u8,
    date: []const u8,
    author: []const u8,
};

pub fn parseFrontMatter(file: []const u8) !FrontMatter {
    const frontMatterEnd = std.mem.indexOf(u8, u8, '\n', file) orelse |err| {
        if (err == std.mem.NotFoundError) {
            return error.InvalidFrontMatter;
        } else {
            return err;
        }
    };

    const frontMatter = file[0..frontMatterEnd];

    var title: []const u8 = null;
    var date: []const u8 = null;
    var author: []const u8 = null;

    const lines = std.mem.split(frontMatter, '\n');
    for (lines) |line| {
        const keyVal = std.mem.split(line, ':');
        if (keyVal.len >= 2) {
            const key = std.mem.trim(keyVal[0]);
            const val = std.mem.trim(keyVal[1]);

            if (key == "title") {
                title = val;
            } else if (key == "date") {
                date = val;
            } else if (key == "author") {
                author = val;
            }
        }
    }

    if (title == null || date == null || author == null) {
        return error.InvalidFrontMatter;
    }

    return FrontMatter{ .title = title, .date = date, .author = author };
}

pub fn main() !void {
    const file = try std.fs.readFileAlloc("blog_post.md");

    const frontMatter = try parseFrontMatter(file);

    std.debug.print("Title: {s}\nDate: {s}\nAuthor: {s}\n",
        .{frontMatter.title, frontMatter.date, frontMatter.author});
}

