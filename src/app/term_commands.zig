const std = @import("std");
const CommandParse = @import("CommandParse");
const Date = @import("dates.zig");
const Database = @import("Database");
const Diagnostic = @import("diagnostics.zig");
pub const AddCommand = @import("add_command.zig");

// const name_length = 20;
// const desc_length = 1000;

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

pub const recordType = enum {
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

pub const recordCategory = enum {
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

pub const Record = struct {
    pub const name_length = 20;
    pub const desc_length = 1000;
    name: [name_length]u8,
    date: Date,
    type: recordType,
    category: recordCategory,
    amount: u64, // <-- fixed point number div by 10
    desc: [desc_length]u8,
};

pub fn returnError(err: anyerror, comptime fmt: []const u8, args: anytype, diag: ?*Diagnostic) anyerror {
    if(diag) |d| {
        _ = std.fmt.bufPrint(&d.msg, fmt, args) catch {};
    }
    return err;
}

test {
    std.testing.refAllDecls(@This());
}
