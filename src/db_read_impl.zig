const std = @import("std");
const budgeter = @import("./budgeter.zig");

pub fn simpleImple(comptime config: budgeter.BudgeterManagerConfig, reader: *std.Io.Reader, args: anytype) anyerror!budgeter.BudgeterItem(config) {}
