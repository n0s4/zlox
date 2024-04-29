//! Scans raw source code into tokens.
const Self = @This();

const std = @import("std");
const Token = @import("Token.zig");

source: []const u8,
start: usize = 0,
current: usize = 0,
line: u32 = 1,

pub fn init(source: []const u8) Self {
    return .{ .source = source };
}

fn makeToken(self: *Self, tok_type: Token.Type) Token {
    return .{
        .type = tok_type,
        .lexeme = self.source[self.start..self.current],
        .line = self.line,
    };
}

fn errorToken(self: *Self, message: []const u8) Token {
    return .{
        .type = .Error,
        .lexeme = message,
        .line = self.line,
    };
}

pub fn nextToken(self: *Self) Token {
    self.skipWhitespace();
    self.start = self.current;
    if (self.isAtEnd()) return self.makeToken(.EOF);

    const c = self.advance();
    if (isAlpha(c)) return self.identifier();
    if (isDigit(c)) return self.number();

    return switch (c) {
        '(' => self.makeToken(.LeftParen),
        ')' => self.makeToken(.RightParen),
        '{' => self.makeToken(.LeftBrace),
        '}' => self.makeToken(.RightBrace),
        ';' => self.makeToken(.Semicolon),
        ',' => self.makeToken(.Comma),
        '.' => self.makeToken(.Dot),
        '-' => self.makeToken(.Minus),
        '+' => self.makeToken(.Plus),
        '/' => self.makeToken(.Slash),
        '*' => self.makeToken(.Star),
        '!' => self.makeToken(if (self.match('=')) .BangEqual else .Bang),
        '=' => self.makeToken(if (self.match('=')) .EqualEqual else .Equal),
        '<' => self.makeToken(if (self.match('=')) .LessEqual else .Less),
        '>' => self.makeToken(if (self.match('=')) .GreaterEqual else .Greater),
        '"' => self.string(),
        else => self.errorToken("Unexpected character."),
    };
}

fn skipWhitespace(self: *Self) void {
    while (true) {
        switch (self.peek()) {
            ' ', '\t', '\r' => _ = self.advance(),
            '\n' => {
                self.line += 1;
                _ = self.advance();
            },
            '/' => if (self.peekNext() == '/') {
                while (!self.isAtEnd() and self.peek() != '\n')
                    _ = self.advance();
            } else return,
            else => break,
        }
    }
}

fn number(self: *Self) Token {
    while (isDigit(self.peek())) _ = self.advance();

    if (self.peek() == '.' and isDigit(self.peekNext())) {
        _ = self.advance();
        while (isDigit(self.peek())) _ = self.advance();
    }

    return self.makeToken(.Number);
}

fn identifier(self: *Self) Token {
    while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();
    return self.makeToken(self.identifierType());
}

fn identifierType(self: *Self) Token.Type {
    return switch (self.source[self.start]) {
        'a' => self.checkKeyword(1, "nd", .And),
        'c' => self.checkKeyword(1, "lass", .Class),
        'e' => self.checkKeyword(1, "lse", .Else),
        'f' => if (self.current > self.start)
            switch (self.source[self.start + 1]) {
                'a' => self.checkKeyword(2, "lse", .False),
                'o' => self.checkKeyword(2, "r", .For),
                'u' => self.checkKeyword(2, "n", .Fun),
                else => .Identifier,
            }
        else
            .Identifier,
        'i' => self.checkKeyword(1, "f", .If),
        'n' => self.checkKeyword(1, "il", .Nil),
        'o' => self.checkKeyword(1, "r", .Or),
        'p' => self.checkKeyword(1, "rint", .Print),
        'r' => self.checkKeyword(1, "eturn", .Return),
        's' => self.checkKeyword(1, "uper", .Super),
        't' => if (self.current > self.start)
            switch (self.source[self.start + 1]) {
                'h' => self.checkKeyword(2, "is", .This),
                'r' => self.checkKeyword(2, "ue", .True),
                else => .Identifier,
            }
        else
            .Identifier,
        'v' => self.checkKeyword(1, "ar", .Var),
        'w' => self.checkKeyword(1, "hile", .While),
        else => .Identifier,
    };
}

fn checkKeyword(
    self: Self,
    start: usize,
    rest: []const u8,
    tok_type: Token.Type,
) Token.Type {
    if (self.current - self.start == start + rest.len and
        std.mem.eql(u8, self.source[self.start + start .. self.current], rest))
    {
        return tok_type;
    }

    return .Identifier;
}

fn string(self: *Self) Token {
    while (!self.isAtEnd() and self.peek() != '"') {
        if (self.peek() == '\n') self.line += 1;
        _ = self.advance();
    }

    if (self.isAtEnd()) return self.errorToken("Unterminated string.");

    _ = self.advance();
    return self.makeToken(.String);
}

fn advance(self: *Self) u8 {
    self.current += 1;
    return self.source[self.current - 1];
}

fn peek(self: *Self) u8 {
    if (self.isAtEnd()) return '\x00';
    return self.source[self.current];
}

fn peekNext(self: *Self) u8 {
    if (self.current + 1 >= self.source.len) return '\x00';
    return self.source[self.current + 1];
}

fn match(self: *Self, char: u8) bool {
    if (self.peek() != char) return false;
    _ = self.advance();
    return true;
}

fn isAtEnd(self: *Self) bool {
    return self.current >= self.source.len;
}

fn isAlpha(c: u8) bool {
    return ('a' <= c and c <= 'z') or
        ('A' <= c and c <= 'Z') or
        c == '_';
}

fn isDigit(c: u8) bool {
    return '0' <= c and c <= '9';
}

const expectEqual = std.testing.expectEqual;
const expectEqualSlces = std.testing.expectEqualSlices;

test Self {
    const source =
        \\fun add(a, b) {
        \\    return a + b;
        \\}
    ;
    const expected = [_]Token{
        .{ .type = .Fun, .lexeme = "fun", .line = 1 },
        .{ .type = .Identifier, .lexeme = "add", .line = 1 },
        .{ .type = .LeftParen, .lexeme = "(", .line = 1 },
        .{ .type = .Identifier, .lexeme = "a", .line = 1 },
        .{ .type = .Comma, .lexeme = ",", .line = 1 },
        .{ .type = .Identifier, .lexeme = "b", .line = 1 },
        .{ .type = .RightParen, .lexeme = ")", .line = 1 },
        .{ .type = .LeftBrace, .lexeme = "{", .line = 1 },
        .{ .type = .Return, .lexeme = "return", .line = 2 },
        .{ .type = .Identifier, .lexeme = "a", .line = 2 },
        .{ .type = .Plus, .lexeme = "+", .line = 2 },
        .{ .type = .Identifier, .lexeme = "b", .line = 2 },
        .{ .type = .Semicolon, .lexeme = ";", .line = 2 },
        .{ .type = .RightBrace, .lexeme = "}", .line = 3 },
        .{ .type = .EOF, .lexeme = "", .line = 3 },
    };

    var scanner = Self.init(source);

    for (expected) |exp| {
        const actual = scanner.nextToken();
        try expectEqual(exp.type, actual.type);
        try expectEqual(exp.line, actual.line);
        try expectEqualSlces(u8, exp.lexeme, actual.lexeme);
    }
}
