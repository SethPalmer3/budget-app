const std = @import("std");
const TermCommands = @import("term_commands.zig");
const Record = TermCommands.Record;
const returnError = TermCommands.returnError;
const CLIError = TermCommands.CLIError;
const recordType = TermCommands.recordType;
const recordCategory = TermCommands.recordCategory;

const Diagnostic = @import("diagnostics.zig");
const Date = @import("dates.zig");
const CommandParse = @import("CommandParse");

// NEW TYPE DAY/MONTH/YEAR NAME CATEGORY AMOUNT DESC -> ID
pub fn handleAdd(parsed: *CommandParse.Command, diags: ?*Diagnostic) !Record{
    var next_arg: u64 = 1;
    const min_num_args = num_args: {
        const rec_info = @typeInfo(Record);
        const rec_fields = rec_info.@"struct".fields;
        break :num_args rec_fields.len;
    };
    const subcommand = try parsed.getNthArg(next_arg);
    next_arg += 1;
    var item: Record = undefined;
    //------------ Checking Sub command -------------------
    if(!std.mem.eql(u8, subcommand.name, "ADD")){
        return returnError(
            CLIError.UnknownCommand, "Cannot handle subcommands other than \"ADD\"\n", .{}, diags
        );
    } // Check subsubcommand

    if (parsed.num_arguments < min_num_args){ // check arguments
        return returnError(CLIError.NotEnoughArguments, "Too many arguments passed to the sub command, expected {d}\n", .{min_num_args}, diags);
    }
    //------------ Getting Record Type -------------------
    const item_type_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if( recordType.convertStrToItemType(item_type_str.name)) |item_type| {
        item.type = item_type;
    }else{ // Cannot convert argument to a type
        return returnError(CLIError.InvalidArgument, "Unkown type {s}\n", .{item_type_str.name}, diags);
    }
    //------------ Getting Record Date -------------------
    const item_date_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    var it = std.mem.splitAny(u8, item_date_str.name, "/");
    var temp_date: Date = undefined;
    if(it.next()) |day_str| { // Getting day
        temp_date.day = std.fmt.parseInt(u8, day_str, 10) catch |err| {
            return returnError(err, "Could not parse the day section \"{s}\"\n", .{day_str}, diags);
        };
    }
    if(it.next()) |month_str| { // Getting month
        temp_date.month = std.fmt.parseInt(u8, month_str, 10) catch |err| {
            return returnError(err, "Could not parse the month section \"{s}\"\n", .{month_str}, diags);
        };
    }else{
        return returnError(CLIError.InvalidArgument, "The date argument must have a month section\n", .{}, diags);
    }
    if(it.next()) |year_str| { // Getting month
        temp_date.year = std.fmt.parseInt(u64, year_str, 10) catch |err| {
            return returnError(err, "Could not parse the year section \"{s}\"\n", .{year_str}, diags);
        };
    }else{
        return returnError(
            CLIError.InvalidArgument, "The date argument must have a year section\n", .{}, diags
        );
    }
    item.date = temp_date;
    //------------ Getting Record Name -------------------
    const name_arg = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if (name_arg.name.len > Record.name_length){
        return returnError(CLIError.InvalidArgument, "Length of the name of the record is too large, must be at most {d} characters\n", .{Record.name_length}, diags);
    }
    std.mem.copyForwards(u8, &item.name, name_arg.name);
    //------------ Getting Record Category -------------------
    const item_category_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if(recordCategory.convertStrToCategory(item_category_str.name)) |item_category|{
        item.category = item_category;
    }else{
        return returnError(CLIError.InvalidArgument, "Unkown category {s}\n", .{item_category_str.name}, diags);
    }
    //------------ Getting Record Amount -------------------
    const item_amount_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    const parsed_float_from_arg = std.fmt.parseFloat(f32, item_amount_str.name) catch |err| {
        return returnError(err, "Cannot parse the given record amount \"{s}\"\n", .{item_amount_str.name}, diags);
    };
    item.amount = @trunc(parsed_float_from_arg * 100.0); // Multiplying by 100 for fixed point
    //------------ Getting Record Description -------------------
    var next_desc_position: u64 = 0;
    while(parsed.getNthArg(next_arg)) |arg| : (next_arg += 1)  {
        std.mem.copyForwards(u8, item.desc[next_desc_position..next_desc_position+arg.name.len], arg.name);
        item.desc[next_desc_position+arg.name.len] = ' '; // Include space
        next_desc_position += arg.name.len + 1;
    }else |_|{} // Discard error

    return item;
}

test handleAdd {
    // ADD TYPE DATE NAME CATEGORY AMOUNT DESC -> ID
    const test_str = "ADD Budget 1/1/2026 test Income 123.45 test desc";
    var diags: Diagnostic = .{};
    var parser = try CommandParse.Parser.parse(test_str, std.testing.allocator);
    defer parser.deinit(std.testing.allocator);
    const item = handleAdd(&parser, &diags) catch |err| {
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
