pub const packages = struct {
    pub const @"../Huge-sl" = struct {
        pub const build_root = "/home/hughjazz/dev/zig/Huge/../Huge-sl";
        pub const build_zig = @import("../Huge-sl");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "hgsl", "../Huge-sl" },
};
