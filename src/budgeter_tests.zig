const std = @import("std");
const hash = std.hash;
const budgeter = @import("./budgeter.zig");
const Date = @import("./date.zig");
test "test hash" {
    const conf = budgeter.BudgeterManagerConfig{ .name_length = 8, .member_size = 10, .description_length = 10 };
    const item = budgeter.BudgeterItem(conf){ .amount = 100, .budgeter_type = budgeter.BudgeterType.Budget, .date = .{ .day = 10, .month = 10, .year = 2000 }, .description = undefined, .tranaction_type = budgeter.TransactionType.Fixed, .who = undefined };
    const id = hash.Wyhash.hash(0, std.mem.asBytes(&item));
    try std.testing.expect(id != 0);
}

test "writing to file" {
    const write_file_path = "./src/write_test.txt";
    var alloc = std.testing.allocator;
    const io = std.testing.io;

    const bm_config: budgeter.BudgeterManagerConfig =
        .{ .description_length = 100, .member_size = 10, .name_length = 10 };
    const test_item =
        budgeter.BudgeterItem(bm_config){ .amount = 1000, .budgeter_type = budgeter.BudgeterType.Budget, .date = Date{ .day = 1, .month = 1, .year = 2000 }, .description = undefined, .tranaction_type = budgeter.TransactionType.Fixed, .who = undefined };
    {
        const file = try std.Io.Dir.cwd().createFile(io, write_file_path, .{ .truncate = false });
        defer file.close(io);

        var buff: [1024]u8 = undefined;
        var file_reader = file.reader(io, &buff);
        var file_writer = file.writer(io, &buff);
        var bm = budgeter.BudgeterManager(bm_config).init(&file_reader.interface, &file_writer.interface);

        _ = try bm.addBudgetItem(alloc, &test_item);
    }

    const write_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, write_file_path, alloc, std.Io.Limit.limited(1024));
    defer alloc.free(write_contents);

    const budget_item_id = hash.Wyhash.hash(0, std.mem.asBytes(&test_item));
    const compare_string = try std.fmt.allocPrint(alloc, "{s}{s}", .{ std.mem.asBytes(&budget_item_id), std.mem.asBytes(&test_item) });
    defer alloc.free(compare_string);

    try std.testing.expectEqualStrings(compare_string, write_contents);
}

test "reconstruct from file" {
    const write_file_path = "./src/rec_test.txt";
    var alloc = std.testing.allocator;

    const io = std.testing.io;

    const bm_config: budgeter.BudgeterManagerConfig =
        .{ .description_length = 100, .member_size = 10, .name_length = 10 };
    var test_item =
        budgeter.BudgeterItem(bm_config){ .amount = 1000, .budgeter_type = budgeter.BudgeterType.Budget, .date = Date{ .day = 1, .month = 1, .year = 2000 }, .description = undefined, .tranaction_type = budgeter.TransactionType.Fixed, .who = undefined };
    {
        const file = try std.Io.Dir.cwd().createFile(io, write_file_path, .{ .truncate = false });
        defer file.close(io);

        var buff: [1024]u8 = undefined;
        var file_reader = file.reader(io, &buff);
        var file_writer = file.writer(io, &buff);
        var bm = budgeter.BudgeterManager(bm_config).init(&file_reader.interface, &file_writer.interface);

        _ = try bm.addBudgetItem(alloc, &test_item);
    }

    const write_contents = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, write_file_path, alloc, std.Io.Limit.limited(1024));
    defer alloc.free(write_contents);
    const reconstructed_test_item: *budgeter.BudgeterItem(bm_config) =
        @alignCast(std.mem.bytesAsValue(budgeter.BudgeterItem(bm_config), write_contents[@sizeOf(u64)..]));

    try std.testing.expectEqualDeep(test_item, reconstructed_test_item.*);
}

test "item description copy" {
    const bm_config: budgeter.BudgeterManagerConfig =
        .{ .description_length = 100, .member_size = 10, .name_length = 10 };
    var test_item =
        budgeter.BudgeterItem(bm_config){ .amount = 1000, .budgeter_type = budgeter.BudgeterType.Budget, .date = Date{ .day = 1, .month = 1, .year = 2000 }, .description = undefined, .tranaction_type = budgeter.TransactionType.Fixed, .who = undefined };
    const test_phrase = "Testing";
    const len = test_phrase.len;
    test_item.write_description(test_phrase);
    try std.testing.expectEqualStrings(test_phrase, test_item.description[0..len]);
}
