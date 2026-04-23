/// File containing the datum structures that the
/// budget and transacation will be based around
/// including their "types"
const std = @import("std");
const Allocator = std.mem.Allocator;
const Date = @import("./date.zig");
const Datums = @This();

pub const Type = enum {
    Income,
    Fixed,
    Variable,
    Loan,
    Saving,
};

pub const BudgetManagerConfig = struct {
    member_size: u8,
    description_length: usize,
    name_length: usize,
    database_writer: std.Io.Writer,
    database_reader: std.Io.Reader,
};

pub fn BudgetManager(comptime config: BudgetManagerConfig) type {
    return struct {
        member_size: u8 = config.member_size,
        description_length: usize = config.description_length,
        name_length: usize = config.name_length,
        database_writer: std.Io.Writer = config.writer,
        database_reader: std.Io.Reader = config.reader,

        const Self = @This();
    };
}
