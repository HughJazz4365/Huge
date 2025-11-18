const std = @import("std");
const huge = @import("root.zig");
pub const glfw = @import("glfw");
const math = huge.math;
const util = huge.util;
const Window = @This();

pub const Handle = *glfw.Window;

handle: Handle = undefined,
title: [:0]const u8,

context: huge.gpu.WindowContext = undefined,

pub const FullHD: math.uvec2 = .{ 1920, 1080 };
pub const HD: math.uvec2 = .{ 1280, 720 };

pub fn present(self: Window) !void {
    try huge.gpu.present(self);
}
pub fn shouldClosePoll(self: Window) bool {
    const should = self.shouldClose();
    if (!should) pollEvents();
    return should;
}
pub fn shouldClose(self: Window) bool {
    return glfw.windowShouldClose(self.handle);
}
pub const pollEvents = glfw.pollEvents;

pub fn create(attributes: Attributes) Error!Window {
    if (huge.gpu.api() == .opengl) {
        glfw.windowHint(glfw.ClientAPI, glfw.OpenGLAPI);
        glfw.windowHint(glfw.ContextVersionMajor, 4);
        glfw.windowHint(glfw.ContextVersionMinor, 3);
        glfw.windowHint(glfw.OpenGLProfile, glfw.OpenGLCoreProfile);
        glfw.windowHint(glfw.OpenGLForwardCompat, @intFromBool(true));
        glfw.windowHint(glfw.Doublebuffer, @intFromBool(true));
    } else glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);

    var window: Window = .{
        .title = attributes.title,
        .handle = try glfw.createWindow(
            @intCast(attributes.size[0]),
            @intCast(attributes.size[1]),
            attributes.title.ptr,
            null,
            null,
        ),
    };
    if (huge.gpu.api() == .opengl) glfw.makeContextCurrent(window.handle);
    window.setAttributes(attributes);
    window.context = huge.gpu.createWindowContext(window) catch
        return Error.ContextCreationError;

    return window;
}

pub fn destroy(self: Window) void {
    huge.gpu.destroyWindowContext(self.context);
    glfw.destroyWindow(self.handle);
}
pub fn setAttributes(self: Window, attributes: Attributes) void {
    inline for (@typeInfo(Attributes).@"struct".fields, 0..) |sf, i| {
        const current = @field(attributes, sf.name);
        switch (i) {
            util.structFieldIndexFromName(Attributes, "size") => glfw.setWindowSize(self.handle, @intCast(current[0]), @intCast(current[1])),
            util.structFieldIndexFromName(Attributes, "title") => glfw.setWindowTitle(self.handle, current.ptr),
            else => glfw.setWindowAttrib(self.handle, comptime switch (i) {
                util.structFieldIndexFromName(Attributes, "resizable") => glfw.Resizable,
                util.structFieldIndexFromName(Attributes, "floating") => glfw.Floating,
                util.structFieldIndexFromName(Attributes, "decorated") => glfw.Decorated,
                else => continue,
            }, @intFromBool(current)),
        }
    }
}
fn getAttributes(self: Window) Attributes {
    var cint2: math.cint2 = @splat(0);
    glfw.getWindowSize(self.handle, &cint2[0], &cint2[1]);
    return .{
        .title = self.title,
        .size = .{ @intCast(cint2[0]), @intCast(cint2[1]) },
        .resizable = glfw.getWindowAttrib(self.handle, glfw.Resizable),
        .floating = glfw.getWindowAttrib(self.handle, glfw.Floating),
        .decorated = glfw.getWindowAttrib(self.handle, glfw.Decorated),
        .visible = glfw.getWindowAttrib(self.handle, glfw.Visible),
        .focused = glfw.getWindowAttrib(self.handle, glfw.Focused),
    };
}
pub fn createDummy(instance: glfw.VkInstance) !DummyWindow {
    glfw.windowHint(glfw.Decorated, @intFromBool(false));
    glfw.windowHint(glfw.Visible, @intFromBool(false));
    glfw.windowHint(glfw.Focused, @intFromBool(false));

    defer defaultWindowHints();

    const window_handle = try glfw.createWindow(1, 1, "", null, null);

    var surface_handle: glfw.VkSurfaceKHR = undefined;
    const result = glfw.createWindowSurface(
        instance,
        window_handle,
        null,
        &surface_handle,
    );
    if (result != .success) return error.SurfaceCreationFailure;

    return .{ .handle = window_handle, .surface_handle = surface_handle };
}
pub const DummyWindow = struct { handle: *glfw.Window, surface_handle: glfw.VkSurfaceKHR };
pub fn init() !void {
    glfw.terminate();
    try glfw.init();
    defaultWindowHints();
}
fn defaultWindowHints() void {
    glfw.windowHint(glfw.ClientAPI, glfw.NoAPI);
    glfw.windowHint(glfw.Resizable, @intFromBool(false));
    glfw.windowHint(glfw.Floating, @intFromBool(false));
    glfw.windowHint(glfw.Maximized, @intFromBool(false));
    glfw.windowHint(glfw.Decorated, @intFromBool(true));
    glfw.windowHint(glfw.Visible, @intFromBool(true));
    glfw.windowHint(glfw.Focused, @intFromBool(true));
}
pub const terminate = glfw.terminate;

pub const Attributes = struct {
    title: [:0]const u8 = "huge",
    size: math.uvec2 = .{ 800, 600 },

    resizable: bool = false,
    floating: bool = false,
    maximized: bool = false,
    decorated: bool = true,
    visible: bool = true,
    focused: bool = true,
};
pub const Error = error{
    ContextCreationError,
} || glfw.GLFWError;
