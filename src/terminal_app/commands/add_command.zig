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

// ADD TYPE DAY/MONTH/YEAR NAME CATEGORY AMOUNT DESC -> ID
pub fn generateHandleAdd(
    comptime DataType: type,
    comptime RefType: type,
    comptime IndexKey: anytype,
) *const fn(*CommandParse.Command, *std.Io.Reader, *std.Io.Writer, *anyopaque) cmdManager.CommandState {
    return struct{
        pub fn execute(
            parsed: *CommandParse.Command,
            reader: *std.Io.Reader,
            write_out: *std.Io.Writer,
            context: *anyopaque,
        ) cmdManager.CommandState{
            _ = reader;
            var next_arg: u64 = 1;
            const min_num_args = num_args: {
                const rec_info = @typeInfo(DataType);
                const rec_fields = rec_info.@"struct".fields;
                break :num_args rec_fields.len;
            };
            var db: *Database.Database.Database(DataType, RefType, IndexKey) = @alignCast(@ptrCast(context));

            //------------ Checking Help Flag -------------------
            if(parsed.getOption(.{.long_form = "help", .short_form = 'h'})) |_|{
                if(parsed.getNthArgAfterOption(.{.long_form = "help", .short_form = 't'}, 1)) |opt_arg| {
                    if(std.mem.eql(u8, opt_arg.name, "TYPE")){
                        const recType_info = @typeInfo(recordType);
                        const recType_fields = recType_info.@"enum".fields;
                        inline for (recType_fields) |field| {
                            write_out.print("{s}", .{field.name})catch{};
                        }
                    }
                    else if(std.mem.eql(u8, opt_arg.name, "CATEGORY")){
                        const recType_info = @typeInfo(recordCategory);
                        const recType_fields = recType_info.@"enum".fields;
                        inline for (recType_fields) |field| {
                            write_out.print("{s}", .{field.name})catch{};
                        }
                    }
                }else |_|{
                    write_out.print("ADD TYPE DAY/MONTH/YEAR NAME CATEGORY AMOUNT DESC\n", .{})catch{};
                }
                return cmdManager.CommandState.Continue;
            }else |err|{
                switch (err) {
                    CommandParse.Command.CommandError.CannotFindFragment => {
                        write_out.print("Unknown Option given\n", .{})catch{};
                    },
                    else => {}
                }
            }

            _ = parsed.getNthArg(next_arg)catch{return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            var item: DataType = undefined;
            //------------ Checking Sub command -------------------
            if (parsed.num_arguments < min_num_args - 1){ // check arguments
                _ = write_out.print("Too few arguments passed to the sub command, expected {d}\n", .{min_num_args})catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            }
            //------------ Getting Type -------------------
            const item_type_str = 
                parsed.getNthArg(next_arg)catch{return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            if(recordType.convertStr(item_type_str.name)) |item_type| {
                item.type = item_type;
            }else{ // Cannot convert argument to a type
                _ = write_out.print("Unkown type {s}\n", .{item_type_str.name})catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            }
            //------------ Getting DataType Date -------------------
            const item_date_str = parsed.getNthArg(next_arg)catch{return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            if(Date.convertStr(item_date_str.name)) |date| {
                item.date = date;
            }else{
                _ = write_out.print("Could not parse the date correctly\n", .{})catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            }
            //------------ Getting DataType Name -------------------
            const name_arg = parsed.getNthArg(next_arg)catch{return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            if (name_arg.name.len > DataType.max_name_length){
                _ = write_out.print(
                    "Length of the name of the record is too large, must be at most {d} characters\n",
                    .{DataType.max_name_length}
                    )catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            }
            std.mem.copyForwards(u8, &item.name, name_arg.name);
            item.name_size = name_arg.name.len;
            //------------ Getting DataType Category -------------------
            const item_category_str = parsed.getNthArg(next_arg)catch{return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            if(recordCategory.convertStr(item_category_str.name)) |item_category|{
                item.category = item_category;
            }else{
                _ = write_out.print("Unkown category {s}\n", .{item_category_str.name})catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            }
            //------------ Getting DataType Amount -------------------
            const item_amount_str = parsed.getNthArg(next_arg)catch{return cmdManager.CommandState.ErrorContinue;};
            next_arg += 1;
            const parsed_float_from_arg = std.fmt.parseFloat(f32, item_amount_str.name) catch {
                _ = write_out.print("Cannot parse the given record amount \"{s}\"\n", .{item_amount_str.name})catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            };
            item.amount = @trunc(parsed_float_from_arg * 100.0); // Multiplying by 100 for fixed point
            //------------ Getting Record Description -------------------
            var next_desc_position: u64 = 0;
            while(parsed.getNthArg(next_arg)) |arg| : (next_arg += 1)  {
                std.mem.copyForwards(u8, item.desc[next_desc_position..next_desc_position+arg.name.len], arg.name);
                item.desc[next_desc_position+arg.name.len] = ' '; // Include space
                next_desc_position += arg.name.len + 1;
            }else |_|{} // Discard error
            item.desc_size = next_desc_position;
            db.StoreData(.{.data = item}) catch {
                _ = write_out.print("Could not store item {any}\n", .{item})catch{return cmdManager.CommandState.ErrorContinue;};
                return cmdManager.CommandState.ErrorContinue;
            };
            return cmdManager.CommandState.Continue;
        }
    }.execute;
}
