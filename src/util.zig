const std = @import("std");
const huge = @import("root.zig");
const math = huge.math;

pub fn f32fromBool(b: bool) f32 {
    return @floatFromInt(@intFromBool(b));
}
pub fn aspectRatioSize(size: math.uvec2) f32 {
    const v: math.vec2 = @floatFromInt(size);
    return v[0] / v[1];
}
pub fn strEql(a: []const u8, b: []const u8) bool {
    return if (a.len == b.len) std.mem.eql(u8, a, b) else false;
}
pub fn strEqlNullTerm(a: [*:0]const u8, b: [*:0]const u8) bool {
    const as = a[0..std.mem.len(a)];
    const bs = a[0..std.mem.len(b)];
    return strEql(as, bs);
}
pub fn structFieldIndexFromName(Struct: type, comptime name: []const u8) usize {
    return for (@typeInfo(Struct).@"struct".fields, 0..) |sf, i| {
        if (strEql(name, sf.name)) break i;
    } else unreachable;
}
pub fn StructFromEnum(Enum: type, T: type, default_value: ?T, layout: std.builtin.Type.ContainerLayout) type {
    const em = @typeInfo(Enum).@"enum";
    var struct_fields: [em.fields.len]std.builtin.Type.StructField = undefined;
    inline for (em.fields, &struct_fields) |ef, *sf| {
        sf.* = .{
            .default_value_ptr = if (default_value) |d| &d else null,
            .alignment = if (layout == .@"packed") 0 else @alignOf(T),
            .is_comptime = false,
            .name = ef.name,
            .type = T,
        };
    }
    return @Type(.{ .@"struct" = .{
        .decls = &.{},
        .fields = &struct_fields,
        .is_tuple = false,
        .layout = layout,
    } });
}
pub fn matchFlagStructs(comptime FlagStruct: type, value: FlagStruct, pattern: FlagStruct) bool {
    return inline for (@typeInfo(FlagStruct).@"struct".fields) |sf| {
        const value_field = @field(value, sf.name);
        const pattern_field = @field(pattern, sf.name);
        if (pattern_field and !value_field) break false;
    } else true;
}
