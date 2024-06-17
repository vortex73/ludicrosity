const std = @import("std");
const datetime = @import("./zig-datetime/src/main.zig");
const assert = std.debug.assert;

pub fn main() !void {
    const d1 = try datetime.datetime.Date.parseIso("2021-12-11");
    const d2 = try datetime.datetime.Date.parseIso("2021-12-12");
    const res = datetime.datetime.Date.cmp(d1, d2);

    std.debug.print("{any}", .{res});
}
