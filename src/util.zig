const std = @import("std");
const huge = @import("root.zig");
const math = huge.math;

pub const KiB = 1024;
pub const MiB = KiB * 1024;
pub const GiB = MiB * 1024;

pub fn rut(T: type, a: T, b: T) T {
    if (@typeInfo(T) != .int)
        @compileError("rut: T must be integer and not " ++ @typeName(T));
    return (a + b - 1) / b * b;
}
pub fn ipp(i: anytype) @typeInfo(@TypeOf(i)).pointer.child {
    const save = i.*;
    i.* += 1;
    return save;
}

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
pub fn enumLen(Enum: type) usize {
    return @typeInfo(Enum).@"enum".fields.len;
}
pub fn BackingInt(Struct: type) type {
    return @typeInfo(Struct).@"struct".backing_integer.?;
}
pub fn FlagStructFromUnion(Union: type, comptime default_value: bool) type {
    const union_fields = @typeInfo(Union).@"union".fields;
    var struct_field_names: [union_fields.len][]const u8 = undefined;
    var struct_field_types: [union_fields.len]type = @splat(bool);
    const struct_field_attributes: [union_fields.len]std.builtin.Type.StructField.Attributes = @splat(.{
        .@"comptime" = false,
        .@"align" = null,
        .default_value_ptr = &default_value,
    });
    inline for (union_fields, 0..) |uf, i| {
        struct_field_names[i] = uf.name;
    }

    return @Struct(
        .@"packed",
        null,
        &struct_field_names,
        &struct_field_types,
        &struct_field_attributes,
    );
}
pub fn StructFromUnion(Union: type, default_values: anytype) type {
    const union_fields = @typeInfo(Union).@"union".fields;
    var struct_field_names: [union_fields.len][]const u8 = undefined;
    var struct_field_types: [union_fields.len]type = undefined;
    var struct_field_attributes: [union_fields.len]std.builtin.Type.StructField.Attributes = undefined;
    inline for (union_fields, 0..) |uf, i| {
        struct_field_names[i] = uf.name;
        struct_field_types[i] = uf.type;
        struct_field_attributes[i] = .{
            .@"comptime" = false,
            .@"align" = @alignOf(uf.type),
            .default_value_ptr = if (default_values.len == 0)
                null
            else
                @ptrCast(&@as(uf.type, default_values[@min(i, default_values.len -| 1)])),
        };
    }

    return @Struct(
        .auto,
        null,
        &struct_field_names,
        &struct_field_types,
        &struct_field_attributes,
    );
}
pub fn StructFromEnum(Enum: type, T: type, default_value: ?T, layout: std.builtin.Type.ContainerLayout) type {
    const em = @typeInfo(Enum).@"enum";
    var struct_field_names: [em.fields.len][]const u8 = undefined;
    var struct_field_types: [em.fields.len]type = undefined;
    const sturct_field_attributes: [em.fields.len]std.builtin.Type.StructField.Attributes =
        @splat(.{
            .@"comptime" = false,
            .@"align" = if (layout == .@"packed") null else @alignOf(T),
            .default_value_ptr = if (default_value) |dv| &dv else null,
        });
    inline for (em.fields, 0..) |ef, i| {
        struct_field_names[i] = ef.name;
        struct_field_types[i] = T;
    }
    return @Struct(
        layout,
        null,
        &struct_field_names,
        &struct_field_types,
        &sturct_field_attributes,
    );
}
pub fn matchFlagStructs(comptime FlagStruct: type, value: FlagStruct, pattern: FlagStruct) bool {
    return inline for (@typeInfo(FlagStruct).@"struct".fields) |sf| {
        const value_field = @field(value, sf.name);
        const pattern_field = @field(pattern, sf.name);
        if (pattern_field and !value_field) break false;
    } else true;
}
