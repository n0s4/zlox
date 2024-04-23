const std = @import("std");
const print = std.debug.print;
const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const Value = @import("value.zig").Value;

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
        .Constant => constantInstruction(instruction, chunk, offset),
        else => simpleInstruction(instruction, offset),
    };
}

fn simpleInstruction(instruction: OpCode, offset: usize) usize {
    print("{s}\n", .{@tagName(instruction)});
    return offset + 1;
}

fn constantInstruction(instruction: OpCode, chunk: *Chunk, offset: usize) usize {
    const constant = chunk.code.items[offset + 1];
    print("{s: <16} {d: >4} '", .{ @tagName(instruction), constant });
    chunk.constants.items[constant].print();
    print("'\n", .{});
    return offset + 2;
}
