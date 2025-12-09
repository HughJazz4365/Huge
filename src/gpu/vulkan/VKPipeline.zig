const std = @import("std");
const vk = @import("vk.zig");
const vulkan = @import("vulkan.zig");
const huge = @import("../../root.zig");
const util = huge.util;
const hgsl = @import("hgsl");
pub const VKPipeline = @This();

const stack_vertex_attributes = 16;
handle: vk.Pipeline = .null_handle,

type: PipelineType = undefined,
entry_point_infos: [max_stages]hgsl.EntryPointInfo = @splat(.{}),

pub const max_stages = @typeInfo(GraphicsPipelineSource).@"struct".fields.len;

pub fn cmdSetPropertiesStruct(
    self: VKPipeline,
    cmd: *const vulkan.VKCommandBuffer,
    @"struct": anytype,
) void {
    const S = @TypeOf(@"struct");
    const st = @typeInfo(S).@"struct";
    if (st.is_tuple) @compileError("struct must not be tuple");
    inline for (st.fields) |sf| {
        self.cmdSetProperty(cmd, sf.name, &@field(@"struct", sf.name));
    }
}

pub fn cmdSetProperty(
    self: VKPipeline,
    cmd: *const vulkan.VKCommandBuffer,
    name: []const u8,
    value: anytype,
) void {
    const T = if (@typeInfo(@TypeOf(value)) == .pointer) @typeInfo(@TypeOf(value)).pointer.child else @TypeOf(value);
    const ptr: *const T = if (@typeInfo(@TypeOf(value)) == .pointer) value else &value;
    switch (T) {
        huge.Transform => cmdPushConstant(self, cmd, name, &ptr.modelMat()),
        huge.Camera => cmdPushConstant(self, cmd, name, &ptr.viewProjectionMat()),
        // Buffer => b.pipelineSetOpaqueUniform(self, name, 0, 0, .buffer, @intFromEnum(value)),
        // Texture => b.pipelineSetOpaqueUniform(self, name, 0, 0, .texture, @intFromEnum(value)),
        else => cmdPushConstant(self, cmd, name, @ptrCast(@alignCast(ptr))),
    }
    self.cmdPushConstant(cmd, name, @ptrCast(@alignCast(value)));
}
pub fn cmdPushConstant(
    self: VKPipeline,
    cmd: *const vulkan.VKCommandBuffer,
    name: []const u8,
    bytes: []const u8,
) void {
    huge.dassert(cmd.queue_type == .graphics or cmd.queue_type == .compute);
    if (!cmd.state.recording) return;

    const current_cmd = cmd.handles[vulkan.fif_index];

    var offsets: [max_stages]u32 = undefined;
    var offset_count: u32 = 0;
    const stage_flags = self.getPushConstantStageMask();
    for (&self.entry_point_infos) |ep_info| {
        pcloop: for (ep_info.push_constant_mappings) |pc| {
            if (util.strEql(name, pc.name)) {
                if (pc.offset >= vulkan.max_push_constant_bytes)
                    continue; //fully out of bounds

                //dont repeat cmdPushConstants call with the same offset
                for (offsets[0..offset_count]) |o| if (o == pc.offset) continue :pcloop;

                offsets[offset_count] = pc.offset;
                offset_count += 1;

                const size = @min(pc.size, bytes.len * 8);
                const trimmed_size = size - ((pc.offset + size) -| vulkan.max_push_constant_bytes);
                // std.debug.print("PC: size: {d}, offset: {d}\n", .{ trimmed_size, pc.offset });
                if (trimmed_size != 0) vulkan.device.cmdPushConstants(
                    current_cmd,
                    self.getLayout() catch unreachable,
                    stage_flags,
                    pc.offset,
                    trimmed_size,
                    @ptrCast(bytes.ptr),
                );
            }
        }
        //log if didnt found
    }
    // const offset: u32 = 0;
    // const trimmed_size = bytes.len;
    // const stage_flags: vk.ShaderStageFlags = .{};
    // vulkan.device.cmdPushConstants(
    //     current_cmd,
    //     self.getLayout() catch unreachable,
    //     stage_flags,
    //     offset,
    //     trimmed_size,
    //     @ptrCast(bytes.ptr),
    // );
}

pub fn createFiles(io: std.Io, source: PipelineSource) Error!VKPipeline {
    const StageCompilationInfo = struct {
        path: []const u8 = "",
        entry_point: []const u8 = "",
        same: usize = max_stages,
        result: hgsl.Result = .{},
        shader_module: vk.ShaderModule = .null_handle,
    };
    var compilation_info: [max_stages]StageCompilationInfo = @splat(.{});
    var futures: [max_stages]std.Io.Future(anyerror!hgsl.Result) = undefined;
    var single_index: usize = max_stages;

    if (source == .graphics) {
        const struct_field = @typeInfo(GraphicsPipelineSource).@"struct".fields;
        inline for (struct_field, 0..) |sf, i| {
            if (i == 0 or @field(source.graphics, sf.name) != null) {
                const stage_source = if (i == 0) @field(source.graphics, sf.name) else @field(source.graphics, sf.name).?;
                if (inline for (0..i) |j| {
                    if (j == 0 or @field(source.graphics, struct_field[j].name) != null) {
                        const prev_stage_source = if (j == 0) @field(source.graphics, struct_field[j].name) else @field(source.graphics, struct_field[j].name).?;
                        if (util.strEql(stage_source.path, prev_stage_source.path)) {
                            compilation_info[i].same = j;
                            compilation_info[i].entry_point = stage_source.entry_point;
                            break false;
                        }
                    }
                } else true) {
                    if (single_index == max_stages) single_index = i;
                    compilation_info[i].path = stage_source.path;
                    compilation_info[i].entry_point = stage_source.entry_point;
                }
            }
        }
    } else {
        compilation_info[0] = .{ .path = source.compute.path };
        single_index = 0;
    }

    if (single_index != max_stages) {
        compilation_info[single_index].result =
            vulkan.shader_compiler.compileFile(io, std.heap.page_allocator, compilation_info[single_index].path) catch
                return Error.ShaderCompilationError;
    } else {
        for (&compilation_info, &futures) |*tc, *f| {
            f.* = io.async(hgsl.Compiler.compileFile, .{
                &vulkan.shader_compiler,
                io,
                std.heap.page_allocator,
                tc.path,
            });
        }
        for (&compilation_info, &futures) |*tc, *f| {
            tc.result = f.await(io) catch
                return Error.ShaderCompilationError;
        }
    }

    var pipeline: VKPipeline = .{ .type = std.meta.activeTag(source) };
    for (&compilation_info, 0..max_stages) |*tc, i| if (tc.entry_point.len != 0) {
        // create shader modules
        tc.shader_module = if (tc.same != max_stages)
            compilation_info[tc.same].shader_module
        else
            vulkan.device.createShaderModule(&.{
                .code_size = tc.result.bytes.len,
                .p_code = @ptrCast(@alignCast(tc.result.bytes)),
            }, vulkan.vka) catch |err|
                return vulkan.wrapMemoryErrors(err);

        // check entry point stages
        const stage: hgsl.Stage = if (source == .graphics) @enumFromInt(i) else .compute;
        const entry_point_infos = if (tc.same == max_stages) tc.result.entry_point_infos else compilation_info[tc.same].result.entry_point_infos;
        for (entry_point_infos) |*epi| {
            if (util.strEql(tc.entry_point, epi.name)) {
                if (std.meta.activeTag(epi.stage_info) != stage)
                    return Error.WrongShaderEntryPointType;
                pipeline.entry_point_infos[i] = epi.*;
                for (0..i) |j| if (pipeline.entry_point_infos[i - j - 1].name.len > 0) {
                    const index = i - j - 1;
                    for (pipeline.entry_point_infos[i].inputMappings()) |im| {
                        const @"type" = for (pipeline.entry_point_infos[index].outputMappings()) |om| {
                            if (om.location == im.location) break om.type;
                        } else return Error.PipelineStageIOMismatch;
                        if (!im.type.eql(@"type")) return Error.PipelineStageIOMismatch;
                    }
                };

                //mark not to free
                break;
            }
        } else return Error.MissingShaderEntryPoint;
    };
    defer for (&compilation_info) |ci| if (ci.same == max_stages and ci.path.len != 0) {
        vulkan.device.destroyShaderModule(ci.shader_module, vulkan.vka);
    };

    var stage_count: u32 = 0;
    var stage_create_infos: [max_stages]vk.PipelineShaderStageCreateInfo = undefined;
    for (pipeline.entry_point_infos, &compilation_info) |epi, ci| if (epi.name.len > 0) {
        stage_create_infos[stage_count] = .{
            .flags = .{},
            .stage = getVKShaderStageFlags(std.meta.activeTag(epi.stage_info)),
            .module = ci.shader_module,
            .p_name = epi.name.ptr,
        };
        stage_count += 1;
    };

    if (pipeline.type == .graphics) {
        const vert_ep_info = pipeline.entry_point_infos[@intFromEnum(ShaderStage.vertex)];
        var vad_storage: [stack_vertex_attributes]vk.VertexInputAttributeDescription = undefined;
        const vertex_attribute_descriptions: []vk.VertexInputAttributeDescription =
            if (vert_ep_info.input_count > stack_vertex_attributes)
                try vulkan.arena.allocator().alloc(vk.VertexInputAttributeDescription, vert_ep_info.input_count)
            else
                &vad_storage;

        const frag_ep_info: ?hgsl.EntryPointInfo = if (pipeline.entry_point_infos[@intFromEnum(ShaderStage.fragment)].name.len > 0)
            pipeline.entry_point_infos[@intFromEnum(ShaderStage.fragment)]
        else
            null;

        //TODO: different vertex attributes layout
        // [all_positions] [all_normals]...
        // as opposed to
        // [[pos][normal]] [[pos2][normal2]]

        //calculate offsets and stride of vertex attributes
        var stride: u32 = 0;
        for (vert_ep_info.inputMappings(), 0..) |im, i| {
            vertex_attribute_descriptions[i] = .{
                .location = im.location,
                .binding = 0,
                .format = formatFromIOType(im.type),
                .offset = stride,
            };
            stride += im.size;
        }
        const vertex_input_state: vk.PipelineVertexInputStateCreateInfo = .{
            .vertex_attribute_description_count = vert_ep_info.input_count,
            .p_vertex_attribute_descriptions = vertex_attribute_descriptions.ptr,
            .vertex_binding_description_count = 1,
            .p_vertex_binding_descriptions = &.{.{
                .binding = 0,
                .stride = stride,
                .input_rate = .vertex,
            }},
        };
        _ = vulkan.device.createGraphicsPipelines(.null_handle, 1, &.{.{
            .p_next = if (frag_ep_info) |frag| &vk.PipelineRenderingCreateInfo{
                .view_mask = 0,
                .color_attachment_count = frag.output_count,
                .p_color_attachment_formats = &.{.b8g8r8a8_unorm},
                .depth_attachment_format = .undefined,
                .stencil_attachment_format = .undefined,
            } else null,
            .stage_count = stage_count,
            .p_stages = &stage_create_infos,
            .p_vertex_input_state = &vertex_input_state,
            .p_input_assembly_state = &.{
                .topology = .triangle_list,
                .primitive_restart_enable = .false,
            },
            // p_tessellation_state: ?*const PipelineTessellationStateCreateInfo = null,
            .p_viewport_state = if (frag_ep_info) |frag| &.{
                .viewport_count = frag.output_count,
                .scissor_count = frag.output_count,
            } else null,

            .p_rasterization_state = &.{
                .depth_clamp_enable = .false,
                .rasterizer_discard_enable = .false,
                .polygon_mode = .fill,
                .line_width = 1,
                .cull_mode = .{},
                .front_face = .clockwise,
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
            .p_color_blend_state = if (frag_ep_info) |frag| &.{
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
                .dynamic_state_count = @intCast(dynamic_states.len),
                .p_dynamic_states = dynamic_states.ptr,
            },
            .layout = try pipeline.getLayout(),

            .subpass = 0,
            .base_pipeline_handle = .null_handle,
            .base_pipeline_index = -1,
        }}, vulkan.vka, @ptrCast(&pipeline.handle)) catch |err|
            return vulkan.wrapMemoryErrors(err);
        if (vert_ep_info.input_count > stack_vertex_attributes) {
            vulkan.arena.allocator().free(vertex_attribute_descriptions);
        }
    }

    //free all the unused memory

    return pipeline;
}
fn getPushConstantStageMask(self: VKPipeline) vk.ShaderStageFlags {
    if (self.type == .graphics) {
        var mask: vk.Flags = 0;
        for (0..max_stages) |i|
            mask |= @as(vk.Flags, @intFromBool(self.entry_point_infos[i].push_constant_mappings.len > 0)) << @intCast(i);

        return @bitCast(mask);
    } else return .{ .compute_bit = self.entry_point_infos[0].push_constant_mappings.len > 0 };
}
fn getLayout(self: VKPipeline) Error!vk.PipelineLayout {
    var index: usize = 0;
    var count: u32 = 0;
    var push_constant_ranges: [max_stages]vk.PushConstantRange = undefined;
    if (self.type == .graphics) {
        for (0..max_stages) |i|
            index |= @as(usize, @intFromBool(self.entry_point_infos[i].push_constant_mappings.len > 0)) << @intCast(i);

        if (index > 0) {
            push_constant_ranges[0] = .{
                .stage_flags = @bitCast(@as(vk.Flags, @intCast(index))),
                .offset = 0,
                .size = vulkan.max_push_constant_bytes,
            };
            count = 1;
        }
    } else if (self.entry_point_infos[0].push_constant_mappings.len > 0) {
        index = 1 << max_stages;
        push_constant_ranges[0] = .{
            .stage_flags = .{ .compute_bit = true },
            .offset = 0,
            .size = vulkan.max_push_constant_bytes,
        };
        count = 1;
    }

    if (vulkan.pipeline_layouts[index] == .null_handle) {
        vulkan.pipeline_layouts[index] = vulkan.device.createPipelineLayout(&.{
            // set_layout_count: u32 = 0,
            // p_set_layouts: ?[*]const DescriptorSetLayout = null,
            .push_constant_range_count = count,
            .p_push_constant_ranges = &push_constant_ranges,
        }, vulkan.vka) catch |err|
            return vulkan.wrapMemoryErrors(err);
    }

    return vulkan.pipeline_layouts[index];
}

pub const PipelineSource = union(PipelineType) {
    graphics: GraphicsPipelineSource,
    compute: PipelineStageSource,
};
pub const GraphicsPipelineSource = struct {
    vertex: PipelineStageSource,
    tesselation_control: ?PipelineStageSource = null,
    tesselation_evaluation: ?PipelineStageSource = null,
    geometry: ?PipelineStageSource = null,
    fragment: ?PipelineStageSource = null,
};
pub const PipelineType = enum { graphics, compute };
pub const PipelineStageSource = struct {
    path: []const u8,
    entry_point: []const u8,
};

fn formatFromIOType(io_type: hgsl.IOType) vk.Format {
    return if (io_type == .scalar) switch (io_type.scalar) {
        .f32 => .r32_sfloat,
        .i32 => .r32_sint,
        .u32 => .r32_uint,
        .f64 => .r64_sfloat,
        .i64 => .r64_sint,
        .u64 => .r64_uint,
    } else switch (io_type.vector.len) {
        ._2 => switch (io_type.vector.component) {
            .f32 => .r32g32_sfloat,
            .i32 => .r32g32_sint,
            .u32 => .r32g32_uint,
            .f64 => .r64g64_sfloat,
            .i64 => .r64g64_sint,
            .u64 => .r64g64_uint,
        },
        ._3 => switch (io_type.vector.component) {
            .f32 => .r32g32b32_sfloat,
            .i32 => .r32g32b32_sint,
            .u32 => .r32g32b32_uint,
            .f64 => .r64g64b64_sfloat,
            .i64 => .r64g64b64_sint,
            .u64 => .r64g64b64_uint,
        },
        ._4 => switch (io_type.vector.component) {
            .f32 => .r32g32b32a32_sfloat,
            .i32 => .r32g32b32a32_sint,
            .u32 => .r32g32b32a32_uint,
            .f64 => .r64g64b64a64_sfloat,
            .i64 => .r64g64b64a64_sint,
            .u64 => .r64g64b64a64_uint,
        },
    };
}
fn getVKShaderStageFlags(stage: ShaderStage) vk.ShaderStageFlags {
    return @bitCast(@as(vk.Flags, 1) << @truncate(@intFromEnum(stage)));
}
pub const ShaderStage = hgsl.Stage;
const Error = vulkan.Error;
//::: dynamic state unused for now
// blend_constants = 4,
// depth_bounds = 5,
// stencil_compare_mask = 6,
// stencil_write_mask = 7,
// stencil_reference = 8,
// viewport_with_count = 1000267003,
// scissor_with_count = 1000267004,
// vertex_input_binding_stride = 1000267005,
// depth_bounds_test_enable = 1000267009,
// stencil_test_enable = 1000267010,
// rasterizer_discard_enable = 1000377001,
// depth_bias_enable = 1000377002,
const dynamic_states: []const vk.DynamicState = &.{
    .viewport,
    .scissor,
    .line_width,
    .depth_bias,
    .cull_mode,
    .front_face,
    .primitive_topology,
    .depth_test_enable,
    .depth_write_enable,
    .depth_compare_op,
    // .stencil_op,
};
