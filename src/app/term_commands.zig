const std = @import("std");
const CommandParse = @import("CommandParse");
const Date = @import("dates.zig");
const Database = @import("Database");

// NEW (BUDGET/TRANSACTION) NAME TYPE AMOUNT DESC -> ID
// EDIT ID ATTR NEW_VALUE -> *ID
// DELETE ID

pub const budgetItemType = enum {
    Budget,
    Transaction,
};

pub const budget_item = struct {
    name: []const u8,
    date: Date,
    type: budgetItemType,
    amount: u64, // <-- fixed point number div by 10
    desc: []const u8,
};

