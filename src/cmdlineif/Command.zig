const Command = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Argument = @import("Argument.zig");
const Option = @import("Option.zig");

pub const CommandError = error {
    CannotFindFragment,
};

pub const CommandFragment = union(enum) {
    Arg: Argument,
    Opt: Option,
};

fragments: []CommandFragment,
next_fragment: u64 = 0,
num_options: u64 = 0,
num_arguments: u64 = 0,

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
    self.num_arguments += 1;
}

pub fn addOption(self: *Command, opt: Option, alloc: Allocator) anyerror!void {
    if (self.next_fragment +  1 >= self.fragments.len) {
        self.fragments = try alloc.realloc(self.fragments, self.fragments.len * 2);
    }

    self.fragments[self.next_fragment] = CommandFragment{.Opt = opt };
    self.next_fragment += 1;
    self.num_options += 1;
}

pub fn getOption(self: *Command, opt: Option) !*const Option {
    for (self.fragments) |fragment| {
        if(fragment != .Opt){continue;}
        const frag_opt = fragment.Opt;

        if((opt.has_short_form and frag_opt.has_short_form and opt.short_form == frag_opt.short_form) or
            (opt.has_long_form and frag_opt.has_long_form and std.mem.eql(u8, opt.long_form, frag_opt.long_form))){
            return &fragment.Opt;
        }
    }
    return CommandError.CannotFindFragment;
}

/// Get the nth argument from the parsed command.
/// This function is 1 indexed so cmd.getNthArg(1)
/// should return the command word(i.e. the first argument).
pub fn getNthArg(self: *Command, ind: usize) !*const Argument{
    var nth_arg: usize = 1;
    for(self.fragments) |fragment| {
        if(fragment != .Arg){continue;}
        if(nth_arg == ind){
            return &fragment.Arg;
        }
        nth_arg += 1;
    }
    return CommandError.CannotFindFragment;
}

test addOption {
    var cmd = try Command.init(std.testing.allocator);
    defer cmd.deinit(std.testing.allocator);
    try cmd.addOption(.{.long_form = "test", .short_form = 't'}, std.testing.allocator);
    try std.testing.expectEqualStrings(cmd.fragments[0].Opt.long_form, "test");
    try std.testing.expect(cmd.fragments[0].Opt.short_form == 't');
}

test addArgument{
    var cmd = try Command.init(std.testing.allocator);
    defer cmd.deinit(std.testing.allocator);
    try cmd.addArgument(.{.name = "test"}, std.testing.allocator);
    try std.testing.expectEqual(cmd.fragments[0].Arg.name, "test");
}

test getOption {
    var cmd = try Command.init(std.testing.allocator);
    defer cmd.deinit(std.testing.allocator);
    try cmd.addOption(.{.long_form = "test", .short_form = 't'}, std.testing.allocator);
    const getopt: *const Option = try cmd.getOption(.{.long_form = "test", .short_form = 't'});
    try std.testing.expectEqual(cmd.fragments[0].Opt, getopt.*);
}

test getNthArg {
    var cmd = try Command.init(std.testing.allocator);
    defer cmd.deinit(std.testing.allocator);
    try cmd.addArgument(.{.name = "test"}, std.testing.allocator);
    const getarg: *const Argument = try cmd.getNthArg(1);
    try std.testing.expectEqual(cmd.fragments[0].Arg, getarg.*);
}

