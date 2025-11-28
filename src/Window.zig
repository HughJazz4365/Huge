const std = @import("std");
const huge = @import("root.zig");
pub const glfw = @import("glfw");
const math = huge.math;
const util = huge.util;
const Window = @This();

const destroyed_window: glfw.Window = 0;
pub const Handle = *glfw.Window;

handle: Handle = undefined,
title: [:0]const u8,

context: huge.gpu.WindowContext = undefined,
current_input_mask: [input_mask_len]usize = @splat(0),
last_input_mask: [input_mask_len]usize = @splat(0),

cursor_pos: math.vec2 = @splat(0),
last_cursor_pos: math.vec2 = @splat(0),

frame_count: u64 = 0,
const input_mask_len = (512 / 8) / @sizeOf(usize);

pub const FullHD: Size = .{ 1920, 1080 };
pub const HD: Size = .{ 1280, 720 };

/// exaple tick function that querries input
/// and returns whether execution should continue
pub fn tick(self: *Window) bool {
    const should = self.shouldClose();
    if (should) return false;
    self.frame_count += 1;
    pollEvents();
    self.last_cursor_pos = self.cursor_pos;
    self.cursor_pos = self.getCursorPosRaw();

    huge.time.tick();
    self.querryInput();
    return true;
}

pub fn disableCursor(self: *const Window) void {
    glfw.setInputMode(self.handle, glfw.Cursor, glfw.CursorDisabled);
}
pub fn getCursorDeltaNormalized(self: *const Window) math.vec2 {
    const aspect = self.aspectRatio();
    const factor = math.vec2{ aspect, -1 } / @as(math.vec2, @floatFromInt(self.size()));
    return (self.cursor_pos - self.last_cursor_pos) *
        math.scale(factor, huge.time.delta());
}

fn getCursorPosRaw(self: *const Window) math.vec2 {
    var pos: [2]f64 = @splat(0);
    glfw.getCursorPos(self.handle, &pos[0], &pos[1]);
    return .{ @floatCast(pos[0]), @floatCast(pos[1]) };
}
// test 3d movement input (wasd - wars)
pub fn warsudVector(self: *const Window, yrot: f32) math.vec3 {
    const topdown: math.vec3 = .{
        util.f32fromBool(self.getKey(.s, .hold)) -
            util.f32fromBool(self.getKey(.a, .hold)),
        0,
        util.f32fromBool(self.getKey(.w, .hold)) -
            util.f32fromBool(self.getKey(.r, .hold)),
    };
    return math.rotateVector(topdown, math.quatFromAxisAngle(math.up(math.vec3), yrot)) +
        math.vec3{ 0, util.f32fromBool(self.getKey(.space, .hold)) -
            util.f32fromBool(self.getKey(.leftShift, .hold)), 0 };
}

pub fn getKey(self: *const Window, key: Key, action: KeyAction) bool {
    const index = @as(usize, @intFromEnum(key)) / (@sizeOf(usize) * 8);
    const bit = @as(usize, @intFromEnum(key)) % (@sizeOf(usize) * 8);
    const current = self.current_input_mask[index] & (@as(usize, 1) << @truncate(bit)) > 0;
    const last = self.last_input_mask[index] & (@as(usize, 1) << @truncate(bit)) > 0;
    return switch (action) {
        .hold => current,
        .up => !current,
        .press => current & !last,
    };
}
pub const KeyAction = enum { press, hold, up };

pub fn querryInput(self: *Window) void {
    self.last_input_mask = self.current_input_mask;
    self.current_input_mask = @splat(0);
    inline for (@typeInfo(Key).@"enum".fields) |ef| {
        const index = @as(usize, ef.value) / (@sizeOf(usize) * 8);
        const bit = @as(usize, ef.value) % (@sizeOf(usize) * 8);
        const is_pressed = glfw.getKey(self.handle, ef.value) != glfw.Release;
        self.current_input_mask[index] |= @as(usize, @intFromBool(is_pressed)) << bit;
    }
}

pub fn aspectRatio(self: Window) f32 {
    return huge.util.aspectRatioSize(self.size());
}
pub fn size(self: Window) Size {
    var storage: math.cint2 = @splat(0);
    glfw.getWindowSize(self.handle, &storage[0], &storage[1]);
    return @intCast(storage);
}
pub fn update(self: Window) void {
    self.context.update();
}
pub fn renderTarget(self: Window) huge.gpu.RenderTarget {
    return huge.gpu.getWindowRenderTarget(self);
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

pub fn destroy(self: *Window) void {
    huge.gpu.destroyWindowContext(self.context);
    if (@intFromPtr(self.handle) != @intFromPtr(&destroyed_window))
        glfw.destroyWindow(self.handle);
    self.handle = @constCast(&destroyed_window);
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
    //force x11
    // glfw.initHint(glfw.Platform, glfw.PlatformX11);
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
const Size = math.uvec2;

pub const Attributes = struct {
    title: [:0]const u8 = "huge",
    size: Size = .{ 800, 600 },

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
const Key = enum(u9) {
    space = glfw.KeySpace,
    apostrophe = glfw.KeyApostrophe,
    comma = glfw.KeyComma,
    minus = glfw.KeyMinus,
    period = glfw.KeyPeriod,
    slash = glfw.KeySlash,
    num0 = glfw.KeyNum0,
    num1 = glfw.KeyNum1,
    num2 = glfw.KeyNum2,
    num3 = glfw.KeyNum3,
    num4 = glfw.KeyNum4,
    num5 = glfw.KeyNum5,
    num6 = glfw.KeyNum6,
    num7 = glfw.KeyNum7,
    num8 = glfw.KeyNum8,
    num9 = glfw.KeyNum9,
    semicolon = glfw.KeySemicolon,
    equal = glfw.KeyEqual,
    a = glfw.KeyA,
    b = glfw.KeyB,
    c = glfw.KeyC,
    d = glfw.KeyD,
    e = glfw.KeyE,
    f = glfw.KeyF,
    g = glfw.KeyG,
    h = glfw.KeyH,
    i = glfw.KeyI,
    j = glfw.KeyJ,
    k = glfw.KeyK,
    l = glfw.KeyL,
    m = glfw.KeyM,
    n = glfw.KeyN,
    o = glfw.KeyO,
    p = glfw.KeyP,
    q = glfw.KeyQ,
    r = glfw.KeyR,
    s = glfw.KeyS,
    t = glfw.KeyT,
    u = glfw.KeyU,
    v = glfw.KeyV,
    w = glfw.KeyW,
    x = glfw.KeyX,
    y = glfw.KeyY,
    z = glfw.KeyZ,
    leftBracket = glfw.KeyLeftBracket,
    backslash = glfw.KeyBackslash,
    rightBracket = glfw.KeyRightBracket,
    graveAccent = glfw.KeyGraveAccent,
    world1 = glfw.KeyWorld1,
    world2 = glfw.KeyWorld2,
    escape = glfw.KeyEscape,
    enter = glfw.KeyEnter,
    tab = glfw.KeyTab,
    backspace = glfw.KeyBackspace,
    insert = glfw.KeyInsert,
    delete = glfw.KeyDelete,
    right = glfw.KeyRight,
    left = glfw.KeyLeft,
    down = glfw.KeyDown,
    up = glfw.KeyUp,
    pageUp = glfw.KeyPageUp,
    pageDown = glfw.KeyPageDown,
    home = glfw.KeyHome,
    end = glfw.KeyEnd,
    capsLock = glfw.KeyCapsLock,
    scrollLock = glfw.KeyScrollLock,
    numLock = glfw.KeyNumLock,
    printScreen = glfw.KeyPrintScreen,
    pause = glfw.KeyPause,
    f1 = glfw.KeyF1,
    f2 = glfw.KeyF2,
    f3 = glfw.KeyF3,
    f4 = glfw.KeyF4,
    f5 = glfw.KeyF5,
    f6 = glfw.KeyF6,
    f7 = glfw.KeyF7,
    f8 = glfw.KeyF8,
    f9 = glfw.KeyF9,
    f10 = glfw.KeyF10,
    f11 = glfw.KeyF11,
    f12 = glfw.KeyF12,
    f13 = glfw.KeyF13,
    f14 = glfw.KeyF14,
    f15 = glfw.KeyF15,
    f16 = glfw.KeyF16,
    f17 = glfw.KeyF17,
    f18 = glfw.KeyF18,
    f19 = glfw.KeyF19,
    f20 = glfw.KeyF20,
    f21 = glfw.KeyF21,
    f22 = glfw.KeyF22,
    f23 = glfw.KeyF23,
    f24 = glfw.KeyF24,
    f25 = glfw.KeyF25,
    kp0 = glfw.KeyKp0,
    kp1 = glfw.KeyKp1,
    kp2 = glfw.KeyKp2,
    kp3 = glfw.KeyKp3,
    kp4 = glfw.KeyKp4,
    kp5 = glfw.KeyKp5,
    kp6 = glfw.KeyKp6,
    kp7 = glfw.KeyKp7,
    kp8 = glfw.KeyKp8,
    kp9 = glfw.KeyKp9,
    kpDecimal = glfw.KeyKpDecimal,
    kpDivide = glfw.KeyKpDivide,
    kpMultiply = glfw.KeyKpMultiply,
    kpSubtract = glfw.KeyKpSubtract,
    kpAdd = glfw.KeyKpAdd,
    kpEnter = glfw.KeyKpEnter,
    kpEqual = glfw.KeyKpEqual,
    leftShift = glfw.KeyLeftShift,
    leftControl = glfw.KeyLeftControl,
    leftAlt = glfw.KeyLeftAlt,
    leftSuper = glfw.KeyLeftSuper,
    rightShift = glfw.KeyRightShift,
    rightControl = glfw.KeyRightControl,
    rightAlt = glfw.KeyRightAlt,
    rightSuper = glfw.KeyRightSuper,
};
