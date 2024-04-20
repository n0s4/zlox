const std = @import("std");
const Value = @import("value.zig").Value;
const printValue = @import("value.zig").printValue;
const debug = @import("debug.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const print = std.debug.print;

/// A bytecode instruction.
pub const OpCode = enum(u8) {
    Constant,
    Add,
    Subtract,
    Multiply,
    Divide,
    Negate,
    Return,
};

/// A chunk of bytecode.
pub const Chunk = struct {
    /// Bytecode Instructions.
    code: ArrayList(u8),
    /// Stores the line number for each corresponding byte in `.code`.
    /// code.items.len == lines.items.len.
    lines: ArrayList(u32),
    constants: ArrayList(Value),

    pub fn init(allocator: Allocator) Chunk {
        return Chunk{
            .code = ArrayList(u8).init(allocator),
            .lines = ArrayList(u32).init(allocator),
            .constants = ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.lines.deinit();
        self.constants.deinit();
    }

    pub fn write(self: *Chunk, byte: u8, line: u32) Allocator.Error!void {
        try self.code.append(byte);
        try self.lines.append(line);
    }

    pub fn addConstant(self: *Chunk, value: Value) Allocator.Error!usize {
        try self.constants.append(value);
        return self.constants.items.len - 1;
    }
};

test Chunk {
    const allocator = std.testing.allocator;
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    var constant = try chunk.addConstant(1.2);
    try chunk.write(@intFromEnum(OpCode.Constant), 123);
    try chunk.write(@intCast(constant), 123);

    constant = try chunk.addConstant(3.4);
    try chunk.write(@intFromEnum(OpCode.Constant), 123);
    try chunk.write(@intCast(constant), 123);

    try chunk.write(@intFromEnum(OpCode.Add), 123);

    constant = try chunk.addConstant(5.6);
    try chunk.write(@intFromEnum(OpCode.Constant), 123);
    try chunk.write(@intCast(constant), 123);

    try chunk.write(@intFromEnum(OpCode.Divide), 123);
    try chunk.write(@intFromEnum(OpCode.Negate), 123);

    try chunk.write(@intFromEnum(OpCode.Return), 123);

    debug.disassembleChunk(&chunk, "the best chunk");
}
