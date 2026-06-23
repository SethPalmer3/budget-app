const std = @import("std");
const CommandParse = @import("CommandParse");
const Database = @import("Database");
pub const AddCommand = @import("add_command.zig");
pub const ListCommand = @import("list_command.zig");
pub const QuitCommand = @import("quit_command.zig");

// const name_length = 20;
// const desc_length = 1000;

// NEW (BUDGET/TRANSACTION) NAME CATEGORY AMOUNT DESC -> ID
// EDIT ID ATTR NEW_VALUE -> *ID
// LIST ATTR -> RECORD
// DELETE ID

pub const CLIError = error{
    UnknownCommand,
    NotEnoughArguments,
    InvalidCommand,
    InvalidArgument,
    InvalidOption,
};

pub fn returnError(err: anyerror, comptime fmt: []const u8, args: anytype, write_out: *std.Io.Writer) anyerror {
    _ = try write_out.print(fmt, args);
    return err;
}

test {
    std.testing.refAllDecls(@This());
}
