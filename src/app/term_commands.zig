const std = @import("std");
const CommandParse = @import("CommandParse");
const Date = @import("dates.zig").Date;
const Database = @import("Database");
const Diagnostic = @import("diagnostics.zig");

const name_length = 20;
const desc_length = 1000;

// NEW (BUDGET/TRANSACTION) NAME CATEGORY AMOUNT DESC -> ID
// EDIT ID ATTR NEW_VALUE -> *ID
// DELETE ID

pub const CLIError = error{
    UnknownCommand,
    NotEnoughArguments,
    InvalidCommand,
    InvalidArgument,
    InvalidOption,
};

pub const budgetItemType = enum {
    const Self = @This();
    Budget,
    Transaction,
     pub fn convertStrToItemType(str: []const u8) ?Self{
         const map = comptime blk: {
             @setEvalBranchQuota(2000);
             const fields = @typeInfo(Self).@"enum".fields;
             var kv: [fields.len]struct {[]const u8, Self} = undefined;
             for (fields, 0..) |field, i| {
                 kv[i] = .{ field.name, @field(Self, field.name) }; 
             }
             break :blk std.StaticStringMap(Self).initComptime(&kv);
         };
         return map.get(str);
     }
};

pub const budgetItemCategory = enum {
    const Self = @This();
     Income,
     Fixed,
     Variable,
     Loan,
     Save,
     Investment,
     pub fn convertStrToCategory(str: []const u8) ?Self{
         const map = comptime blk: {
             @setEvalBranchQuota(2000);
             const fields = @typeInfo(Self).@"enum".fields;
             var kv: [fields.len]struct {[]const u8, Self} = undefined;
             for (fields, 0..) |field, i| {
                 kv[i] = .{ field.name, @field(Self, field.name) }; 
             }
             break :blk std.StaticStringMap(Self).initComptime(&kv);
         };
         return map.get(str);
     }
};

pub const budget_item = struct {
    name: [name_length]u8,
    date: Date,
    type: budgetItemType,
    category: budgetItemCategory,
    amount: u64, // <-- fixed point number div by 10
    desc: [desc_length]u8,
};

fn returnError(err: anyerror, msg: []const u8, diag: ?*Diagnostic) anyerror {
    if(diag) |d| {
        d.msg = msg;
    }
    return err;
}

// NEW (BUDGET/TRANSACTION) NAME CATEGORY AMOUNT DESC -> ID
pub fn handleAdd(parsed: *CommandParse.Command, diags: ?*Diagnostic) !budget_item{
    var next_arg: u64 = 1;
    const subcommand = try parsed.getNthArg(next_arg);
    next_arg += 1;
    var item: budget_item = undefined;
    if(!std.mem.eql(u8, subcommand.name, "ADD")){
        return returnError(CLIError.UnknownCommand,  "Cannot handle subcommands other than \"ADD\"", diags);
    } // Check subsubcommand

    if (parsed.num_arguments < 5){ // check arguments
        return returnError(CLIError.NotEnoughArguments,  "Too many arguments passed to the sub command", diags);
    }
    // Get item type
    const item_type_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if( budgetItemType.convertStrToItemType(item_type_str.name)) |item_type| {
        item.type = item_type;
    }else{
        return returnError(CLIError.InvalidArgument, "(WIP)Unkown budget item", diags);
    }
    // get the name 
    const name_arg = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if (name_arg.name.len > name_length){
        return CLIError.InvalidArgument;
    }
    std.mem.copyForwards(u8, &item.name, name_arg.name);
    // get the budget category
    const item_category_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if(budgetItemCategory.convertStrToCategory(item_category_str.name)) |item_category|{
        item.category = item_category;
    }else{
        return CLIError.InvalidArgument;
    }
    // get ammount
    const item_amount_str = try parsed.getNthArg(next_arg);
    next_arg += 1;
    item.amount = @trunc((try std.fmt.parseFloat(f32, item_amount_str.name)) * 100.0);
    // get description
    var next_desc_position: u64 = 0;
    while(parsed.getNthArg(next_arg)) |arg| : (next_arg += 1)  {
        std.mem.copyForwards(u8, item.desc[next_desc_position..next_desc_position+arg.name.len], arg.name);
        item.desc[next_desc_position+arg.name.len] = ' '; // Include space
        next_desc_position += arg.name.len + 1;
    }else |_|{} // Discard error

    item.date = .{.day = 0, .month = 0, .year = 0};

    return item;
}

test handleAdd {
    // ADD (BUDGET/TRANSACTION) NAME CATEGORY AMOUNT DESC -> ID
    const test_str = "ADD Budget test Income 123.45 test desc";
    var parser = try CommandParse.Parser.parse(test_str, std.testing.allocator);
    defer parser.deinit(std.testing.allocator);
    const item = try handleAdd(&parser);

    try std.testing.expect(item.type == .Budget);
    try std.testing.expectEqualStrings("test", item.name[0..4]);
    try std.testing.expect(item.category == .Income);
    try std.testing.expect(item.amount == 12345);
    try std.testing.expectEqualStrings("test desc ", item.desc[0..10]);
}
