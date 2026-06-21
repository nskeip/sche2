const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const t = @import("types.zig");
const Cons = t.Cons;
const Token = t.Token;
const Value = t.Value;
const ParseError = t.ParseError;

const Cursor = struct {
    tokens: []const Token,
    pos: usize,

    fn peek(self: *Cursor) ?Token {
        return if (self.pos < self.tokens.len) self.tokens[self.pos] else null;
    }

    fn advance(self: *Cursor) !Token {
        if (self.pos >= self.tokens.len) {
            return ParseError.UnexpectedEnd;
        }
        const tok = self.tokens[self.pos];
        self.pos += 1;
        return tok;
    }
};

pub fn parse(allocator: std.mem.Allocator, tokens: []const Token) ParseError!Value {
    var cursor = Cursor{ .tokens = tokens, .pos = 0 };
    const result = try parseExpr(allocator, &cursor);
    return result;
}

fn parseExpr(allocator: std.mem.Allocator, cursor: *Cursor) ParseError!Value {
    return switch (cursor.peek() orelse return ParseError.NoExpressionFound) {
        .lparen => parseList(allocator, cursor),
        .integer, .symbol => parseSingle(try cursor.advance()),
        .rparen, .dot => ParseError.UnexpectedToken,
    };
}

fn parseList(allocator: std.mem.Allocator, cursor: *Cursor) !Value {
    _ = try cursor.advance(); // consume `(`

    if (cursor.peek().? == .rparen) {
        _ = try cursor.advance(); // consume `)`
        return .nil;
    }

    const firstCons = try allocator.create(Cons);
    firstCons.car = .nil;
    firstCons.cdr = .nil;
    errdefer consDeinit(allocator, firstCons);
    var current = firstCons;

    while (cursor.peek().? != .rparen) {
        current.car = try parseExpr(allocator, cursor);

        if (cursor.peek().? == .dot) {
            _ = try cursor.advance(); // consume `.`
            current.cdr = try parseExpr(allocator, cursor);
            if (cursor.peek().? != .rparen) return ParseError.UnexpectedToken;
            break;
        }

        if (cursor.peek().? != .rparen) {
            const nextCons = try allocator.create(Cons);
            nextCons.car = .nil;
            nextCons.cdr = .nil;
            current.cdr = .{ .cons = nextCons };
            current = nextCons;
        } else {
            current.cdr = .nil;
        }
    }

    _ = try cursor.advance(); // consume `)`
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
            while (nullableC) |cThatIsNotNull| {
                try debugPrintValue(cThatIsNotNull.car);
                std.debug.print(" , ", .{});
                nullableC = cThatIsNotNull.cdr;
            }
            std.debug.print(" ) ", .{});
        },
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
        const next = switch (cThatIsNotNull.cdr) {
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
    const tokens = [_]Token{
        .lparen,
        .{ .integer = 1 },
        .{ .integer = 2 },
        .dot,
        .{ .integer = 3 },
        .rparen,
    };

    const parsed = try parse(std.testing.allocator, &tokens);
    defer consDeinit(std.testing.allocator, parsed.cons);
    try expect(parsed.cons.car.integer == 1);
    
    const cons2 = parsed.cons.cdr.cons;
    try expect(cons2.car.integer == 2);
    try expect(cons2.cdr.integer == 3);
}

test "(1 . 2 3) is not allowed" {
    const tokens = [_]Token{
        .lparen,
        .{ .integer = 1 },
        .dot,
        .{ .integer = 2 },
        .{ .integer = 3 },
        .rparen,
    };

    try std.testing.expectError(ParseError.UnexpectedToken, parse(std.testing.allocator, &tokens));
}

test "(1 . (2 . 3))" {
    const tokens = [_]Token{
        .lparen,
        .{ .integer = 1 },
        .dot,
        .lparen,
        .{ .integer = 2 },
        .dot,
        .{ .integer = 3 },
        .rparen,
        .rparen,
    };

    const parsed = try parse(std.testing.allocator, &tokens);
    defer consDeinit(std.testing.allocator, parsed.cons);
    try expect(parsed.cons.car.integer == 1);
    try expect(parsed.cons.cdr.cons.car.integer == 2);
    try expect(parsed.cons.cdr.cons.cdr.integer == 3);
}

