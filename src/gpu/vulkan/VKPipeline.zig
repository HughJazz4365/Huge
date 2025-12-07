const vk = @import("vk.zig");
const vulkan = @import("vulkan.zig");
pub const VKPipeline = @This();

handle: vk.Pipeline = .null_handle,

type: PipelineType = undefined,
sources: [max_stages]PipelineStageSource = undefined,
mask: StageMask = 0,

pub const max_stages = @typeInfo(GraphicsPipelineSource).@"struct".fields.len;
pub const StageMask = @Int(.unsigned, max_stages);

pub fn create(source: PipelineSource) Error!VKPipeline {
    return .{};
}
fn getLayout(pipeline_type: PipelineType, stage_mask: StageMask) Error!vk.PipelineLayout {}

pub const PipelineSource = union(enum) {
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
const Error = vulkan.Error;
