const std = @import("std");
const root = @import("../root.zig");
const gpu = root.gpu;
const shader = gpu.shader;
const Backend = @This();

const Error = error{};
api: gpu.GApi = .none,
api_version: gpu.ApiVersion = .{},
createPipeline: CreatePipelineFn = undefined,

pub const CreatePipelineFn = *const fn (shader.ShaderInfo) Error!Pipeline;

const Pipeline = gpu.Pipeline;
