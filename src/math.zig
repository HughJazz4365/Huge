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

pub fn cast(T: type, num: anytype) T {
    const F = @TypeOf(num);
    const finfo, const tinfo = .{ @typeInfo(F), @typeInfo(T) };
    return if (finfo == .vector and tinfo == .vector) //
        (if (finfo.vector.len == tinfo.vector.len)
            scalarCast(T, num)
        else
            vectorCast(T, num))
    else if (tinfo == .vector and isScalar(finfo))
        @splat(scalarCast(tinfo.vector.child, num))
    else if (isScalar(tinfo) and finfo == .vector)
        scalarCast(T, num[0])
    else if (isScalar(tinfo) and isScalar(finfo))
        scalarCast(T, num)
    else
        @compileError("cannot cast '" ++
            @typeName(F) ++
            "' into '" ++
            @typeName(T) ++ "'");
}

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

inline fn isScalar(comptime tinfo: std.builtin.Type) bool {
    return tinfo == .int or tinfo == .float or tinfo == .comptime_int or tinfo == .comptime_float;
}
inline fn scalarCast(T: type, val: anytype) T {
    const F = @TypeOf(val);
    if (F == T) return val;
    const finfo, const tinfo = if (@typeInfo(T) == .vector)
        .{ @typeInfo(@typeInfo(F).vector.child), @typeInfo(@typeInfo(T).vector.child) }
    else
        .{ @typeInfo(F), @typeInfo(T) };
    return if (tinfo == .int or tinfo == .comptime_int) ( //
        if (finfo == .int or finfo == .comptime_int)
            @intCast(val)
        else
            @intFromFloat(val)) else ( //
        if (finfo == .int or finfo == .comptime_int)
            @floatFromInt(val)
        else
            @floatCast(val));
}

//=======|vector|========

fn vectorCast(T: type, v: anytype) T {
    const F = @TypeOf(v);
    const finfo, const tinfo = .{ @typeInfo(F).vector, @typeInfo(T).vector };
    return scalarCast(T, @shuffle(
        finfo.child,
        v,
        @Vector(2, finfo.child){ 0, 0 },
        blk: {
            var m: @Vector(tinfo.len, i32) = @splat(-1);
            for (0..@min(tinfo.len, finfo.len)) |i| m[i] = i;
            break :blk m;
        },
    ));
}
pub fn normalized(v: anytype) @TypeOf(v) {
    const m = mag(v);
    return if (m == 0) @splat(0) else scale(v, 1.0 / m);
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
    const st: SwizzleLiteral = comptime switch (@TypeOf(a)) {
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
    return vectorCast(V, ivec2{ 0, 1 });
}
pub inline fn down(comptime V: type) V {
    return vectorCast(V, ivec2{ 0, -1 });
}
pub inline fn forward(comptime V: type) V {
    return vectorCast(V, ivec3{ 0, 0, 1 });
}
pub inline fn backwards(comptime V: type) V {
    return vectorCast(V, ivec3{ 0, 0, -1 });
}
pub inline fn right(comptime V: type) V {
    return vectorCast(V, ivec2{ 1, 0 });
}
pub inline fn left(comptime V: type) V {
    return vectorCast(V, ivec2{ -1, 0 });
}

pub const SwizzleLiteral = @TypeOf(._);
pub fn swizzle(v: anytype, comptime s: SwizzleLiteral) SwizzleType(s, @TypeOf(v)) {
    const sl = @tagName(s);
    const vector = @typeInfo(@TypeOf(v)).vector;
    if (sl.len == 1) return swizzleElem(v, sl[0]);
    return if (std.mem.countScalar(u8, sl, sl[0]) == sl.len)
        @splat(swizzleElem(v, sl[0]))
    else
        @shuffle(
            vector.child,
            v,
            @Vector(2, vector.child){ 0, 1 },
            swizzleCharMask(s),
        );
}
inline fn swizzleElem(v: anytype, comptime char: u8) @typeInfo(@TypeOf(v)).vector.child {
    return switch (char) {
        '0' => 0,
        '1' => 1,
        else => v[comptime swizzleCharIndex(char)],
    };
}
fn swizzleCharMask(comptime s: SwizzleLiteral) @Vector(@tagName(s).len, i32) {
    const len = @tagName(s).len;
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
        '0' => -1,
        '1' => -2,
        else => @compileError("invalid swizzle character"),
    };
}
fn SwizzleType(comptime s: SwizzleLiteral, comptime T: type) type {
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
    var result: mat = undefined;
    inline for (0..4) |i| inline for (0..4) |j| {
        result[i][j] = a[j][i];
    };
    return result;
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
    return mmMul(mmMul(translationMat(t), rotationMat(r)), scaleMat(s));
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
    result[2] = swizzle(-look_dir, .xyz0);
    result[0] = normalized(crossUp4(result[2]));
    result[1] = normalized(cross(result[2], result[0]));
    result[3] = identity(quat);
    inline for (0..3) |i|
        result[i][3] = -dot(swizzle(result[i], .xyz), pos);
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
    const half = angle * 0.5;
    return swizzle(axis, .xyz1) *
        swizzle(vec2{ @sin(half), @cos(half) }, .xxxy);
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
