const std = @import("std");

const Option = @This();

short_form: u8,
long_form: []const u8,
optional: bool = true,
has_short_form: bool = true,
has_long_form: bool = true,
