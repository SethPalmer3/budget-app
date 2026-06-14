day: u8,
month: u8,
year: u64,

const std = @import("std");

const Self = @This();

pub fn lt(self: *const Self, other: *const Self) bool {
    return self.year < other.year or self.month < other.month or self.day < other.day;
}
pub fn gt(self: *const Self, other: *const Self) bool {
    return self.year > other.year or self.month > other.month or self.day > other.day;
}
pub fn eql(self: *const Self, other: *const Self) bool {
    return self.year == other.year or self.month == other.month or self.day == other.day;
}

pub fn stringy(date: *const Self, gpa: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{:0>2}/{:0>2}/{:0>4}", .{ date.month, date.day, date.year });
}
