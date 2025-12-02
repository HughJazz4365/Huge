const std = @import("std");
const huge = @import("../root.zig");
const util = huge.util;
const math = huge.math;
pub const hgsl = @import("hgsl");
pub const Backend = @import("GpuBackend.zig");

pub const b = @import("vulkan/vulkanBackend.zig");
// var backend: Backend = undefined; //default to software renderer??

//2x2 image: |purple| green|
//           |red   | blue |
pub const default_image = [_]u8{
    156, 39,  176, 255,
    0,   244, 92,  255,
    255, 0,   0,   255,
    3,   81,  244, 255,
};

//=======|methods|=======

//draw commands(can ideally be calls from a separate threaad?)
pub fn draw(pipeline: Pipeline, params: DrawParams) void {
    b.draw(pipeline, params);
}
pub fn clear(value: ClearValue) void {
    b.clear(value);
}
pub fn bindVertexBuffer(buffer: Buffer) void {
    b.bindVertexBuffer(buffer);
}
pub fn bindIndexBuffer(buffer: Buffer, index_type: IndexType) void {
    b.bindIndexBuffer(buffer, index_type);
}
//draw control flow
pub fn beginRendering(render_target: RenderTarget, clear_value: ClearValue) Error!void {
    try b.beginRendering(render_target, clear_value);
}
pub fn endRendering() Error!void {
    try b.endRendering();
}
//resource/state management
pub fn getWindowRenderTarget(window: huge.Window) RenderTarget {
    return b.getWindowRenderTarget(window);
}
pub fn createWindowContext(window: huge.Window) Error!WindowContext {
    return try b.createWindowContext(window);
}
pub fn destroyWindowContext(window_context: WindowContext) void {
    b.destroyWindowContext(window_context);
}
pub fn reloadPipelines() Error!void {
    if (huge.zigbuiltin.mode == .Debug)
        try b.reloadPipelines();
}
pub inline fn coordinateSystem() math.CoordinateSystem {
    return .right_handed;
    // return backend.coordinate_system;
}
pub inline fn api() GApi {
    return .vulkan;
    // return backend.api;
}
pub inline fn apiVersion() huge.Version {
    return .{ .major = 1, .minor = 4 };
    // return backend.api_version;
}

//====|initialization|===

pub fn init() Error!void {
    _ = @import("vulkan/vulkanBackend.zig").initBackend() catch
        return Error.BackendInitializationFailure;
}
pub fn deinit() void {
    b.deinit();
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
    pub fn setPropertiesStruct(self: Pipeline, values: anytype) void {
        const tinfo = @typeInfo(@TypeOf(values));
        const T = if (tinfo == .pointer) tinfo.pointer.child else @TypeOf(values);
        if (@typeInfo(T) != .@"struct")
            @compileError("values must be a struct value or pointer");
        const ptr: *const T = &@as([*]const T, @ptrCast(if (tinfo == .pointer)
            values
        else
            &values))[0];
        inline for (@typeInfo(T).@"struct".fields) |sf|
            self.setProperty(sf.name, @field(ptr, sf.name));
    }

    pub fn setProperty(self: Pipeline, name: []const u8, value: anytype) void {
        const T = if (@typeInfo(@TypeOf(value)) == .pointer) @typeInfo(@TypeOf(value)).pointer.child else @TypeOf(value);
        const ptr: *const T = if (@typeInfo(@TypeOf(value)) == .pointer) value else &value;
        switch (T) {
            huge.Transform => b.pipelinePushConstant(self, name, 0, 0, &ptr.modelMat()),
            huge.Camera => b.pipelinePushConstant(self, name, 0, 0, &ptr.viewProjectionMat()),
            Buffer => b.pipelineSetOpaqueUniform(self, name, 0, 0, .buffer, @intFromEnum(value)),
            Texture => b.pipelineSetOpaqueUniform(self, name, 0, 0, .texture, @intFromEnum(value)),
            else => b.pipelinePushConstant(self, name, 0, 0, ptr),
        }
    }
    pub fn createPath(pipeline_source: PipelineSourcePath, params: PipelineParams) Error!Pipeline {
        var shader_modules: [max_pipeline_stages]ShaderModule = undefined;
        var index: usize = 0;
        while (pipeline_source.next(index)) |ps| {
            if (index + 1 >= max_pipeline_stages) return Error.ResourceCreationError;
            shader_modules[index] =
                try b.createShaderModulePath(ps.path, ps.entry_point);
            index += 1;
        }
        return try b.createPipeline(shader_modules[0..index], params);
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

pub const OpaqueType = enum { buffer, texture };
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
        return b.renderTargetSize(self);
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

        return try b.createRenderTargetFromTextures(color, depth_stencil);
    }
    pub fn create(tex_size: math.uvec2, color_format: ?Format, depth_stencil_format: ?Format, sampling_options: ?SamplingOptions) Error!RenderTarget {
        if (color_format != null and color_format.?.isDepthStencil())
            return Error.WrongFormat;
        if (depth_stencil_format != null and !depth_stencil_format.?.isDepthStencil())
            return Error.WrongFormat;
        return try b.createRenderTarget(tex_size, color_format, depth_stencil_format, sampling_options);
    }
    pub fn destroy(self: RenderTarget) void {
        b.destroyRenderTarget(self);
    }
};

pub const Buffer = enum(Handle) {
    _,
    pub fn loadSlice(self: Buffer, T: type, slice: []const T, offset: usize) Error!void {
        try self.loadBytes(@ptrCast(@alignCast(slice)), offset);
    }
    pub fn loadBytes(self: Buffer, bytes: []const u8, offset: usize) Error!void {
        try b.loadBuffer(self, bytes, offset);
    }
    pub fn map(self: Buffer, bytes: usize, offset: usize) Error![]u8 {
        return try b.mapBuffer(self, bytes, offset);
    }
    pub fn unmap(self: Buffer) void {
        b.unmapBuffer(self);
    }
    pub fn usage(self: Buffer) BufferUsage {
        return b.getBufferUsage(self);
    }
    pub const bindVertex = bindVertexBuffer;
    pub const bindIndex = bindIndexBuffer;
    pub fn create(size: usize, buf_usage: BufferUsage) Error!Buffer {
        return try b.createBuffer(size, buf_usage);
    }
    pub fn destroy(self: Buffer) void {
        b.destroyBuffer(self);
    }
};
pub const IndexType = enum { u32, u16, u8 };
pub const BufferUsage = enum { uniform, vertex, index, storage, transfer };
pub const Texture = enum(Handle) {
    _,
    pub fn dimensions(self: Texture) TextureDimensions {
        return b.getTextureDimensions(self);
    }
    pub fn format(self: Texture) Format {
        return b.getTextureFormat(self);
    }
    pub fn renderTarget(self: Texture) Error!RenderTarget {
        return try b.createRenderTargetFromTextures(
            if (self.format().isDepthStencil()) null else self,
            if (!self.format().isDepthStencil()) null else self,
        );
    }
    pub fn create(
        tex_dimensions: TextureDimensions,
        tex_format: Format,
        opt: ?SamplingOptions,
    ) Error!Texture {
        return try b.createTexture(tex_dimensions, tex_format, opt);
    }
    pub fn destroy(self: Texture) void {
        b.destroyTexture(self);
    }
};

pub const TextureDimensions = union(TextureType) {
    @"1d": u32,
    @"2d": math.uvec2,
    @"3d": math.uvec3,
    cube: math.uvec2,
    @"1d_array": ArrayDimensionsType(u32),
    @"2d_array": ArrayDimensionsType(math.uvec2),
    cube_array: ArrayDimensionsType(math.uvec2),
    fn ArrayDimensionsType(Size: type) type {
        return struct { size: Size, array_layers: u32 };
    }
    pub fn isCube(self: TextureDimensions) bool {
        return self == .cube or self == .cube_array;
    }
    pub fn size(self: TextureDimensions) math.uvec4 {
        return switch (self) {
            .@"1d" => |d| .{ d, 1, 1, 1 },
            .@"2d" => |d| math.swizzle(d, .xy11),
            .@"3d" => |d| math.swizzle(d, .xyz1),
            .cube => |d| math.swizzle(d, .xy11),
            .@"1d_array" => |d| .{ d.size, 1, 1, d.array_layers },
            .@"2d_array" => |d| .{ d.size[0], d.size[1], 1, d.array_layers },
            .cube_array => |d| .{ d.size[0], d.size[1], 1, d.array_layers },
        };
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
pub const SamplingOptions = struct {
    shrink: Filtering = .point,
    expand: Filtering = .point,
    tiling: Tiling = .clamp_to_border,
    mip_levels: u32 = 1,
    // samples: u8,
};
pub const CompareOp = struct {
    .never,
    .less,
    .equal,
    .less_or_equal,
    .greater,
    .not_equal,
    .greater_or_equal,
    .always,
};
pub const Tiling = enum {
    repeat,
    mirror,
    clamp_to_edge,
    clamp_to_border,
    mirror_clamp_to_edge,
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
        b.updateWindowContext(self);
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
    PipelineDescriptorCollision,

    NonMatchingRenderTargetAttachmentSizes,
    NonMatchingRenderAttachmentParams,
    WrongFormat,
    WrongTextureType,
    InvalidTextureDimensions,

    MemoryRemap,

    PresentationError,
    SynchronisationError,
};
