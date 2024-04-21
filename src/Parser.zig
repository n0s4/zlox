const Parser = @This();
const std = @import("std");
const print = std.debug.print;
const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");

scanner: Scanner,
current: Token = undefined,
previous: Token = undefined,
had_error: bool = false,
panic_mode: bool = false,

pub fn init(source: []const u8) Parser {
    return .{ .scanner = Scanner.init(source) };
}
