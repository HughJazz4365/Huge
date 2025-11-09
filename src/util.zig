const std = @import("std");
pub fn strEql(a: []const u8, b: []const u8) bool {
    return if (a.len == b.len) std.mem.eql(u8, a, b) else false;
}
pub fn structFieldIndexFromName(Struct: type, comptime name: []const u8) usize {
    return for (@typeInfo(Struct).@"struct".fields, 0..) |sf, i| {
        if (strEql(name, sf.name)) break i;
    } else unreachable;
}
