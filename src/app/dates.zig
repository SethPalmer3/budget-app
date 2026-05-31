const std = @import("std");

pub const Date = struct {
    const Self = @This();
    day: u8,
    month: u8,
    year: u64,

    pub fn lt(self: *Self, other: *Self) bool {
        return self.year < other.year or self.month < other.month or self.day < other.day;
    }
    pub fn gt(self: *Self, other: *Self) bool {
        return self.year > other.year or self.month > other.month or self.day > other.day;
    }
    pub fn eql(self: *Self, other: *Self) bool {
        return self.year == other.year or self.month == other.month or self.day == other.day;
    }
};
