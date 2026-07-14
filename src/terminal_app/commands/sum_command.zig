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
pub const extractQueryFromCommand = @import("../extract_query_specifiers.zig").extractQueryFromCommand;

const LIST_COMMAND_NAME = "SUM";
const sum_on_field_name = "field";

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

pub fn generateHandleSum(
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
            const min_num_args = 2;
            const data_info = @typeInfo(DataType);

            const ranged_list: []const []const u8 = 
                comptime Database.getCompareableFieldNames(DataType, Database.container_compare_fn_name);
            //------------ Checking Help Flag -------------------
            if(parsed.getOption(.{.long_form = "help", .short_form = 'h'})) |_|{
                writer.print("SUM --{s} FIELD [--field <VALUE> [MAX VALUE]...]\n", .{sum_on_field_name})catch{};
                writer.print("Avaliable fields:\n", .{})catch{};
                // const data_info = @typeInfo(DataType);
                inline for (data_info.@"struct".fields) |field| {
                    if(@typeInfo(field.type) == .int){
                        writer.print(" - {s}\n", .{field.name}) catch {};
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
            //------------ Fetching Query Data -------------------
            const query: Database.StorageEngine.StorageEngine(DataType, RefType, ranged_list).QueryType  = extractQueryFromCommand(DataType, RefType, ranged_list, conversion_fn_name, parsed, writer) catch {
                return cmdManager.CommandState.ErrorContinue;
            };
            // std.debug.print("query: {any}\n", .{query});

            //------------ Query Execution -------------------
            const items = db.storage_engine.Query(db.alloc, query) catch |err| {
                writer.print("({s}) Could not fetch the query correctly\n", .{@errorName(err)}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(items);

            //------------ Preform Sum operation -------------------
            const sum_option: CommandParse.Option =
                .{.long_form = sum_on_field_name, .short_form = 'f', .has_short_form = false};
            var sum: u64 = 0;
            if(parsed.getOption(sum_option)) |_|{
                const field_to_sum = parsed.getNthArgAfterOption(sum_option, 1) catch {
                    writer.print("Please give the sum option a field to sum on\n", .{}) catch {};
                    return cmdManager.CommandState.ErrorContinue;
                };

                for(items) |*item| {
                    const field_value: u64 = blk: {
                        inline for (data_info.@"struct".fields) |field| {
                            if(std.mem.eql(u8, field.name, field_to_sum.name)){
                               const field_val = @field(item.*, field.name);
                               if(@typeInfo(@TypeOf(field_val)) != .int){
                                    writer.print("The field '{s}' needs to be a int type, got '{s}' instead\n", .{field_to_sum.name, @typeName(@TypeOf(field_val))}) catch {};
                                    return cmdManager.CommandState.ErrorContinue;
                               }
                                break :blk @field(item.*, field.name);
                            }
                        }
                        writer.print("Could not find a field with name '{s}' in '{s}'\n", .{field_to_sum.name, @typeName(DataType)}) catch {};
                        return cmdManager.CommandState.ErrorContinue;
                    };
                    sum += @as(u64, field_value);
                }

            }else |_|{
                writer.print("Please specify a sum option with which field to sum\n", .{}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            }

            //------------ Printing Data -------------------
            writer.print("Sum: {d}\n", .{sum}) catch {};
            return cmdManager.CommandState.Continue;
        }
    }.execute;
}

