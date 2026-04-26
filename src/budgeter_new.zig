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
        database_reader: *std.Io.Reader,
        database_writer: *std.Io.Writer,

        const Self = @This();

        pub fn init(given_reader: *std.Io.Reader, given_writer: *std.Io.Writer) Self {
            return .{
                .database_reader = given_reader,
                .database_writer = given_writer,
            };
        }

        pub fn addBudgetItem(bm: *Self, gpa: Allocator, budget_item: *const BudgeterItem(config)) !void {
            const budget_item_id = hash.Wyhash.hash(0, std.mem.asBytes(budget_item));
            const output_string = try std.fmt.allocPrint(gpa, "{s}{s}", .{ std.mem.asBytes(&budget_item_id), std.mem.asBytes(budget_item) });
            defer gpa.free(output_string);
            const w = try bm.database_writer.write(output_string);
            try bm.database_writer.flush();
            std.debug.print("bytes written: {d}\n", .{w});
        }
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
    // std.debug.print("{}\n", .{id});
    try std.testing.expect(id != 0);
}

// test "write file" {
//     const write_file_path = "./write_file.txt";
//     const alloc = std.testing.allocator;
//     var thread: std.Io.Threaded = .init(alloc, .{});
//     defer thread.deinit();
//     const io = thread.io();
//
//     var buff: [100]u8 = undefined;
//     var file = try std.Io.Dir.cwd().createFile(io, write_file_path, .{});
//     defer file.close(io);
//     var file_writer = file.writer(io, &buff);
//
//     var writer = &file_writer.interface;
//     const byte_written = try writer.write("Testing");
//     try file_writer.flush();
//     std.debug.print("written: {d}\n", .{byte_written});
// }

test "writing to file" {
    const write_file_path = "./src/write_test.txt";
    var alloc = std.testing.allocator;
    // var thread: std.Io.Threaded = .init(alloc, .{});
    // defer thread.deinit();

    const io = std.testing.io;

    const bm_config: BudgeterManagerConfig = .{ .description_length = 100, .member_size = 10, .name_length = 10 };
    const test_item = BudgeterItem(bm_config){ .amount = 1000, .budgeter_type = Datums.BudgeterType.Budget, .date = Date{ .day = 1, .month = 1, .year = 2000 }, .description = undefined, .tranaction_type = Datums.TransactionType.Fixed, .who = undefined };
    {
        const file = try std.Io.Dir.cwd().createFile(io, write_file_path, .{ .truncate = false });
        defer file.close(io);

        var buff: [1024]u8 = undefined;
        var file_reader = file.reader(io, buff[0..]);
        var file_writer = file.writer(io, buff[0..]);
        var bm = BudgeterManager(bm_config).init(&file_reader.interface, &file_writer.interface);

        try bm.addBudgetItem(alloc, &test_item);
    }

    const write_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, write_file_path, alloc, std.Io.Limit.limited(1024));
    defer alloc.free(write_contents);
    const r = write_contents.len;
    std.debug.print("bytes read: {d}\n", .{r});
    // defer alloc.free(write_file);

    // std.debug.print("{s}\n", .{write_contents});

    const budget_item_id = hash.Wyhash.hash(0, std.mem.asBytes(&test_item));
    const compare_string = try std.fmt.allocPrint(alloc, "{s}{s}", .{ std.mem.asBytes(&budget_item_id), std.mem.asBytes(&test_item) });
    defer alloc.free(compare_string);

    try std.testing.expectEqualStrings(compare_string, write_contents);
}
