const std = @import("std");
const Value = @import("value.zig").Value;
const printValue = @import("value.zig").printValue;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const print = std.debug.print;

/// A bytecode instruction.
pub const OpCode = enum(u8) {
    Constant,
    Return,
};

/// A chunk of bytecode.
pub const Chunk = struct {
    const LineNo = u32;

    /// Bytecode Instructions.
    code: ArrayList(u8),
    /// Stores the line number for each corresponding byte in `.code`.
    /// code.items.len == lines.items.len.
    lines: ArrayList(LineNo),
    constants: ArrayList(Value),

    pub fn init(allocator: Allocator) Chunk {
        return Chunk{
            .code = ArrayList(u8).init(allocator),
            .lines = ArrayList(LineNo).init(allocator),
            .constants = ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit();
        self.lines.deinit();
        self.constants.deinit();
    }

    pub fn write(self: *Chunk, byte: u8, line: LineNo) Allocator.Error!void {
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

    const constant = try chunk.addConstant(1.2);
    try chunk.write(@intFromEnum(OpCode.Constant), 123);
    try chunk.write(@intCast(constant), 123);

    try chunk.write(@intFromEnum(OpCode.Return), 123);

    disassembleChunk(&chunk, "the best chunk");
}

/// Prints a human-readable representation of bytecode.
pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len)
        offset = disassembleInstruction(chunk, offset);
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    print("{d:0>4} ", .{offset});

    const line = chunk.lines.items[offset];
    if (offset > 0 and line == chunk.lines.items[offset - 1]) {
        print("   | ", .{});
    } else {
        print("{d: >4} ", .{line});
    }

    const byte = chunk.code.items[offset];
    std.debug.assert(byte < @typeInfo(OpCode).Enum.fields.len);
    const instruction: OpCode = @enumFromInt(byte);

    return switch (instruction) {
        .Return => simpleInstruction(instruction, offset),
        .Constant => constantInstruction(instruction, chunk, offset),
    };
}

fn simpleInstruction(instruction: OpCode, offset: usize) usize {
    print("{s}\n", .{@tagName(instruction)});
    return offset + 1;
}

fn constantInstruction(instruction: OpCode, chunk: *Chunk, offset: usize) usize {
    const constant = chunk.code.items[offset + 1];
    print("{s: <16} {d: >4} '", .{ @tagName(instruction), constant });
    printValue(chunk.constants.items[constant]);
    print("'\n", .{});
    return offset + 2;
}
