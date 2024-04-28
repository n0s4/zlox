const VM = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

const builtin = @import("builtin");

const bc = @import("bytecode.zig");
const Chunk = bc.Chunk;
const OpCode = bc.OpCode;

const Value = @import("value.zig").Value;
const Object = @import("Object.zig").Object;
const ObjectList = @import("ObjectList.zig");

const Compiler = @import("Compiler.zig");

const debug = @import("debug.zig");

const stack_max = 256;

// chunk is never used until interpret, at which point it is given.
chunk: *Chunk = undefined,

objects: ObjectList,

// I chose to use an index over a many-pointer here as pointer subtraction
// is painful in Zig, and there is no real performance difference afaik.
/// The index of the *next* instruction to be read from the chunk.
ip: usize = 0,

stack: [stack_max]Value = undefined,

stack_top: usize = 0,

pub fn init(allocator: Allocator) VM {
    return .{
        .objects = ObjectList.init(allocator),
    };
}

pub fn deinit(self: *VM) void {
    self.objects.deinit();
}

const Error = error{ CompileTime, RunTime };

pub fn interpret(self: *VM, source: []u8, allocator: Allocator) Error!void {
    var chunk = Chunk.init(allocator);
    defer chunk.deinit();

    var compiler = Compiler.init(source);
    if (!compiler.compile(&chunk, &self.objects)) return Error.CompileTime;

    self.chunk = &chunk;
    try self.run();
}

fn run(self: *VM) Error!void {
    while (true) {
        if (comptime builtin.mode == .Debug) {
            print("          ", .{});
            for (self.stack[0..self.stack_top]) |value| {
                print("[ ", .{});
                value.print();
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
            .Nil => self.push(.nil),
            .True => self.push(.{ .boolean = true }),
            .False => self.push(.{ .boolean = false }),
            .Equal => {
                const b = self.pop();
                const a = self.pop();
                self.push(.{ .boolean = a.equals(b) });
            },
            .Greater => {
                const ops = try self.getNumberOperands();
                self.push(.{ .boolean = ops.left > ops.right });
            },
            .Less => {
                const ops = try self.getNumberOperands();
                self.push(.{ .boolean = ops.left < ops.right });
            },
            .Add => {
                if (self.peek(0).isObjectOf(.string) and self.peek(1).isObjectOf(.string)) {
                    self.concatenate() catch return Error.RunTime;
                } else if (self.peek(0).is(.number) and self.peek(1).is(.number)) {
                    const b = self.pop().number;
                    const a = self.pop().number;
                    self.push(.{ .number = a + b });
                } else {
                    self.runtimeError("Operands must be both numbers or strings.", .{});
                    return Error.RunTime;
                }
            },
            .Subtract => {
                const ops = try self.getNumberOperands();
                self.push(.{ .number = ops.left - ops.right });
            },
            .Multiply => {
                const ops = try self.getNumberOperands();
                self.push(.{ .number = ops.left * ops.right });
            },
            .Divide => {
                const ops = try self.getNumberOperands();
                self.push(.{ .number = ops.left / ops.right });
            },
            .Not => self.push(.{ .boolean = !isTruthy(self.pop()) }),
            .Negate => {
                if (!self.peek(0).is(.number)) {
                    self.runtimeError("Operand must be a number.", .{});
                    return Error.RunTime;
                }
                self.push(.{ .number = -self.pop().number });
            },
            .Return => {
                self.pop().print();
                print("\n", .{});
                return;
            },
        }
    }
}

fn concatenate(self: *VM) !void {
    const b = self.pop().object.string;
    const a = self.pop().object.string;
    const object = try self.objects.newString(a.len + b.len);
    std.mem.copyForwards(u8, object.string, a);
    std.mem.copyForwards(u8, object.string[a.len..], b);
    self.push(.{ .object = object });
}

/// Ensures both values at the top of the stack are numbers and returns them in order.
fn getNumberOperands(self: *VM) Error!struct { left: f32, right: f32 } {
    if (!self.peek(0).is(.number) or !self.peek(1).is(.number)) {
        self.runtimeError("Operands must be numbers.", .{});
        return Error.RunTime;
    }
    // The top value should be the rhs, so we pop them in reverse order.
    return .{ .right = self.pop().number, .left = self.pop().number };
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

fn peek(self: *VM, distance: usize) Value {
    return self.stack[self.stack_top - 1 - distance];
}

/// False and nil are falsey, all other values are truthy.
fn isTruthy(value: Value) bool {
    return switch (value) {
        .boolean => value.boolean,
        .nil => false,
        else => true,
    };
}

fn runtimeError(self: *VM, comptime fmt: []const u8, args: anytype) void {
    print(fmt, args);
    print("\n[line {d}] in script.\n", .{self.chunk.lines.items[self.ip - 1]});
    self.stack_top = 0;
}
