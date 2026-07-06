const std = @import("std");
const Database = @import("Database");
const QueryParam = Database.StorageEngine.QueryParam;
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
            const min_num_args = 2;

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
            var query: Database.StorageEngine.StorageEngine(DataType, RefType, ranged_list).QueryType = .{};

            const data_info = @typeInfo(DataType); // Might need to check if this is not a struct
            inline for (data_info.@"struct".fields) |data_field| {
                iter_block: {
                    const option = // Fetch option with field name
                        parsed.getOption(.{
                            .long_form = data_field.name,
                            .short_form = data_field.name[0],
                            .has_short_form = false
                        }) catch {break :iter_block;};

                    // Get first argument
                    const opt_arg = parsed.getNthArgAfterOption(option.*, 1) catch |err| {
                        writer.print("({s})Could not find argument\n", .{@errorName(err)}) catch {};
                        return cmdManager.CommandState.ErrorContinue;
                    };
                    // Get possible second value
                    const opt_arg_max: ?*const CommandParse.Argument =
                        parsed.getNthArgAfterOption(option.*, 2) catch null;

                    // Check if given a second arguement even with a non-ranged field
                    if(opt_arg_max != null and !Database.isRangedField(ranged_list, data_field.name)) {
                        writer.print("Field '{s}' does not accept ranges\n", .{data_field.name}) catch {};
                        return cmdManager.CommandState.ErrorContinue;
                    }

                    const conversion_fn = // conversion function for both arguments
                        fetchConvertStrFn(?data_field.type, data_field.type, conversion_fn_name);

                    // Convert first arguement to its associated field type
                    const convert_arg =
                        conversion_fn(opt_arg.name) orelse {
                            writer.print("Could not convert '{s}' properly\n", .{opt_arg.name}) catch {};
                            return cmdManager.CommandState.ErrorContinue;
                    };
                    // std.debug.print("converted_arg: {any}\n", .{convert_arg});
                    // Convert optional second argument to the same field type
                    const convert_arg_max = 
                        if(opt_arg_max) |max_opt_arg| conversion_fn(max_opt_arg.name) else null;

                    // Populate the corresponding query field with the 
                    // appropriate value
                    @field(query, data_field.name) = blk: {
                        const is_range: bool = comptime is_range_blk: {
                            var ranged = false;
                            for (ranged_list) |field_name| {
                                if(std.mem.eql(u8, field_name, data_field.name)){
                                    ranged = true;
                                }
                            }
                            break :is_range_blk ranged;
                        };
                        // Check if the type of the query field is a query parameter
                        // with the child type being the data type field
                        if(is_range){
                            // If optional second argument exists
                            if(convert_arg_max) |arg_max| {
                                // send a query parameter of an `range` tag
                                break :blk QueryParam(@TypeOf(convert_arg)){
                                    .range = .{
                                        .max = arg_max,
                                        .min = convert_arg 
                                    }
                                };
                            }else{
                                // else use the `exact` tag
                                break :blk QueryParam(@TypeOf(convert_arg)){.exact = convert_arg};
                            }
                        }else{
                            break :blk convert_arg;
                        }
                    };
                }
            }
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

