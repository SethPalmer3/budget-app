const std = @import("std");
const Databases = @import("Database");
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
        db: *Databases.Database.Database(D, R, Key),
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

