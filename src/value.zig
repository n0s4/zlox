const std = @import("std");
const meta = std.meta;

pub const Value = union(enum) {
    pub const Type = std.meta.Tag(Value);

    nil,
    boolean: bool,
    number: f32,

    pub fn print(self: Value) void {
        switch (self) {
            .nil => std.debug.print("nil", .{}),
            .boolean => |b| std.debug.print("{}", .{b}),
            .number => |num| std.debug.print("{d}", .{num}),
        }
    }

    pub inline fn is(self: Value, t: Type) bool {
        return meta.activeTag(self) == t;
    }

    pub fn equals(self: Value, other: Value) bool {
        return meta.eql(self, other);
    }
};
