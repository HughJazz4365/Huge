const std = @import("std");
const huge = @import("../root.zig");
pub const hgsl = @import("hgsl");
pub const Backend = @import("GpuBackend.zig");

var backend: Backend = undefined; //default to software renderer??

pub const Error = error{
    OutOfMemory,

    WindowContextCreationError,
    BackendInitializationFailure,

    ShaderCompilationError,
};
pub fn init() Error!void {
    backend = @import("vulkan/vulkanBackend.zig").initBackend() catch
        return Error.BackendInitializationFailure;
}
pub fn deinit() void {
    backend.deinit();
}
pub inline fn api() GApi {
    return backend.api;
}
pub inline fn apiVersion() huge.Version {
    return backend.api_version;
}
pub fn createWindowContext(window: huge.Window) Error!WindowContext {
    return try backend.createWindowContext(window);
}

pub const Pipeline = enum(u32) {
    _,
    pub fn create(
        ptype: PipelineType,
        source_paths: []const ShaderSourcePath,
    ) Error!Pipeline {
        const m = max_pipeline_stages;
        if (source_paths.len > m) @panic(
            \\too many pipeline stages
            \\TODO: output default pipeline for corresponding ptype
        );
        _ = ptype;
        return try backend.createPipeline(&.{});
    }
    pub fn setProperty(self: Pipeline, name: []const u8, value: anytype) Error!void {
        const ptr: *const anyopaque = if (@typeInfo(@TypeOf(value)) == .ptr) value else &value;
        try backend.setPipelineProperty(self, name, ptr);
    }

    pub const max_pipeline_stages = 7;
};
pub const PipelineType = enum { surface, compute };
pub const ShaderSourcePath = struct {
    path: []const u8,
    entry_point: []const u8,
};

pub const Feature = enum {
    geometry_shaders,
    tessellation_shaders,
    sparse_binding,

    shader_float64,
    shader_int64,
    shader_int16,
};
pub const FeatureSet = huge.util.StructFromEnum(Feature, bool, false, .@"packed");

pub const ShaderModule = enum(Handle) { _ };
pub const ShaderStage = hgsl.Parser.ShaderStage;

pub const Buffer = enum(Handle) { _ };
pub const CommandBuffer = enum(Handle) { _ };
pub const Texture = enum(Handle) { _ };

pub const WindowContext = enum(Handle) { _ };
pub const Handle = u32;

pub const GApi = enum { vulkan, opengl, none };
const max_handle = ~@as(Handle, 0);
