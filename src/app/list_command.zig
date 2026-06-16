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
    if(!std.mem.eql(u8, subcommand.name, "ADD")){
        return returnError(
            CLIError.UnknownCommand, "Cannot handle subcommands other than \"LIST\"\n", .{}, diags
        );
    } // Check subsubcommand
    if (parsed.num_arguments < min_num_args){ // check arguments
        return returnError(CLIError.NotEnoughArguments, "Not enough arguments, expected {d} got {d}\n", .{min_num_args, parsed.num_arguments}, diags);
    }
    //------------ Getting Index -------------------
    const index_str = try parsed.getNthArg(next_arg);
    if(grabIndexFromStr(index_str, Key, convertStr)) |conv_index| {
       return try db.GetEntriesByIndex(conv_index);
    }
    return returnError(TermCommands.CLIError.InvalidArgument, "Could not convert the index correctly", .{}, diags);
}

