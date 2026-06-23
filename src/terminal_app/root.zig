const std = @import("std");
pub const TermCommands = @import("term_commands.zig");
pub const TerminalManager = @import("command_manager.zig");

test {
    std.testing.refAllDecls(@This());
}
