const std = @import("std");
const Database = @import("Database");
const DBType = Database.Database.Database;
const CommandParse = @import("CommandParse");
const cmdManager = @import("../command_manager.zig");
const Domain = @import("Domain");
const Date = Domain.Date;
const Query = Database.Query;

const fetchConvertStrFn = @import("./list_cmd_utils/fetch_conversion_fn.zig").fetchConvertStrFn;

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

fn collectSummary(comptime dbType: type, writer: *std.Io.Writer, db: *dbType, query: Query) !Domain.Services.DataSummary(u64) {
    const DataType = db.*.DataType;
    const items = db.storage_engine.Query(db.alloc, query) catch |err| {
        writer.print("({t}) Could not fetch the query correctly\n", .{err}) catch {};
        return err;
    };
    defer db.alloc.free(items);
    var budget_data: [] *const DataType = db.alloc.alloc(*const DataType, items.len) catch |err| {
        writer.print("({t}) Could not allocate memory\n", .{err}) catch {};
        return err;
    };
    defer db.alloc.free(budget_data);
    for (0..items.len) |i| {
        budget_data[i] = &items[i].data;
    }
    const budget_summary = Domain.Services.data_summary(DataType, "category", "amount", db.alloc, budget_data) catch |err| {
        writer.print("({t}) Could not allocate memory\n", .{err}) catch {};
        return err;
    };
    return budget_summary;
}


pub fn generateHandleInfo(
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
                writer.print("INFO MONTH/YEAR\n", .{})catch{};
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
                end_date.day += 99; // To ensure all items are within the same month
            }else{
                _ = writer.print("Could not parse the date, '{s}', correctly\n", .{item_date_str.name})catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            }
            //------------ Setting up Query Data -------------------
            std.debug.print("start_date:{any} - end_date:{any}", .{start_date, end_date});
            const budget_query: Database.StorageEngine.StorageEngine(DataType, RefType, ranged_list).QueryType = .{
                .type = .Budget,
                .date = Query.QueryParam(Date){.range = .{ .min = start_date, .max = end_date }},
            };
            const transaction_query: Database.StorageEngine.StorageEngine(DataType, RefType, ranged_list).QueryType = .{
                .type = .Transaction,
                .date = Query.QueryParam(Date){.range = .{ .min = start_date, .max = end_date }},
            };

            //------------ Budgets -------------------
            const budget_items = db.storage_engine.Query(db.alloc, budget_query) catch |err| {
                writer.print("({s}) Could not fetch the query correctly\n", .{@errorName(err)}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(budget_items);
            std.debug.print("budget_items_len: {d}\n", .{budget_items.len});
            var budget_data: [] *const DataType = db.alloc.alloc(*const DataType, budget_items.len) catch |err| {
                writer.print("({t}) Could not allocate memory\n", .{err}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(budget_data);
            for (0..budget_items.len) |i| {
                budget_data[i] = &budget_items[i].data;
            }
            const budget_summary = Domain.Services.data_summary(DataType, "category", "amount", db.alloc, budget_data) catch |err| {
                writer.print("({t}) Could not allocate memory\n", .{err}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(budget_summary.individual_totals);
            // ------------------Transactions-------------------
            const transaction_items = db.storage_engine.Query(db.alloc, transaction_query) catch |err| {
                writer.print("({s}) Could not fetch the query correctly\n", .{@errorName(err)}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(transaction_items);
            std.debug.print("transaction_items_len: {d}\n", .{transaction_items.len});
            var transaction_data: [] *const DataType = db.alloc.alloc(*const DataType, transaction_items.len) catch |err| {
                writer.print("({t}) Could not allocate memory\n", .{err}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(transaction_data);
            for (0..transaction_items.len) |i| {
                transaction_data[i] = &transaction_items[i].data;
            }
            const transaction_summary = Domain.Services.data_summary(DataType, "category", "amount", db.alloc, transaction_data) catch |err| {
                writer.print("({t}) Could not allocate memory\n", .{err}) catch {};
                return cmdManager.CommandState.ErrorContinue;
            };
            defer db.alloc.free(transaction_summary.individual_totals);

            //-------------Totals---------------------
            if(budget_summary.total == 0){
                writer.print("Total: ${d}.{d:0<2} (no budgeting)\n",
                    .{
                        transaction_summary.total / 100, @rem(transaction_summary.total, 100),
                    }
                ) catch {};
            }else{
                const total_percent: u64 = (transaction_summary.total * 10000) / budget_summary.total;

                //------------ Printing Data -------------------
                writer.print("Total: ${d}.{d:0<2} / ${d}.{d:0<2} (%{d}.{d:0<2})\n",
                    .{
                        transaction_summary.total / 100, @rem(transaction_summary.total, 100),
                        budget_summary.total / 100, @rem(budget_summary.total, 100),
                        total_percent / 100, @rem(total_percent, 100),
                    }
                ) catch {};
            }

            //----------------Category Breakdown-----------------
            const category_info = @typeInfo(@FieldType(DataType, "category"));
            for(0..category_info.@"enum".fields.len) |i| {
                if(budget_summary.individual_totals[i] == 0){
                    writer.print("  {s}: ${d}.{d:0<2} (no budget allocated)\n",
                        .{
                            category_info.@"enum".fields[i].name,
                            transaction_summary.individual_totals[i] / 100, @rem(transaction_summary.individual_totals[i], 100),
                        }
                    ) catch {};
                    continue;
                }
                const category_total_percent: u64 = (transaction_summary.individual_totals[i] * 10000) / budget_summary.individual_totals[i] ;
                writer.print("  {s}: ${d}.{d:0<2} / ${d}.{d:0<2} (%{d}.{d:0<2} used)\n",
                    .{
                        category_info.@"enum".fields[i].name,
                        transaction_summary.individual_totals[i] / 100, @rem(transaction_summary.individual_totals[i], 100),
                        budget_summary.individual_totals[i] / 100, @rem(budget_summary.individual_totals[i], 100),
                        category_total_percent / 100, @rem(category_total_percent, 100),
                    }
                ) catch {};
            }
            // writer.print("\n", .{}) catch {};
            return cmdManager.CommandState.Continue;
        }
    }.execute;
}
