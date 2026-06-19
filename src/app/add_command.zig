const std = @import("std");
const TermCommands = @import("term_commands.zig");
const returnError = TermCommands.returnError;
const CLIError = TermCommands.CLIError;

const Diagnostic = @import("diagnostics.zig");
const CommandParse = @import("CommandParse");
const Domain = @import("Domain");
const Record = Domain.Record;
const recordType = Domain.RecordType;
const recordCategory = Domain.RecordCategory;
const Date = Domain.Date;

// ADD TYPE DAY/MONTH/YEAR NAME CATEGORY AMOUNT DESC -> ID
pub fn handleAdd(parsed: *CommandParse.Command, write_out: *std.Io.Writer) !Record{
    var next_arg: u64 = 1;
    const min_num_args = num_args: {
        const rec_info = @typeInfo(Record);
        const rec_fields = rec_info.@"struct".fields;
        break :num_args rec_fields.len;
    };
    _ = try parsed.getNthArg(next_arg);
    next_arg += 1;
    var item: Record = undefined;
    //------------ Checking Sub command -------------------
    if (parsed.num_arguments < min_num_args){ // check arguments
        _ = try write_out.print("Too many arguments passed to the sub command, expected {d}\n", .{min_num_args});
        return CLIError.NotEnoughArguments;
    }
    //------------ Getting Record Type -------------------
    const item_type_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if( recordType.convertStr(item_type_str.name)) |item_type| {
        item.type = item_type;
    }else{ // Cannot convert argument to a type
        _ = try write_out.print("Unkown type {s}\n", .{item_type_str.name});
        return CLIError.InvalidArgument;
    }
    //------------ Getting Record Date -------------------
    const item_date_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if(Date.convertStr(item_date_str.name)) |date| {
        item.date = date;
    }else{
        _ = try write_out.print("Could not parse the date correctly\n", .{});
        return CLIError.InvalidArgument;
    }
    //------------ Getting Record Name -------------------
    const name_arg = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if (name_arg.name.len > Record.max_name_length){
        _ = try write_out.print("Length of the name of the record is too large, must be at most {d} characters\n", .{Record.max_name_length});
        return CLIError.InvalidArgument;
    }
    std.mem.copyForwards(u8, &item.name, name_arg.name);
    item.name_size = name_arg.name.len;
    //------------ Getting Record Category -------------------
    const item_category_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if(recordCategory.convertStr(item_category_str.name)) |item_category|{
        item.category = item_category;
    }else{
        _ = try write_out.print("Unkown category {s}\n", .{item_category_str.name});
        return CLIError.InvalidArgument;
    }
    //------------ Getting Record Amount -------------------
    const item_amount_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    const parsed_float_from_arg = std.fmt.parseFloat(f32, item_amount_str.name) catch |err| {
        _ = try write_out.print("Cannot parse the given record amount \"{s}\"\n", .{item_amount_str.name});
        return err;
    };
    item.amount = @trunc(parsed_float_from_arg * 100.0); // Multiplying by 100 for fixed point
    //------------ Getting Record Description -------------------
    var next_desc_position: u64 = 0;
    while(parsed.getNthArg(next_arg)) |arg| : (next_arg += 1)  {
        std.mem.copyForwards(u8, item.desc[next_desc_position..next_desc_position+arg.name.len], arg.name);
        item.desc[next_desc_position+arg.name.len] = ' '; // Include space
        next_desc_position += arg.name.len + 1;
    }else |_|{} // Discard error
    item.desc_size = next_desc_position;

    return item;
}

test handleAdd {
    // ADD TYPE DATE NAME CATEGORY AMOUNT DESC -> ID
    var debug_writer = std.Io.File.stderr().writer(std.testing.io, &.{});
    const gen_writer = &debug_writer.interface;

    const test_str = "ADD Budget 1/1/2026 test Income 123.45 test desc";
    var diags: Diagnostic = .{};
    var parser = try CommandParse.Parser.parse(test_str, std.testing.allocator);
    defer parser.deinit(std.testing.allocator);
    const item = handleAdd(&parser, gen_writer) catch |err| {
        std.debug.print("{s}", .{std.mem.sliceTo(&diags.msg, 0)});
        return err;
    };

    try std.testing.expect(item.type == .Budget);
    try std.testing.expectEqual(item.date, Date{.day = 1, .month = 1, .year = 2026});
    try std.testing.expectEqualStrings("test", item.name[0..4]);
    try std.testing.expect(item.category == .Income);
    try std.testing.expect(item.amount == 12345);
    try std.testing.expectEqualStrings("test desc ", item.desc[0..10]);
}
