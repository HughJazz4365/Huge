const std = @import("std");
const huge = @import("../root.zig");
const gpu = huge.gpu;
const Backend = @This();

api: gpu.GApi = .none,
api_version: huge.Version = .{},
coordinate_system: huge.math.CoordinateSystem = .right_handed,

deinit: DeinitFn = undefined,

draw: DrawFn = undefined,
bindVertexBuffer: BindVertexBufferFn = undefined,
bindIndexBuffer: BindIndexBufferFn = undefined,

beginRendering: BeginRenderingFn = undefined,
endRendering: EndRenderingFn = undefined,

pipelinePushConstant: PipelinePushConstantFn = undefined,
setPipelineOpaqueUniform: SetPipelineOpaqueUniformFn = undefined,
getDefaultPipeline: GetDefaultPipelineFn = undefined,
createPipeline: CreatePipelineFn = undefined,
destroyPipeline: DestroyPipelineFn = undefined,

createShaderModulePath: CreateShaderModuleFn = undefined,
createShaderModuleSource: CreateShaderModuleFn = undefined,
destroyShaderModule: DestroyShaderModuleFn = undefined,

loadBuffer: LoadBufferFn = undefined,
mapBuffer: MapBufferFn = undefined,
unmapBuffer: UnmapBufferFn = undefined,
createBuffer: CreateBufferFn = undefined,
destroyBuffer: DestroyBufferFn = undefined,

renderTargetSize: RenderTargetSizeFn = undefined,

updateWindowContext: UpdateWindowContextFn = undefined,
getWindowRenderTarget: GetWindowRenderTargetFn = undefined,
createWindowContext: CreateWindowContextFn = undefined,
destroyWindowContext: DestroyWindowContextFn = undefined,

pub const DrawFn = *const fn (Pipeline, gpu.DrawParams) Error!void;
pub const BindVertexBufferFn = *const fn (Buffer) Error!void;
pub const BindIndexBufferFn = *const fn (Buffer, gpu.IndexType) Error!void;
pub const BeginRenderingFn = *const fn (RenderTarget, gpu.ClearValue) Error!void;
pub const EndRenderingFn = *const fn () Error!void;

pub const PipelinePushConstantFn = *const fn (Pipeline, []const u8, u32, u32, *const anyopaque) Error!void;
pub const SetPipelineOpaqueUniformFn = *const fn (Pipeline, []const u8, u32, u32, gpu.OpaqueType, gpu.Handle) Error!void;
pub const GetDefaultPipelineFn = *const fn (gpu.PipelineType) Pipeline;
pub const CreatePipelineFn = *const fn ([]const ShaderModule, gpu.PipelineOptions) Error!Pipeline;
pub const DestroyPipelineFn = *const fn (Pipeline) void;

pub const CreateShaderModuleFn = *const fn ([]const u8, []const u8) Error!ShaderModule;
pub const DestroyShaderModuleFn = *const fn (ShaderModule) void;

pub const LoadBufferFn = *const fn (Buffer, []const u8, usize) Error!void;
pub const MapBufferFn = *const fn (Buffer, usize, usize) Error![]u8;
pub const UnmapBufferFn = *const fn (Buffer) void;
pub const CreateBufferFn = *const fn (usize, gpu.BufferUsage) Error!Buffer;
pub const DestroyBufferFn = *const fn (Buffer) void;

pub const RenderTargetSizeFn = *const fn (RenderTarget) huge.math.uvec2;

pub const UpdateWindowContextFn = *const fn (WindowContext) void;
pub const GetWindowRenderTargetFn = *const fn (Window) RenderTarget;
pub const CreateWindowContextFn = *const fn (Window) Error!WindowContext;
pub const DestroyWindowContextFn = *const fn (WindowContext) void;

pub const DeinitFn = *const fn () void;

const Window = huge.Window;
const RenderTarget = gpu.RenderTarget;
const WindowContext = gpu.WindowContext;
const Pipeline = gpu.Pipeline;
const Buffer = gpu.Buffer;
const ShaderModule = gpu.ShaderModule;
const Error = gpu.Error;
