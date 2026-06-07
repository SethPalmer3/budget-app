const std = @import("std");
const CommandParse = @import("CommandParse");
const Date = @import("dates.zig");
const Database = @import("Database");

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

pub fn handleAdd(parsed: *CommandParse.Command) !budget_item{
    const subcommand = try parsed.getNthArg(1);
    var item: budget_item = .{};
    if(!std.mem.eql(u8, subcommand.name, "ADD")){return CLIError.UnknownCommand;} // Check subsubcommand

    if (parsed.num_arguments < 5){return CLIError.NotEnoughArguments;} // check arguments
    // Get item type
    const item_type_str = try parsed.getNthArg(2);
    if( budgetItemType.convertStrToItemType(item_type_str)) |item_type| {
        item.type = item_type;
    }else{
        return CLIError.InvalidArgument;
    }
    // get the name 
    const name_arg = try parsed.getNthArg(3);
    if (name_arg.name.len > 20){
        return CLIError.InvalidArgument;
    }
    std.mem.copyForwards(u8, &item.name, (try parsed.getNthArg(3)).name);
    // get the budget category
    const item_category_str = try parsed.getNthArg(4);
    if(budgetItemCategory.convertStrToCategory(item_category_str)) |item_category|{
        item.category = item_category;
    }
    // get ammount
    const item_amount_str = try parsed.getNthArg(4);
    item.amount = @intFromFloat(std.fmt.parseFloat(f32, item_amount_str.name) * 100);
    // get description
}
