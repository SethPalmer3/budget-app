const std = @import("std");
const CommandParse = @import("CommandParse");
const Self = @This();
const Allocator = std.mem.Allocator;

pub const CommandEntry = struct {
    name: []const u8,
    execute_fn: *const fn(*CommandParse.Command, *std.Io.Reader, *std.Io.Writer, *anyopaque) CommandState,
    execute_context: *anyopaque,
};

pub const CommandState = enum {
    Continue,
    ErrorStop,
    ErrorContinue,
    Stop,
};

command_entries: []const CommandEntry,

pub fn init(command_entries: []const CommandEntry) Self{
    return .{
        .command_entries = command_entries,
    };
}

pub fn executeLoop(
    self: *const Self, gpa: Allocator, in_reader: *std.Io.Reader, out_writer: *std.Io.Writer
) void {
    while(true){
        self.executeWithInput(gpa, in_reader, out_writer);
    }
}

pub fn executeWithInput(
    self: *const Self,
    gpa: Allocator,
    in_read: *std.Io.Reader,
    out_writer: *std.Io.Writer,
) bool {
    out_writer.writeAll("> ")catch{};
    out_writer.flush()catch{};
    const input = in_read.takeDelimiterInclusive('\n')catch{return false;};
    const trimmed_input = std.mem.trim(u8, input, " \t\n\r");
    std.debug.print("Received input \'{s}\'\n", .{trimmed_input});
    var cmd = CommandParse.Parser.parse(trimmed_input, gpa)catch{return false;};
    defer cmd.deinit(gpa);
    const subcommand = cmd.getNthArg(1)catch{return true;};

    const normalized_subcommand_name = gpa.alloc(u8, subcommand.name.len)catch{return false;};
    defer gpa.free(normalized_subcommand_name);
    _ = std.ascii.upperString(normalized_subcommand_name, subcommand.name);

    for(self.command_entries) |*entry| {
        if(!std.mem.eql(u8, entry.name, normalized_subcommand_name)){
            continue;
        }
        switch (entry.execute_fn(&cmd, in_read, out_writer, entry.execute_context)) {
            CommandState.Stop => return false,
            else => return true,
        }
    }
    out_writer.print("No matching command found", .{}) catch {};
    return true;
}
