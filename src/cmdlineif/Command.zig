const Command = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Argument = @import("Argument.zig");
const Option = @import("Option.zig");

pub const CommandFragment = union(enum) {
    Arg: Argument,
    Opt: Option,
};

fragments: []CommandFragment,
next_fragment: u64 = 0,

/// Initalized a new command
pub fn init(alloc: Allocator) anyerror!Command {
    return .{
        .fragments = try alloc.alloc(CommandFragment, 1),
    };
}

pub fn deinit(self: *Command, allc: Allocator) void {
    allc.free(self.fragments);
}

pub fn addArgument(self: *Command, arg: Argument, alloc: Allocator) anyerror!void {
    if (self.next_fragment + 1 >= self.fragments.len) {
        self.fragments = try alloc.realloc(self.fragments, self.fragments.len * 2);
    }

    self.fragments[self.next_fragment] = CommandFragment{ .Arg = arg };
    self.next_fragment += 1;
}

pub fn addOption(self: *Command, opt: Option, alloc: Allocator) anyerror!void {
    if (self.next_fragment +  1 >= self.fragments.len) {
        self.fragments = try alloc.realloc(self.fragments, self.fragments.len * 2);
    }

    self.fragments[self.next_fragment] = CommandFragment{.Opt = opt };
    self.next_fragment += 1;
}
