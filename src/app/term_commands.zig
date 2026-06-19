const std = @import("std");
const CommandParse = @import("CommandParse");
const Database = @import("Database");
const Date = @import("dates.zig");
pub const Diagnostic = @import("diagnostics.zig");
pub const AddCommand = @import("add_command.zig");
pub const ListCommand = @import("list_command.zig");

// const name_length = 20;
// const desc_length = 1000;

// NEW (BUDGET/TRANSACTION) NAME CATEGORY AMOUNT DESC -> ID
// EDIT ID ATTR NEW_VALUE -> *ID
// LIST ATTR -> RECORD
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
    pub fn convertStr(str: []const u8) ?Self{
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
     pub fn convertStr(str: []const u8) ?Self{
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
    pub const max_name_length = 20;
    pub const max_desc_length = 1000;
    const Self = @This();
    name_size: u64,
    name: [max_name_length]u8,
    date: Date,
    type: recordType,
    category: recordCategory,
    amount: u64, // <-- fixed point number div by 10
    desc_size: u64,
    desc: [max_desc_length]u8,

    pub fn display(self: *const Self, w: *std.Io.Writer) void {
        const type_info = @typeInfo(Self);
        const type_fields = type_info.@"struct".fields;
        inline for(type_fields) |field| {
            w.print("{s}: ", .{field.name}) catch {};
            switch (field.type) {
                recordType => w.print("{s}", .{@tagName(@field(self, field.name))}) catch {},
                recordCategory => w.print("{s}", .{@tagName(@field(self, field.name))}) catch {},
                u8,u16,u32,u64 => w.print("{d}", .{@field(self, field.name)}) catch {},
                Date => {
                    const d: Date = @field(self, field.name);
                    w.print("{d}/{d}/{d}", .{d.day, d.month, d.year}) catch {};
                },
                else => {
                    var display_length: usize = 0;
                    const unknown_field = @field(self, field.name);
                    const field_type = @TypeOf(unknown_field);
                    const field_info = @typeInfo(field_type);
                    if (field_info == .array) {
                        display_length = field_info.array.len;
                        const str = @as([field_info.array.len]u8, unknown_field);
                        std.debug.print("accessing field: {s}\n", .{field.name ++ "_size"});
                        if(@hasField(Self, field.name ++ "_size")){
                            display_length = @as(usize, @field(self, field.name ++ "_size"));
                        }
                        std.debug.print("display_length: {d}\n", .{display_length});
                        w.print("{s}", .{str[0..display_length]}) catch {};
                    }
                    else {
                        w.print("{any}", .{unknown_field}) catch {};
                    }
                }
            }
            w.print("\n", .{}) catch {};
        }
    }
};

pub fn returnError(err: anyerror, comptime fmt: []const u8, args: anytype, diag: ?*Diagnostic) anyerror {
    if(diag) |d| {
        d.msg_size = std.fmt.count(fmt, args);
        _ = std.fmt.bufPrint(&d.msg, fmt, args) catch {};
    }
    return err;
}

test {
    std.testing.refAllDecls(@This());
}
