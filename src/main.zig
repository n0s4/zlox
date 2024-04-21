const std = @import("std");
const Allocator = std.mem.Allocator;
const GPA = std.heap.GeneralPurposeAllocator(.{});
const print = std.debug.print;

const VM = @import("VM.zig");

pub fn main() !void {
    var gpa = GPA{};

    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    switch (args.len) {
        1 => try repl(gpa.allocator()),
        2 => try runFile(args[1], gpa.allocator()),
        else => {
            print("Usage: clox [path]\n", .{});
            std.process.exit(64);
        },
    }
}

fn repl(allocator: Allocator) !void {
    var line: [1024]u8 = undefined;
    var stdin = std.io.getStdIn().reader();
    while (true) {
        print("> ", .{});
        const code = stdin.readUntilDelimiter(&line, '\n') catch {
            print("\n", .{});
            break;
        };
        var vm = VM{};
        vm.interpret(code, allocator) catch |err| switch (err) {
            error.CompileTime => std.process.exit(65),
            error.RunTime => std.process.exit(70),
        };
    }
}

fn runFile(path: [:0]u8, allocator: Allocator) !void {
    var file = try std.fs.cwd().openFileZ(path, .{});
    const source = try file.readToEndAlloc(allocator, try file.getEndPos());
    var vm = VM{};
    try vm.interpret(source, allocator);
}
