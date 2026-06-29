const std = @import("std");
const TermCommands = @import("../term_commands.zig");
const cmdManager = @import("../command_manager.zig");

const CommandParse = @import("CommandParse");

pub fn handleQuit(
    parsed: *CommandParse.Command, reader: *std.Io.Reader, writer: *std.Io.Writer, context: *anyopaque
) cmdManager.CommandState{
    _ = parsed;
    _ = reader;
    _ = context;

    writer.print("Quitting CLI", .{})catch{};
    return cmdManager.CommandState.Stop;
}
