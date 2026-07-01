const std = @import("std");
const Database = @import("Database");
const DBType = Database.Database.Database;
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
        db: *DBType(DataType, RefType, IndexKey),
        // convertStr: *const fn([]const u8) ?@FieldType(DataType, IndexKey),
        displayData: *const fn(*const DataType, *std.Io.Writer) void,
    };
}

pub fn generateHandleList(
    comptime DataType: type,
    comptime RefType: type,
    comptime IndexKey: anytype,
    comptime conversion_fn_name: []const u8,
)*const fn(*CommandParse.Command, *std.Io.Reader, *std.Io.Writer, *anyopaque) cmdManager.CommandState{
    return struct{
        fn collectItemsFromParser(parsed: *CommandParse.Command, next_argument: u64, db: *DBType(DataType, RefType, IndexKey), writer: *std.Io.Writer) ![]const DataType {
            var next_arg = next_argument;
            const index_key_type = Database.Database.convertIndexKeyIntoType(DataType, IndexKey);
            const convertStr: *const fn([]const u8) ?index_key_type = 
                fetchConvertStrFn(?index_key_type, index_key_type, conversion_fn_name);
            //------------ Getting Range ----------------
                const start_index_str = 
                    (parsed.getNthArg(next_arg) catch |err| {return err;}).name;
                next_arg += 1;
                const end_index_str: ?[]const u8 = blk: {
                    if(parsed.num_options > 2){
                        break :blk (parsed.getNthArg(next_arg) catch |err| {return err;}).name;
                    }else{
                        break :blk null;
                    }
                };
                next_arg += 1;

                const start_index = 
                    Database.Database.convertStringToIndexValue(
                        DataType, IndexKey, start_index_str, convertStr
                    ) orelse {
                        writer.print(
                            "Could not convert the index \"{s}\" correctly\n",
                            .{start_index_str},
                        ) catch {};
                        return error.CouldNotConvertArgument;
                    }; 
                const end_index: ?index_key_type = blk: {
                    if (end_index_str) |end_index_str_noop| {
                        break :blk Database.Database.convertStringToIndexValue(
                            DataType, IndexKey, end_index_str_noop, convertStr
                        ) orelse {
                            writer.print(
                                "Could not convert the index \"{s}\" correctly\n",
                                .{end_index_str},
                            ) catch {};
                            return error.CouldNotConvertArgument;
                        };
                    }else{break :blk null;}
                };

                return db.GetEntriesByIndex(
                    .{.start_index = start_index, .end_index = end_index}
                ) catch |err| {
                    writer.print(
                        "({s})Could not get entries with the indexes {s} and {s}\n",
                        .{@errorName(err), start_index_str, end_index_str},
                    ) catch {};
                    return err;
                };
        }
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
                writer.print("LIST [--field FILED NAME]\n", .{})catch{};
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
            const items = collectItemsFromParser(parsed, next_arg, db, writer) catch {
                return cmdManager.CommandState.ErrorContinue;
            };

            writer.print("----------------------------", .{}) catch {};
            for (items) |*item| {
                cntxt.displayData(item, writer);
                writer.print("----------------------------", .{}) catch {};
            }
            defer db.alloc.free(items);
            return cmdManager.CommandState.Continue;
        }
    }.execute;
}

