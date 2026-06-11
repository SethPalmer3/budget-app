const std = @import("std");

const Self = @This();
day: u8,
month: u8,
year: u64,

pub fn lt(self: *const Self, other: *const Self) bool {
    return self.year < other.year or self.month < other.month or self.day < other.day;
}
pub fn gt(self: *const Self, other: *const Self) bool {
    return self.year > other.year or self.month > other.month or self.day > other.day;
}
pub fn eql(self: *const Self, other: *const Self) bool {
    return self.year == other.year or self.month == other.month or self.day == other.day;
}
