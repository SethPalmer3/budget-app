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

/// Converst day/month/year or 
/// 1/month/year
pub fn convertStr(s: []const u8) ?Self{
    var it = std.mem.splitAny(u8, s, "/");
    var count: u64 = 0;
    while(it.next()) |_| {
        count += 1;
    }
    it.reset();

    var temp_date: Self = undefined;
    if(it.next()) |first_str| { // Getting day
        const convert_first = std.fmt.parseInt(u8, first_str, 10) catch {return null;};
        if(count == 2){
            temp_date.day = 1;
            temp_date.month = convert_first;
        }else{
            temp_date.day = convert_first;
        }
    }
    if(it.next()) |second_str| { // Getting month
        const convert_second = std.fmt.parseInt(u64, second_str, 10) catch {return null;}; 
        if(count == 2){
            temp_date.year = convert_second;
        }else{
            temp_date.month = @intCast(convert_second);
        }
    }
    if(it.next()) |year_str| { // Getting year
        temp_date.year = std.fmt.parseInt(u64, year_str, 10) catch {return null;};
    }
    return temp_date;
}

pub fn stringy(date: *const Self, gpa: std.mem.Allocator) ![]u8 {
    return try std.fmt.allocPrint(gpa, "{:0>2}/{:0>2}/{:0>4}", .{ date.day, date.month, date.year });
}

test "conversion" {
    const three_parts = "1/2/3";
    const two_parts = "1/2026";
    const three_parts_conv = Self.convertStr(three_parts).?;
    const two_parts_conv = Self.convertStr(two_parts).?;
    try std.testing.expect(three_parts_conv.eql(&.{ .day = 1, .month = 2, .year = 3}));
    try std.testing.expect(two_parts_conv.eql(&Self{ .day = 1, .month = 1, .year = 2026}));
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
