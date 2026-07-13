const Command = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Argument = @import("Argument.zig");
const Option = @import("Option.zig");

pub const CommandError = error {
    CannotFindFragment,
    NoOptions,
};

pub const CommandFragment = union(enum) {
    Arg: Argument,
    Opt: Option,
};

raw_string: []const u8,
fragments: []CommandFragment,
size: u64 = 0,
num_options: u64 = 0,
num_arguments: u64 = 0,

/// Initalized a new command
pub fn init(alloc: Allocator) anyerror!Command {
    return .{
        .fragments = try alloc.alloc(CommandFragment, 1),
        .raw_string = undefined,
    };
}

pub fn deinit(self: *Command, allc: Allocator) void {
    allc.free(self.fragments);
}

pub fn addArgument(self: *Command, arg: Argument, alloc: Allocator) anyerror!void {
    if (self.size + 1 >= self.fragments.len) {
        self.fragments = try alloc.realloc(self.fragments, self.fragments.len * 2);
    }

    self.fragments[self.size] = CommandFragment{ .Arg = arg };
    self.size += 1;
    self.num_arguments += 1;
}

pub fn addOption(self: *Command, opt: Option, alloc: Allocator) anyerror!void {
    if (self.size +  1 >= self.fragments.len) {
        self.fragments = try alloc.realloc(self.fragments, self.fragments.len * 2);
    }

    self.fragments[self.size] = CommandFragment{ .Opt = opt };
    self.size += 1;
    self.num_options += 1;
}

pub fn getOption(self: *const Command, opt: Option) !*const Option {
    if (self.num_options == 0) {return CommandError.NoOptions;}
    for (self.fragments, 0..) |fragment, i| {
        if (i >= self.size) {break;}
        if(fragment != .Opt){continue;}
        const frag_opt = fragment.Opt;

        if((opt.has_short_form and frag_opt.has_short_form and opt.short_form == frag_opt.short_form) or
            (opt.has_long_form and frag_opt.has_long_form and std.mem.eql(u8, opt.long_form, frag_opt.long_form)
        )){
            return &self.fragments[i].Opt;
        }
    }
    return CommandError.CannotFindFragment;
}

/// Get the nth arguement after a specified option
/// If it cannot find that option, or if another
/// option appears before reaching the desired number
/// of arguments it will throw an error.
pub fn getNthArgAfterOption(self: *const Command, opt: Option, ind: usize) !*const Argument {
    var arg_ind = ind;
    var opt_pos: usize = 0; // <-- 0 should always be a argument so used as an invalid value
    var found_opt = false;
    for (self.fragments, 0..) |fragment, i| {
        if (i >= self.size) {break;}
        if(found_opt){
            if (fragment != .Arg) {return CommandError.CannotFindFragment;} // Broken continuous argument

            arg_ind -= 1;
            if(arg_ind == 0){
                return &self.fragments[i].Arg;
            }
        }
        if(fragment != .Opt){continue;}
        const frag_opt = fragment.Opt;

        if((opt.has_short_form and frag_opt.has_short_form and opt.short_form == frag_opt.short_form) or
            (opt.has_long_form and frag_opt.has_long_form and std.mem.eql(u8, opt.long_form, frag_opt.long_form))){
            found_opt = true;
            opt_pos = i;
        }
    }
    return CommandError.CannotFindFragment;
}

/// Get the nth argument from the parsed command.
/// This function is 1 indexed so cmd.getNthArg(1)
/// should return the command word(i.e. the first argument).
pub fn getNthArg(self: *Command, ind: usize) !*const Argument{
    var nth_arg: usize = 1;
    for(self.fragments, 0..) |fragment, i| {
        if (i >= self.size) {break;}
        if(fragment != .Arg){continue;}
        if(nth_arg == ind){
            return &self.fragments[i].Arg;
        }
        nth_arg += 1;
    }
    return CommandError.CannotFindFragment;
}

pub fn getNthFragment(self: *Command, ind: usize) !*const CommandFragment{
    if(ind < self.fragments.len){
        return self.fragments[ind];
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

test getNthArgAfterOption {
    var cmd = try Command.init(std.testing.allocator);
    defer cmd.deinit(std.testing.allocator);
    try cmd.addOption(.{.long_form = "test", .short_form = 't'}, std.testing.allocator);
    try cmd.addArgument(.{.name = "next_arg"}, std.testing.allocator);
    const getopt: *const Argument = 
        try cmd.getNthArgAfterOption(.{.long_form = "test", .short_form = 't'}, 1);
    try std.testing.expectEqual(cmd.fragments[1].Arg, getopt.*);
}
