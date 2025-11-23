const std = @import("std");
const zigbuiltin = @import("builtin");
const huge = @import("../../root.zig");
const math = huge.math;
const util = huge.util;
const gpu = huge.gpu;
const hgsl = gpu.hgsl;

pub const vk = @import("vk.zig");

//=====|constants|======

const u32m = ~@as(u32, 0);
const timeout: u64 = std.time.ns_per_s * 5;
const max_queue_family_count = 16;

const min_vulkan_version: Version = .{ .major = 1, .minor = 2 };
const max_vulkan_version: Version = undefined;

const max_push_constant_bytes = 128;
const layers: []const [*:0]const u8 = if (zigbuiltin.mode == .Debug) &.{
    "VK_LAYER_KHRONOS_validation",
    // "VK_LAYER_LUNARG_api_dump",
} else &.{};

//=======|state|========

var vka: ?*vk.AllocationCallbacks = null;

var instance: vk.InstanceProxy = undefined;
var physical_devices: [3]PhysicalDevice = @splat(.{});
var valid_physical_device_count: usize = 0;
var current_physical_device_index: usize = 0;
var device: vk.DeviceProxy = undefined;

var bwp: vk.BaseWrapper = undefined;
var iwp: vk.InstanceWrapper = undefined;
var dwp: vk.DeviceWrapper = undefined;
var queues: [queue_type_count]vk.Queue = @splat(.null_handle);
inline fn queue(queue_type: QueueType) vk.Queue {
    return queues[@intFromEnum(queue_type)];
}

var command_pools: [queue_type_count]vk.CommandPool = @splat(.null_handle);

inline fn pd() PhysicalDevice {
    return physical_devices[current_physical_device_index];
}

var api_version: Version = undefined;
var arena: std.heap.ArenaAllocator = undefined;
var shader_compiler: hgsl.Compiler = undefined;
// var pipelines: List(VKPipeline) = .empty;

var shader_module_list: List(VKShaderModule) = .empty;
var pipeline_list: List(VKPipeline) = .empty;
var buffer_list: List(VKBuffer) = .empty;

var window_context_primary: VKWindowContext = undefined;
var window_context_list: List(VKWindowContext) = .empty;
var window_context_count: u32 = 0;

var current_render_target: ?RenderTarget = null;
//======|methods|========

fn draw(handle: Pipeline, params: gpu.DrawParams) Error!void {
    _, const cmd = if (try getRenderingResources()) |r| r else return;
    errdefer forceEndRendering();

    device.cmdBindPipeline(cmd, .graphics, VKPipeline.get(handle).vk_handle);
    if (params.indexed_vertex_offset) |vo| {
        device.cmdDrawIndexed(
            cmd,
            params.count,
            params.instance_count,
            params.offset,
            vo,
            params.instance_offset,
        );
    } else device.cmdDraw(
        cmd,
        params.count,
        params.instance_count,
        params.offset,
        params.instance_offset,
    );
}
fn bindIndexBuffer(handle: Buffer, index_type: gpu.IndexType) Error!void {
    _, const cmd = if (try getRenderingResources()) |r| r else return;
    errdefer forceEndRendering();

    const buffer: *VKBuffer = .get(handle);
    if (buffer.usage != .index) return Error.BufferMisuse;

    if (api_version.minor < 4 and index_type == .u8)
        @panic("TODO: index_type u8 extension");
    device.cmdBindIndexBuffer(cmd, buffer.vk_handle, 0, switch (index_type) {
        .u32 => .uint32,
        .u16 => .uint16,
        .u8 => .uint8, //only in core spec from 1_4
    });
}
fn bindVertexBuffer(handle: Buffer) Error!void {
    _, const cmd = if (try getRenderingResources()) |r| r else return;
    errdefer forceEndRendering();

    const buffer: *VKBuffer = .get(handle);
    if (buffer.usage != .vertex) return Error.BufferMisuse;

    device.cmdBindVertexBuffers(cmd, 0, 1, &.{buffer.vk_handle}, &.{0});
}
fn beginRendering(render_target: RenderTarget, clear_value: ClearValue) Error!void {
    if (current_render_target) |_| try endRendering();

    current_render_target = render_target;
    if (VKWindowContext.fromRenderTarget(render_target)) |wc| {
        try wc.setRenderTargetState(clear_value);
    } else @panic("begin rendering NOT to WINDOW");
}
fn endRendering() Error!void {
    const rt = if (current_render_target) |render_target| render_target else return;
    defer current_render_target = null;

    if (VKWindowContext.fromRenderTarget(rt)) |wc| {
        try wc.endRendering();
    } else @panic("end rendering NOT to WINDOW");
}

fn forceEndRendering() void {
    const rt = if (current_render_target) |render_target| render_target else return;
    defer current_render_target = null;

    if (VKWindowContext.fromRenderTarget(rt)) |wc| {
        wc.forceEndRendering();
    } else @panic("end rendering URGENT NOT to WINDOW");
}

// setPipelineOpaqueUniform: SetPipelineOpaqueUniformFn = undefined,
fn pipelinePushConstant(
    handle: Pipeline,
    name: []const u8,
    local_offset: u32,
    local_size: u32,
    ptr: *const anyopaque,
) Error!void {
    _ = .{ local_offset, local_size };
    _, const cmd = if (try getRenderingResources()) |r| r else return;
    const pipeline: *VKPipeline = .get(handle);

    var offsets: [Pipeline.max_pipeline_stages]u32 = undefined;
    var offset_count: u32 = 0;
    for (pipeline.entry_point_info_storage[0..pipeline.stage_count]) |ep_info| {
        pcloop: for (ep_info.push_constant_mappings) |pc| {
            if (util.strEql(name, pc.name)) {
                if (pc.offset + pc.size > max_push_constant_bytes)
                    return Error.ShaderPushConstantOutOfBounds;
                //dont repeat cmdPushConstants call with the same offset
                for (offsets[0..offset_count]) |o| if (o == pc.offset) continue :pcloop;

                offsets[offset_count] = pc.offset;
                offset_count += 1;

                var stage_flags: vk.Flags = 0;
                for (pipeline.push_constant_ranges[0..pipeline.push_constant_range_count]) |r| {
                    if (r.size < pc.offset + pc.size) break;
                    stage_flags |= r.stage_flags.toInt();
                }
                // const bytes: []const u8 = @as([*]const u8, @ptrCast(ptr))[0..pc.size];
                // if (pc.size & 3 == 0)
                //     std.debug.print("floats: {any}\n", .{@as([]const f32, @ptrCast(@alignCast(bytes)))});
                device.cmdPushConstants(
                    cmd,
                    pipeline.layout,
                    @bitCast(stage_flags),
                    pc.offset,
                    pc.size,
                    ptr,
                );
            }
        }
        //log if didnt found
        //for opaque uniform
    }
}
fn createPipeline(stages: []const ShaderModule, opt: gpu.PipelineOptions) Error!Pipeline {
    var pipeline: VKPipeline = .{};
    const mps = gpu.Pipeline.max_pipeline_stages;
    var stage_create_infos: [mps]vk.PipelineShaderStageCreateInfo = undefined;

    for (0..stages.len) |i| {
        const shader_module: *VKShaderModule = .get(stages[i]);
        const ep_info = shader_module.entry_point_info;
        const stage_flags = getStageFlags(ep_info.stage_info);
        stage_create_infos[i] = .{
            .module = shader_module.vk_handle,
            .p_name = ep_info.name,
            .stage = stage_flags,
        };
        pipeline.entry_point_info_storage[i] = ep_info;
        pipeline.stage_count = @intCast(stages.len);

        if (ep_info.push_constant_mappings.len != 0) {
            const last_pc = ep_info.push_constant_mappings[ep_info.push_constant_mappings.len - 1];
            pipeline.push_constant_ranges[pipeline.push_constant_range_count] = .{
                .stage_flags = stage_flags,
                .offset = 0,
                .size = last_pc.offset + last_pc.size,
            };
            pipeline.push_constant_range_count += 1;
        }
    }
    pipeline.sortRanges();
    //CHECK stages *compatibility

    const fragment: ?FragmentStageInfo = FragmentStageInfo.fromStageSlice(stages);
    const vertex: ?VertexStageInfo = VertexStageInfo.fromStageSlice(stages);

    const layout = device.createPipelineLayout(&.{
        // set_layout_count: u32 = 0,
        // p_set_layouts: ?[*]const DescriptorSetLayout = null,
        .push_constant_range_count = pipeline.push_constant_range_count,
        .p_push_constant_ranges = &pipeline.push_constant_ranges,
    }, vka) catch return Error.ResourceCreationError;
    pipeline.layout = layout;

    _ = device.createGraphicsPipelines(.null_handle, 1, &.{.{
        .p_next = if (fragment) |frag| &(try frag.pipelineCreationInfo(
            &.{.b8g8r8a8_unorm},
            .undefined,
            .undefined,
        )) else null,
        .stage_count = @intCast(stages.len),
        .p_stages = stage_create_infos[0..stages.len].ptr,
        .layout = layout,

        .p_vertex_input_state = if (vertex) |vert| &.{
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = &.{vert.binding_description},
            .vertex_attribute_description_count = @intCast(vert.attributes.len),
            .p_vertex_attribute_descriptions = vert.attributes.ptr,
        } else null,
        .p_input_assembly_state = if (vertex) |_| &.{
            .topology = castPrimitiveTopology(opt.primitive),
            .primitive_restart_enable = .false,
        } else null,
        // p_tessellation_state: ?*const PipelineTessellationStateCreateInfo = null,
        .p_viewport_state = if (fragment) |frag| &.{
            .viewport_count = frag.output_count,
            .scissor_count = frag.output_count,
        } else null,
        // p_rasterization_state: ?*const PipelineRasterizationStateCreateInfo = null,
        .p_rasterization_state = &.{
            .depth_clamp_enable = .false,
            .rasterizer_discard_enable = .false,
            .polygon_mode = .fill,
            .line_width = 1,
            .cull_mode = .{
                .back_bit = opt.cull == .back or opt.cull == .both,
                .front_bit = opt.cull == .front or opt.cull == .both,
            },
            .front_face = if (opt.winding_order == .clockwise) .clockwise else .counter_clockwise,
            .depth_bias_enable = .false,
            .depth_bias_constant_factor = 0,
            .depth_bias_clamp = 0,
            .depth_bias_slope_factor = 0,
        },

        .p_multisample_state = &.{
            .sample_shading_enable = .false,
            .rasterization_samples = .{ .@"1_bit" = true },
            .min_sample_shading = 1,
            .p_sample_mask = null,
            .alpha_to_coverage_enable = .false,
            .alpha_to_one_enable = .false,
        },
        // p_depth_stencil_state: ?*const PipelineDepthStencilStateCreateInfo = null,
        .p_color_blend_state = if (fragment) |frag| &.{
            .logic_op_enable = .false,
            .logic_op = .clear,
            .attachment_count = frag.output_count,
            .p_attachments = &.{.{
                .color_write_mask = .{
                    .r_bit = true,
                    .b_bit = true,
                    .g_bit = true,
                    .a_bit = true,
                },
                .blend_enable = .false,
                .src_color_blend_factor = .one,
                .dst_color_blend_factor = .zero,
                .color_blend_op = .add,
                .src_alpha_blend_factor = .one,
                .dst_alpha_blend_factor = .zero,
                .alpha_blend_op = .add,
            }},
            .blend_constants = @splat(0),
        } else null,
        .p_dynamic_state = &.{
            .p_dynamic_states = &.{ .viewport, .scissor },
            .dynamic_state_count = 2,
        },

        .subpass = 0,
        .base_pipeline_index = -1,
        .flags = .{},
    }}, vka, @ptrCast(&pipeline.vk_handle)) catch
        return Error.ResourceCreationError;

    const handle: Pipeline = @enumFromInt(@as(gpu.Handle, @intCast(pipeline_list.items.len)));
    try pipeline_list.append(arena.allocator(), pipeline);
    return handle;
}

fn createShaderModulePath(path: []const u8, entry_point: []const u8) Error!ShaderModule {
    const result = shader_compiler.compileFile(path) catch
        return @enumFromInt(u32m);
    const vk_handle: vk.ShaderModule = device.createShaderModule(&.{
        .code_size = result.bytes.len,
        .p_code = @ptrCast(@alignCast(result.bytes.ptr)),
    }, vka) catch
        return Error.OutOfMemory;

    const handle: ShaderModule = @enumFromInt(@as(gpu.Handle, @intCast(shader_module_list.items.len)));
    try shader_module_list.append(arena.allocator(), .{
        .vk_handle = vk_handle,
        .entry_point_info = for (result.entry_point_infos) |ep| {
            if (util.strEql(entry_point, ep.name)) break ep;
        } else return Error.ShaderEntryPointNotFound,
    });
    return handle;
}
fn destroyShaderModule(shader_module: ShaderModule) void {
    _ = shader_module;
}
fn loadBuffer(handle: Buffer, bytes: []const u8, offset: usize) Error!void {
    const mapped = try mapBuffer(handle, bytes.len, offset);
    @memcpy(mapped, bytes);
    defer unmapBuffer(handle);
}
fn mapBuffer(handle: Buffer, bytes: usize, offset: usize) Error![]u8 {
    const buffer: *VKBuffer = .get(handle);
    if (buffer.mapped) return Error.MemoryRemap;

    if (bytes > buffer.size) return Error.OutOfMemory;
    const ptr = (device.mapMemory(buffer.device_memory, offset, @intCast(bytes), .{}) catch
        return Error.OutOfMemory) orelse
        return Error.OutOfMemory;
    buffer.mapped = true;
    return @as([*]u8, @ptrCast(ptr))[0..bytes];
}
fn unmapBuffer(handle: Buffer) void {
    const buffer: *VKBuffer = .get(handle);
    if (!buffer.mapped) return;

    device.unmapMemory(buffer.device_memory);
    buffer.mapped = false;
}
fn createBuffer(size: usize, usage: BufferUsage) Error!Buffer {
    const buffer = try VKBuffer.create(@intCast(size), usage);
    const handle: Buffer = @enumFromInt(@as(gpu.Handle, @intCast(buffer_list.items.len)));
    try buffer_list.append(arena.allocator(), buffer);
    return handle;
}
fn destroyBuffer(handle: Buffer) void {
    const buffer: *VKBuffer = .get(handle);
    buffer.destroy();
}

fn renderTargetSize(render_target: RenderTarget) math.uvec2 {
    return if (VKWindowContext.fromRenderTarget(render_target)) |wc|
        .{ wc.extent.width, wc.extent.height }
    else
        @panic("render target size of NOT WINDOW");
}

fn updateWindowContext(handle: WindowContext) void {
    _ = handle;
}

fn getWindowRenderTarget(window: huge.Window) RenderTarget {
    return @enumFromInt((1 << 31) | @intFromEnum(window.context));
}

fn createWindowContext(window: huge.Window) Error!WindowContext {
    const wc = VKWindowContext.create(window) catch
        return Error.WindowContextCreationError;
    if (window_context_count == 0) {
        window_context_primary = wc;
        return @enumFromInt(0);
    } else {
        @panic("VK multiple window contexts");
    }
}
fn destroyWindowContext(handle: WindowContext) void {
    const window_context = VKWindowContext.get(handle);
    window_context.destroy();
}

//===|implementations|===
const VKShaderModule = struct {
    vk_handle: vk.ShaderModule = .null_handle,

    entry_point_info: hgsl.EntryPointInfo = undefined,
    pub fn createPath(path: []const u8, entry_point: []const u8) Error!VKShaderModule {
        _ = .{ path, entry_point };
        // const result = shader_compiler.compileFile(path);
    }
    pub fn createSource(source: []const u8, entry_point: []const u8) Error!VKShaderModule {
        if (true) @panic("VKShaderModule.createRaw");
        return try createPath(source, entry_point);
    }
    pub fn destroy(self: VKShaderModule) void {
        _ = self;
    }

    pub fn get(handle: ShaderModule) *VKShaderModule {
        return &shader_module_list.items[@intFromEnum(handle)];
    }
};
//handle array with functions that have explicit
//(offset and size) or (binding) args on top of 'name'
const VKPipeline = struct {
    vk_handle: vk.Pipeline = .null_handle,
    layout: vk.PipelineLayout = .null_handle,

    stage_count: u32 = 0,
    entry_point_info_storage: [Pipeline.max_pipeline_stages]hgsl.EntryPointInfo = undefined,
    push_constant_ranges: [Pipeline.max_pipeline_stages]vk.PushConstantRange = undefined,
    push_constant_range_count: u32 = 0,

    //descriptor_set
    //stages
    //pc mapping, uniform mapping(just concat from stages
    // and dont care about repeating names)
    pub fn get(handle: Pipeline) *VKPipeline {
        return &pipeline_list.items[@intFromEnum(handle)];
    }
    pub fn destroy(self: *VKPipeline) void {
        device.destroyPipelineLayout(self.layout, vka);
        device.destroyPipeline(self.vk_handle, vka);
        self.layout = .null_handle;
        self.pipeline = .null_handle;
    }
    fn sortRanges(self: *VKPipeline) void {
        if (self.push_constant_range_count < 2) return;
        for (0..self.push_constant_range_count - 1) |i| {
            for (i + 1..self.push_constant_range_count) |j| {
                if (self.push_constant_ranges[i].size < self.push_constant_ranges[j].size)
                    std.mem.swap(vk.PushConstantRange, &self.push_constant_ranges[i], &self.push_constant_ranges[j]);
            }
        }
    }
};
const FragmentStageInfo = struct {
    output_count: u32,

    pub fn fromStageSlice(stages: []const ShaderModule) ?FragmentStageInfo {
        const ep_info: hgsl.EntryPointInfo = for (stages) |s| {
            const shader_module: *VKShaderModule = VKShaderModule.get(s);
            if (shader_module.entry_point_info.stage_info == .fragment)
                break shader_module.entry_point_info;
        } else return null;
        _ = ep_info;
        return .{
            .output_count = 1, //TODO: check that
        };
    }
    pub fn pipelineCreationInfo(
        self: *const FragmentStageInfo,
        formats: []const vk.Format,
        depth_format: vk.Format,
        stencil_format: vk.Format,
    ) Error!vk.PipelineRenderingCreateInfo {
        //
        if (formats.len != self.output_count) return Error.ResourceCreationError;
        return .{
            .color_attachment_count = self.output_count,
            .p_color_attachment_formats = formats.ptr,
            .depth_attachment_format = depth_format,
            .stencil_attachment_format = stencil_format,
            .view_mask = 0,
        };
    }
};
const VertexStageInfo = struct {
    attributes: []const vk.VertexInputAttributeDescription = &.{},
    binding_description: vk.VertexInputBindingDescription,
    var attribute_storage: [10]vk.VertexInputAttributeDescription = undefined;

    pub fn fromStageSlice(stages: []const ShaderModule) ?VertexStageInfo {
        const ep_info: hgsl.EntryPointInfo = for (stages) |s| {
            const shader_module: *VKShaderModule = .get(s);
            if (shader_module.entry_point_info.stage_info == .vertex)
                break shader_module.entry_point_info;
        } else return null;
        if (ep_info.inputMappings().len > attribute_storage.len)
            @panic("TODO: unlimited vertex attributes");

        var stride: u32 = 0;
        for (ep_info.inputMappings(), 0..) |im, i| {
            attribute_storage[i] = .{
                .location = im.location,
                .binding = 0,
                .format = .r32g32b32_sfloat,
                .offset = stride,
            };
            stride += im.size;
        }
        return .{
            .attributes = attribute_storage[0..ep_info.input_count],
            .binding_description = .{
                .binding = 0,
                .stride = stride,
                .input_rate = .vertex,
            },
        };
    }
};

const VKBuffer = struct {
    vk_handle: vk.Buffer = .null_handle,
    device_memory: vk.DeviceMemory = .null_handle,
    size: u64 = 0,
    usage: BufferUsage = undefined,

    mapped: bool = false,
    pub fn create(size: u64, usage: BufferUsage) Error!VKBuffer {
        if (size == 0) return .{ .size = 0, .usage = usage };

        const handle = device.createBuffer(&.{
            .size = size,
            .usage = switch (usage) {
                .vertex => .{ .vertex_buffer_bit = true },
                .index => .{ .index_buffer_bit = true },
                .uniform => .{ .uniform_buffer_bit = true },
                else => .{},
            },
            .sharing_mode = .exclusive,
            // .p_queue_family_indices = &.{},
            // .queue_family_index_count = 1,
        }, vka) catch return Error.ResourceCreationError;

        const memory_requirements = device.getBufferMemoryRequirements(handle);
        const pd_mem_props = instance.getPhysicalDeviceMemoryProperties(pd().handle);
        const mem_type: u32 = for (0..pd_mem_props.memory_type_count) |i| {
            if ((memory_requirements.memory_type_bits & (@as(u32, 1) << @as(u5, @intCast(i)))) == 0) continue;
            if (pd_mem_props.memory_types[i].property_flags.contains(.{
                .host_visible_bit = true,
                // .host_coherent_bit = true,
            }))
                break @intCast(i);
        } else return Error.ResourceCreationError;
        const memory_allocate_info: vk.MemoryAllocateInfo = .{
            .allocation_size = memory_requirements.size,
            .memory_type_index = mem_type,
        };
        const memory = device.allocateMemory(&memory_allocate_info, vka) catch
            return Error.ResourceCreationError;
        device.bindBufferMemory(handle, memory, 0) catch
            return Error.ResourceCreationError;
        return .{
            .vk_handle = handle,
            .device_memory = memory,
            .size = size,
            .usage = usage,
        };
    }
    pub fn destroy(self: *VKBuffer) void {
        _ = self;
    }
    pub fn get(handle: Buffer) *VKBuffer {
        return &buffer_list.items[@intFromEnum(handle)];
    }
};

const VKRenderTarget = struct {};
fn getRenderingResources() Error!?std.meta.Tuple(&.{ RenderTarget, vk.CommandBuffer }) {
    huge.dassert(current_render_target != null);
    const rt = if (current_render_target) |render_target| render_target else return null;
    const cmd = if (VKWindowContext.fromRenderTarget(rt)) |wc|
        try wc.initRenderingCmd()
    else
        @panic("init rendering resources NOT of WINDOW rt");

    return .{ rt, cmd };
}

const VKWindowContext = struct {
    const mic = 3; //max_image_count
    const mfif = mic - 1; //max_frame_in_flight
    acquired_image_index: u32 = u32m,

    fif_index: u32 = 0, //current frame-in-flight index

    surface: vk.SurfaceKHR = .null_handle,
    request_recreate: bool = false,
    swapchain: vk.SwapchainKHR = .null_handle,

    images: [mic]vk.Image = @splat(.null_handle),
    image_views: [mic]vk.ImageView = @splat(.null_handle),
    image_count: u32 = undefined,

    extent: vk.Extent2D = undefined,
    surface_format: vk.SurfaceFormatKHR = undefined,
    present_mode: vk.PresentModeKHR = .fifo_khr,

    current_frame: usize = 0,
    acquire_semaphores: [mfif]vk.Semaphore = undefined,
    submit_semaphores: [mic]vk.Semaphore = undefined,
    fences: [mfif]vk.Fence = undefined,

    //render target
    rendering_cmds: [mfif * queue_type_count]vk.CommandBuffer = @splat(.null_handle),
    clear_value: ClearValue = undefined,

    inline fn fif(self: VKWindowContext) u32 {
        return @max(self.image_count - 1, 1);
    }
    pub fn setRenderTargetState(self: *VKWindowContext, clear_value: ClearValue) Error!void {
        self.clear_value = clear_value;
        self.fif_index = (self.fif_index + 1) % self.fif();
    }
    pub fn initRenderingCmd(self: *VKWindowContext) Error!vk.CommandBuffer {
        const rt = if (current_render_target) |render_target| render_target else return Error.Unknown;
        const cmd = try self.getRenderingCmd(.graphics);
        if (~self.acquired_image_index != 0) return cmd;

        _ = device.waitForFences(1, &.{self.fences[self.fif_index]}, .true, timeout) catch
            return Error.SynchronisationError;
        device.resetFences(1, &.{self.fences[self.fif_index]}) catch
            return Error.SynchronisationError;
        self.acquired_image_index = (device.acquireNextImageKHR(
            self.swapchain,
            timeout,
            self.acquire_semaphores[self.fif_index],
            .null_handle,
        ) catch return Error.ResourceCreationError).image_index;

        device.resetCommandBuffer(cmd, .{}) catch
            return Error.ResourceCreationError;

        device.beginCommandBuffer(cmd, &.{}) catch return Error.Unknown;
        const rt_size = renderTargetSize(rt);
        device.cmdSetScissor(cmd, 0, 1, &.{.{
            .extent = .{ .width = rt_size[0], .height = rt_size[1] },
            .offset = .{ .x = 0, .y = 0 },
        }});
        device.cmdSetViewport(cmd, 0, 1, &.{.{
            .x = 0,
            .y = 0,
            .width = @floatFromInt(rt_size[0]),
            .height = @floatFromInt(rt_size[1]),
            .min_depth = 0,
            .max_depth = 1,
        }});
        device.cmdBeginRendering(cmd, &.{
            .render_area = .{
                .offset = .{ .x = 0, .y = 0 },
                .extent = self.extent,
            },
            .color_attachment_count = 1,
            .p_color_attachments = &.{.{
                .image_view = self.image_views[self.acquired_image_index],
                .image_layout = .attachment_optimal,
                .load_op = .clear,
                .store_op = .store,
                .clear_value = .{
                    .color = if (self.clear_value.color) |cc|
                        .{ .float_32 = @as(*const [4]f32, @ptrCast(&cc)).* }
                    else
                        .{ .float_32 = @splat(0) },
                },

                .resolve_image_layout = .undefined,
                .resolve_mode = .{},
            }},

            .flags = .{},
            .layer_count = 1,
            .view_mask = 0,
            // p_depth_attachment: ?*const RenderingAttachmentInfo = null,
            // p_stencil_attachment: ?*const RenderingAttachmentInfo = null,
        });
        return cmd;
    }

    pub fn endRendering(self: *VKWindowContext) Error!void {
        defer self.acquired_image_index = u32m;

        const cmd = self.getRenderingCmdOpt(.graphics);
        if (cmd == .null_handle) return;
        device.cmdEndRendering(cmd);
        self.present(cmd) catch
            return Error.PresentationError;
    }
    pub fn forceEndRendering(self: *VKWindowContext) void {
        defer self.acquired_image_index = u32m;

        const cmd = self.getRenderingCmdOpt(.graphics);
        if (cmd == .null_handle) return;
        device.cmdEndRendering(cmd);
        device.endCommandBuffer(cmd) catch {};
        device.queueSubmit(queue(.presentation), 1, &.{.{
            .command_buffer_count = 0,
            .p_wait_dst_stage_mask = &.{.{ .color_attachment_output_bit = true }},
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{self.acquire_semaphores[self.fif_index]},
        }}, self.fences[self.fif_index]) catch {};
    }
    fn getRenderingCmd(self: *VKWindowContext, queue_type: QueueType) Error!vk.CommandBuffer {
        const ptr = &self.rendering_cmds[@intFromEnum(queue_type) + self.fif_index * queue_type_count];
        if (ptr.* == .null_handle)
            ptr.* = try allocCommandBuffer(queue_type, .primary);
        return ptr.*;
    }
    fn getRenderingCmdOpt(self: *VKWindowContext, queue_type: QueueType) vk.CommandBuffer {
        return self.rendering_cmds[@intFromEnum(queue_type) + self.fif_index * queue_type_count];
    }

    fn present(self: VKWindowContext, cmd: vk.CommandBuffer) !void {
        const image_barrier: vk.ImageMemoryBarrier = .{
            .src_access_mask = .{ .color_attachment_write_bit = true },
            .dst_access_mask = .{},
            .old_layout = .undefined,
            .new_layout = .present_src_khr,
            .src_queue_family_index = pd().queueFamilyIndex(.presentation),
            .dst_queue_family_index = pd().queueFamilyIndex(.presentation),
            .image = self.images[self.acquired_image_index],
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };
        device.cmdPipelineBarrier(cmd, .{
            .all_commands_bit = true,
        }, .{
            .bottom_of_pipe_bit = true,
        }, .{}, 0, null, 0, null, 1, &.{
            image_barrier,
        });

        try device.endCommandBuffer(cmd);
        try device.queueSubmit(
            queue(.presentation),
            1,
            &.{.{
                .command_buffer_count = 1,
                .p_command_buffers = &.{cmd},
                .p_wait_dst_stage_mask = &.{.{ .color_attachment_output_bit = true }},

                .wait_semaphore_count = 1,
                .p_wait_semaphores = &.{self.acquire_semaphores[self.fif_index]},
                .signal_semaphore_count = 1,
                .p_signal_semaphores = &.{self.submit_semaphores[self.acquired_image_index]},
            }},
            self.fences[self.fif_index],
        );

        _ = device.queuePresentKHR(queue(.presentation), &.{
            .wait_semaphore_count = 1,
            .p_wait_semaphores = &.{self.submit_semaphores[self.acquired_image_index]},
            .swapchain_count = 1,
            .p_swapchains = &.{self.swapchain},
            .p_image_indices = &.{self.acquired_image_index},
        }) catch |err|
            switch (err) {
                error.OutOfDateKHR => {
                    @panic("recreate swapchain");
                    // self.request_recreate = true;
                },
                else => return error.PresentationError,
            };
    }
    fn fromRenderTarget(render_target: RenderTarget) ?*VKWindowContext {
        const int: gpu.Handle = @intFromEnum(render_target);
        if ((int >> 31) == 0) return null;
        return VKWindowContext.get(@enumFromInt(int & (~@as(gpu.Handle, 0) >> 1)));
    }

    pub fn create(window: huge.Window) !VKWindowContext {
        var surface_handle: u64 = undefined;
        if (glfw.createWindowSurface(
            @intFromEnum(instance.handle),
            window.handle,
            null,
            &surface_handle,
        ) != .success) return Error.WindowContextCreationError;
        var result: VKWindowContext = .{
            .surface = @enumFromInt(surface_handle),
        };

        const capabilities = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(pd().handle, result.surface);

        result.extent = blk: {
            if (capabilities.current_extent.width == std.math.maxInt(u32)) {
                var res: [2]c_int = @splat(0);
                glfw.getFramebufferSize(window.handle, &res[0], &res[1]);
                break :blk .{
                    .width = std.math.clamp(@as(u32, @intCast(res[0])), capabilities.min_image_extent.width, capabilities.max_image_extent.width),
                    .height = std.math.clamp(@as(u32, @intCast(res[1])), capabilities.min_image_extent.height, capabilities.max_image_extent.height),
                };
            }
            break :blk .{
                .width = std.math.clamp(capabilities.current_extent.width, capabilities.min_image_extent.width, capabilities.max_image_extent.width),
                .height = std.math.clamp(capabilities.current_extent.height, capabilities.min_image_extent.height, capabilities.max_image_extent.height),
            };
        };

        result.surface_format = blk: {
            const max_surface_format_count = 100;
            var surface_format_count: u32 = 0;
            _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pd().handle, result.surface, &surface_format_count, null);
            surface_format_count = @min(max_surface_format_count, surface_format_count);
            var surface_format_storage: [max_surface_format_count]vk.SurfaceFormatKHR = undefined;
            _ = try instance.getPhysicalDeviceSurfaceFormatsKHR(pd().handle, result.surface, &surface_format_count, &surface_format_storage);
            break :blk for (surface_format_storage[0..surface_format_count]) |sf| {
                if (sf.format == .b8g8r8a8_unorm and sf.color_space == .srgb_nonlinear_khr) break sf;
            } else surface_format_storage[0];
        };

        result.present_mode = blk: {
            var present_mode_storage: [@typeInfo(vk.PresentModeKHR).@"enum".fields.len]vk.PresentModeKHR = undefined;
            var present_mode_count: u32 = 0;
            _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pd().handle, result.surface, &present_mode_count, null);
            _ = try instance.getPhysicalDeviceSurfacePresentModesKHR(pd().handle, result.surface, &present_mode_count, &present_mode_storage);
            break :blk for (present_mode_storage[0..present_mode_count]) |pm| {
                if (pm == vk.PresentModeKHR.mailbox_khr) break pm;
            } else vk.PresentModeKHR.fifo_khr;
        };

        result.image_count = @max(capabilities.min_image_count, @as(u32, if (result.present_mode == .mailbox_khr) 3 else 2));
        const exclusive = pd().queueFamilyIndex(.graphics) == pd().queueFamilyIndex(.presentation);
        result.swapchain = try device.createSwapchainKHR(&.{
            .surface = result.surface,
            .min_image_count = result.image_count,

            .present_mode = result.present_mode,
            .image_format = result.surface_format.format,
            .image_color_space = result.surface_format.color_space,
            .image_extent = result.extent,

            .image_array_layers = 1,
            .image_sharing_mode = if (exclusive) .exclusive else .concurrent,
            .image_usage = .{
                .transfer_dst_bit = true,
                .color_attachment_bit = true,
            },
            .queue_family_index_count = if (exclusive) 0 else 2,
            .p_queue_family_indices = if (exclusive) null else &.{
                pd().queueFamilyIndex(.graphics),
                pd().queueFamilyIndex(.presentation),
            },
            .pre_transform = capabilities.current_transform,
            .composite_alpha = .{ .opaque_bit_khr = true },
            .clipped = .true,
        }, vka);

        _ = try device.getSwapchainImagesKHR(result.swapchain, &result.image_count, null);
        result.image_count = @min(result.image_count, mic);
        _ = try device.getSwapchainImagesKHR(result.swapchain, &result.image_count, &result.images);

        for (0..result.image_count) |i|
            result.image_views[i] = try device.createImageView(&.{
                .components = .{ .r = .identity, .g = .identity, .b = .identity, .a = .identity },
                .format = result.surface_format.format,
                .image = result.images[i],
                .subresource_range = .{
                    .aspect_mask = .{ .color_bit = true },
                    .layer_count = 1,
                    .base_array_layer = 0,
                    .level_count = 1,
                    .base_mip_level = 0,
                },
                .view_type = .@"2d",
            }, vka);

        for (0..result.fif()) |i| {
            result.acquire_semaphores[i] = try device.createSemaphore(&.{}, vka);
            result.fences[i] = try device.createFence(&.{ .flags = .{ .signaled_bit = true } }, vka);
        }
        for (0..result.image_count) |i|
            result.submit_semaphores[i] = try device.createSemaphore(&.{}, vka);
        return result;
    }
    pub fn destroy(self: VKWindowContext) void {
        device.queueWaitIdle(queue(.presentation)) catch
            @panic("window context destruction failure");
        _ = device.waitForFences(self.fif(), &self.fences, .true, timeout) catch
            @panic("window context destruction failure");
        for (self.image_views[0..self.image_count]) |iw|
            device.destroyImageView(iw, vka);
        device.destroySwapchainKHR(self.swapchain, vka);

        for (0..self.fif()) |i| {
            device.destroySemaphore(self.acquire_semaphores[i], vka);
            device.destroyFence(self.fences[i], vka);
        }
        for (0..self.image_count) |i|
            device.destroySemaphore(self.submit_semaphores[i], vka);

        instance.destroySurfaceKHR(self.surface, vka);
    }
    pub fn get(handle: WindowContext) *VKWindowContext {
        return if (@intFromEnum(handle) == 0)
            &window_context_primary
        else
            @panic("");
    }
};

fn commandPool(queue_type: QueueType) Error!vk.CommandPool {
    const index = @intFromEnum(queue_type);
    if (command_pools[index] == .null_handle) {
        const qfi = pd().queueFamilyIndex(queue_type);
        const created = device.createCommandPool(&.{
            .flags = .{ .reset_command_buffer_bit = true },
            .queue_family_index = qfi,
        }, vka) catch
            return Error.ResourceCreationError;
        for (&command_pools, 0..) |*cmd_pools, i| {
            if (pd().queueFamilyIndex(@enumFromInt(i)) == qfi)
                cmd_pools.* = created;
        }
    }
    return command_pools[index];
}
fn allocCommandBuffer(queue_type: QueueType, level: vk.CommandBufferLevel) Error!vk.CommandBuffer {
    var result: vk.CommandBuffer = .null_handle;
    device.allocateCommandBuffers(&.{
        .command_pool = try commandPool(queue_type),
        .level = level,
        .command_buffer_count = 1,
    }, @ptrCast(&result)) catch return Error.ResourceCreationError;
    return result;
}
//===|vkextensions|====

fn isDynamicRenderingBuiltin() bool {
    return api_version.@">="(.{ .major = 1, .minor = 3 });
}
fn cmdBeginRendering(command_buffer: vk.CommandBuffer, rendering_info: *const vk.RenderingInfo) void {
    if (isDynamicRenderingBuiltin())
        device.cmdBeginRendering(command_buffer, rendering_info)
    else
        device.cmdBeginRenderingKHR(command_buffer, rendering_info);
}
fn cmdEndRendering(command_buffer: vk.CommandBuffer, rendering_info: *const vk.RenderingInfo) void {
    if (isDynamicRenderingBuiltin())
        device.cmdEndRendering(command_buffer, rendering_info)
    else
        device.cmdEndRenderingKHR(command_buffer, rendering_info);
}

//===|initialization|====

pub fn initBackend() VKError!gpu.Backend {
    bwp = .load(loader);
    arena = .init(std.heap.page_allocator);

    const instance_api_version = castVersion(@bitCast(bwp.enumerateInstanceVersion() catch return error.OutOfMemory));
    if (!instance_api_version.@">="(min_vulkan_version))
        return VKError.UnsupportedApiVersion;
    try initInstance(arena.allocator(), instance_api_version);

    var extension_name_buf: [10][*:0]const u8 = undefined;
    var device_extension_list: List([*:0]const u8) = .initBuffer(&extension_name_buf);

    device_extension_list.appendAssumeCapacity(vk.extensions.khr_swapchain.name);
    if (!instance_api_version.@">="(.{ .major = 1, .minor = 3 }))
        device_extension_list.appendAssumeCapacity(vk.extensions.khr_dynamic_rendering.name);

    try initPhysicalDevices(arena.allocator(), device_extension_list.items);
    const physical_device_api_version = castVersion(@bitCast(instance.getPhysicalDeviceProperties(pd().handle).api_version));

    api_version = if (physical_device_api_version.@">="(instance_api_version)) instance_api_version else physical_device_api_version;
    try initLogicalDeviceAndQueues(device_extension_list.items);

    shader_compiler = .new(null, null, .{
        .target_env = .vulkan1_4,
        .max_push_constant_buffer_size = max_push_constant_bytes,
    });
    return versionBackend(api_version);
}

fn deinit() void {
    defer _ = arena.deinit();
    endRendering() catch {};

    device.deviceWaitIdle() catch {};
    shader_compiler.deinit();
    for (&command_pools) |cmd_pool| {
        for (&command_pools) |*i| {
            if (cmd_pool == i.*) i.* = .null_handle;
        }
        if (cmd_pool != .null_handle)
            device.destroyCommandPool(cmd_pool, vka);
    }
}
fn initLogicalDeviceAndQueues(extensions: []const [*:0]const u8) VKError!void {
    var queue_create_infos: [queue_type_count]vk.DeviceQueueCreateInfo = undefined;
    var queues_to_create: [queue_type_count]u8 = undefined;
    var count: usize = 0;

    //track all unique queue families
    for (pd().queue_family_indices) |qi| {
        if (~qi == 0) continue;

        for (0..count) |c| {
            if (queues_to_create[c] == qi) break;
        } else {
            queues_to_create[count] = qi;
            queue_create_infos[count] = .{
                .queue_count = 1,
                .queue_family_index = qi,
                .p_queue_priorities = &.{1.0},
            };
            count += 1;
        }
    }

    const dynamic_rendering_feature_ptr: *const anyopaque =
        if (isDynamicRenderingBuiltin())
            &vk.PhysicalDeviceDynamicRenderingFeatures{ .dynamic_rendering = .true }
        else
            &vk.PhysicalDeviceDynamicRenderingFeaturesKHR{ .dynamic_rendering = .true };

    const device_create_info: vk.DeviceCreateInfo = .{
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .queue_create_info_count = @intCast(count),
        .p_queue_create_infos = &queue_create_infos,
        .pp_enabled_layer_names = layers.ptr,
        .enabled_layer_count = @intCast(layers.len),

        .p_next = dynamic_rendering_feature_ptr,
    };

    const device_handle = instance.createDevice(
        pd().handle,
        &device_create_info,
        vka,
    ) catch return VKError.LogicalDeviceInitializationFailure;
    dwp = .load(device_handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    device = .init(device_handle, &dwp);

    for (0..queue_type_count) |i| {
        if (~pd().queue_family_indices[i] != 0)
            queues[i] = device.getDeviceQueue(pd().queue_family_indices[i], 0);
    }
}
fn initInstance(allocator: Allocator, instance_api_version: Version) VKError!void {
    const available_layers: []vk.LayerProperties =
        if (layers.len > 0) bwp.enumerateInstanceLayerPropertiesAlloc(allocator) catch return VKError.OutOfMemory else &.{};

    try checkLayerPresence(layers, available_layers);
    if (layers.len > 0) allocator.free(available_layers);

    var glfw_ext_count: u32 = 0; //get platform presentation extensions
    const glfw_exts = glfw.getRequiredInstanceExtensions(&glfw_ext_count);
    const instance_extensions: []const [*:0]const u8 = if (glfw_exts) |ge| ge[0..glfw_ext_count] else &.{};

    const available_instance_extensions: []vk.ExtensionProperties =
        bwp.enumerateInstanceExtensionPropertiesAlloc(null, allocator) catch return VKError.OutOfMemory;

    try checkExtensionPresence(instance_extensions, available_instance_extensions);
    allocator.free(available_instance_extensions);

    const app_info: vk.ApplicationInfo = .{
        .p_application_name = huge.name ++ " app",
        .application_version = @bitCast(@as(u32, 0)),
        .p_engine_name = huge.name,
        .engine_version = toVulkanVersion(huge.version),
        .api_version = toVulkanVersion(instance_api_version),
    };
    const instance_create_info: vk.InstanceCreateInfo = .{
        .p_application_info = &app_info,
        .enabled_extension_count = @intCast(instance_extensions.len),
        .pp_enabled_extension_names = instance_extensions.ptr,
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = layers.ptr,
    };
    const instance_handle = bwp.createInstance(&instance_create_info, vka) catch return VKError.InstanceInitializationFailure;

    iwp = .load(instance_handle, loader);
    instance = .init(instance_handle, &iwp);
}
fn initPhysicalDevices(allocator: Allocator, extensions: []const [*:0]const u8) VKError!void {
    var count: u32 = 0;
    _ = instance.enumeratePhysicalDevices(&count, null) catch
        return VKError.PhysicalDeviceInitializationFailure;

    if (count == 0) return error.PhysicalDeviceInitializationFailure;

    count = @min(physical_devices.len, count);
    var physical_device_handles: [physical_devices.len]vk.PhysicalDevice = undefined;
    _ = instance.enumeratePhysicalDevices(&count, &physical_device_handles) catch
        return VKError.PhysicalDeviceInitializationFailure;
    for (&physical_devices, &physical_device_handles) |*p, *ph| p.handle = ph.*;

    // create dummy window to use its surface
    // for physical device initialization
    const dummy_window = huge.Window.createDummy(@intFromEnum(instance.handle)) catch
        return VKError.DummyWindowCreationFailure;
    defer {
        instance.destroySurfaceKHR(@enumFromInt(dummy_window.surface_handle), vka);
        glfw.destroyWindow(dummy_window.handle);
    }

    valid_physical_device_count = count;
    var i: usize = 0;
    while (i < valid_physical_device_count) : (i += 1)
        initPhysicalDevice(allocator, &physical_devices[i], extensions, dummy_window) catch {
            valid_physical_device_count -= 1;
            std.mem.swap(PhysicalDevice, &physical_devices[i], &physical_devices[valid_physical_device_count]);
            i -= 1;
            continue; //remove from the array if initializaiton failed
        };
    if (valid_physical_device_count == 0) return VKError.PhysicalDeviceInitializationFailure;

    var max_score: u32 = 0; //pick best physical device
    //add ability to overwrite current physical device index
    for (physical_devices[0..valid_physical_device_count], 0..) |p, index| {
        const score = scorePhysicalDevice(p);
        if (score > max_score) {
            current_physical_device_index = index;
            max_score = score;
        }
    }
}

fn scorePhysicalDevice(physical_device: PhysicalDevice) u32 {
    var score: u32 = 0;
    score = switch (physical_device.type) {
        .discrete_gpu => 4000,
        .integrated_gpu => 3000,
        .virtual_gpu => 2000,
        .cpu => 1000,
        else => 1,
    };
    if (physical_device.features.geometry_shaders) score += 100;
    if (physical_device.features.tessellation_shaders) score += 100;
    return score;
}

fn initPhysicalDevice(allocator: Allocator, p: *PhysicalDevice, extensions: []const [*:0]const u8, dummy_window: huge.Window.DummyWindow) VKError!void {
    p.features = getPhysicalDeviceFeatures(p.handle);

    const properties = instance.getPhysicalDeviceProperties(p.handle); //limits?
    if (!castVersion(@bitCast(properties.api_version)).@">="(min_vulkan_version))
        return VKError.UnsupportedApiVersion;

    p.type = properties.device_type;
    p.name_len = @min(
        std.mem.len(@as([*:0]const u8, @ptrCast(@alignCast(&properties.device_name)))),
        PhysicalDevice.max_name_len,
    );
    @memcpy(p.name_storage[0..p.name_len], properties.device_name[0..p.name_len]);

    const available_extensions =
        instance.enumerateDeviceExtensionPropertiesAlloc(p.handle, null, allocator) catch return VKError.OutOfMemory;
    try checkExtensionPresence(extensions, available_extensions);
    allocator.free(available_extensions);

    p.queue_family_indices =
        try getQueueFamilyIndices(allocator, p.handle, dummy_window);
}
fn getQueueFamilyIndices(allocator: Allocator, handle: vk.PhysicalDevice, dummy_window: huge.Window.DummyWindow) VKError![queue_type_count]u8 {
    const queue_family_properties = instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(handle, allocator) catch
        return VKError.OutOfMemory;
    defer allocator.free(queue_family_properties);

    var index_lists: [queue_type_count]IndexList = undefined;

    for (&index_lists) |*l| l.init();

    for (queue_family_properties, 0..) |qfp, i| {
        const flags: QueueConfiguration = .{
            .graphics = qfp.queue_flags.graphics_bit,
            .compute = qfp.queue_flags.compute_bit,
            .transfer = qfp.queue_flags.transfer_bit,
            .sparse_binding = qfp.queue_flags.sparse_binding_bit,
            .protected = qfp.queue_flags.protected_bit,
            .video_decode = qfp.queue_flags.video_decode_bit_khr,
            .video_encode = qfp.queue_flags.video_encode_bit_khr,
            .presentation = @intFromEnum(instance.getPhysicalDeviceSurfaceSupportKHR(handle, @intCast(i), @enumFromInt(dummy_window.surface_handle)) catch .false) > 0,
        };
        inline for (@typeInfo(QueueType).@"enum".fields, 0..) |ef, j|
            if (@field(flags, ef.name))
                index_lists[j].append(@intCast(i));
    }
    //check for minimal reqired queues
    var any_flags: QueueConfiguration = .{};
    inline for (@typeInfo(QueueType).@"enum".fields, 0..) |ef, i| {
        // check if there are any queue families
        // at the index corresponding to that queue
        @field(any_flags, ef.name) = index_lists[i].list.items.len > 0;
    }
    if (!util.matchFlagStructs(
        QueueConfiguration,
        any_flags,
        minimal_required_queue_family_config,
    )) return VKError.MissingQueueType;

    //iterate through all the possible queue configurations score them and use the best one
    var non_empty_index_storage: [queue_type_count]usize = undefined;
    var count: usize = 0;
    //use this to avoid iterating through queue families that have no available queue
    for (&index_lists, 0..) |*l, i| {
        if (l.list.items.len > 0) {
            non_empty_index_storage[count] = i;
            count += 1;
        }
    }
    var max_score: i32 = std.math.minInt(i32);
    var current_queue_family_indices: [queue_type_count]u8 = @splat(0xff);

    var queue_family_indices: [queue_type_count]u8 = @splat(0xff);
    findBestQueueConfiguration(
        &queue_family_indices,
        index_lists,
        non_empty_index_storage[0..count],
        &current_queue_family_indices,
        0,
        &max_score,
    );
    return queue_family_indices;
}

const IndexList = struct {
    list: std.ArrayList(u8),
    buf: [max_queue_family_count]u8,
    pub fn init(self: *IndexList) void {
        self.list = .initBuffer(&self.buf);
    }
    pub fn append(self: *IndexList, i: u8) void {
        self.list.appendAssumeCapacity(i);
    }
};
fn findBestQueueConfiguration(
    out: *[queue_type_count]u8,
    index_lists: [queue_type_count]IndexList,
    non_empty_indices: []usize,
    current: *[queue_type_count]u8,
    depth: usize,
    max_score: *i32,
) void {
    if (depth == non_empty_indices.len) {
        const score = scoreQueueConfiguration(current);
        if (score > max_score.*) {
            max_score.* = score;
            //copy the best into the global storage
            out.* = current.*;
        }
        return;
    }
    const index = non_empty_indices[depth];
    for (index_lists[index].list.items) |value| {
        current[index] = value;
        findBestQueueConfiguration(
            out,
            index_lists,
            non_empty_indices,
            current,
            depth + 1,
            max_score,
        );
    }
}
fn scoreQueueConfiguration(configuration: []u8) i32 {
    var score: i32 = 0;
    inline for (queueConfigurationScoringRules) |rule| {
        const values: [2]u8 = .{
            configuration[@intFromEnum(rule[1][0])],
            configuration[@intFromEnum(rule[1][1])],
        };
        if (values[0] == values[1] and ~values[0] != 0) score += rule[0];
    }
    return score;
}
fn getPhysicalDeviceFeatures(handle: vk.PhysicalDevice) gpu.FeatureSet {
    const vk_features = instance.getPhysicalDeviceFeatures(handle);
    return .{
        .geometry_shaders = vk_features.geometry_shader != .false,
        .tessellation_shaders = vk_features.tessellation_shader != .false,
        .shader_float64 = vk_features.shader_float_64 != .false,
        .shader_int64 = vk_features.shader_int_64 != .false,
        .shader_int16 = vk_features.shader_int_16 != .false,
    };
}
const PhysicalDevice = struct {
    handle: vk.PhysicalDevice = .null_handle,
    queue_family_indices: [queue_type_count]u8 = @splat(0xff),
    name_storage: [max_name_len]u8 = @splat(0),
    name_len: usize = 0,
    features: gpu.FeatureSet = .{},
    type: vk.PhysicalDeviceType = .discrete_gpu,

    pub const max_name_len = 128;
    pub fn queueFamilyIndex(self: *const PhysicalDevice, queue_type: QueueType) u8 {
        return self.queue_family_indices[@intFromEnum(queue_type)];
    }
    pub fn format(self: PhysicalDevice, writer: *std.Io.Writer) !void {
        try writer.print("Physical Device({}){{\n", .{self.handle});
        try writer.print("Name: {s}\n", .{self.name_storage[0..self.name_len]});
        try writer.print("Family Queue Indices: {any}\n", .{self.queue_family_indices});
        try writer.print("Type: {}\n", .{self.type});
        try writer.print("Features: {{\n", .{});
        inline for (@typeInfo(gpu.Feature).@"enum".fields) |ef|
            try writer.print("\t{s} = {}\n", .{ ef.name, @field(self.features, ef.name) });
        try writer.print("}}", .{});
    }
};
fn checkExtensionPresence(required: []const [*:0]const u8, available: []const vk.ExtensionProperties) VKError!void {
    for (required) |re| { //chech for unavailable instance extensions
        if (!for (available) |ae| {
            if (huge.util.strEqlNullTerm(re, @ptrCast(@alignCast(&ae.extension_name)))) break true;
        } else false) return VKError.UnavailableExtension; //TODO: log missing extension name
    }
}
fn checkLayerPresence(required: []const [*:0]const u8, available: []const vk.LayerProperties) VKError!void {
    for (required) |rl| { //chech for unavailable instance extensions
        if (!for (available) |al| {
            if (huge.util.strEqlNullTerm(rl, @ptrCast(@alignCast(&al.layer_name)))) break true;
        } else false) return VKError.UnavailableLayer; //TODO: log missing layer name
    }
}

//=======================

pub const queue_type_count = @typeInfo(QueueType).@"enum".fields.len;
const QueueConfiguration = util.StructFromEnum(QueueType, bool, false, .@"packed");
const queueConfigurationScoringRules: []const std.meta.Tuple(&.{ i32, [2]QueueType }) = &.{
    .{ -150, .{ .graphics, .compute } },
    .{ -150, .{ .graphics, .transfer } },
    .{ 100, .{ .graphics, .presentation } },
    .{ -90, .{ .compute, .transfer } },
    .{ 30, .{ .sparse_binding, .transfer } },
};
pub const minimal_required_queue_family_config: QueueConfiguration = .{
    .graphics = true,
    .presentation = true,
    .transfer = true,
    .compute = true,
};
pub const QueueType = enum(u8) { graphics, presentation, compute, transfer, sparse_binding, protected, video_decode, video_encode };

//=======================
fn getStageFlags(stage_info: hgsl.StageInfo) vk.ShaderStageFlags {
    return .{
        .vertex_bit = stage_info == .vertex,
        .fragment_bit = stage_info == .fragment,
    };
}
fn castPrimitiveTopology(primitive: gpu.PrimitiveTopology) vk.PrimitiveTopology {
    return switch (primitive) {
        .triangle => .triangle_list,
        .triangle_strip => .triangle_strip,
        .triangle_fan => .triangle_fan,
        .line => .line_list,
        .line_strip => .line_strip,
        .point => .point_list,
    };
}
pub const loader = &struct {
    pub fn l(i: vk.Instance, name: [*:0]const u8) ?glfw.VKproc {
        return glfw.getInstanceProcAddress(@intFromEnum(i), name);
    }
}.l;
fn castVersion(vk_version: vk.Version) Version {
    return .{
        .major = vk_version.major,
        .minor = vk_version.minor,
    };
}
fn toVulkanVersion(version: Version) u32 {
    return @bitCast(vk.makeApiVersion(0, @truncate(version.major), @truncate(version.minor), 0));
}
const glfw = huge.Window.glfw;
const Error = gpu.Error;
const Pipeline = gpu.Pipeline;
const ShaderModule = gpu.ShaderModule;
const RenderTarget = gpu.RenderTarget;
const Buffer = gpu.Buffer;
const BufferUsage = gpu.BufferUsage;
const WindowContext = gpu.WindowContext;
const ClearValue = gpu.ClearValue;
const Version = huge.Version;
const Allocator = std.mem.Allocator;
const List = std.ArrayList;
const VKError = error{
    OutOfMemory,

    UnavailableExtension,
    UnsupportedApiVersion,
    UnavailableLayer,

    InstanceInitializationFailure,
    PhysicalDeviceInitializationFailure,
    DummyWindowCreationFailure,
    MissingQueueType,

    LogicalDeviceInitializationFailure,
};
fn versionBackend(version: Version) gpu.Backend {
    return .{
        .api = .vulkan,
        .api_version = version,
        .deinit = &deinit,

        .draw = &draw,
        .bindVertexBuffer = &bindVertexBuffer,
        .bindIndexBuffer = &bindIndexBuffer,
        .beginRendering = &beginRendering,
        .endRendering = &endRendering,

        .pipelinePushConstant = pipelinePushConstant,
        .createPipeline = &createPipeline,
        .createShaderModulePath = &createShaderModulePath,
        .destroyShaderModule = &destroyShaderModule,

        .loadBuffer = &loadBuffer,
        .mapBuffer = &mapBuffer,
        .unmapBuffer = &unmapBuffer,
        .createBuffer = &createBuffer,
        .destroyBuffer = &destroyBuffer,

        .renderTargetSize = &renderTargetSize,

        .updateWindowContext = &updateWindowContext,
        .getWindowRenderTarget = &getWindowRenderTarget,
        .createWindowContext = &createWindowContext,
        .destroyWindowContext = &destroyWindowContext,
    };
}
