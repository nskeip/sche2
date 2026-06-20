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
    var currentCons: *Cons = firstCons;

    var i: u64 = 1;
    const idxOfClosingPar = tokens.len - 1;
    const lastIdx = idxOfClosingPar - 1;
    while (i < idxOfClosingPar) {
        const tok = tokens[i];
        switch (tok) {
            .integer, .symbol => {
                currentCons.car = try parseSingle(tok);
                if (i == lastIdx) {
                    currentCons.cdr = null;
                } else {
                    currentCons.cdr = try allocator.create(Cons);
                    currentCons = currentCons.cdr.?;
                }
                i += 1;
            },
            .lparen => {
                var subexprTokensIdx = i + 1;
                {
                    var openingParenNum: i64 = 1;
                    while (openingParenNum != 0 and subexprTokensIdx < tokens.len) {
                        if (tokens[subexprTokensIdx] == .lparen) {
                            openingParenNum += 1;
                        } else if (tokens[subexprTokensIdx] == .rparen) {
                            openingParenNum -= 1;
                        }
                        subexprTokensIdx += 1;
                    }
                    if (subexprTokensIdx >= tokens.len) {
                        return ParseError.UnmatchedParen;
                    }
                }
                currentCons.cdr = switch (try parse(allocator, tokens[i..subexprTokensIdx])) {
                    .cons => |c| c,
                    else => unreachable,
                };
                i = subexprTokensIdx;
            },
            .rparen => {
                return ParseError.UnmatchedParen;
            },
        }
    }

    return .{ .cons = firstCons };
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
        const newCopy = cThatIsNotNull.cdr;
        allocator.destroy(cThatIsNotNull);
        nullableC = newCopy;
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
    try expect(parsed.cons.cdr != null);

    const cons2 = parsed.cons.cdr.?;
    const v2 = cons2.car;
    try expect(v2.integer == 1);

    const cons3 = cons2.cdr.?;
    const v3 = cons3.car;
    try expect(v3.integer == 2);
    try expect(cons3.cdr == null);
}
