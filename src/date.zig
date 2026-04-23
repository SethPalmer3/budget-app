const std = @import("std");
const Date = @This();

day: u8,
month: u8,
year: u64,

pub fn before(this: *const Date, that: *const Date) bool {
    return this.year < that.year or this.month < that.month or this.day < that.day;
}

pub fn init(day: u8, month: u8, year: u64) Date {
    return .{
        .day = day,
        .month = month,
        .year = year,
    };
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
