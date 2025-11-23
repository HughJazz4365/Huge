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
pub fn bindVertexBuffer(buffer: Buffer) Error!void {
    try backend.bindVertexBuffer(buffer);
}
pub fn bindIndexBuffer(buffer: Buffer, index_type: IndexType) Error!void {
    try backend.bindIndexBuffer(buffer, index_type);
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
pub inline fn coordinateSystem() math.CoordinateSystem {
    return backend.coordinate_system;
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

    indexed_vertex_offset: ?i32 = 0,
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
    pub const max_pipeline_stages = 3;
    pub fn setPropertiesStruct(self: Pipeline, values: anytype) Error!void {
        const tinfo = @typeInfo(@TypeOf(values));
        const T = if (tinfo == .pointer) tinfo.pointer.child else @TypeOf(values);
        if (@typeInfo(T) != .@"struct")
            @compileError("values must be a struct value or pointer");
        const ptr: *const T = &@as([*]const T, @ptrCast(if (tinfo == .pointer)
            values
        else
            &values))[0];
        inline for (@typeInfo(T).@"struct".fields) |sf|
            try self.setProperty(sf.name, @field(ptr, sf.name));
    }

    pub fn setProperty(self: Pipeline, name: []const u8, value: anytype) Error!void {
        const T = if (@typeInfo(@TypeOf(value)) == .pointer) @typeInfo(@TypeOf(value)).pointer.child else @TypeOf(value);
        const ptr: *const T = if (@typeInfo(@TypeOf(value)) == .pointer) value else &value;
        switch (T) {
            huge.Transform => try backend.pipelinePushConstant(self, name, 0, 0, &ptr.modelMat()),
            huge.Camera => try backend.pipelinePushConstant(self, name, 0, 0, &ptr.viewProjectionMat()),
            Buffer => try backend.setPipelineOpaqueUniform(self, name, 0, 0, .buffer, @intFromEnum(value)),
            else => try backend.pipelinePushConstant(self, name, 0, 0, ptr),
        }
    }
    pub fn createPath(pipeline_source: PipelineSourcePath, opt: PipelineOptions) Error!Pipeline {
        var shader_modules: [max_pipeline_stages]ShaderModule = undefined;
        var index: usize = 0;
        while (pipeline_source.next(index)) |ps| {
            if (index + 1 >= max_pipeline_stages) return Error.ResourceCreationError;
            shader_modules[index] =
                try backend.createShaderModulePath(ps.path, ps.entry_point);
            index += 1;
        }
        return try backend.createPipeline(shader_modules[0..index], opt);
    }
};
pub const PipelineOptions = struct {
    //vertex
    winding_order: WindingOrder = .clockwise,
    cull: Cull = .none,
    primitive: PrimitiveTopology = .triangle,
    // polygon
    // .depth_clamp_enable = @intFromBool(false),
    // .rasterizer_discard_enable = @intFromBool(false),
    // .polygon_mode = .fill,
    // .line_width = 1,
    // .cull_mode = .{ .back_bit = true },
    // // .cull_mode = .{},
    // .front_face = .clockwise,
    // .depth_bias_enable = @intFromBool(false),
    // .depth_bias_constant_factor = 0,
    // .depth_bias_clamp = 0,
    // .depth_bias_slope_factor = 0,
};
pub const PrimitiveTopology = enum {
    triangle,
    triangle_strip,
    triangle_fan,

    line,
    line_strip,

    point,
};
pub const Cull = enum { none, back, front, both };
pub const WindingOrder = enum { clockwise, counter_clockwise };

pub const PipelineType = enum { surface, compute };
pub const PipelineSourcePath = union(PipelineType) {
    surface: SurfacePipelineSourcePath,
    compute: ShaderSourcePath,
    pub fn next(self: PipelineSourcePath, index: usize) ?ShaderSourcePath {
        return switch (self) {
            .surface => |surface| blk: {
                var non_null_count: usize = 0;
                const slice: []const ShaderSourcePath =
                    &.{ surface.tesselation, surface.vertex, surface.geometry, surface.fragment };
                break :blk for (slice) |s| {
                    if (s.isNull()) continue;
                    if (index == non_null_count) break s;

                    non_null_count += 1;
                } else null;
            },
            .compute => |compute| if (index == 0) compute else null,
        };
    }
};
pub const SurfacePipelineSourcePath = struct {
    tesselation: ShaderSourcePath = ShaderSourcePath._null,
    vertex: ShaderSourcePath,
    geometry: ShaderSourcePath = ShaderSourcePath._null,
    fragment: ShaderSourcePath,
};
pub const ShaderSourcePath = struct {
    path: []const u8,
    entry_point: []const u8,
    pub const _null: ShaderSourcePath = .{ .path = "", .entry_point = "" };
    pub fn isNull(self: ShaderSourcePath) bool {
        return self.path.len == 0;
    }
};

pub const OpaqueType = hgsl.OpaqueType;
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
pub const RenderTarget = enum(Handle) {
    _,
    pub fn size(self: RenderTarget) math.uvec2 {
        return backend.renderTargetSize(self);
    }
};

pub const Buffer = enum(Handle) {
    _,
    pub fn loadSlice(self: Buffer, T: type, slice: []const T, offset: usize) Error!void {
        try self.loadBytes(@ptrCast(@alignCast(slice)), offset);
    }
    pub fn loadBytes(self: Buffer, bytes: []const u8, offset: usize) Error!void {
        try backend.loadBuffer(self, bytes, offset);
    }
    pub fn map(self: Buffer, bytes: usize, offset: usize) Error![]u8 {
        return try backend.mapBuffer(self, bytes, offset);
    }
    pub fn unmap(self: Buffer) void {
        backend.unmapBuffer(self);
    }
    pub const bindVertex = bindVertexBuffer;
    pub const bindIndex = bindIndexBuffer;
    pub fn create(size: usize, usage: BufferUsage) Error!Buffer {
        return try backend.createBuffer(size, usage);
    }
    pub fn destroy(self: Buffer) void {
        backend.destroyBuffer(self);
    }
};
pub const IndexType = enum { u32, u16, u8 };
pub const BufferUsage = enum { uniform, vertex, index, storage };
pub const Texture = enum(Handle) { _ };

pub const ShaderModule = enum(Handle) { _ };
pub const ShaderStage = hgsl.Parser.ShaderStage;

pub const WindowContext = enum(Handle) {
    _,
    pub fn update(self: WindowContext) void {
        backend.updateWindowContext(self);
    }
};
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
    ShaderEntryPointNotFound,
    ShaderPushConstantOutOfBounds,

    BufferMisuse,
    MemoryRemap,

    PresentationError,
    SynchronisationError,
};
