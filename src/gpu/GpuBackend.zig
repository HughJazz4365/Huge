const std = @import("std");
const huge = @import("../root.zig");
const gpu = huge.gpu;
const Backend = @This();

api: gpu.GApi = .none,
api_version: huge.Version = .{},

deinit: DeinitFn = undefined,

createPipeline: CreatePipelineFn = undefined,
setPipelineProperty: SetPipelinePropertyFn = undefined,
getDefaultPipeline: GetDefaultPipelineFn = undefined,

createShaderModulePath: CreateShaderModulePathFn = undefined,
createShaderModuleSource: CreateShaderModuleSourceFn = undefined,

createWindowContext: CreateWindowContextFn = undefined,

pub const CreateWindowContextFn = *const fn (huge.Window) Error!gpu.WindowContext;
pub const CreatePipelineFn = *const fn ([]const ShaderModule) Error!Pipeline;
pub const CreateShaderModulePathFn = *const fn (path: []const u8, entry_point: []const u8) Error!ShaderModule;
pub const CreateShaderModuleSourceFn = *const fn (source: []const u8, entry_point: []const u8) Error!ShaderModule;
pub const SetPipelinePropertyFn = *const fn (Pipeline, []const u8, *const anyopaque) Error!void;
pub const GetDefaultPipelineFn = *const fn (gpu.PipelineType) Pipeline;

pub const DeinitFn = *const fn () void;

const Pipeline = gpu.Pipeline;
const ShaderModule = gpu.ShaderModule;
const Error = gpu.Error;
