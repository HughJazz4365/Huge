const std = @import("std");
const huge = @import("../root.zig");
const gpu = huge.gpu;
const Backend = @This();

api: gpu.GApi = .none,
api_version: huge.Version = .{},

deinit: DeinitFn = undefined,

draw: DrawFn = undefined,
beginRendering: BeginRenderingFn = undefined,
endRendering: EndRenderingFn = undefined,

createPipeline: CreatePipelineFn = undefined,
getDefaultPipeline: GetDefaultPipelineFn = undefined,
setPipelinePushConstant: SetPipelinePushConstantFn = undefined,
setPipelineOpaqueUniform: SetPipelineOpaqueUniformFn = undefined,

createShaderModulePath: CreateShaderModuleFn = undefined,
createShaderModuleSource: CreateShaderModuleFn = undefined,
destroyShaderModule: DestroyShaderModuleFn = undefined,

renderTargetSize: RenderTargetSizeFn = undefined,
getWindowRenderTarget: GetWindowRenderTargetFn = undefined,
createWindowContext: CreateWindowContextFn = undefined,
destroyWindowContext: DestroyWindowContextFn = undefined,

pub const DrawFn = *const fn (Pipeline, gpu.DrawParams) Error!void;
pub const BeginRenderingFn = *const fn (RenderTarget, gpu.ClearValue) Error!void;
pub const EndRenderingFn = *const fn () Error!void;

pub const CreatePipelineFn = *const fn ([]const ShaderModule, gpu.PipelineOptions) Error!Pipeline;
pub const SetPipelinePushConstantFn = *const fn (Pipeline, []const u8, u32, u32, *const anyopaque) Error!void;
pub const SetPipelineOpaqueUniformFn = *const fn (Pipeline, []const u8, u32, u32, gpu.OpaqueType, gpu.Handle) Error!void;

pub const CreateShaderModuleFn = *const fn ([]const u8, []const u8) Error!ShaderModule;
pub const DestroyShaderModuleFn = *const fn (ShaderModule) void;

pub const GetDefaultPipelineFn = *const fn (gpu.PipelineType) Pipeline;

pub const RenderTargetSizeFn = *const fn (RenderTarget) huge.math.uvec2;
pub const GetWindowRenderTargetFn = *const fn (Window) RenderTarget;
pub const CreateWindowContextFn = *const fn (Window) Error!WindowContext;
pub const DestroyWindowContextFn = *const fn (WindowContext) void;

pub const DeinitFn = *const fn () void;

const Window = huge.Window;
const RenderTarget = gpu.RenderTarget;
const WindowContext = gpu.WindowContext;
const Pipeline = gpu.Pipeline;
const ShaderModule = gpu.ShaderModule;
const Error = gpu.Error;
