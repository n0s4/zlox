const std = @import("std");
const Object = @import("Object.zig").Object;
const meta = std.meta;

/// A dynamically typed runtime value.
pub const Value = union(enum) {
    pub const Type = std.meta.Tag(Value);

    nil,
    boolean: bool,
    number: f32,
    object: *Object,

    pub fn print(self: Value) void {
        switch (self) {
            .nil => std.debug.print("nil", .{}),
            .boolean => |b| std.debug.print("{}", .{b}),
            .number => |num| std.debug.print("{d}", .{num}),
            .object => |obj| switch (obj.*) {
                .string => |s| std.debug.print("{s}", .{s}),
            },
        }
    }

    pub inline fn is(self: Value, t: Type) bool {
        return meta.activeTag(self) == t;
    }

    pub inline fn isObjectOf(self: Value, t: Object.Type) bool {
        return meta.activeTag(self) == .object and self.object.* == t;
    }

    pub fn equals(self: Value, other: Value) bool {
        return switch (self) {
            .object => |obj| other == .object and switch (obj.*) {
                .string => |s| std.mem.eql(u8, s, other.object.string),
            },
            else => meta.eql(self, other),
        };
    }
};
