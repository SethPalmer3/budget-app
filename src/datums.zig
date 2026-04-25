/// File containing the datum structures that the
/// budget and transacation will be based around
/// including their "types"
const std = @import("std");
const hash = std.hash;
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
pub fn QueryBudgeterItem(comptime config: BudgeterManagerConfig) type {
    return struct {
        budgeter_type: ?Datums.BudgeterType,
        tranaction_type: ?Datums.TransactionType,
        who: ?[config.member_size][config.name_length]u8,
        amount: ?u64, // Will treat as a fix point value
        description: ?[config.description_length]u8,
        date: ?Date,
    };
}

pub fn BudgeterManager(comptime config: BudgeterManagerConfig) type {
    return struct {
        config: BudgeterManagerConfig = config,
        database_reader: std.Io.Reader,
        database_writer: std.Io.Writer,

        const Self = @This();

        // pub fn addBudgetItem(bm: *Self, budget_item: BudgeterItem(config)) !void {
        //     const id = hash.Wyhash.hash(0, budget_item);
        // }
        // pub fn readBudgetItem(bm: *Self, identifier: anytype) !BudgeterItem(config) { // Not sure yet what to use as a identifier
        //     // TODO: Implement
        // }
        // pub fn filterBudgetItems(bm: *Self, query: QueryBudgeterItem(config)) ![]BudgeterItem(config) {}
    };
}

test "test hash" {
    const conf = BudgeterManagerConfig{ .name_length = 8, .member_size = 10, .description_length = 10 };
    const item = BudgeterItem(conf){ .amount = 100, .budgeter_type = BudgeterType.Budget, .date = .{ .day = 10, .month = 10, .year = 2000 }, .description = undefined, .tranaction_type = TransactionType.Fixed, .who = undefined };
    const id = hash.Wyhash.hash(0, std.mem.asBytes(&item));
    std.debug.print("{}\n", .{id});
    try std.testing.expect(id != 0);
}
