/// File containing the datum structures that the
/// budget and transacation will be based around
/// including their "types"
const std = @import("std");
// const read_implementations = @import("./db_read_impl.zig");
// const defaultImpl = read_implementations.simpleImple;
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

        const Self = @This();

        pub fn write_description(item: *Self, data: []const u8) void {
            @memset(&item.description, 0);
            const len = @min(item.description.len, data.len);
            @memcpy(item.description[0..len], data[0..len]);
        }
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
        const Self = @This();
        config: BudgeterManagerConfig = config,
        database_reader: *std.Io.Reader,
        database_writer: *std.Io.Writer,
        // _readitems: *const fn (comptime BudgeterManagerConfig, std.Io.Reader, anytype) anyerror!BudgeterItem(config),

        pub fn init(given_reader: *std.Io.Reader, given_writer: *std.Io.Writer) Self {
            return .{
                .database_reader = given_reader,
                .database_writer = given_writer,
                // ._readitems = defaultImpl,
            };
        }

        pub fn addBudgetItem(bm: *Self, gpa: Allocator, budget_item: *const BudgeterItem(config)) !u64 {
            const budget_item_id: u64 = hash.Wyhash.hash(0, std.mem.asBytes(budget_item));
            const output_string = try std.fmt.allocPrint(gpa, "{s}{s}", .{ std.mem.asBytes(&budget_item_id), std.mem.asBytes(budget_item) });
            defer gpa.free(output_string);
            _ = try bm.database_writer.write(output_string);
            try bm.database_writer.flush();
            return budget_item_id;
        }
        // pub fn readBudgetItem(bm: *Self, identifier: anytype) !BudgeterItem(config) { // Not sure yet what to use as a identifier
        //     return bm._readitems(config, identifier);
        // }
        // pub fn filterBudgetItems(bm: *Self, query: QueryBudgeterItem(config)) ![]BudgeterItem(config) {}
    };
}
