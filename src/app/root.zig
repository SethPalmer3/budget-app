const std = @import("std");
pub const TermCommands = @import("term_commands.zig");

test {
    std.testing.refAllDecls(@This());
}
