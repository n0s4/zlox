const VM = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const builtin = @import("builtin");

const bc = @import("bytecode.zig");
const Chunk = bc.Chunk;
const OpCode = bc.OpCode;

const v = @import("value.zig");
const Value = v.Value;
const printValue = v.printValue;

const Compiler = @import("Compiler.zig");

const debug = @import("debug.zig");

const stack_max = 256;

// chunk is never used until interpret, at which point it is given.
chunk: *Chunk = undefined,

// I chose to use an index over a many-pointer here as pointer subtraction
// is painful in Zig, and there is no real performance difference afaik.
ip: usize = 0,

stack: [stack_max]Value = undefined,

stack_top: usize = 0,

const Error = error{ CompileTime, RunTime };

pub fn interpret(self: *VM, source: []u8, allocator: Allocator) Error!void {
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    var compiler = Compiler.init(source);
    if (!compiler.compile(&chunk)) return Error.CompileTime;

    self.chunk = &chunk;
    try self.run();
}

fn run(self: *VM) Error!void {
    while (true) {
        if (comptime builtin.mode == .Debug) {
            print("          ", .{});
            for (self.stack[0..self.stack_top]) |value| {
                print("[ ", .{});
                printValue(value);
                print(" ]", .{});
            }
            print("\n", .{});
            _ = debug.disassembleInstruction(self.chunk, self.ip);
        }

        const instruction: OpCode = @enumFromInt(self.readByte());
        switch (instruction) {
            .Constant => {
                const constant = self.readConstant();
                self.push(constant);
            },
            .Add => {
                const b = self.pop();
                const a = self.pop();
                self.push(a + b);
            },
            .Subtract => {
                const b = self.pop();
                const a = self.pop();
                self.push(a - b);
            },
            .Multiply => {
                const b = self.pop();
                const a = self.pop();
                self.push(a * b);
            },
            .Divide => {
                const b = self.pop();
                const a = self.pop();
                self.push(a / b);
            },
            .Negate => self.push(-self.pop()),
            .Return => {
                printValue(self.pop());
                print("\n", .{});
                return;
            },
        }
    }
}

fn readByte(self: *VM) u8 {
    self.ip += 1;
    return self.chunk.code.items[self.ip - 1];
}

fn readConstant(self: *VM) Value {
    return self.chunk.constants.items[self.readByte()];
}

fn push(self: *VM, value: Value) void {
    self.stack[self.stack_top] = value;
    self.stack_top += 1;
}

fn pop(self: *VM) Value {
    self.stack_top -= 1;
    return self.stack[self.stack_top];
}
