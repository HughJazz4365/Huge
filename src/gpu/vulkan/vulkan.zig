const std = @import("std");
const hgsl = @import("hgsl");
const huge = @import("../../root.zig");
const math = huge.math;
const util = huge.util;
const glfw = huge.Window.glfw;

const vk = @import("vk.zig");
const vulkan_alloc = @import("vulkanAllocation.zig");
pub var bwp: vk.BaseWrapper = undefined;
pub var iwp: vk.InstanceWrapper = undefined;
pub var dwp: vk.DeviceWrapper = undefined;

pub var arena: std.heap.ArenaAllocator = undefined;
var thread_safe_allocator: std.heap.ThreadSafeAllocator = undefined;
const pr = std.debug.print;

//=========|constants|==========

pub const timeout: u64 = std.time.ns_per_s * 5;
pub const max_push_constant_bytes = 128;
pub const mfif = VKWindowContext.mfif;

//===========|state|============

var allocation_callbacks: vk.AllocationCallbacks = undefined;
pub var vka: ?*vk.AllocationCallbacks = null;
pub var api_version: vk.Version = undefined;

pub var instance: vk.InstanceProxy = undefined;

pub var physical_devices: [3]PhysicalDevice = @splat(.{});
pub var valid_physical_device_count: usize = 0;
var current_physical_device_index: usize = 0;
pub var physical_device_memory_properties: vk.PhysicalDeviceMemoryProperties = undefined;

pub var device: vk.DeviceProxy = undefined;

pub var queues: [queue_type_count]vk.Queue = @splat(.null_handle);
// var command_pools: [queue_type_count]vk.CommandPool = @splat(.null_handle);

pub var fif_index: u32 = 0;

var shader_error_writer_buffer: [256]u8 = undefined;
var shader_error_writer: std.fs.File.Writer = undefined;
var shader_compiler: hgsl.Compiler = undefined;

//=========|resources|==========

var heap_storage: [(4 * 1024) / MemoryHeap.general_size]MemoryHeap = undefined;
pub var heaps: List(MemoryHeap) = .initBuffer(&heap_storage);

const max_threads = 4;
var command_pools: [mfif][max_threads][queue_type_count]vk.CommandPool = @splat(@splat(@splat(.null_handle)));

var pipeline_layout: [1 << VKPipeline.max_stages]vk.PipelineLayout = @splat(.null_handle);

//==============================

pub inline fn pd() PhysicalDevice {
    return physical_devices[current_physical_device_index];
}

pub inline fn queue(queue_type: QueueType) vk.Queue {
    return queues[@intFromEnum(queue_type)];
}
pub inline fn qfi(queue_type: QueueType) QFI {
    return pd().queue_family_indices[@intFromEnum(queue_type)];
}

//=====|command recording|======

pub fn cmdDraw(cmd: *VKCommandBuffer, pipeline: VKPipeline, params: DrawParams) void {
    huge.dassert(cmd.queue_type == .graphics);

    const current_cmd = cmd.handles[fif_index];
    cmdBindPipeline(cmd, pipeline);
    // if (cmd.bound_pipeline != pipeline) {
    //     cmd.bound_pipeline = pipeline;
    //      device.cmdBi
    // }

    if (params.mode == .indexed) {
        device.cmdDrawIndexed(
            current_cmd,
            params.count,
            params.instance_count,
            params.offset,
            params.indexed_vertex_offset,
            params.instance_offset,
        );
    } else device.cmdDraw(
        current_cmd,
        params.count,
        params.instance_count,
        params.offset,
        params.instance_offset,
    );
}
fn cmdBindPipeline(cmd: *VKCommandBuffer, pipeline: VKPipeline) void {
    // if pipeline is graphics assert that cmd.queue_type == .graphics
    // same with compute
    if (cmd.state.bound_pipeline == pipeline.handle) return;
    device.cmdBindPipeline(
        cmd.handles[fif_index],
        .graphics,
        pipeline.handle,
    );
    cmd.state.bound_pipeline = pipeline.handle;
}
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
pub fn cmdBeginRenderingToWindow(cmd: *VKCommandBuffer, window_ctx: *VKWindowContext, clear_value: ClearValue) void {
    huge.dassert(cmd.queue_type == .graphics);

    if (cmd.state.rendering or !cmd.state.recording) return;
    const current_cmd = cmd.handles[fif_index];
    defer cmd.state.rendering = true;

    device.cmdSetScissor(current_cmd, 0, 1, &.{.{
        .extent = window_ctx.extent,
        .offset = .{ .x = 0, .y = 0 },
    }});

    device.cmdSetViewport(current_cmd, 0, 1, &.{.{
        .x = 0,
        .y = 0,
        .width = @floatFromInt(window_ctx.extent.width),
        .height = @floatFromInt(window_ctx.extent.width),
        .min_depth = 0,
        .max_depth = 1,
    }});

    device.cmdBeginRendering(current_cmd, &.{
        .render_area = .{
            .offset = .{ .x = 0, .y = 0 },
            .extent = window_ctx.extent,
        },
        .layer_count = 1,
        .view_mask = 0,
        .color_attachment_count = 1,
        .p_color_attachments = &.{.{
            .image_view = window_ctx.image_views[window_ctx.acquired_image_index],
            .image_layout = .attachment_optimal,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{
                .color = if (clear_value.color) |cc|
                    .{ .float_32 = @as(*const [4]f32, @ptrCast(&cc)).* }
                else
                    .{ .float_32 = @splat(0) },
            },

            .resolve_image_layout = .undefined,
            .resolve_mode = .{},
        }},
    });
}
pub fn cmdEndRendering(cmd: *VKCommandBuffer) void {
    huge.dassert(cmd.queue_type == .graphics);

    if (!cmd.state.rendering or !cmd.state.recording) return;
    device.cmdEndRendering(cmd.handles[fif_index]);
    cmd.state.rendering = false;
}
pub const ClearValue = struct {
    color: ?math.vec4 = null,
};

//=======|presentation|=========

/// ends the command buffer recording and handles
/// submitting it to the presentation queue
pub fn present(cmd: *VKCommandBuffer, window_ctx: *VKWindowContext) Error!void {
    huge.dassert(cmd.queue_type == .presentation or cmd.queue_type == .graphics);

    if (!cmd.state.recording) return;

    if (qfi(.presentation) != qfi(.graphics)) {
        @panic("submit graphics first then start recording into new cmd");
    }
    const current_cmd = cmd.handles[fif_index];

    if (~window_ctx.acquired_image_index == 0)
        return Error.SwapchainImageNotAcquired;

    defer window_ctx.acquired_image_index = ~@as(u32, 0);

    cmdEndRendering(cmd);

    device.cmdPipelineBarrier2(current_cmd, &.{
        // vk.DependencyFlags = .{},
        .image_memory_barrier_count = 1,
        .p_image_memory_barriers = &.{.{
            .src_stage_mask = .{ .all_commands_bit = true },
            .dst_stage_mask = .{},

            .src_access_mask = .{ .color_attachment_write_bit = true },
            .dst_access_mask = .{},

            .old_layout = .undefined,
            .new_layout = if (qfi(.graphics) == qfi(.presentation))
                .present_src_khr
            else
                .shared_present_khr,

            .src_queue_family_index = qfi(.graphics),
            .dst_queue_family_index = qfi(.presentation),
            .image = window_ctx.images[window_ctx.acquired_image_index],
            .subresource_range = .{
                .aspect_mask = .{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        }},
    });
    try cmd.end();
    device.queueSubmit2(
        queue(.presentation),
        1,
        &.{.{
            .command_buffer_info_count = 1,
            .p_command_buffer_infos = &.{.{ .command_buffer = current_cmd, .device_mask = 0 }},

            .wait_semaphore_info_count = 1,
            .p_wait_semaphore_infos = &.{.{
                .semaphore = window_ctx.acquire_semaphores[fif_index],
                .value = 0,
                .device_index = 0,
            }},
            .signal_semaphore_info_count = 1,
            .p_signal_semaphore_infos = &.{.{
                .semaphore = window_ctx.submit_semaphores[window_ctx.acquired_image_index],
                .value = 0,
                .device_index = 0,
            }},
        }},
        window_ctx.fences[fif_index],
    ) catch |err| return wrapMemoryErrors(err);

    _ = device.queuePresentKHR(queue(.presentation), &.{
        .wait_semaphore_count = 1,
        .p_wait_semaphores = &.{window_ctx.submit_semaphores[window_ctx.acquired_image_index]},
        .swapchain_count = 1,
        .p_swapchains = &.{window_ctx.swapchain},
        .p_image_indices = &.{window_ctx.acquired_image_index},
    }) catch |err|
        switch (err) {
            error.OutOfDateKHR => {
                @panic("recreate swapchain");
                // self.request_recreate = true;
            },
            else => return Error.PresentationError,
        };
}
pub fn acquireSwapchainImage(window_ctx: *VKWindowContext) Error!void {
    //maybe we should have separate fif_index for each window context
    if (~window_ctx.acquired_image_index != 0) return;

    _ = device.waitForFences(1, &.{window_ctx.fences[fif_index]}, .true, timeout) catch |err|
        return wrapMemoryErrors(err);
    device.resetFences(1, &.{window_ctx.fences[fif_index]}) catch |err|
        return wrapMemoryErrors(err);
    window_ctx.acquired_image_index = (device.acquireNextImageKHR(
        window_ctx.swapchain,
        timeout,
        window_ctx.acquire_semaphores[fif_index],
        .null_handle,
    ) catch |err| switch (err) {
        error.OutOfDateKHR => @panic("recreate swapchain"),
        else => return wrapMemoryErrors(err),
    }).image_index;
}

//=====|resource creation|======

pub fn allocateCommandBuffer(thread_id: ThreadID, queue_type: QueueType) Error!VKCommandBuffer {
    const pool = try getCommandPool(thread_id, queue_type);
    var handles: [mfif]vk.CommandBuffer = @splat(.null_handle);
    device.allocateCommandBuffers(&.{
        .command_pool = pool,
        .level = .primary,
        .command_buffer_count = mfif,
    }, &handles) catch |err| return wrapMemoryErrors(err);
    return .{ .handles = handles, .queue_type = queue_type };
}
pub const VKCommandBuffer = struct {
    handles: [mfif]vk.CommandBuffer = @splat(.null_handle),
    queue_type: QueueType,

    state: CommandBufferState = .{},

    pub fn begin(self: *VKCommandBuffer) Error!void {
        if (self.state.recording) return;
        device.beginCommandBuffer(self.handles[fif_index], &.{}) catch |err| return wrapMemoryErrors(err);
        self.state.recording = true;
    }
    pub fn end(self: *VKCommandBuffer) Error!void {
        if (!self.state.recording) return;
        cmdEndRendering(self);
        device.endCommandBuffer(self.handles[fif_index]) catch |err| return wrapMemoryErrors(err);
        self.state = .{};
    }
    const CommandBufferState = packed struct {
        recording: bool = false,
        rendering: bool = false,
        bound_pipeline: vk.Pipeline = .null_handle,
    };
};

fn getCommandPool(thread_id: ThreadID, queue_type: QueueType) Error!vk.CommandPool {
    const ptr = &command_pools[fif_index][@intFromEnum(thread_id)][@intFromEnum(queue_type)];
    if (ptr.* == .null_handle) {
        const pool = try createCommandPool(queue_type);
        for (0..queue_type_count) |i| {
            if (pd().queue_family_indices[i] == qfi(queue_type))
                command_pools[fif_index][@intFromEnum(thread_id)][i] = pool;
        }
    }
    return ptr.*;
}
fn createCommandPool(queue_type: QueueType) Error!vk.CommandPool {
    return device.createCommandPool(&.{
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = qfi(queue_type),
    }, vka) catch |err| wrapMemoryErrors(err);
}

//======|initialization|========

pub fn initAdditionalThreadResources(out: []ThreadID) Error!void {
    for (out, 0..) |*o, i| {
        o.* = if (i >= max_threads) .main else @enumFromInt(i + 1);
    }
}
pub const ThreadID = enum(u32) { main = 0, _ };

pub fn init(allocator: Allocator, create_queue_configuration: QueueConfiguration) Error!void {
    const vkinit = @import("vulkanInit.zig");
    arena = .init(allocator);
    thread_safe_allocator = .{ .child_allocator = arena.allocator() };

    allocation_callbacks = vkinit.getArenaAllocationCallbacks(&arena);
    // vka = &allocation_callbacks;

    bwp = .load(loader);
    const minimal_vulkan_version: vk.Version = .{ .major = 1, .minor = 3 };
    const layers: []const [*:0]const u8 = if (huge.zigbuiltin.mode == .Debug) &.{
        "VK_LAYER_KHRONOS_validation",
        // "VK_LAYER_LUNARG_api_dump",
    } else &.{};
    instance = try vkinit.initInstance(minimal_vulkan_version, layers, &.{});

    var extension_name_buf: [10][*:0]const u8 = undefined;
    var device_extension_list: List([*:0]const u8) = .initBuffer(&extension_name_buf);

    device_extension_list.appendAssumeCapacity(vk.extensions.khr_swapchain.name);
    current_physical_device_index = try vkinit.initPhysicalDevices(
        minimal_vulkan_version,
        device_extension_list.items,
        create_queue_configuration,
    );

    physical_device_memory_properties = instance.getPhysicalDeviceMemoryProperties(pd().handle);
    try vkinit.initLogicalDeviceAndQueues(layers, device_extension_list.items, create_queue_configuration);
    pr("{f}\n", .{pd()});

    shader_error_writer = std.fs.File.stdout().writer(&shader_error_writer_buffer);
    shader_compiler = .new(arena.allocator(), &shader_error_writer.interface, .{
        .target_env = .vulkan,
        .spirv_version = .{ .major = 1, .minor = 6 },
        .optimize = .none, //.speed
        .max_push_constant_buffer_size = max_push_constant_bytes,
    });
}

pub fn deinit() void {
    defer arena.deinit();
    // defer instance.destroyInstance(vka);
    // defer device.destroyDevice(vka);
    // free command pools
}

//==============================

pub const PhysicalDevice = struct {
    pub const qfi_null: QFI = 0xff;
    handle: vk.PhysicalDevice = .null_handle,
    queue_family_indices: [queue_type_count]QFI = @splat(qfi_null),
    name_storage: [max_name_len]u8 = @splat(0),
    name_len: usize = 0,
    features: FeatureSet = .{},
    type: vk.PhysicalDeviceType = .discrete_gpu,

    pub const max_name_len = 128;

    //     pub fn getUniqueQFIIndex(self: *const PhysicalDevice, queue_type: QueueType) usize {
    //         const qfi = self.queueFamilyIndex(queue_type);
    //         var unique_qfi: [queue_type_count]u8 = @splat(0xff);
    //         var count: usize = 0;

    //         return for (&self.queue_family_indices) |q| {
    //             if (q == qfi) break count;
    //             for (unique_qfi[0..count]) |u| (if (u == q) break) else {
    //                 unique_qfi[count] = q;
    //                 count += 1;
    //             }
    //         } else unreachable;
    //     }
    pub fn format(self: PhysicalDevice, writer: *std.Io.Writer) !void {
        try writer.print("Physical Device({}){{\n", .{self.handle});
        try writer.print("Name: {s}\n", .{self.name_storage[0..self.name_len]});
        try writer.print("Family Queue Indices: {any}\n", .{self.queue_family_indices});
        try writer.print("Type: {}\n", .{self.type});
        try writer.print("Features: {{\n", .{});
        inline for (@typeInfo(Feature).@"enum".fields) |ef|
            try writer.print("\t{s} = {}\n", .{ ef.name, @field(self.features, ef.name) });
        try writer.print("}}", .{});
    }
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

pub const queue_type_count = util.enumLen(QueueType);
pub const QueueConfiguration = util.StructFromEnum(QueueType, bool, false, .@"packed");
pub const QueueType = enum(u8) { graphics, presentation, compute, transfer, sparse_binding, video_decode, video_encode };
pub const QFI = u8;
fn wrapMemoryErrors(err: anyerror) Error {
    return if (err == error.OutOfDeviceMemory) Error.OutOfDeviceMemory else Error.OutOfMemory;
}

pub const loader = &struct {
    pub fn l(i: vk.Instance, name: [*:0]const u8) ?glfw.VKproc {
        return glfw.getInstanceProcAddress(@intFromEnum(i), name);
    }
}.l;

//==============================

const Allocator = std.mem.Allocator;
const List = std.ArrayList;
pub const VKPipeline = @import("VKPipeline.zig");
pub const VKWindowContext = @import("VKWindowContext.zig");
const MemoryHeap = vulkan_alloc.MemoryHeap;
const MemoryFlags = vulkan_alloc.MemoryFlags;
const DeviceAllocation = vulkan_alloc.DeviceAllocation;
const allocateDeviceMemory = vulkan_alloc.allocateDeviceMemory;

pub const Error = error{
    InitializationFailure,
    UnsupportedApiVersion,

    UnavailableExtension,
    UnavailableLayer,
    PhysicalDeviceInitializationFailure,
    NoCompatiblePhysicalDevices,
    DummyWindowCreationFailure,
    DeviceInitializationFailure,
    WindowContextCreationError,

    OutOfMemory,
    OutOfDeviceMemory,

    SwapchainImageNotAcquired,
    PresentationError,
};
