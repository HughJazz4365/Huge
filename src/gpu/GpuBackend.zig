const std = @import("std");
const huge = @import("../root.zig");
const math = huge.math;
const gpu = huge.gpu;
const Backend = @This();

api: gpu.GApi = .none,
api_version: huge.Version = .{},
coordinate_system: huge.math.CoordinateSystem = .right_handed,

deinit: *const DeinitFn = undefined,

//draw commands
draw: *const DrawFn = undefined,
bindVertexBuffer: *const BindVertexBufferFn = undefined,
bindIndexBuffer: *const BindIndexBufferFn = undefined,
pipelinePushConstant: *const PipelinePushConstantFn = undefined,
setPipelineOpaqueUniform: *const SetPipelineOpaqueUniformFn = undefined,

//draw control flow
beginRendering: *const BeginRenderingFn = undefined,
endRendering: *const EndRenderingFn = undefined,

//resource/state management
reloadPipelines: *const ReloadPipelinesFn = undefined,
getDefaultPipeline: *const GetDefaultPipelineFn = undefined,
createPipeline: *const CreatePipelineFn = undefined,
destroyPipeline: *const DestroyPipelineFn = undefined,

createShaderModulePath: *const CreateShaderModuleFn = undefined,
createShaderModuleSource: *const CreateShaderModuleFn = undefined,
destroyShaderModule: *const DestroyShaderModuleFn = undefined,

createRenderTargetFromTextures: *const createRendrerTargetFromTexturesFn = undefined,
createRenderTarget: *const CreateRenderTargetFn = undefined,
destroyRenderTarget: *const DestroyRenderTargetFn = undefined,

getTextureType: *const GetTextureTypeFn = undefined,
getTextureSize: *const GetTextureSizeFn = undefined,
getTextureFormat: *const GetTextureFormatFn = undefined,
createTexture: *const CreateTextureFn = undefined,
destroyTexture: *const DestroyTextureFn = undefined,

loadBuffer: *const LoadBufferFn = undefined,
mapBuffer: *const MapBufferFn = undefined,
unmapBuffer: *const UnmapBufferFn = undefined,
createBuffer: *const CreateBufferFn = undefined,
destroyBuffer: *const DestroyBufferFn = undefined,

renderTargetSize: *const RenderTargetSizeFn = undefined,

updateWindowContext: *const UpdateWindowContextFn = undefined,
getWindowRenderTarget: *const GetWindowRenderTargetFn = undefined,
createWindowContext: *const CreateWindowContextFn = undefined,
destroyWindowContext: *const DestroyWindowContextFn = undefined,

pub const DrawFn = fn (Pipeline, gpu.DrawParams) void;
pub const BindVertexBufferFn = fn (Buffer) void;
pub const BindIndexBufferFn = fn (Buffer, gpu.IndexType) void;
pub const PipelinePushConstantFn = fn (Pipeline, []const u8, u32, u32, *const anyopaque) void;
pub const SetPipelineOpaqueUniformFn = fn (Pipeline, []const u8, u32, u32, gpu.OpaqueType, gpu.Handle) void;

pub const BeginRenderingFn = fn (RenderTarget, gpu.ClearValue) Error!void;
pub const EndRenderingFn = fn () Error!void;

pub const ReloadPipelinesFn = fn () Error!void;
pub const GetDefaultPipelineFn = fn (gpu.PipelineType) Pipeline;
pub const CreatePipelineFn = fn ([]const ShaderModule, gpu.PipelineParams) Error!Pipeline;
pub const DestroyPipelineFn = fn (Pipeline) void;

pub const CreateShaderModuleFn = fn ([]const u8, []const u8) Error!ShaderModule;
pub const DestroyShaderModuleFn = fn (ShaderModule) void;

pub const RenderTargetSizeFn = fn (RenderTarget) math.uvec2;
pub const createRendrerTargetFromTexturesFn = fn (?Texture, ?Texture) Error!RenderTarget;
pub const CreateRenderTargetFn = fn (math.uvec2, ?gpu.Format, ?gpu.Format, gpu.TextureParams) Error!RenderTarget;
pub const DestroyRenderTargetFn = fn (RenderTarget) void;

pub const GetTextureSizeFn = fn (Texture) math.uvec3;
pub const GetTextureTypeFn = fn (Texture) gpu.TextureType;
pub const GetTextureFormatFn = fn (Texture) gpu.Format;
pub const CreateTextureFn = fn (math.uvec3, gpu.Format, gpu.TextureParams) Error!Texture;
pub const DestroyTextureFn = fn (Texture) void;

pub const LoadBufferFn = fn (Buffer, []const u8, usize) Error!void;
pub const MapBufferFn = fn (Buffer, usize, usize) Error![]u8;
pub const UnmapBufferFn = fn (Buffer) void;
pub const CreateBufferFn = fn (usize, gpu.BufferUsage) Error!Buffer;
pub const DestroyBufferFn = fn (Buffer) void;

pub const UpdateWindowContextFn = fn (WindowContext) void;
pub const GetWindowRenderTargetFn = fn (Window) RenderTarget;
pub const CreateWindowContextFn = fn (Window) Error!WindowContext;
pub const DestroyWindowContextFn = fn (WindowContext) void;

pub const DeinitFn = fn () void;

const Window = huge.Window;
const RenderTarget = gpu.RenderTarget;
const WindowContext = gpu.WindowContext;
const Pipeline = gpu.Pipeline;
const Texture = gpu.Texture;
const Buffer = gpu.Buffer;
const ShaderModule = gpu.ShaderModule;
const Error = gpu.Error;
