const std = @import("std");
const Database = @import("Database");
const QueryParam = Database.Query.QueryParam;
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
const extractQueryFromCommand = @import("../extract_query_specifiers.zig").extractQueryFromCommand;

const LIST_COMMAND_NAME = "LIST";
const string_conversion_name = "convertStr";

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
            const min_num_args = 1;

            const ranged_list: []const []const u8 = 
                comptime Database.getCompareableFieldNames(DataType, Database.container_compare_fn_name);
            //------------ Checking Help Flag -------------------
            if(parsed.getOption(.{.long_form = "help", .short_form = 'h'})) |_|{
                writer.print("LIST [--field <VALUE> [MAX VALUE]...]\n", .{})catch{};
                writer.print("Avaliable fields:\n", .{})catch{};
                const data_info = @typeInfo(DataType);
                inline for (data_info.@"struct".fields) |field| {
                    if(Database.isRangedField(ranged_list, field.name)){
                        writer.print("--{s}(can have a range)\n", .{field.name}) catch {};
                    }else{
                        writer.print("--{s}\n", .{field.name}) catch {};
                    }
                }
                return cmdManager.CommandState.Continue;
            }else |_|{}
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
            //------------ Setting up Query Data -------------------
            const query: ?Database.StorageEngine.StorageEngine(DataType, RefType, ranged_list).QueryType = 
                blk:{
                    if(parsed.num_arguments == 1){
                        break :blk null;
                    }
                    break :blk extractQueryFromCommand(DataType, RefType, ranged_list, conversion_fn_name, parsed, writer) catch {
                    return cmdManager.CommandState.ErrorContinue;
                };
            };

            // std.debug.print("query: {any}\n", .{query});

            //------------ Query Execution -------------------
            const items = db.storage_engine.Query(db.alloc, query) catch |err| {
                writer.print("({s}) Could not fetch the query correctly\n", .{@errorName(err)}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(items);

            //------------ Printing Data -------------------
            writer.print("----------------------------\n", .{}) catch {};
            for (items) |*item| {
                cntxt.displayData(item, writer);
                writer.print("----------------------------\n", .{}) catch {};
            }
            // writer.print("\n", .{}) catch {};
            return cmdManager.CommandState.Continue;
        }
    }.execute;
}

