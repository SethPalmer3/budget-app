const std = @import("std");
const CommandParse = @import("CommandParse");
const Date = @import("dates.zig");
const Database = @import("Database");

const name_length = 20;
const desc_length = 1000;

// NEW (BUDGET/TRANSACTION) NAME TYPE AMOUNT DESC -> ID
// EDIT ID ATTR NEW_VALUE -> *ID
// DELETE ID

pub const CLIError = error{
    UnknownCommand,
    NotEnoughArguments,
};

pub const budgetItemType = enum {
    Budget,
    Transaction,
};

pub const budgetItemCategory = enum {
     Income,
     Fixed,
     Variable,
     Loan,
     Save,
     Investment,
};

pub const budget_item = struct {
    name: [name_length]u8,
    date: Date,
    type: budgetItemType,
    category: budgetItemCategory,
    amount: u64, // <-- fixed point number div by 10
    desc: [desc_length]u8,

};

pub fn handleAdd(parsed: *CommandParse.Command) !void{
    const subcommand = try parsed.getNthArg(1);
    if(!std.mem.eql(u8, subcommand, "ADD")){return CLIError.UnknownCommand;} // Check subsubcommand

    if (parsed.num_arguments < 5){return CLIError.NotEnoughArguments;} // check arguments

    
}
