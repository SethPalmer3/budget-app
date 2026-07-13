const std = @import("std");
const Allocator = std.mem.Allocator;
const Command = @import("Command.zig");
const Argument = @import("Argument.zig");
const Option = @import("Option.zig");

const Self = @This();

pub const ParseError = error{
    InvalidOption,
    FirstSegmentNotArg,
};

pub fn parse(input: []const u8, alloc: Allocator) !Command {
    var cmd = try Command.init(alloc);
    cmd.raw_string = input;
    var it = std.mem.splitAny(u8, input, " ");
    var i: u64 = 0;
    var opt_pos: usize = 0; // To differentiate Arguments and Options
    while (it.next()) |segment| {
        if(segment.len == 0){
            continue;
        }
        opt_pos = 0; 
        while (segment[opt_pos] == '-') {
            opt_pos += 1;
        }

        if (opt_pos > 2) {
            cmd.deinit(alloc);
            return ParseError.InvalidOption;
        }
        if (opt_pos > 0) { // Found Option
            if (i == 0) { // First segment should be an argument
                cmd.deinit(alloc);
                return ParseError.FirstSegmentNotArg;
            }
            try cmd.addOption(.{
                .long_form = segment[opt_pos ..], // Removes '-' prefix
                .short_form = segment[opt_pos], // Removes '-' prefix
            }, alloc);
        } else {
            try cmd.addArgument(.{ .name = segment }, alloc);
        }
        i += 1;
    }
    return cmd;
}

test parse {
    var cmd = try Self.parse("CMD -f a", std.testing.allocator);
    defer cmd.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, cmd.fragments[0].Arg.name, "CMD");
    try std.testing.expectEqualSlices(u8, cmd.fragments[1].Opt.long_form, "f");
    try std.testing.expectEqualSlices(u8, cmd.fragments[2].Arg.name, "a");
    try std.testing.expectEqual(3, cmd.size);
}

test "one arg" {
    var cmd = try Self.parse("CMD", std.testing.allocator);
    defer cmd.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, cmd.fragments[0].Arg.name, "CMD");
    try std.testing.expectEqual(1, cmd.size);

}

test "first segment option" {
    const cmd = Self.parse("-f", std.testing.allocator);
    // defer cmd.deinit(std.testing.allocator);
    try std.testing.expectError(ParseError.FirstSegmentNotArg, cmd);
}

test "invalid option"{
    const cmd = Self.parse("CMD ---f a", std.testing.allocator);
    try std.testing.expectError(ParseError.InvalidOption, cmd);
}
