const std = @import("std");
const huge = @import("../root.zig");
const gpu = huge.gpu;
const Backend = @This();

api: gpu.GApi = .none,
api_version: huge.Version = .{},

deinit: DeinitFn = undefined,

createPipeline: CreatePipelineFn = undefined,
getDefaultPipeline: GetDefaultPipelineFn = undefined,
setPipelinePushConstant: SetPipelinePushConstantFn = undefined,
setPipelineOpaqueUniform: SetPipelineOpaqueUniformFn = undefined,

createShaderModulePath: CreateShaderModulePathFn = undefined,
createShaderModuleSource: CreateShaderModuleSourceFn = undefined,

getWindowRenderTarget: GetWindowRenderTargetFn = undefined,
createWindowContext: CreateWindowContextFn = undefined,
destroyWindowContext: DestroyWindowContextFn = undefined,
present: PresentFn = undefined,

pub const CreatePipelineFn = *const fn ([]const ShaderModule) Error!Pipeline;
pub const SetPipelinePushConstantFn = *const fn (Pipeline, []const u8, u32, u32, *const anyopaque) Error!void;
pub const SetPipelineOpaqueUniformFn = *const fn (Pipeline, []const u8, u32, u32, gpu.OpaqueType, gpu.Handle) Error!void;
pub const CreateShaderModulePathFn = *const fn (path: []const u8, entry_point: []const u8) Error!ShaderModule;
pub const CreateShaderModuleSourceFn = *const fn (source: []const u8, entry_point: []const u8) Error!ShaderModule;

pub const GetDefaultPipelineFn = *const fn (gpu.PipelineType) Pipeline;
pub const GetWindowRenderTargetFn = *const fn (Window) RenderTarget;
pub const CreateWindowContextFn = *const fn (Window) Error!WindowContext;
pub const DestroyWindowContextFn = *const fn (WindowContext) void;
pub const PresentFn = *const fn (Window) Error!void;

pub const DeinitFn = *const fn () void;

const Window = huge.Window;
const RenderTarget = gpu.RenderTarget;
const WindowContext = gpu.WindowContext;
const Pipeline = gpu.Pipeline;
const ShaderModule = gpu.ShaderModule;
const Error = gpu.Error;
