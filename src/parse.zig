const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const t = @import("types.zig");
const Cons = t.Cons;
const Token = t.Token;
const Value = t.Value;
const ParseError = t.ParseError;

pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) ParseError!Value {
    if (tokens.len == 0) {
        return ParseError.NoExpressionFound;
    } else if (tokens.len == 1) {
        return parseSingle(tokens[0]);
    } else if (tokens[0] != .lparen or tokens[tokens.len - 1] != .rparen) {
        return ParseError.UnmatchedParen;
    }

    const firstCons = try allocator.create(Cons);
    firstCons.cdr = .nil;
    var currentCons: *Cons = firstCons;

    var i: u64 = 1;
    const idxOfClosingPar = tokens.len - 1;
    while (i < idxOfClosingPar) {
        const tok = tokens[i];
        switch (tok) {
            .integer, .symbol => {
                currentCons.car = try parseSingle(tok);
                i += 1;
            },
            .lparen => {
                var subexprEnd = i + 1;
                {
                    var openingParenNum: i64 = 1;
                    while (openingParenNum != 0 and subexprEnd < tokens.len) {
                        if (tokens[subexprEnd] == .lparen) {
                            openingParenNum += 1;
                        } else if (tokens[subexprEnd] == .rparen) {
                            openingParenNum -= 1;
                        }
                        subexprEnd += 1;
                    }
                    if (subexprEnd >= tokens.len) {
                        return ParseError.UnmatchedParen;
                    }
                }
                switch (try parse(allocator, tokens[i..subexprEnd])) {
                    .cons => |c| currentCons.car = Value{ .cons = c },
                    else => unreachable,
                }
                i = subexprEnd;
            },
            .rparen => {
                return ParseError.UnmatchedParen;
            },
        }
        if (i < idxOfClosingPar) {
            const nextCons = try allocator.create(Cons);
            nextCons.cdr = .nil;
            currentCons.cdr = .{ .cons = nextCons };
            currentCons = nextCons;
        }
    }

    // return first_expr;
    return .{ .cons = firstCons };
}

fn debugPrintValue(v: Value) !void {
    switch (v) {
        .integer => |i| std.debug.print(" {d} ", .{i}),
        .symbol => |s| std.debug.print(" '{s}' ", .{s}),
        .nil => std.debug.print(" nil ", .{}),
        .cons => |c| {
            var nullableC: ?*Cons = c;
            std.debug.print(" ( ", .{});
            while(nullableC) |cThatIsNotNull| {
                try debugPrintValue(cThatIsNotNull.car);
                std.debug.print(" , ", .{});
                nullableC = cThatIsNotNull.cdr;
            }
            std.debug.print(" ) ", .{});
        }
    }
    std.debug.print("\n", .{});
}

fn parseSingle(token: Token) ParseError!Value {
    return switch (token) {
        .lparen, .rparen => ParseError.UnexpectedToken,
        .integer => |v| .{ .integer = v },
        .symbol => |s| if (std.mem.eql(u8, "nil", s)) .nil else .{ .symbol = s },
    };
}

pub fn consDeinit(allocator: std.mem.Allocator, c: *Cons) void {
    var nullableC: ?*Cons = c;
    while (nullableC) |cThatIsNotNull| {
        if (cThatIsNotNull.car == .cons) {
            consDeinit(allocator, cThatIsNotNull.car.cons);
        }
        const next = switch(cThatIsNotNull.cdr) {
            .cons => |innerC| innerC,
            else => null,
        };
        allocator.destroy(cThatIsNotNull);
        nullableC = next;
    }
}

test "single token numeric" {
    const tokens = [_]Token{
        .{ .integer = 100500 },
    };
    const parsed = try parse(std.testing.allocator, &tokens);
    try expect(parsed.integer == 100500);
}

test "signle token nil" {
    const tokens = [_]Token{.{ .symbol = "nil" }};

    const parsed = try parse(std.testing.allocator, &tokens);
    try expect(parsed == .nil);
}

test "simple (+ 1 2)" {
    const tokens = [_]Token{
        .lparen,
        .{ .symbol = "+" },
        .{ .integer = 1 },
        .{ .integer = 2 },
        .rparen,
    };

    const parsed = try parse(std.testing.allocator, &tokens);
    defer consDeinit(std.testing.allocator, parsed.cons);
    try expect(std.mem.eql(u8, parsed.cons.car.symbol, "+"));
    try expect(parsed.cons.cdr != .nil);

    const cons2 = parsed.cons.cdr.cons;
    const v2 = cons2.car;
    try expect(v2.integer == 1);

    const cons3 = cons2.cdr.cons;
    const v3 = cons3.car;
    try expect(v3.integer == 2);
    try expect(cons3.cdr == .nil);
}

test "simple (+ (- 5 4) 40 1)" {
    const tokens = [_]Token{
        .lparen,
        .{ .symbol = "+" },

        // zig fmt: off
            .lparen,
            .{ .symbol = "-" },
            .{ .integer = 5 },
            .{ .integer = 4 },
            .rparen,

        // zig fmt: off
        .{ .integer = 10 },
        .{ .integer = 1 },
        .rparen,
    };

    const parsed = try parse(std.testing.allocator, &tokens);
    defer consDeinit(std.testing.allocator, parsed.cons);
    try expect(std.mem.eql(u8, parsed.cons.car.symbol, "+"));

    const cons2 = parsed.cons.cdr.cons;
    const inner = cons2.car.cons;
    try expect(std.mem.eql(u8, inner.car.symbol, "-"));
    try expect(inner.cdr.cons.car.integer == 5);
    try expect(inner.cdr.cons.cdr.cons.car.integer == 4);
    try expect(inner.cdr.cons.cdr.cons.cdr == .nil);

    const cons3 = cons2.cdr.cons;
    try expect(cons3.car.integer == 10);

    const cons4 = cons3.cdr.cons;
    try expect(cons4.car.integer == 1);
    try expect(cons4.cdr == .nil);
}
