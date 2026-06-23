const std = @import("std");
const Database = @import("Database");
const TermCommands = @import("term_commands.zig");
const cmdManager = @import("command_manager.zig");
const returnError = TermCommands.returnError;
const CLIError = TermCommands.CLIError;

const Diagnostic = @import("diagnostics.zig");
const CommandParse = @import("CommandParse");
const Domain = @import("Domain");
const Record = Domain.Record;
const recordType = Domain.RecordType;
const recordCategory = Domain.RecordCategory;
const Date = Domain.Date;

fn grabIndexFromStr(
        index_str: []const u8,
        comptime Key: []const u8,
        convertStr: *const fn([]const u8) ?@FieldType(Record, Key)
        ) ?@FieldType(Record, Key) {
    return convertStr(index_str);
}

const LIST_COMMAND_NAME = "LIST";

// LIST INDEX
pub fn handleList(
        comptime D: type,
        comptime R: type,
        comptime Key: []const u8,
        parsed: *CommandParse.Command,
        convertStr: *const fn([]const u8) ?@FieldType(D, Key),
        db: *Database.Database.Database(D, R, Key),
        write_out: *std.Io.Writer,
) ![]const D{
    var next_arg: u64 = 1;
    const min_num_args = 2;
    _ = try parsed.getNthArg(next_arg);
    next_arg += 1;
    if (parsed.num_arguments < min_num_args){ // check arguments
        try write_out.print(
            "Not enough arguments, expected {d} got {d}",
            .{min_num_args, parsed.num_arguments},
        );
        return CLIError.NotEnoughArguments;
    }
    //------------ Getting Index -------------------
    const index_str = (try parsed.getNthArg(next_arg)).name;
    if(grabIndexFromStr(index_str, Key, convertStr)) |conv_index| {
       return db.GetEntriesByIndex(conv_index) catch |err| {
           try write_out.print(
               "Could not get entries with that index {s}",
               .{index_str},
            );
           return err;
        };
    }
    try write_out.print(
        "Could not convert the index \"{s}\" correctly",
        .{index_str},
    );
    return TermCommands.CLIError.InvalidArgument;
}


pub fn contextPackage(
    comptime DataType: type,
    comptime RefType: type,
    comptime IndexKey: anytype,
) type {
    return struct {
        db: *Database.Database.Database(DataType, RefType, IndexKey),
        convertStr: *const fn([]const u8) ?@FieldType(DataType, IndexKey),
        displayData: *const fn(*const DataType, *std.Io.Writer) void,
    };
}
pub fn generateHandleList(
    comptime DataType: type,
    comptime RefType: type,
    comptime IndexKey: anytype,
)*const fn(*CommandParse.Command, *std.Io.Reader, *std.Io.Writer, *anyopaque) cmdManager.CommandState{
    return struct{
        pub fn execute(
            parsed: *CommandParse.Command,
            reader: *std.Io.Reader,
            writer: *std.Io.Writer,
            context: *anyopaque
        ) cmdManager.CommandState {
            _ = reader;
            const cntxt: *contextPackage(DataType, RefType, IndexKey) = @alignCast(@ptrCast(context));
            var db = cntxt.db;
            var next_arg: u64 = 1;
            const min_num_args = 2;
            _ = parsed.getNthArg(next_arg) catch {return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            if (parsed.num_arguments < min_num_args){ // check arguments
                writer.print(
                    "Not enough arguments, expected {d} got {d}",
                    .{min_num_args, parsed.num_arguments},
                ) catch {};
            return cmdManager.CommandState.ErrorContinue;
            }
            //------------ Getting Index -------------------
            const index_str = 
                (parsed.getNthArg(next_arg) catch {return cmdManager.CommandState.ErrorContinue;}).name;
            if(grabIndexFromStr(index_str, IndexKey, cntxt.convertStr)) |conv_index| {
                const items = db.GetEntriesByIndex(conv_index) catch {
                    writer.print(
                        "Could not get entries with that index {s}",
                        .{index_str},
                    ) catch {};
                    return cmdManager.CommandState.ErrorContinue;
                };
                defer db.alloc.free(items);
                writer.print("-----------------------\n", .{}) catch {};
                for(items) |*item| {
                    cntxt.displayData(item, writer);
                    writer.print("-----------------------\n", .{}) catch {};
                }
                return cmdManager.CommandState.Continue;
            }
            writer.print(
                "Could not convert the index \"{s}\" correctly",
                .{index_str},
            ) catch {};
            return cmdManager.CommandState.ErrorContinue;
        }
    }.execute;
}

