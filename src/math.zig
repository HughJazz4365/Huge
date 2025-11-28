const std = @import("std");
const huge = @import("root.zig");

pub const pi = std.math.pi;
pub const d2r = std.math.rad_per_deg;
pub const r2d = std.math.deg_per_rad;

pub const cint2 = @Vector(2, c_int);
pub const vec2 = @Vector(2, f32);
pub const vec3 = @Vector(3, f32);
pub const vec4 = @Vector(4, f32);
pub const dvec2 = @Vector(2, f64);
pub const dvec3 = @Vector(3, f64);
pub const dvec4 = @Vector(4, f64);

pub const uvec2 = @Vector(2, u32);
pub const uvec3 = @Vector(3, u32);
pub const uvec4 = @Vector(4, u32);

pub const ivec2 = @Vector(2, i32);
pub const ivec3 = @Vector(3, i32);
pub const ivec4 = @Vector(4, i32);

pub const quat = vec4;
pub const euler = vec3;
pub const mat = [4]vec4;
pub const CoordinateSystem = enum { right_handed, left_handed };

pub fn mul(l: anytype, r: anytype) mulType(@TypeOf(l), @TypeOf(r)) {
    const L = @TypeOf(l);
    const R = @TypeOf(r);
    return if (L == mat and R == mat)
        mmMul(l, r)
    else if (L == mat and R == vec4)
        mvMul(l, r)
    else
        comptime unreachable;
}
fn mulType(L: type, R: type) type {
    return if (L == mat and R == mat)
        mat
    else if (L == mat and R == vec4)
        vec4
    else
        @compileError("cannot multiply " ++ @typeName(L) ++ " and " ++ @typeName(R));
}
pub fn identity(comptime T: type) T {
    return switch (T) {
        mat => identityMat,
        quat => identityQuat,
        else => @compileError("unexpected type - " ++ @typeName(T)),
    };
}
//=======|vector|========

pub fn vectorCast(comptime Target: type, v: anytype) Target {
    const V = @TypeOf(v);
    const vv, const tv = .{ @typeInfo(V).vector, @typeInfo(Target).vector };
    huge.cassert(vv.child == tv.child);
    var result: Target = @splat(0);
    inline for (0..@min(tv.len, vv.len)) |i| result[i] = v[i];
    return result;
}
pub fn normalized(v: anytype) @TypeOf(v) {
    const m = mag(v);
    return if (m == 0) @splat(0) else v * @as(@TypeOf(v), @splat(1.0 / m));
}
pub fn dot(a: anytype, b: anytype) @typeInfo(@TypeOf(a, b)).vector.child {
    return @reduce(.Add, a * b);
}
pub fn mag(v: anytype) @typeInfo(@TypeOf(v)).vector.child {
    return @sqrt(dot(v, v));
}
pub inline fn crossUp4(v: vec4) vec4 {
    return .{ v[2], 0, -v[0], 0 };
}
pub fn cross(a: anytype, b: anytype) @TypeOf(a, b) {
    const st: Swizzle = comptime switch (@TypeOf(a)) {
        vec4 => .yzxw,
        vec3 => .yzx,
        else => |T| @compileError("unexpected type - " ++ @typeName(T)),
    };
    return swizzle(a * swizzle(b, st) - swizzle(a, st) * b, st);
}
pub fn scale(v: anytype, s: @typeInfo(@TypeOf(v)).vector.child) @TypeOf(v) {
    return v * @as(@TypeOf(v), @splat(s));
}

pub inline fn zero(comptime V: type) V {
    return @splat(0);
}
pub inline fn one(comptime V: type) V {
    return @splat(1);
}
pub const w1: vec4 = .{ 0, 0, 0, 1 };
pub inline fn up(comptime V: type) V {
    return comptime blk: {
        var v: V = @splat(0);
        if (@typeInfo(V).vector.len < 2) break :blk v;
        v[1] = 1;
        break :blk v;
    };
}
pub inline fn down(comptime V: type) V {
    return comptime -up(V);
}
pub inline fn forward(comptime V: type) V {
    return comptime blk: {
        var v: V = @splat(0);
        if (@typeInfo(V).vector.len < 3) break :blk v;
        v[2] = 1;
        break :blk v;
    };
}
pub inline fn backwards(comptime V: type) V {
    return comptime -forward(V);
}
pub inline fn right(comptime V: type) V {
    return comptime blk: {
        var v: V = @splat(0);
        if (@typeInfo(V).vector.len < 1) break :blk v;
        v[0] = 1;
        break :blk v;
    };
}
pub inline fn left(comptime V: type) V {
    return comptime -right(V);
}

pub const Swizzle = @TypeOf(._);
pub fn swizzle(v: anytype, comptime s: Swizzle) SwizzleType(s, @TypeOf(v)) {
    const S = SwizzleType(s, @TypeOf(v));
    const tn = @tagName(s);
    const vector = @typeInfo(@TypeOf(v)).vector;
    if (tn.len == 1) return swizzleElem(v, tn[0]);
    //we use builtin shuffle function if we can
    if (tn.len == vector.len and comptime !swizzleHasNumbers(s))
        return @shuffle(vector.child, v, undefined, swizzleCharMask(vector.len, s));

    var result: S = undefined;
    inline for (tn, 0..) |c, i| result[i] = swizzleElem(v, c);
    return result;
}
fn swizzleHasNumbers(comptime s: Swizzle) bool {
    return for (@tagName(s)) |c| {
        if (c == '0' or c == '1') break true;
    } else false;
}

inline fn swizzleElem(v: anytype, comptime char: u8) @typeInfo(@TypeOf(v)).vector.child {
    return switch (char) {
        '0' => 0,
        '1' => 1,
        else => v[comptime swizzleCharIndex(char)],
    };
}
fn swizzleCharMask(comptime len: comptime_int, comptime s: Swizzle) @Vector(len, i32) {
    const I = @Vector(len, i32);
    var result: I = @splat(0);
    for (@tagName(s), 0..) |c, i| result[i] = swizzleCharIndex(c);
    return result;
}

fn swizzleCharIndex(comptime char: u8) comptime_int {
    return switch (char) {
        'x'...'z' => char - 'x',
        'w' => 3,
        'r' => 0,
        'g' => 1,
        'b' => 2,
        'a' => 3,
        // '0', '1' => 'o','l', //special literals
        else => @compileError("invalid swizzle character"),
    };
}
fn SwizzleType(comptime s: Swizzle, comptime T: type) type {
    const vector = @typeInfo(T).vector;
    const l = comptime @tagName(s).len;
    if (l == 1) return vector.child;
    return @Vector(@intCast(l), vector.child);
}

//=======|matrix|========

pub fn lerpMat(a: mat, b: mat, t: f32) mat {
    return .{
        std.math.lerp(a[0], b[0], @as(vec4, @splat(t))),
        std.math.lerp(a[1], b[1], @as(vec4, @splat(t))),
        std.math.lerp(a[2], b[2], @as(vec4, @splat(t))),
        std.math.lerp(a[3], b[3], @as(vec4, @splat(t))),
    };
}
pub fn transpose(a: mat) mat {
    _ = a;
    @compileError("TODO");
    // return a;
}
pub fn mmMul(a: mat, b: mat) mat {
    return .{
        mvMul(a, b[0]),
        mvMul(a, b[1]),
        mvMul(a, b[2]),
        mvMul(a, b[3]),
    };
}
pub fn mvMul(m: mat, v: vec4) vec4 {
    return m[0] * @as(vec4, @splat(v[0])) +
        m[1] * @as(vec4, @splat(v[1])) +
        m[2] * @as(vec4, @splat(v[2])) +
        m[3] * @as(vec4, @splat(v[3]));
}
pub fn modelMat(t: vec3, r: quat, s: vec3) mat {
    const x, const y, const z, const w = r;
    if (true) return mmMul(mmMul(translationMat(t), rotationMat(r)), scaleMat(s));
    //but manual
    return mat{
        .{ (1 - 2 * (y * y + z * z)) * s[0], 2 * (x * y - z * w), 2 * (x * z + y * w), 0 },
        .{ 2 * (x * y + z * w), (1 - 2 * (x * x + z * z)) * s[1], 2 * (y * z - x * w), 0 },
        .{ 2 * (x * z - y * w), 2 * (y * z + x * w), (1 - 2 * (x * x + y * y)) * s[2], 0 },
        .{ t[0], t[1], t[2], 1 },
    };
}
pub fn scaleMat(s: vec3) mat {
    return mat{
        .{ s[0], 0, 0, 0 },
        .{ 0, s[1], 0, 0 },
        .{ 0, 0, s[2], 0 },
        .{ 0, 0, 0, 1 },
    };
}
pub const matFromQuat = rotationMat;
pub fn rotationMat(r: quat) mat {
    const x, const y, const z, const w = r;
    return mat{
        .{ 1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0 },
        .{ 2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0 },
        .{ 2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0 },
        .{ 0, 0, 0, 1 },
    };
}
pub fn translationMat(t: vec3) mat {
    return mat{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ t[0], t[1], t[2], 1 },
    };
}
pub fn perspectiveMatRh(fov: f32, aspect_ratio: f32, near: f32, far: f32) mat {
    const r = aspect_ratio; //x / y
    const t = -1.0 / (@tan(fov * 0.5) * r);
    const a = far / (near - far);
    const b = near * a;
    return mat{
        .{ t, 0, 0, 0 },
        .{ 0, t * r, 0, 0 },
        .{ 0, 0, a, -1 },
        .{ 0, 0, b, 0 },
    };
}
//assumes that look dir is normalized
pub fn viewMatRh(pos: vec3, look_dir: vec3) mat {
    const z = -look_dir;
    const x = normalized(vec3{ z[2], 0, -z[0] });
    const y = normalized(cross(z, x));
    return .{
        .{ x[0], y[0], z[0], 0 },
        .{ x[1], y[1], z[1], 0 },
        .{ x[2], y[2], z[2], 0 },
        .{ -dot(pos, x), -dot(pos, y), -dot(pos, z), 1 },
    };
}
pub fn viewMatTransposedRh(pos: vec3, look_dir: vec3) mat {
    var result: mat = undefined;
    result[2] = vectorCast(vec4, -look_dir);
    result[0] = normalized(crossUp4(result[2]));
    result[1] = normalized(cross(result[2], result[0]));
    result[3] = identity(quat);
    inline for (0..3) |i|
        result[i][3] = -dot(vectorCast(vec3, result[i]), pos);
    return result;
}
pub const identityMat: mat = .{
    .{ 1, 0, 0, 0 },
    .{ 0, 1, 0, 0 },
    .{ 0, 0, 1, 0 },
    .{ 0, 0, 0, 1 },
};

//=====|quatertion|======

pub inline fn quatFromEulerDeg(degrees: euler) quat {
    return quatFromEuler(scale(degrees, d2r));
}

pub fn rotateVector(v: vec3, q: quat) vec3 {
    const u = swizzle(q, .xyz);
    const s = q[3];
    const a = scale(u, 2 * dot(v, u));
    const b = scale(v, s * s - dot(u, u));
    const c = scale(cross(u, v), 2 * s);
    return a + b + c;
}

pub fn quatFromAxisAngle(axis: vec3, angle: f32) quat {
    const a = angle * 0.5;
    const sc: vec2 = vec2{ @sin(a), @cos(a) };
    return swizzle(axis, .xyz1) * swizzle(sc, .xxxy);
}
pub fn quatFromEuler(radians: euler) quat {
    const half = scale(radians, 0.5);
    const s, const c = .{ @sin(half), @cos(half) };
    // const m = ivec3;
    return .{
        // rm(@shuffle(f32, s, c, m{ 0, -2, -3 })) -
        //     rm(@shuffle(f32, s, c, m{ -1, 1, 2 })),

        // rm(@shuffle(f32, s, c, m{ -1, 1, -3 })) +
        //     rm(@shuffle(f32, s, c, m{ 0, -2, 2 })),

        // rm(@shuffle(f32, s, c, m{ -1, -2, 2 })) -
        //     rm(@shuffle(f32, s, c, m{ 0, 1, -3 })),

        // rm(@shuffle(f32, s, c, m{ -1, -2, -3 })) +
        //     rm(@shuffle(f32, s, c, m{ 0, 1, 2 })),
        s[0] * c[1] * c[2] - c[0] * s[1] * s[2],
        c[0] * s[1] * c[2] + s[0] * c[1] * s[2],
        c[0] * c[1] * s[2] - s[0] * s[1] * c[2],
        c[0] * c[1] * c[2] + s[0] * s[1] * s[2],
    };
}
inline fn rm(v: vec3) f32 {
    return @reduce(.Mul, v);
}

pub const identityQuat: quat = .{ 0, 0, 0, 1 };

//=======================
