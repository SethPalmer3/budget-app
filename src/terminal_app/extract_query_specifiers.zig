const std = @import("std");
const CommandParse = @import("CommandParse");
const Database = @import("Database");
const cmdManager = @import("command_manager.zig");
const fetchConvertStrFn = @import("commands/list_cmd_utils/fetch_conversion_fn.zig").fetchConvertStrFn;

pub fn extractQueryFromCommand(
    comptime DataType: type,
    comptime RefType: type,
    comptime ranged_list: []const []const u8,
    comptime conversion_fn_name: []const u8,
    parsed: *const CommandParse.Command,
    writer: *std.Io.Writer,
) !Database.StorageEngine.StorageEngine(DataType, RefType, ranged_list).QueryType {
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
                writer.print("Could not find argument\n", .{}) catch {};
                return err;
            };
            // Get possible second value
            const opt_arg_max: ?*const CommandParse.Argument =
                parsed.getNthArgAfterOption(option.*, 2) catch null;

            // Check if given a second arguement even with a non-ranged field
            if(opt_arg_max != null and !Database.isRangedField(ranged_list, data_field.name)) {
                writer.print("Field '{s}' does not accept ranges\n", .{data_field.name}) catch {};
                return error.NonAcceptibleRange;
            }

            const conversion_fn = // conversion function for both arguments
                fetchConvertStrFn(?data_field.type, data_field.type, conversion_fn_name);

            // Convert first arguement to its associated field type
            const convert_arg =
                conversion_fn(opt_arg.name) orelse {
                    writer.print("Could not convert '{s}' properly\n", .{opt_arg.name}) catch {};
                    return error.CannotConvertValue;
            };
            // std.debug.print("converted_arg: {any}\n", .{convert_arg});
            // Convert optional second argument to the same field type
            const convert_arg_max = 
                if(opt_arg_max) |max_opt_arg| conversion_fn(max_opt_arg.name) else null;

            // Populate the corresponding query field with the 
            // appropriate value
            @field(query, data_field.name) = blk: {
                const is_range = comptime Database.isRangedField(ranged_list, data_field.name);
                // Check if the type of the query field is a query parameter
                // with the child type being the data type field
                if(is_range){
                    // If optional second argument exists
                    if(convert_arg_max) |arg_max| {
                        // send a query parameter of an `range` tag
                        break :blk Database.Query.QueryParam(@TypeOf(convert_arg)){
                            .range = .{
                                .max = arg_max,
                                .min = convert_arg 
                            }
                        };
                    }else{
                        // else use the `exact` tag
                        break :blk Database.Query.QueryParam(@TypeOf(convert_arg)){.exact = convert_arg};
                    }
                }else{
                    break :blk convert_arg;
                }
            };
        }
    }
    return query;
}
