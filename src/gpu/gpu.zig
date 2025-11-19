const std = @import("std");
const huge = @import("../root.zig");
const math = huge.math;
pub const hgsl = @import("hgsl");
pub const Backend = @import("GpuBackend.zig");

var backend: Backend = undefined; //default to software renderer??

//=======|methods|=======

pub fn draw(
    command_buffer: CommandBuffer,
    render_target: RenderTarget,
    pipeline: Pipeline,
    params: DrawParams,
) Error!void {
    try backend.draw(command_buffer, render_target, pipeline, params);
}
pub fn clear(
    command_buffer: CommandBuffer,
    render_target: RenderTarget,
    value: ClearValue,
) Error!void {
    try backend.clear(command_buffer, render_target, value);
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
pub fn present(window: huge.Window) Error!void {
    try backend.present(window);
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
        _ = pipeline_source;
        return try backend.createPipeline(&.{});
    }
    pub fn setProperty(self: Pipeline, name: []const u8, value: anytype) Error!void {
        const ptr: *const anyopaque = if (@typeInfo(@TypeOf(value)) == .ptr) value else &value;
        try backend.setPipelineProperty(self, name, ptr);
    }

    pub const max_pipeline_stages = 7;
};
pub const OpaqueType = hgsl.OpaqueType;
pub const PipelineType = enum { surface, compute };
pub const PipelineSourcePath = union(PipelineType) {
    surface: SurfacePipelineSourcePath,
    compute: ShaderSourcePath,
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
pub const CommandBuffer = enum(Handle) { _ };
pub const Texture = enum(Handle) { _ };

pub const ShaderModule = enum(Handle) { _ };
pub const ShaderStage = hgsl.Parser.ShaderStage;

pub const WindowContext = enum(Handle) { _ };
pub const Handle = u32;

pub const GApi = enum { vulkan, opengl, none };
const max_handle = ~@as(Handle, 0);

pub const Error = error{
    OutOfMemory,
    ResourceCreationError,

    WindowContextCreationError,
    BackendInitializationFailure,

    ShaderCompilationError,

    PresentationError,

    CommadBufferRecordingError,
    CommadBufferSubmitionError,
};
