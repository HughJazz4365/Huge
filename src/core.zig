const std = @import("std");
const huge = @import("root.zig");
const math = huge.math;
const util = huge.util;

pub const Camera = struct {
    fov: f32 = 80 * math.d2r,
    aspect_ratio: f32 = undefined,
    near: f32 = 0.1,
    far: f32 = 300,

    transform: *const Transform = &.{},
    pub fn viewProjectionMat(self: *const Camera) mat {
        return math.mul(self.projectionMat(), self.viewMat());
    }
    pub fn projectionMat(self: *const Camera) mat {
        return if (huge.gpu.coordinateSystem() == .right_handed)
            math.perspectiveMatRh(self.fov, self.aspect_ratio, self.near, self.far)
        else
            @panic("left handed projection matrix!");
    }
    pub fn viewMat(self: *const Camera) mat {
        return if (huge.gpu.coordinateSystem() == .right_handed)
            math.viewMatRh(self.transform.position, self.transform.lookDir())
        else
            @panic("left handed view matrix!");
    }
};
pub const Transform = struct {
    rotation: vec4 = math.identity(quat),
    position: vec3 = @splat(0),
    scale: vec3 = @splat(1),
    pub fn lookDir(self: *const Transform) vec3 {
        return math.rotateVector(math.forward(vec3), self.rotation);
    }
    pub fn modelMat(self: *const Transform) mat {
        return math.modelMat(
            self.position,
            self.rotation,
            self.scale,
        );
    }
    pub fn setEuler(self: *Transform, radians: vec3) void {
        self.rotation = math.quatFromEuler(radians);
    }
    pub fn setEulerDeg(self: *Transform, degrees: vec3) void {
        self.setEuler(math.scale(degrees, math.d2r));
    }
};
const vec3 = math.vec3;
const vec4 = math.vec4;
const mat = math.mat;
const quat = math.quat;
