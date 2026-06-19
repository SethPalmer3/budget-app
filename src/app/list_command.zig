const std = @import("std");
const Databases = @import("Database");
const TermCommands = @import("term_commands.zig");
const Record = TermCommands.Record;
const returnError = TermCommands.returnError;
const CLIError = TermCommands.CLIError;
const recordType = TermCommands.recordType;
const recordCategory = TermCommands.recordCategory;

const Diagnostic = @import("diagnostics.zig");
const Date = @import("dates.zig");
const CommandParse = @import("CommandParse");

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
        convertStr: *const fn([]const u8) ?@FieldType(Record, Key),
        db: *Databases.Database.Database(D, R, Key),
        diags: ?*Diagnostic
        ) ![]const D{
    var next_arg: u64 = 1;
    const min_num_args = 2;
    const subcommand = try parsed.getNthArg(next_arg);
    next_arg += 1;
    //------------ Checking Sub command -------------------
    if(!std.mem.eql(u8, subcommand.name, LIST_COMMAND_NAME)){
        return returnError(
            CLIError.UnknownCommand,
            "Cannot handle subcommands other than \"" ++ LIST_COMMAND_NAME ++ "\"",
            .{},
            diags
        );
    } // Check subsubcommand
    if (parsed.num_arguments < min_num_args){ // check arguments
        return returnError(
            CLIError.NotEnoughArguments,
            "Not enough arguments,expected {d} got {d}",
            .{min_num_args, parsed.num_arguments},
            diags
        );
    }
    //------------ Getting Index -------------------
    const index_str = (try parsed.getNthArg(next_arg)).name;
    if(grabIndexFromStr(index_str[0..index_str.len-1], Key, convertStr)) |conv_index| {
       return db.GetEntriesByIndex(conv_index) catch |err| {
           return returnError(
               err,
               "Could not get entries with that index {s}",
               .{index_str},
               diags
            );
        };
    }
    return returnError(
        TermCommands.CLIError.InvalidArgument,
        "Could not convert the index \"{s}\" correctly",
        .{index_str},
        diags
    );
}

