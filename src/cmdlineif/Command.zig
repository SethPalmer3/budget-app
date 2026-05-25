const std = @import("std");
const Argument = @import("Argument.zig");

const Command = @This();

name: []const u8,
arguments: []const Argument,
