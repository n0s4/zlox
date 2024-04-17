const std = @import("std");
const gpa = std.heap.GeneralPurposeAllocator(.{});

const bytecode = @import("bytecode.zig");
const Chunk = bytecode.Chunk;
const OpCode = bytecode.OpCode;
const disassembleChunk = @import("debug.zig").disassembleChunk;

const VM = @import("VM.zig");

pub fn main() !void {
    var allocator = gpa{};
    var chunk = Chunk.init(allocator.allocator());
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

    disassembleChunk(&chunk, "the best chunk");

    var vm = VM{};
    try vm.interpret(&chunk);
}
