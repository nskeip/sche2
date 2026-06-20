const std = @import("std");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const t = @import("types.zig");
const Token = t.Token;

pub fn tokenize(allocator: std.mem.Allocator, input: []const u8) !std.ArrayList(Token) {
    var tokens: std.ArrayList(Token) = .empty;

    var i: usize = 0;

    while (i < input.len) {
        const ch = input[i];

        switch (ch) {
            ' ', '\n', '\t', '\r' => {
                i += 1;
            },
            '(' => {
                try tokens.append(allocator, .lparen);
                i += 1;
            },
            ')' => {
                try tokens.append(allocator, .rparen);
                i += 1;
            },
            else => {
                if (std.ascii.isDigit(ch)) {
                    const start = i;

                    while (i < input.len and std.ascii.isDigit(input[i])) {
                        i += 1;
                    }

                    const text = input[start..i];

                    try tokens.append(allocator, .{
                        .integer = try std.fmt.parseInt(i64, text, 10),
                    });

                    continue;
                }
                const start = i;

                while (i < input.len and
                    !std.ascii.isWhitespace(input[i]) and
                    input[i] != '(' and
                    input[i] != ')')
                {
                    i += 1;
                }

                try tokens.append(allocator, .{
                    .symbol = input[start..i],
                });
            },
        }
    }

    return tokens;
}

test "tokenize simple expression" {
    var tokens = try tokenize(
        std.testing.allocator,
        "(+ 1 2)",
    );
    defer tokens.deinit(std.testing.allocator);

    try expectEqual(@as(usize, 5), tokens.items.len);

    try expect(tokens.items[0] == .lparen);
    try expect(tokens.items[1] == .symbol);
    try expect(tokens.items[2] == .integer);
    try expect(tokens.items[3] == .integer);
    try expect(tokens.items[4] == .rparen);
}

