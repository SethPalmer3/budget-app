const std = @import("std");
const cmdManager = @import("command_manager.zig");
const CommandParse = @import("CommandParse");

pub fn singleIndex(parsed: *CommandParse.Command, writer: *std.Io.Writer) cmdManager.CommandState{
    const index_str = 
        (parsed.getNthArg(2) catch {return cmdManager.CommandState.ErrorContinue;}).name;

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
