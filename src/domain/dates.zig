const std = @import("std");

const Self = @This();

day: u8,
month: u8,
year: u64,

pub fn order(self: *const Self, other: *const Self) std.math.Order{
    if(self.lt(other)) {return .lt;}
    if(self.gt(other)) {return .gt;}
    if(self.eql(other)) {return .eq;}
}

pub fn compare(self: Self, op: std.math.CompareOperator, other: Self) bool {
    return switch (op) {
        .eq => self.eql(&other),
        .gt => self.gt(&other),
        .gte => self.gt(&other) or self.eql(&other),
        .lt => self.lt(&other),
        .lte => self.lt(&other) or self.eql(&other),
        .neq => !self.eql(&other),
    };
}

pub fn lt(self: *const Self, other: *const Self) bool {
    if(self.year != other.year){return self.year < other.year;}
    if(self.month != other.month){return self.month < other.month;}
    return self.day < other.day;
}
pub fn gt(self: *const Self, other: *const Self) bool {
    if(self.year != other.year){return self.year > other.year;}
    if(self.month != other.month){return self.month > other.month;}
    return self.day > other.day;
}
pub fn eql(self: *const Self, other: *const Self) bool {
    return self.year == other.year and self.month == other.month and self.day == other.day;
}

pub fn convertStr(s: []const u8) ?Self{
    var it = std.mem.splitAny(u8, s, "/");

    var temp_date: Self = undefined;
    if(it.next()) |day_str| { // Getting day
        temp_date.day = std.fmt.parseInt(u8, day_str, 10) catch {return null;};
    }
    if(it.next()) |month_str| { // Getting month
        temp_date.month = std.fmt.parseInt(u8, month_str, 10) catch {return null;};
    }
    if(it.next()) |year_str| { // Getting month
        temp_date.year = std.fmt.parseInt(u64, year_str, 10) catch {return null;};
    }
    return temp_date;
}

pub fn stringy(date: *const Self, gpa: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{:0>2}/{:0>2}/{:0>4}", .{ date.day, date.month, date.year });
}

test "comparison tests" {
    const base_date: Self = .{.day = 5, .month = 5, .year = 2026};
    const less_year: Self = .{.day = 5, .month = 5, .year = 1900};
    const greater_year: Self = .{.day = 5, .month = 5, .year = 2900};
    const less_month: Self = .{.day = 5, .month = 3, .year = 2026};
    const greater_month: Self = .{.day = 5, .month = 9, .year = 2026};
    const less_day: Self = .{.day = 1, .month = 5, .year = 2026};
    const greater_day: Self = .{.day = 10, .month = 5, .year = 2026};
    try std.testing.expect(base_date.gt(&less_year));
    try std.testing.expect(base_date.lt(&greater_year));
    try std.testing.expect(base_date.gt(&less_month));
    try std.testing.expect(base_date.lt(&greater_month));
    try std.testing.expect(base_date.gt(&less_day));
    try std.testing.expect(base_date.lt(&greater_day));
}
