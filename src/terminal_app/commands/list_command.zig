const std = @import("std");
const Database = @import("Database");
const TermCommands = @import("../term_commands.zig");
const cmdManager = @import("../command_manager.zig");
const returnError = TermCommands.returnError;
const CLIError = TermCommands.CLIError;

const CommandParse = @import("CommandParse");
const Domain = @import("Domain");
const Record = Domain.Record;
const recordType = Domain.RecordType;
const recordCategory = Domain.RecordCategory;
const Date = Domain.Date;

pub const fetchConvertStrFn = @import("./list_cmd_utils/fetch_conversion_fn.zig").fetchConvertStrFn;

const LIST_COMMAND_NAME = "LIST";

pub fn contextPackage(
    comptime DataType: type,
    comptime RefType: type,
    comptime IndexKey: anytype,
) type {
    return struct {
        db: *Database.Database.Database(DataType, RefType, IndexKey),
        // convertStr: *const fn([]const u8) ?@FieldType(DataType, IndexKey),
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
            const index_key_type = Database.Database.convertIndexKeyIntoType(DataType, IndexKey);
            //------------ Checking Help Flag -------------------
            if(parsed.getOption(.{.long_form = "help", .short_form = 'h'})) |_|{
                const index_string: []const u8 =
                    @typeName(index_key_type);
                writer.print("LIST INDEX [END INDEX]({s})\n", .{index_string})catch{};
                return cmdManager.CommandState.Continue;
            }else |err|{
                switch (err) {
                    CommandParse.Command.CommandError.CannotFindFragment => {
                        writer.print("Unknown Option given\n", .{})catch{};
                    },
                    else => {}
                }
            }
            //------------ Checking Command -------------------
            _ = parsed.getNthArg(next_arg) catch {return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            if (parsed.num_arguments < min_num_args){ // check arguments
                writer.print(
                    "Not enough arguments, expected at least {d} got {d}\n",
                    .{min_num_args, parsed.num_arguments},
                ) catch {};
            return cmdManager.CommandState.ErrorContinue;
            }
            const convertStr: *const fn([]const u8) ?index_key_type = 
                fetchConvertStrFn(?index_key_type, index_key_type, "convertStr");
            //------------ Determine if range or single value ----------------
            if(parsed.num_arguments > 2){ // Selected range
            //------------ Getting Range ----------------
                const start_index_str = 
                    (parsed.getNthArg(next_arg) catch {return cmdManager.CommandState.ErrorContinue;}).name;
                next_arg += 1;
                const end_index_str = 
                    (parsed.getNthArg(next_arg) catch {return cmdManager.CommandState.ErrorContinue;}).name;
                next_arg += 1;

                const start_index = 
                    Database.Database.convertStringToIndexValue(
                        DataType, IndexKey, start_index_str, convertStr
                    ) orelse {
                    writer.print(
                        "Could not convert the index \"{s}\" correctly\n",
                        .{start_index_str},
                    ) catch {};
                    return cmdManager.CommandState.ErrorContinue;
                }; 
                const end_index = 
                    Database.Database.convertStringToIndexValue(
                        DataType, IndexKey, end_index_str, convertStr
                    ) orelse {
                    writer.print(
                        "Could not convert the index \"{s}\" correctly\n",
                        .{end_index_str},
                    ) catch {};
                    return cmdManager.CommandState.ErrorContinue;
                };

                const items = db.GetEntriesByIndex(
                    .{.start_index = start_index, .end_index = end_index}
                ) catch |err| {
                    writer.print(
                        "({s})Could not get entries with the indexes {s} and {s}\n",
                        .{@errorName(err),start_index_str, end_index_str},
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

            //------------ Getting Single Index -------------------
            const index_str = 
                (parsed.getNthArg(next_arg) catch {return cmdManager.CommandState.ErrorContinue;}).name;

            if(Database.Database.convertStringToIndexValue(DataType, IndexKey, index_str, convertStr)) |conv_index| {
                const items = db.GetEntriesByIndex(.{.start_index = conv_index}) catch {
                    writer.print(
                        "Could not get entries with that index {s}\n",
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
                "Could not convert the index \"{s}\" correctly\n",
                .{index_str},
            ) catch {};
            return cmdManager.CommandState.ErrorContinue;
        }
    }.execute;
}

