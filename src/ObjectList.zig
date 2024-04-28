//! A *temporary* memory management solution for objects so that we aren't
//! leaking memory until the GC is implemented. Every time a new object is
//! needed, it is appended to the list and a pointer to it is provided.
const Self = @This();

const std = @import("std");
const Object = @import("Object.zig").Object;
const Allocator = std.mem.Allocator;

head: ?*Node = null,

allocator: Allocator,

const Node = struct {
    next: ?*Node,
    object: Object,
};

pub fn init(allocator: Allocator) Self {
    return .{ .allocator = allocator };
}

pub fn deinit(self: *Self) void {
    var current = self.head;
    while (current) |node| {
        const next = node.next;
        switch (node.object) {
            .string => |chars| self.allocator.free(chars),
        }
        self.allocator.destroy(node);
        current = next;
    }
}

/// Creates a managed string object from a copy of `chars`.
pub fn newString(self: *Self, len: usize) !*Object {
    const string = try self.allocator.alloc(u8, len);
    var object = try self.newObject();
    object.string = string;
    return object;
}

/// Allocates a new object in the list and returns a reference to it.
fn newObject(self: *Self) !*Object {
    var node = try self.allocator.create(Node);
    node.next = self.head;
    self.head = node;
    return &node.object;
}
