const std = @import("std");
const huge = @import("../root.zig");
const gpu = huge.gpu;

pub const MeshRenderer = struct {
    count: u32 = 0,
    index_type: gpu.IndexType,
    index_buffer: ?gpu.Buffer = null,
    vertex_buffer: gpu.Buffer = undefined,

    pub fn draw(self: MeshRenderer, pipeline: gpu.Pipeline) void {
        self.vertex_buffer.bindVertex();
        if (self.index_buffer) |ib| ib.bindIndex(self.index_type);
        gpu.draw(pipeline, .{
            .count = self.count,
            .indexed_vertex_offset = if (self.index_buffer) |_| 0 else null,
        });
    }
    pub fn new(
        vertices: []const f32,
        I: type,
        indices: []const I,
    ) !MeshRenderer {
        var result: MeshRenderer = .{ .index_type = switch (I) {
            u32 => .u32,
            u16 => .u16,
            u8 => .u8,
            else => @compileError("Invalid index type - " ++ @typeName(I)),
        } };
        result.vertex_buffer = try .create(vertices.len * @sizeOf(f32), .vertex);
        try result.vertex_buffer.loadSlice(f32, vertices, 0);

        if (indices.len > 0) {
            const index_buffer: gpu.Buffer = try .create(indices.len * @sizeOf(I), .index);
            try index_buffer.loadSlice(I, indices, 0);
            result.index_buffer = index_buffer;
            result.count = @intCast(indices.len);
        } else result.count = @intCast(vertices.len);
        return result;
    }
};
pub const RawRenderer = struct {};
