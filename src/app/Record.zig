const recordType = @import("record_type.zig");
const recordCategory = @import("record_category.zig");
const Date = @import("dates.zig");

pub const name_length = 20;
pub const desc_length = 1000;
name: [name_length]u8,
date: Date,
type: recordType,
category: recordCategory,
amount: u64, // <-- fixed point number div by 10
desc: [desc_length]u8,
