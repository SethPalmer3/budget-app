/// File containing the datum structures that the
/// budget and transacation will be based around
/// including their "types"
const std = @import("std");
const Allocator = std.mem.Allocator;
const Date = @import("./date.zig");
const Datums = @This();

pub const BudgeterType = enum {
    Budget,
    Actual,
};

pub const TransactionType = enum {
    Income,
    Fixed,
    Variable,
    Loan,
    Saving,
};

pub const BudgeterManagerConfig = struct {
    member_size: u8,
    description_length: usize,
    name_length: usize,
    database_writer: std.Io.Writer,
    database_reader: std.Io.Reader,
};

pub fn BudgeterItem(comptime config: BudgeterManagerConfig) type {
    return struct {
        budgeter_type: Datums.BudgeterType,
        tranaction_type: Datums.TransactionType,
        who: [config.member_size][config.name_length]u8,
        amount: u64, // Will treat as a fix point value
        description: [config.description_length]u8,
        date: Date,
    };
}

pub fn BudgeterManager(comptime config: BudgeterManagerConfig) type {
    return struct {
        config: BudgeterManagerConfig = config,

        const Self = @This();

        pub fn addBudgetItem(bm: *Self, budget_item: BudgeterItem(config)) !void {
            // TODO: Implement
        }
        pub fn readBudgetItem(bm: *Self, identifier: anytype) !BudgeterItem(config) { // Not sure yet what to use as a identifier
            // TODO: Implement
        }
    };
}
