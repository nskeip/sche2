const std = @import("std");

pub const Token = union(enum) {
    lparen,
    rparen,
    integer: i64,
    symbol: []const u8,
};

pub const Value = union(enum) {
    integer: i64,
    symbol: []const u8,
    cons: *Cons,
    nil, // TODO: remove, use null as cons
};

pub const Cons = struct {
    car: Value,
    cdr: ?*Cons,
};

pub const Env = struct {
    table: std.StringHashMap(Value),
    parent: ?*Env,
};

pub const ParseError = error {
    NoExpressionFound,
    UnexpectedToken,
    UnmatchedParen,
    OutOfMemory,
};
