/// Parses tokens output by Scanner and compiles into a chunk.
const Compiler = @This();

const std = @import("std");
const builtin = @import("builtin");
const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
const bc = @import("bytecode.zig");
const Value = @import("value.zig").Value;
const debug = @import("debug.zig");
const print = std.debug.print;
const Chunk = bc.Chunk;
const OpCode = bc.OpCode;

scanner: Scanner,
current: Token = undefined,
previous: Token = undefined,

chunk: *Chunk = undefined,

had_error: bool = false,
panic_mode: bool = false,

pub fn init(source: []const u8) Compiler {
    return .{ .scanner = Scanner.init(source) };
}

const Precedence = enum {
    None,
    Assignment, // =
    Or, // or
    And, // and
    Equality, // == !=
    Comparison, // < > <= >=
    Term, // + -
    Factor, // * /
    Unary, // ! -
    Call, // . ()
    Primary,
};

const ParseFn = *const fn (*Compiler) anyerror!void;

const ParseRule = struct {
    prefix: ?ParseFn = null,
    infix: ?ParseFn = null,
    precedence: Precedence = .None,
};

const rules = blk: {
    const num_tokens = @typeInfo(Token.Type).Enum.fields.len;
    var table = [_]ParseRule{.{}} ** num_tokens;

    const addRule = struct {
        fn addRule(t: []ParseRule, tok_type: Token.Type, rule: ParseRule) void {
            t[@intFromEnum(tok_type)] = rule;
        }
    }.addRule;

    addRule(&table, .LeftParen, .{ .prefix = grouping });
    addRule(&table, .Minus, .{ .prefix = unary, .infix = binary, .precedence = .Term });
    addRule(&table, .Plus, .{ .infix = binary, .precedence = .Term });
    addRule(&table, .Star, .{ .infix = binary, .precedence = .Factor });
    addRule(&table, .Slash, .{ .infix = binary, .precedence = .Factor });
    addRule(&table, .Number, .{ .prefix = number });

    break :blk table;
};

fn getRule(tok_type: Token.Type) *const ParseRule {
    return &rules[@intFromEnum(tok_type)];
}

pub fn compile(self: *Compiler, chunk: *Chunk) bool {
    self.chunk = chunk;
    self.advance();
    self.expression() catch return false;
    self.consume(.EOF, "Expect end of expression.");
    self.emitByte(@intFromEnum(OpCode.Return)) catch return false;
    if (comptime builtin.mode == .Debug) {
        if (!self.had_error) debug.disassembleChunk(self.chunk, "code");
    }
    return !self.had_error;
}

fn expression(self: *Compiler) !void {
    try self.parsePrecedence(.Assignment);
}

fn parsePrecedence(self: *Compiler, precedence: Precedence) !void {
    self.advance();
    const prefixRule = getRule(self.previous.type).prefix orelse {
        self.errorAtPrevious("Expect expression");
        return;
    };

    try prefixRule(self);

    while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.current.type).precedence)) {
        self.advance();
        const infixRule = getRule(self.previous.type).infix.?;
        try infixRule(self);
    }
}

fn grouping(self: *Compiler) !void {
    try self.expression();
    self.consume(.RightParen, "Expect ')' after expression.");
}

fn number(self: *Compiler) !void {
    const value = try std.fmt.parseFloat(f32, self.previous.lexeme);
    try self.emitConstant(value);
}

fn unary(self: *Compiler) !void {
    const operator_type = self.previous.type;
    std.debug.assert(operator_type == .Minus);

    try self.parsePrecedence(.Unary);

    try self.emitByte(@intFromEnum(OpCode.Negate));
}

fn binary(self: *Compiler) !void {
    const operator_type = self.previous.type;
    const rule = getRule(operator_type);
    try self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

    try self.emitByte((switch (operator_type) {
        .Plus => @intFromEnum(OpCode.Add),
        .Minus => @intFromEnum(OpCode.Subtract),
        .Star => @intFromEnum(OpCode.Multiply),
        .Slash => @intFromEnum(OpCode.Divide),
        else => unreachable,
    }));
}

fn emitConstant(self: *Compiler, value: Value) !void {
    try self.emitBytes(
        @intFromEnum(OpCode.Constant),
        @intCast(try self.makeConstant(value)),
    );
}

fn makeConstant(self: *Compiler, value: Value) !usize {
    const constant = try self.chunk.addConstant(value);
    if (constant > std.math.maxInt(u8)) {
        self.errorAtPrevious("Too many constants in one chunk.");
        return error.TooManyConstants;
    }
    return constant;
}

fn emitByte(self: *Compiler, byte: u8) !void {
    try self.chunk.write(byte, self.previous.line);
}

fn emitBytes(self: *Compiler, byte1: u8, byte2: u8) !void {
    try self.emitByte(byte1);
    try self.emitByte(byte2);
}

fn advance(self: *Compiler) void {
    self.previous = self.current;

    while (true) {
        self.current = self.scanner.nextToken();
        if (self.current.type != .Error) break;

        self.errorAtCurrent(self.current.lexeme);
    }
}

fn consume(self: *Compiler, tok_type: Token.Type, message: []const u8) void {
    if (self.current.type == tok_type) {
        self.advance();
        return;
    }
    self.errorAtCurrent(message);
}

fn errorAtCurrent(self: *Compiler, message: []const u8) void {
    self.errorAt(&self.current, message);
}

fn errorAtPrevious(self: *Compiler, message: []const u8) void {
    self.errorAt(&self.previous, message);
}

fn errorAt(self: *Compiler, token: *Token, message: []const u8) void {
    if (self.panic_mode) return;
    self.panic_mode = true;
    print("[line {d}] Error", .{token.line});
    switch (token.type) {
        .Error => {},
        .EOF => print(" at end", .{}),
        else => print(" at {s}", .{token.lexeme}),
    }
    print(": {s}\n", .{message});
    self.had_error = true;
}
