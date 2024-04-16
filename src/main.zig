const std = @import("std");
const gpa = std.heap.GeneralPurposeAllocator(.{});

const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const disassembleChunk = @import("debug.zig").disassembleChunk;

pub fn main() !void {
    var allocator = gpa{};
    var chunk = Chunk.init(allocator.allocator());
    defer chunk.deinit();

    const constant = try chunk.addConstant(1.2);
    try chunk.write(@intFromEnum(OpCode.Constant), 123);
    try chunk.write(@intCast(constant), 123);

    try chunk.write(@intFromEnum(OpCode.Return), 123);

    disassembleChunk(&chunk, "the best chunk");
}
