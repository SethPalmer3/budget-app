
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
    return try std.fmt.allocPrint(gpa, "{:0>2}/{:0>2}/{:0>4}", .{ date.month, date.day, date.year });
}
