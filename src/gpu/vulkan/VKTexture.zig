const std = @import("std");
const huge = @import("../../root.zig");
const util = huge.util;
const gpu = huge.gpu;
const math = huge.math;
const frmt = @import("format.zig");
const VKTexture = @This();

const vk = @import("vk.zig");
const b = @import("vulkanBackend.zig");

image: vk.Image = .null_handle,
view: vk.ImageView = .null_handle,
sampler: vk.Sampler = .null_handle,

memory_allocation: u32 = b.u32m,
memory_offset: u64 = 0,

dimensions: TextureDimensions = undefined,
format: Format = .rgba8_norm,
sampling_options: ?SamplingOptions = null,

is_attachment: bool = false,
vk_format: vk.Format = .undefined,

staging_buffer: ?gpu.Buffer = null,

const max_textures_per_allocation = 16;
const mt = max_textures_per_allocation;

pub fn samplingLayout(self: VKTexture) vk.ImageLayout {
    _ = self;
    return .shader_read_only_optimal;

    // general = 1,
    // shader_read_only_optimal = 5,
    // depth_read_only_optimal = 1000241001,
    // depth_attachment_stencil_read_only_optimal = 1000117001,
    // read_only_optimal = 1000314000,
    // attachment_optimal = 1000314001,
    // stencil_read_only_optimal = 1000241003,
    // rendering_local_read = 1000232000,

}
// pub fn loadBytes(self: *VKTexture) Error!void {
//     try recreateIfNeeded(@ptrCast(self), .{ .transfer = true });
//     if (self.staging_buffer == null) {
//         const size = @reduce(.Add, self.size) * frmt.formatSize(self.vk_format);
//         self.staging_buffer = try (try VKBuffer.create(size, .storage)).append();
//     }
//     std.debug.print("STAGINGBUFFER: {}\n", .{self.staging_buffer});
// }
// pub fn createStagingBuffer(self: *VKTexture) Buffer {
//     _ = self;
// }
pub fn recreateAsAttachment(textures: []VKTexture) Error!bool {
    if (textures.len == 0) return false;
    var recreated = false;
    if (textures.len > mt)
        recreated = try recreateAsAttachment(textures[mt..]);

    var params: [mt]TextureCreateParams = undefined;
    var offset: usize = 0;
    var count: usize = 0;
    for (textures, 0..) |t, i| if (t.is_attachment) {
        if (count == 0) {
            offset += 1;
        } else {
            recreated = true;
            try createSlice(
                textures[offset..i],
                params[offset..i],
            );
            offset = i;
            count = 0;
        }
    } else {
        count += 1;
        params[i] = .{
            .dimensions = t.dimensions,
            .format = t.format,
            .sampling_options = t.sampling_options,
            .is_attachment = true,
            .memory_allocation = t.memory_allocation,
            .memory_offset = t.memory_offset,
        };
    };
    if (count > 0) try createSlice(textures[offset..], params[offset..]);

    return recreated | (count > 0);
}

pub fn create(
    dimensions: gpu.TextureDimensions,
    format: gpu.Format,
    sampling_options: ?gpu.SamplingOptions,
    is_attachment: bool,
) Error!VKTexture {
    var t: VKTexture = undefined;
    try createSlice(@ptrCast(&t), &.{.{
        .dimensions = dimensions,
        .format = format,
        .sampling_options = sampling_options,
        .is_attachment = is_attachment,
    }});
    return t;
}

pub fn createSlice(
    output: []VKTexture,
    params: []const TextureCreateParams,
) Error!void {
    if (output.len == 0 or params.len == 0) return;
    if (output.len > mt) //only creating 'max_textures_per_allocation' at a time
        try createSlice(
            output[mt..],
            params[@min(mt, params.len - 1)..],
        );

    const tex = output[0..@min(output.len, mt)];
    for (tex, 0..) |*t, i| {
        const p = params[@min(i, params.len - 1)];
        const size = p.dimensions.size();
        if (@reduce(.Or, @as(math.uvec4, @splat(0)) == size))
            return Error.InvalidTextureDimensions;
        t.* = .{
            .format = p.format,
            .dimensions = p.dimensions,
            .sampling_options = p.sampling_options,
            .is_attachment = p.is_attachment,
        };

        const format_usage: b.FormatUsage = .{
            .sampled = if (p.sampling_options) |_| true else false,
            .sampled_linear = if (p.sampling_options) |so|
                so.shrink == .linear or so.expand == .linear
            else
                false,

            .color_attachment = !p.format.isDepthStencil() and p.is_attachment,
            .depth_stencil_attachment = p.format.isDepthStencil() and p.is_attachment,

            .blit_src = true,
            .blit_dst = true,
            .transfer_src = true,
            .transfer_dst = true,
        };

        var linear_tiling = false;
        t.vk_format = b.getVulkanFormat(p.format, format_usage, .image_optimal);
        if (t.vk_format == .undefined) {
            linear_tiling = true;
            t.vk_format = b.getVulkanFormat(p.format, format_usage, .image_linear);
        }
        std.debug.print("VKFORMAT:{} => {}\n", .{ t.format, t.vk_format });
        if (t.vk_format == .undefined) continue;

        t.image = b.device.createImage(&.{
            .image_type = switch (p.dimensions) {
                .@"1d", .@"1d_array" => .@"1d",
                .@"2d", .@"2d_array", .cube, .cube_array => .@"2d",
                .@"3d" => .@"3d",
            },
            .flags = .{
                .cube_compatible_bit = t.dimensions.isCube(),
            },
            .format = t.vk_format,
            .extent = .{
                .width = size[0],
                .height = size[1],
                .depth = size[2],
            },
            .mip_levels = if (t.sampling_options) |so| so.mip_levels else 1,
            .array_layers = size[3],
            .samples = .{ .@"1_bit" = true },
            .tiling = if (linear_tiling) .linear else .optimal,
            .usage = format_usage.toImageUsage(),
            .initial_layout = .undefined,
            .sharing_mode = .exclusive,
            // sharing_mode: SharingMode,
            // queue_family_index_count: u32 = 0,
            // p_queue_family_indices: ?[*]const u32 = null,
        }, b.vka) catch return Error.ResourceCreationError;
        if (p.sampling_options) |so| {
            const address_mode: vk.SamplerAddressMode = switch (so.tiling) {
                .repeat => .repeat,
                .mirror => .mirrored_repeat,
                .clamp_to_edge => .clamp_to_edge,
                .clamp_to_border => .clamp_to_border,
                .mirror_clamp_to_edge => .mirror_clamp_to_edge,
            };

            t.sampler = b.device.createSampler(&.{
                .mag_filter = if (so.expand == .point)
                    .nearest
                else
                    .linear,
                .min_filter = if (so.shrink == .point)
                    .nearest
                else
                    .linear,
                .mipmap_mode = .nearest, //: vk.SamplerMipmapMode,
                .address_mode_u = address_mode,
                .address_mode_v = address_mode,
                .address_mode_w = address_mode,
                .mip_lod_bias = 0,
                .anisotropy_enable = .false,
                .max_anisotropy = 1,
                .compare_enable = .true,
                .compare_op = .never,
                .min_lod = 0,
                .max_lod = 1,
                .border_color = .float_transparent_black,
                .unnormalized_coordinates = .false,
            }, b.vka) catch return Error.ResourceCreationError;
        }
    }
    var memory_allocations: [mt]struct {
        req: vk.MemoryRequirements,
        allocation: u32,
    } = undefined;
    var index_map: [mt]struct {
        index: usize,
        offset: u64 = 0,
    } = undefined;

    var mem_req_index: usize = 0;
    for (tex, 0..) |*t, i| {
        if (t.image == .null_handle) continue;
        const p = params[@min(i, params.len - 1)];
        if (~p.memory_allocation != 0) {
            index_map[i] = .{ .index = p.memory_allocation, .offset = p.memory_offset };
            continue;
        }

        const req = b.device.getImageMemoryRequirements(t.image);
        for (memory_allocations[0..mem_req_index], 0..) |*ma, j| {
            if (req.memory_type_bits == ma.req.memory_type_bits and req.alignment == ma.req.alignment) {
                const offset = util.rut(u64, ma.req.size, ma.req.alignment);
                ma.req.size += req.size + (offset - ma.req.size);
                index_map[i] = .{ .index = j, .offset = offset };
                break;
            }
        } else {
            memory_allocations[mem_req_index].req = req;
            index_map[i] = .{ .index = mem_req_index };
            mem_req_index += 1;
        }
    }
    for (memory_allocations[0..mem_req_index]) |*ma|
        ma.allocation = try b.allocateDeviceMemory(ma.req, .{});

    for (tex, 0..) |*t, i| {
        if (t.image == .null_handle) continue;
        t.memory_allocation = if (~params[@min(i, params.len - 1)].memory_allocation == 0)
            memory_allocations[index_map[i].index].allocation
        else
            @intCast(index_map[i].index);
        t.memory_offset = index_map[i].offset;
        b.device.bindImageMemory(t.image, b.getMemoryReference(t.memory_allocation), index_map[i].offset) catch
            return Error.ResourceCreationError;
        const mask = frmt.mask(t.vk_format);
        t.view = b.device.createImageView(&.{
            .image = t.image,
            .view_type = switch (t.dimensions) {
                .@"1d" => .@"1d",
                .@"2d" => .@"2d",
                .@"3d" => .@"3d",
                .cube => .cube,
                .@"1d_array" => .@"1d_array",
                .@"2d_array" => .@"2d_array",
                .cube_array => .cube_array,
            },
            .format = t.vk_format,
            .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
            .subresource_range = .{
                .aspect_mask = .{
                    .color_bit = mask.color,
                    .depth_bit = mask.depth,
                    .stencil_bit = mask.stencil,
                },
                .layer_count = t.dimensions.size()[3],
                .base_array_layer = 0,
                .level_count = if (t.sampling_options) |so| so.mip_levels else 1,
                .base_mip_level = 0,
            },
        }, b.vka) catch
            return Error.ResourceCreationError;
    }
}
pub fn destroy(self: *VKTexture) void {
    self.destroyHandles();
    if (self.staging_buffer) |sb|
        b.VKBuffer.get(sb).destroy();
    self.staging_buffer = null;
    self.sampler = .null_handle;
    if (~self.memory_allocation != 0)
        b.removeMemoryReference(self.memory_allocation);
    self.memory_allocation = ~@as(u32, 0);
    self.* = .{};
}
fn destroyHandles(self: *VKTexture) void {
    b.device.destroyImage(self.image, b.vka);
    self.image = .null_handle;
    b.device.destroyImageView(self.view, b.vka);
    self.view = .null_handle;
    b.device.destroySampler(self.sampler, b.vka);
    self.sampler = .null_handle;
}
pub fn append(self: VKTexture) Error!gpu.Texture {
    const handle: gpu.Texture = @enumFromInt(@as(gpu.Handle, @intCast(b.texture_list.items.len)));
    try b.texture_list.append(b.arena.allocator(), self);
    return handle;
}
pub fn get(handle: gpu.Texture) *VKTexture {
    return &b.texture_list.items[@intFromEnum(handle)];
}
pub const TextureCreateParams = struct {
    dimensions: gpu.TextureDimensions = .{ .@"2d" = .{ 2, 2 } },
    format: Format = .rgba8_norm,
    sampling_options: ?gpu.SamplingOptions = null,
    is_attachment: bool = false,
    memory_allocation: u32 = b.u32m,
    memory_offset: u64 = 0,
};
const Error = gpu.Error;
const Format = gpu.Format;
const TextureDimensions = gpu.TextureDimensions;
const SamplingOptions = gpu.SamplingOptions;
