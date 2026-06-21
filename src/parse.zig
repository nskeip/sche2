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

    const result = Value{ .cons = try allocator.create(Cons)};
    result.cons.cdr = .nil;
    var currentCons: *Cons = result.cons;

    var i: u64 = 1;
    const idxOfClosingPar = tokens.len - 1;
    while (i < idxOfClosingPar) {
        var nextI: u64 = undefined;
        switch (tokens[i]) {
            .integer, .symbol => {
                currentCons.car = try parseSingle(tokens[i]);
                nextI = i + 1;
            },
            .lparen => {
                const subexprEnd = i + (try calcCurrentSubexprEnd(tokens[i..]));
                switch (try parse(allocator, tokens[i..subexprEnd])) {
                    .cons => |c| currentCons.car = Value{ .cons = c },
                    else => unreachable,
                }
                nextI = subexprEnd;
            },
            .rparen => return ParseError.UnmatchedParen,
            .dot => nextI = i + 1,
        }
        const haveMoreTokens = nextI < idxOfClosingPar;
        if (haveMoreTokens and tokens[i] != .dot and tokens[nextI] != .dot) {
            const nextCons = try allocator.create(Cons);
            nextCons.cdr = .nil;
            currentCons.cdr = .{ .cons = nextCons };
            currentCons = nextCons;
        } else if (tokens[i] == .dot and tokens[nextI] != .lparen) {
            if (nextI + 1 != idxOfClosingPar) return ParseError.UnexpectedToken;
            currentCons.cdr = try parseSingle(tokens[nextI]);
            return result;
        } else if (tokens[i] == .dot and tokens[nextI] == .lparen) {
            const subexprOffset = try calcCurrentSubexprEnd(tokens[nextI..]);
            const subexprEnd = nextI + subexprOffset;
            if (subexprEnd != idxOfClosingPar) return ParseError.UnexpectedToken;
            switch (try parse(allocator, tokens[nextI..subexprEnd])) {
                .cons => |c| currentCons.cdr = .{ .cons = c },
                else => unreachable,
            }
            return result;
        }
        i = nextI;
    }

    return result;
}

fn calcCurrentSubexprEnd(tokens: []const Token) !usize {
    var endIdx: usize = 1;
    {
        var depth: i64 = 1;  // we have already opened
        while (depth != 0 and endIdx < tokens.len) {
            if (tokens[endIdx] == .lparen) {
                depth += 1;
            } else if (tokens[endIdx] == .rparen) {
                depth -= 1;
            }
            endIdx += 1;
        }
        if (endIdx >= tokens.len) {
            return ParseError.UnmatchedParen;
        }
    }
    return endIdx;
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
        .lparen, .rparen, .dot => ParseError.UnexpectedToken,
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

test "(1 2) is a list" {
    const tokens = [_]Token{
        .lparen,
        .{ .integer = 1 },
        .{ .integer = 2 },
        .rparen,
    };

    const parsed = try parse(std.testing.allocator, &tokens);
    defer consDeinit(std.testing.allocator, parsed.cons);
    try expect(parsed.cons.car.integer == 1);

    const cons2 = parsed.cons.cdr.cons;
    const v2 = cons2.car;
    try expect(v2.integer == 2);
}

test "(1 . 2) is a pair" {
    const tokens = [_]Token{
        .lparen,
        .{ .integer = 1 },
        .dot,
        .{ .integer = 2 },
        .rparen,
    };

    const parsed = try parse(std.testing.allocator, &tokens);
    defer consDeinit(std.testing.allocator, parsed.cons);
    try expect(parsed.cons.car.integer == 1);
    try expect(parsed.cons.cdr.integer == 2);  // TODO: fixme
}

test "(1 2 . 3) is allowed" {
    // TODO: add test
    // TODO: check the pair at the end (should have (2, 3) pair)
}

test "(1 . 2 3) is not allowed" {
    // TODO: add test
}

// TODO: complex example of (1 . (2 . 3))

