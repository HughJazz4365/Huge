const std = @import("std");
const vk = @import("vk.zig");
const vulkan = @import("vulkan.zig");
const huge = @import("../../root.zig");
const math = huge.math;
const util = huge.util;

const VKTexture = @This();

image: vk.Image = .null_handle,
view: vk.ImageView = .null_handle,
sampler: vk.Sampler = .null_handle,

allocation: vulkan.DeviceAllocation = undefined,
size: math.uvec4 = @splat(0),

vk_format: vk.Format = .undefined,

descriptor_id: vulkan.DescriptorID = .null,

pub fn load(self: *VKTexture, bytes: []const u8) Error!void {
    var staging_buffer = try vulkan.getImageStagingBuffer(self.size, self.vk_format);
    try staging_buffer.loadBytes(bytes, 0);
    const cmd = try vulkan.allocateCommandBufferHandleCount(.main, .transfer, 1);

    vulkan.device.beginCommandBuffer(cmd.handles[0], &.{}) catch |err| return vulkan.wrapMemoryErrors(err);

    const mask = vulkan.frmt.mask(self.vk_format);
    vulkan.device.cmdPipelineBarrier2(cmd.handles[0], &.{
        // vk.DependencyFlags = .{},
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &.{.{
            .src_stage_mask = .{},
            .dst_stage_mask = .{ .all_transfer_bit = true },

            .src_access_mask = .{},
            .dst_access_mask = .{ .transfer_write_bit = true },

            .old_layout = .undefined,
            .new_layout = .transfer_dst_optimal,

            .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
            .image = self.image,
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = mask.color, .depth_bit = mask.depth, .stencil_bit = mask.stencil },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }},
    });
    vulkan.device.cmdCopyBufferToImage(
        cmd.handles[0],
        staging_buffer.handle,
        self.image,
        .transfer_dst_optimal,
        1,
        &.{.{
            .buffer_offset = 0,
            .buffer_row_length = 0,
            .buffer_image_height = 0,

            .image_subresource = .{
                .aspect_mask = .{ .color_bit = mask.color, .depth_bit = mask.depth, .stencil_bit = mask.stencil },
                .mip_level = 0,
                .base_array_layer = 0,
                .layer_count = self.size[3],
            },
            .image_offset = .{ .x = 0, .y = 0, .z = 0 },
            .image_extent = .{ .width = self.size[0], .height = self.size[1], .depth = self.size[2] },
        }},
    );
    vulkan.device.endCommandBuffer(cmd.handles[0]) catch |err| return vulkan.wrapMemoryErrors(err);
    vulkan.device.queueSubmit2(vulkan.queue(.transfer), 1, &.{.{
        .command_buffer_info_count = 1,
        .p_command_buffer_infos = &.{
            .{ .command_buffer = cmd.handles[0], .device_mask = 0 },
        },
    }}, .null_handle) catch |err| return vulkan.wrapMemoryErrors(err);
    vulkan.device.queueWaitIdle(vulkan.queue(.transfer)) catch |err|
        return vulkan.wrapMemoryErrors(err);
}

pub fn create(
    dimensions: TextureDimensions,
    format: Format,
    sampling_options: ?TextureSamplingParameters,
    usage: TextureUsage,
) Error!VKTexture {
    const size = dimensions.size();
    const texture_type = std.meta.activeTag(dimensions);
    if (@reduce(.Or, @as(math.uvec4, @splat(0)) == size))
        return Error.InvalidTextureDimensions;
    if (sampling_options != null and sampling_options.?.mip_levels == 0)
        return Error.InvalidTextureDimensions;

    const vk_format = vulkan.getVulkanFormat(format, .{
        .storage_image_bit = usage.storage,
        .sampled_image_bit = sampling_options != null,
        .sampled_image_filter_linear_bit = if (sampling_options) |so| so.shrink == .linear or so.expand == .linear else false,
        // sampled_image_filter_cubic_bit_ext: bool = false,

        .color_attachment_bit = usage.attachment and !format.isDepthStencil(),
        .color_attachment_blend_bit = usage.attachment and !format.isDepthStencil() and usage.blend,
        .depth_stencil_attachment_bit = usage.attachment and format.isDepthStencil(),

        .blit_dst_bit = usage.blit_dst,
        .blit_src_bit = usage.blit_src,
        .transfer_dst_bit = usage.transfer_dst,
        .transfer_src_bit = usage.transfer_src,
    }, .image_optimal, .b8g8r8a8_unorm);

    std.debug.print("VKFORMAT:{} => {}\n", .{ format, vk_format });

    const image = vulkan.device.createImage(&.{
        .flags = .{
            // mutable_format_bit: bool = false,
            .cube_compatible_bit = texture_type == .cube or texture_type == .cube_array,
            .@"2d_array_compatible_bit" = texture_type == .@"2d_array",
        },
        .image_type = switch (texture_type) {
            .@"1d", .@"1d_array" => .@"1d",
            .@"3d" => .@"3d",
            else => .@"2d",
        },
        .format = vk_format,
        .extent = .{
            .width = size[0],
            .height = size[1],
            .depth = size[2],
        },
        .mip_levels = if (sampling_options) |so| so.mip_levels else 1,
        .array_layers = size[3],
        .samples = .{ .@"1_bit" = true },
        .tiling = .optimal,
        .usage = getImageUsageFlags(usage, sampling_options != null, format),
        .sharing_mode = .exclusive,
        // queue_family_index_count: u32 = 0,
        // p_queue_family_indices: ?[*]const u32 = null,
        .initial_layout = .undefined,
    }, vulkan.vka) catch |err| return vulkan.wrapMemoryErrors(err);

    const sampler = if (sampling_options) |so|
        vulkan.device.createSampler(&.{
            .min_filter = if (so.shrink == .point) .nearest else .linear,
            .mag_filter = if (so.expand == .point) .nearest else .linear,
            .mipmap_mode = .linear,
            .address_mode_u = getSamplerAddressMode(so.tiling[0]),
            .address_mode_v = getSamplerAddressMode(so.tiling[1]),
            .address_mode_w = getSamplerAddressMode(so.tiling[2]),
            .mip_lod_bias = 0,
            .anisotropy_enable = .false,
            .max_anisotropy = 1,
            .compare_enable = @enumFromInt(@intFromBool(usage.attachment and format.isDepthStencil())),
            .compare_op = .never,
            .min_lod = 0,
            .max_lod = 1,
            .border_color = .float_transparent_black,
            .unnormalized_coordinates = .false,
        }, vulkan.vka) catch |err| return vulkan.wrapMemoryErrors(err)
    else
        .null_handle;
    const memory_requirements = vulkan.device.getImageMemoryRequirements(image);
    const allocation = try vulkan.allocateDeviceMemory(memory_requirements, .regular);

    try vulkan.device_allocator.bind(.{ .image = image }, allocation, 0);

    const mask = vulkan.frmt.mask(vk_format);
    const view = vulkan.device.createImageView(&.{
        .image = image,
        .view_type = switch (dimensions) {
            .@"1d" => .@"1d",
            .@"2d" => .@"2d",
            .@"3d" => .@"3d",
            .cube => .cube,
            .@"1d_array" => .@"1d_array",
            .@"2d_array" => .@"2d_array",
            .cube_array => .cube_array,
        },
        .format = vk_format,
        .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
        .subresource_range = .{
            .aspect_mask = .{
                .color_bit = mask.color,
                .depth_bit = mask.depth,
                .stencil_bit = mask.stencil,
            },
            .layer_count = size[3],
            .base_array_layer = 0,
            .level_count = if (sampling_options) |so| so.mip_levels else 1,
            .base_mip_level = 0,
        },
    }, vulkan.vka) catch |err| return vulkan.wrapMemoryErrors(err);

    return .{
        .image = image,
        .sampler = sampler,
        .view = view,

        .allocation = allocation,
        .size = size,
        .vk_format = vk_format,
    };
}

pub const TextureUsage = util.StructFromEnum(enum {
    attachment,
    blend,
    transfer_src,
    transfer_dst,
    blit_src,
    blit_dst,
    storage,
}, bool, false, .@"packed");

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

pub const TextureSamplingParameters = struct {
    shrink: Filtering = .point,
    expand: Filtering = .point,
    tiling: [3]Tiling = @splat(.clamp_to_border),
    mip_levels: u32 = 1,
    // samples: u8,
};

pub const Tiling = enum {
    repeat,
    mirror,
    clamp_to_edge,
    clamp_to_border,
    mirror_clamp_to_edge,
};

pub const Filtering = enum { point, linear };
fn getSamplerAddressMode(filtering: Tiling) vk.SamplerAddressMode {
    return switch (filtering) {
        .repeat => .repeat,
        .mirror => .mirrored_repeat,
        .clamp_to_edge => .clamp_to_edge,
        .clamp_to_border => .clamp_to_border,
        .mirror_clamp_to_edge => .mirror_clamp_to_edge,
    };
}
fn getImageUsageFlags(
    texture_usage: TextureUsage,
    sampled: bool,
    format: Format,
) vk.ImageUsageFlags {
    return .{
        .transfer_src_bit = texture_usage.transfer_src,
        .transfer_dst_bit = texture_usage.transfer_dst,
        .sampled_bit = sampled,
        .storage_bit = texture_usage.storage,
        .color_attachment_bit = texture_usage.attachment and !format.isDepthStencil(),
        .depth_stencil_attachment_bit = texture_usage.attachment and format.isDepthStencil(),
    };
}

const Error = vulkan.Error;
const Format = vulkan.Format;
