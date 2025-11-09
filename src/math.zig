const std = @import("std");
const huge = @import("root");

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
