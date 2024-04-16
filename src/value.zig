const std = @import("std");

pub const Value = f32;

pub fn printValue(value: Value) void {
    std.debug.print("{d}", .{value});
}
