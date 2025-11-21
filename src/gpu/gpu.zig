const std = @import("std");
const huge = @import("../root.zig");
const math = huge.math;
pub const hgsl = @import("hgsl");
pub const Backend = @import("GpuBackend.zig");

var backend: Backend = undefined; //default to software renderer??

//=======|methods|=======

pub fn draw(pipeline: Pipeline, params: DrawParams) Error!void {
    try backend.draw(pipeline, params);
}
pub fn clear(value: ClearValue) Error!void {
    try backend.clear(value);
}
pub fn beginRendering(render_target: RenderTarget, clear_value: ClearValue) Error!void {
    try backend.beginRendering(render_target, clear_value);
}
pub fn endRendering() Error!void {
    try backend.endRendering();
}
pub fn getWindowRenderTarget(window: huge.Window) RenderTarget {
    return backend.getWindowRenderTarget(window);
}
pub fn createWindowContext(window: huge.Window) Error!WindowContext {
    return try backend.createWindowContext(window);
}
pub fn destroyWindowContext(window_context: WindowContext) void {
    backend.destroyWindowContext(window_context);
}
pub inline fn api() GApi {
    return backend.api;
}
pub inline fn apiVersion() huge.Version {
    return backend.api_version;
}

//====|initialization|===

pub fn init() Error!void {
    backend = @import("vulkan/vulkanBackend.zig").initBackend() catch
        return Error.BackendInitializationFailure;
}
pub fn deinit() void {
    backend.deinit();
}

//=======================
pub const DrawParams = struct {
    mode: DrawMode = .array,
    count: u32,
    offset: u32 = 0,

    instance_count: u32 = 1,
    instance_offset: u32 = 0,

    indexed_vertex_offset: i32 = 0,
};
pub const DrawMode = enum {
    array,
    indexed,
};
pub const ClearValue = struct {
    color: ?math.vec4 = null,
};
pub const Pipeline = enum(u32) {
    _,
    pub fn createPath(pipeline_source: PipelineSourcePath) Error!Pipeline {
        var shader_modules: [max_pipeline_stages]ShaderModule = undefined;
        const slice = pipeline_source.slice();
        for (shader_modules[0..slice.len], slice) |*m, source|
            m.* = try backend.createShaderModulePath(source.path, source.entry_point);

        return try backend.createPipeline(shader_modules[0..slice.len]);
    }
    pub fn setProperty(self: Pipeline, name: []const u8, value: anytype) Error!void {
        const ptr: *const anyopaque = if (@typeInfo(@TypeOf(value)) == .ptr) value else &value;
        try backend.setPipelineProperty(self, name, ptr);
    }
    pub const max_pipeline_stages = 3;
};
pub const OpaqueType = hgsl.OpaqueType;
pub const PipelineType = enum { surface, compute };
pub const PipelineSourcePath = union(PipelineType) {
    surface: SurfacePipelineSourcePath,
    compute: ShaderSourcePath,
    pub fn slice(self: PipelineSourcePath) []const ShaderSourcePath {
        return switch (self) {
            .surface => |surface| if (surface.geometry) |geometry|
                &.{ surface.vertex, surface.fragment, geometry }
            else
                &.{ surface.vertex, surface.fragment },
            .compute => |compute| &.{compute},
        };
    }
};
pub const SurfacePipelineSourcePath = struct {
    vertex: ShaderSourcePath,
    fragment: ShaderSourcePath,
    geometry: ?ShaderSourcePath = null,
};
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

//handle types
pub const RenderTarget = enum(Handle) { _ };

pub const Buffer = enum(Handle) { _ };
pub const Texture = enum(Handle) { _ };

pub const ShaderModule = enum(Handle) { _ };
pub const ShaderStage = hgsl.Parser.ShaderStage;

pub const WindowContext = enum(Handle) { _ };
pub const Handle = u32;

pub const GApi = enum { vulkan, opengl, none };
const max_handle = ~@as(Handle, 0);

pub const Error = error{
    Unknown,

    OutOfMemory,
    ResourceCreationError,
    NullAccess,

    WindowContextCreationError,
    BackendInitializationFailure,

    ShaderCompilationError,

    PresentationError,
    SynchronisationError,
};
