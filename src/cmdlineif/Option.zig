const std = @import("std");

const Option = @This();

short_form: u8,
long_form: []const u8,
optional: bool = true,
num_arguments: u64 = 0,
