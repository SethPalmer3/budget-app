const std = @import("std");
const Allocator = std.mem.Allocator;
pub const Date = @This();

day: u8,
month: u8,
year: u64,

pub inline fn before(this: *const Date, that: *const Date) bool {
    return this.year < that.year or this.month < that.month or this.day < that.day;
}

pub fn after(this: *const Date, that: *const Date) bool {
    return !Date.before(this, that) and !Date.same(this, that);
}

pub inline fn same(this: *const Date, that: *const Date) bool {
    return this.year == that.year and this.month == that.month and this.day == that.day;
}

pub fn init(day: u8, month: u8, year: u64) Date {
    return .{
        .day = day,
        .month = month,
        .year = year,
    };
}

pub fn stringify(date: *const Date, gpa: Allocator) []u8 {
    var date_str_buffer: []u8 = gpa.alloc(u8, 3 + 3 + 4 + 1);
    std.fmt.allocPrint(gpa, "{:0>2}/{:0>2}/{:0>4}", .{ date.month, date.day, date.year });

    return date_str_buffer[0..];
}

test "before method check year" {
    const this: Date = Date.init(1, 1, 2000);
    const that: Date = Date.init(1, 1, 2100);
    try std.testing.expect(Date.before(&this, &that));
}
test "before method check month" {
    const this: Date = Date.init(1, 1, 2000);
    const that: Date = Date.init(1, 2, 2000);
    try std.testing.expect(Date.before(&this, &that));
}
test "before method check day" {
    const this: Date = Date.init(1, 1, 2000);
    const that: Date = Date.init(2, 1, 2000);
    try std.testing.expect(Date.before(&this, &that));
}
