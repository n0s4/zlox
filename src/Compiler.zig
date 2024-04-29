/// Parses tokens output by Scanner and compiles into a chunk.
const Compiler = @This();

const std = @import("std");
const builtin = @import("builtin");
const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
const bc = @import("bytecode.zig");
const Value = @import("value.zig").Value;
const Object = @import("Object.zig");
const ObjectList = @import("ObjectList.zig");
const debug = @import("debug.zig");
const print = std.debug.print;
const Chunk = bc.Chunk;
const OpCode = bc.OpCode;

scanner: Scanner,

// The compiler only needs to view 2 tokens at any given time while parsing.
current: Token = undefined,
previous: Token = undefined,

/// Target chunk to write code to.
chunk: *Chunk,

objects: *ObjectList,

/// Set during parsing if at least one error is encountered.
had_error: bool = false,
/// Set after an error to prevent cascading errors from being reported.
panic_mode: bool = false,

pub fn init(source: []const u8, chunk: *Chunk, objects: *ObjectList) Compiler {
    return .{
        .scanner = Scanner.init(source),
        .chunk = chunk,
        .objects = objects,
    };
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
    addRule(&table, .Nil, .{ .prefix = literal });
    addRule(&table, .False, .{ .prefix = literal });
    addRule(&table, .True, .{ .prefix = literal });
    addRule(&table, .EqualEqual, .{ .infix = binary, .precedence = .Equality });
    addRule(&table, .BangEqual, .{ .infix = binary, .precedence = .Equality });
    addRule(&table, .Greater, .{ .infix = binary, .precedence = .Comparison });
    addRule(&table, .GreaterEqual, .{ .infix = binary, .precedence = .Comparison });
    addRule(&table, .Less, .{ .infix = binary, .precedence = .Comparison });
    addRule(&table, .LessEqual, .{ .infix = binary, .precedence = .Comparison });
    addRule(&table, .Bang, .{ .prefix = unary });
    addRule(&table, .Minus, .{ .prefix = unary, .infix = binary, .precedence = .Term });
    addRule(&table, .Plus, .{ .infix = binary, .precedence = .Term });
    addRule(&table, .Star, .{ .infix = binary, .precedence = .Factor });
    addRule(&table, .Slash, .{ .infix = binary, .precedence = .Factor });
    addRule(&table, .Number, .{ .prefix = number });
    addRule(&table, .String, .{ .prefix = string });

    break :blk table;
};

fn getRule(tok_type: Token.Type) *const ParseRule {
    return &rules[@intFromEnum(tok_type)];
}

pub fn compile(self: *Compiler) bool {
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
    const num = try std.fmt.parseFloat(f32, self.previous.lexeme);
    try self.emitConstant(.{ .number = num });
}

fn string(self: *Compiler) !void {
    const str = self.previous.lexeme;
    // slicing out the surrounding quotation marks.
    const chars = str[1 .. str.len - 1];

    const object = try self.objects.newString(chars.len);
    std.mem.copyForwards(u8, object.string, chars);
    try self.emitConstant(.{ .object = object });
}

fn unary(self: *Compiler) !void {
    const operator_type = self.previous.type;

    try self.parsePrecedence(.Unary);

    try self.emitOp(switch (operator_type) {
        .Bang => .Not,
        .Minus => .Negate,
        else => unreachable,
    });
}

fn binary(self: *Compiler) !void {
    const operator_type = self.previous.type;
    const rule = getRule(operator_type);
    try self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

    try switch (operator_type) {
        .EqualEqual => self.emitOp(.Equal),
        .Greater => self.emitOp(.Greater),
        .Less => self.emitOp(.Less),
        .BangEqual => self.emitOps(.Equal, .Not),
        .GreaterEqual => self.emitOps(.Less, .Not),
        .LessEqual => self.emitOps(.Greater, .Not),
        .Plus => self.emitOp(.Add),
        .Minus => self.emitOp(.Subtract),
        .Star => self.emitOp(.Multiply),
        .Slash => self.emitOp(.Divide),
        else => unreachable,
    };
}

fn literal(self: *Compiler) !void {
    try self.emitOp(switch (self.previous.type) {
        .False => .False,
        .True => .True,
        .Nil => .Nil,
        else => unreachable,
    });
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

fn emitOp(self: *Compiler, op: OpCode) !void {
    try self.emitByte(@intFromEnum(op));
}

fn emitOps(self: *Compiler, op1: OpCode, op2: OpCode) !void {
    try self.emitBytes(@intFromEnum(op1), @intFromEnum(op2));
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
