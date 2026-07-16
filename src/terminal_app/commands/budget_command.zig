const std = @import("std");
const Database = @import("Database");
const QueryParam = Database.Query.QueryParam;
const DBType = Database.Database.Database;
const Query = Database.Query;
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


pub fn generateHandleBudget(
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
                writer.print("BUDGET MONTH/YEAR\n", .{})catch{};
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
            //------------ Getting Month to Lookup ------------------
            var start_date: Date = undefined;
            var end_date: Date = undefined;
            const item_date_str =
                parsed.getNthArg(next_arg)catch{return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            if(fetchConvertStrFn(?Date, conversion_fn_name)(item_date_str.name)) |date| {
                start_date = date;
                start_date.day = 1;
                end_date = start_date;
                end_date.month += 1;
            }else{
                _ = writer.print("Could not parse the date, '{s}', correctly\n", .{item_date_str.name})catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            }
            //------------ Setting up Query Data -------------------
            const budget_query: Database.StorageEngine.StorageEngine(DataType, RefType, ranged_list).QueryType = .{
                .type = .Budget,
                .date = Query.QueryParam(Date){.range = .{ .min = start_date, .max = end_date }},
            };

            //------------ Query Execution -------------------
            const budget_items = db.storage_engine.Query(db.alloc, budget_query) catch |err| {
                writer.print("({s}) Could not fetch the query correctly\n", .{@errorName(err)}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(budget_items);

            const select_datatype_field = "category";
            const category_info = @typeInfo(@FieldType(DataType, select_datatype_field));

            var budget_total: u64 = 0;
            const num_categories = category_info.@"enum".fields.len;
            var category_breakdown_budget: [num_categories]u64 = .{0} ** num_categories;
            for(budget_items) |budget_item| {
                budget_total += @field(budget_item, "amount");
                const cat_index = @intFromEnum(@field(budget_item, select_datatype_field));
                category_breakdown_budget[cat_index] += @field(budget_item, "amount");
            }
            //------------ Printing Data -------------------
            writer.print("Total Budget: {d}.{d:0<2}\n", .{
                budget_total / 100,
                @rem(budget_total, 100),
            }) catch {};
            if (budget_total == 0) {
                return cmdManager.CommandState.Continue;
            }
            for (0..num_categories) |i| {
                // Multiply by 10000 because it's 100, for the percentage, * 100 for the fix point
                const percentage_of_total = (category_breakdown_budget[i] * 10000) / budget_total;
                writer.print("  {s}: {d}.{d:0<2} (%{d}.{d:0<2})\n", .{
                    category_info.@"enum".fields[i].name,
                    category_breakdown_budget[i] / 100, @rem(category_breakdown_budget[i], 100),
                    percentage_of_total / 100, @rem(percentage_of_total, 100),

                }) catch {};
            }
            // writer.print("\n", .{}) catch {};
            return cmdManager.CommandState.Continue;
        }
    }.execute;
}

