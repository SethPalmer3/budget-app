const std = @import("std");
const Database = @import("Database");
const TermCommands = @import("term_commands.zig");
const cmdManager = @import("command_manager.zig");
const returnError = TermCommands.returnError;
const CLIError = TermCommands.CLIError;

const Diagnostic = @import("diagnostics.zig");
const CommandParse = @import("CommandParse");
const Domain = @import("Domain");
const Record = Domain.Record;
const recordType = Domain.RecordType;
const recordCategory = Domain.RecordCategory;
const Date = Domain.Date;


const LIST_COMMAND_NAME = "LIST";

fn fetchConvertStrFn(
    comptime returnType: type,
    comptime index_type: type,
    comptime conversion_fn_name: []const u8
) *const fn ([]const u8) returnType{
    const index_info = @typeInfo(index_type);
    switch (index_info) {
        .int => {
            return struct{
                pub fn conv(str: []const u8) ?index_type {
                    return std.fmt.parseInt(index_type, str, 10);
                }
            }.conv;
        },
        .float => {
            return struct{
                pub fn conv(str: []const u8) ?index_type {
                    return std.fmt.parseFloat(index_type, str, 10);
                }
            }.conv;
        },
        .@"struct", .@"enum", .@"union" => {
            if(!@hasDecl(index_type, conversion_fn_name)){
                @compileError("Container that is used as the index type must specify a function(" ++ conversion_fn_name ++ ") which can convert string like data to that container type");
            }
            const conv_fn = &@field(index_type, conversion_fn_name);
            const conv_fn_type = @TypeOf(conv_fn);
            const comp_expr = *const fn([]const u8) returnType;
            if(conv_fn_type != comp_expr){
                @compileError("The containers specified conversion function must have the signature " ++ @typeName(comp_expr) ++ ", found " ++ @typeName(conv_fn_type));
            }
            return conv_fn;
        },
        else => { // Must have a conversion_fn_name function to do the conversion
            @compileError("The index type must be a type that has a way to convert string like data into it's type or the container must have a function(" ++ conversion_fn_name ++ ") which can do that.");
        }
    }
}

pub fn contextPackage(
    comptime DataType: type,
    comptime RefType: type,
    comptime IndexKey: anytype,
) type {
    return struct {
        db: *Database.Database.Database(DataType, RefType, IndexKey),
        convertStr: *const fn([]const u8) ?@FieldType(DataType, IndexKey),
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
                writer.print("LIST INDEX({s})\n", .{index_string})catch{};
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
                    "Not enough arguments, expected {d} got {d}\n",
                    .{min_num_args, parsed.num_arguments},
                ) catch {};
            return cmdManager.CommandState.ErrorContinue;
            }
            //------------ Getting Index -------------------
            const index_str = 
                (parsed.getNthArg(next_arg) catch {return cmdManager.CommandState.ErrorContinue;}).name;

            const convertStr: *const fn([]const u8) ?index_key_type = 
                fetchConvertStrFn(?index_key_type, index_key_type, "convertStr");
            if(Database.Database.convertStringToIndexValue(DataType, IndexKey, index_str, convertStr)) |conv_index| {
                const items = db.GetEntriesByIndex(conv_index) catch {
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

