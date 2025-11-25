const std = @import("std");
const huge = @import("../root.zig");
const util = huge.util;
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
pub fn reloadPipelines() Error!void {
    // if (huge.zigbuiltin.mode == .Debug)
    try backend.reloadPipelines();
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
    pub fn createPath(pipeline_source: PipelineSourcePath, params: PipelineParams) Error!Pipeline {
        var shader_modules: [max_pipeline_stages]ShaderModule = undefined;
        var index: usize = 0;
        while (pipeline_source.next(index)) |ps| {
            if (index + 1 >= max_pipeline_stages) return Error.ResourceCreationError;
            shader_modules[index] =
                try backend.createShaderModulePath(ps.path, ps.entry_point);
            index += 1;
        }
        return try backend.createPipeline(shader_modules[0..index], params);
    }
};
pub const PipelineParams = struct {
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
    // pub fn colorAttachment(self: RenderTarget) ?Texture
    // pub fn depthStencilAttachment(self: RenderTarget) ?Texture
    pub fn fromTextures(color: ?Texture, depth_stencil: ?Texture) Error!RenderTarget {
        if (color != null and depth_stencil != null) {
            const c, const ds = .{ color.?, depth_stencil.? };
            if (c.format().isDepthStencil()) return Error.WrongFormat;
            if (!ds.format().isDepthStencil()) return Error.WrongFormat;
            if (c.texType() != .@"2d") return Error.WrongTextureType;
            if (ds.texType() != .@"2d") return Error.WrongTextureType;
            if (@reduce(.Or, c.size() != ds.size())) return Error.NonMatchingRenderTargetAttachmentSizes;
        } else if (color) |c| {
            if (c.format().isDepthStencil()) return Error.WrongFormat;
            if (c.texType() != .@"2d") return Error.WrongTextureType;
        } else if (depth_stencil) |ds| {
            if (!ds.format().isDepthStencil()) return Error.WrongFormat;
            if (ds.texType() != .@"2d") return Error.WrongTextureType;
        }

        return try backend.createRenderTargetFromTextures(color, depth_stencil);
    }
    pub fn create(tex_size: math.uvec2, color_format: ?Format, depth_stencil_format: ?Format, params: TextureParams) Error!RenderTarget {
        if (color_format != null and color_format.?.isDepthStencil())
            return Error.WrongFormat;
        if (depth_stencil_format != null and !depth_stencil_format.?.isDepthStencil())
            return Error.WrongFormat;
        return try backend.createRenderTarget(tex_size, color_format, depth_stencil_format, params);
    }
    pub fn destroy(self: RenderTarget) void {
        backend.destroyRenderTarget(self);
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
pub const Texture = enum(Handle) {
    _,
    pub fn texType(self: Texture) TextureType {
        return backend.getTextureType(self);
    }
    pub fn size(self: Texture) math.uvec3 {
        return backend.getTextureSize(self);
    }
    pub fn format(self: Texture) Format {
        return backend.getTextureFormat(self);
    }
    pub fn renderTarget(self: Texture) Error!RenderTarget {
        return try backend.createRenderTargetFromTextures(
            if (self.format().isDepthStencil()) null else self,
            if (!self.format().isDepthStencil()) null else self,
        );
    }
    pub fn create(tex_size: math.uvec3, tex_format: Format, params: TextureParams) Error!Texture {
        return try backend.createTexture(tex_size, tex_format, params);
    }
    pub fn destroy(self: Texture) void {
        backend.destroyTexture(self);
    }
};
pub const TextureType = enum {
    @"1d",
    @"2d",
    @"3d",
    cube,
    @"1d_array",
    @"2d_array",
    cube_array,
};
pub const TextureParams = struct {
    filtering: SampleFiltering = null,
    mip_levels: u32 = 1,
    array_layers: u32 = 1,
    cubemap: bool = false,
    // samples: u8,
};
pub const SampleFiltering = ?struct {
    shrink: Filtering = .point,
    expand: Filtering = .point,
};
pub const Filtering = enum { point, linear };
pub const Format = enum {
    r8,
    r8_norm,
    rgba8,
    rgba8_norm,
    rgba4,

    r11_g11_b10,
    rgb10_a2,
    rgb5_a1,

    r32,
    rg32,
    rgb32,
    rgba32,

    //depth
    depth32,
    depth16,
    stencil8,
    depth16_stencil8,
    depth24_stencil8,
    depth32_stencil8,

    //block compressed
    bc1_rgb_norm,
    bc1_rgb_srgb,
    bc1_rgba_norm,
    bc1_rgba_srgb,

    bc2_norm,
    bc2_srgb,

    bc3_srgb,
    bc3_norm,

    bc4_norm,

    bc5_norm,

    bc6_sfloat,
    bc6_ufloat,

    bc7_norm,
    bc7_srgb,
    pub fn isDepthStencil(self: Format) bool {
        return switch (self) {
            .depth32,
            .depth16,
            .stencil8,
            .depth16_stencil8,
            .depth24_stencil8,
            .depth32_stencil8,
            => true,
            else => false,
        };
    }
};

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
    PipelineStageIOMismatch,

    NonMatchingRenderTargetAttachmentSizes,
    NonMatchingRenderAttachmentParams,
    WrongFormat,
    WrongTextureType,
    InvalidImageType,

    BufferMisuse,
    MemoryRemap,

    PresentationError,
    SynchronisationError,
};
