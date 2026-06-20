const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const t = @import("./types.zig");
const Env = t.Env;
const Value = t.Value;

fn makeRootEnv(allocator: std.mem.Allocator) Env {
    return Env{
        .table = std.StringHashMap(Value).init(allocator),
        .parent = null,
    };
}

fn cleanUpRootEnv(env: *Env) void {
    env.table.deinit();
}

test "trivial 42" {
    try expect((eval(std.testing.allocator, .{.integer = 42}, null).?).integer == 42);
}

test "trivial variable eval" {
    var env = makeRootEnv(std.testing.allocator);
    defer cleanUpRootEnv(&env);
    try env.table.put("x", .{ .integer = 42 });
    try expect((eval(std.testing.allocator, .{.symbol = "x"}, &env).?).integer == 42);
}

pub fn eval(allocator: std.mem.Allocator, input: Value, env: ?*Env) ?Value {
    _ = allocator;
    return switch (input) {
        .integer => |v| .{.integer = v},
        .symbol => |s| lookup(env, s),
        else => unreachable
    };
}

test "lookup" {
    var rootEnv = makeRootEnv(std.testing.allocator);
    defer cleanUpRootEnv(&rootEnv);
    try rootEnv.table.put("x", .{ .integer = 42 });
    try rootEnv.table.put("y", .{ .integer = 2000 });

    var env = makeRootEnv(std.testing.allocator);
    try env.table.put("y", .{ .integer = 269 });
    defer cleanUpRootEnv(&env);

    env.parent = &rootEnv;

    try expect(eval(std.testing.allocator, .{.symbol = "non-existing"}, &env) == null);
    try expect((eval(std.testing.allocator, .{.symbol = "x"}, &env).?).integer == 42);
    try expect((eval(std.testing.allocator, .{.symbol = "y"}, &env).?).integer == 269);
}

fn lookup(env: ?* const Env, name: []const u8) ?Value {
    var cur = env;

    while(cur) |e| : (cur = e.parent) {
        if(e.table.get(name)) |v| { return v; }
    }
    return null;
}

// pub fn eval(allocator: std.mem.Allocator, input: []const u8) !i64 {
//     if(input.len == 0) {
//         return 0;
//    }
//     // const trimmed = std.mem.trim(u8, input, " \t\n\r");
//     // return try std.fmt.parseInt(i64, trimmed, 10);
//     var tokens = try tokenize(allocator, input);
//     defer tokens.deinit(allocator);
// 
//     if(tokens.items.len == 1) {
//         return switch (tokens.items[0]) {
//             .integer => |v| v,
//             else => unreachable,  // TODO: should be error
//         };
//     }
// 
//     return 3;
// }
// 
// test "integer literal" {
//     try expect((try eval(std.testing.allocator, "  42 ")) == 42);
// }
// 
// test "simple addition" {
//     try expect((try eval(std.testing.allocator, "(+ 1 2)")) == 3);
// }
