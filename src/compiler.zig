const std = @import("std");
const print = std.debug.print;
const bytecode = @import("bytecode.zig");
const Scanner = @import("Scanner.zig");

pub fn compile(source: []u8) void {
    var scanner = Scanner.init(source);
    var line: u32 = 0;
    while (true) {
        const token = scanner.nextToken();
        if (token.line != line) {
            line = token.line;
            print("{d: >4} ", .{line});
        } else print("   | ", .{});

        print("{s} '{s}'\n", .{ @tagName(token.type), token.lexeme });

        if (token.type == .EOF) break;
    }
}
