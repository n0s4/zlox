const std = @import("std");

/// A dynamically allocated runtime value.
pub const Object = union(enum) {
    pub const Type = std.meta.Tag(Object);
    string: []u8,
};
