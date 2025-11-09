pub const packages = struct {
    pub const @"../Huge-sl" = struct {
        pub const build_root = "/home/hughjazz/dev/zig/Huge/../Huge-sl";
        pub const build_zig = @import("../Huge-sl");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"system_sdk-0.3.0-dev-alwUNnYaaAJAtIdE2fg4NQfDqEKs7QCXy_qYukAOBfmF" = struct {
        pub const build_root = "/home/hughjazz/.cache/zig/p/system_sdk-0.3.0-dev-alwUNnYaaAJAtIdE2fg4NQfDqEKs7QCXy_qYukAOBfmF";
        pub const build_zig = @import("system_sdk-0.3.0-dev-alwUNnYaaAJAtIdE2fg4NQfDqEKs7QCXy_qYukAOBfmF");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"zglfw-0.10.0-dev-zgVDNDVvIgCvcfVlhUJW0raBmELJiQwpOilGKmMiL4Ya" = struct {
        pub const build_root = "/home/hughjazz/.cache/zig/p/zglfw-0.10.0-dev-zgVDNDVvIgCvcfVlhUJW0raBmELJiQwpOilGKmMiL4Ya";
        pub const build_zig = @import("zglfw-0.10.0-dev-zgVDNDVvIgCvcfVlhUJW0raBmELJiQwpOilGKmMiL4Ya");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "system_sdk", "system_sdk-0.3.0-dev-alwUNnYaaAJAtIdE2fg4NQfDqEKs7QCXy_qYukAOBfmF" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "hgsl", "../Huge-sl" },
    .{ "zglfw", "zglfw-0.10.0-dev-zgVDNDVvIgCvcfVlhUJW0raBmELJiQwpOilGKmMiL4Ya" },
};
