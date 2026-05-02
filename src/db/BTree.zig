const std = @import("std");
const Database = @import("./database.zig");

const Self = @This();

pub fn init(){
    // 1. Ensure the data structure type is actually a struct.
    if (@typeInfo(T) != .@"struct") {
        @compileError(std.fmt.comptimePrint("Expected a struct for the data structure, but got '{s}'", .{@typeName(T)}));
    }

    // 2. Ensure the indexes parameter is a tuple.
    const indexes_info = @typeInfo(@TypeOf(indexes));
    if (indexes_info != .@"struct" or !indexes_info.@"struct".is_tuple) {
        @compileError("The indexes parameter must be a tuple (e.g., .{\"field1\", \"field2\"}).");
    }

    // 3. Validate every entry in the tuple.
    inline for (indexes) |index| {
        // Verify the element is a string literal or string slice
        const is_string = switch (@typeInfo(@TypeOf(index))) {
            .pointer => |ptr| switch (ptr.size) {
                .slice => ptr.child == u8,
                .one => @typeInfo(ptr.child) == .array and @typeInfo(ptr.child).array.child == u8,
                else => false,
            },
            else => false,
        };

        if (!is_string) {
            @compileError("The index tuple must contain only strings.");
        }

        // Verify the string matches a field in the provided struct type `T`
        const field_name: []const u8 = index;
        if (!@hasField(T, field_name)) {
            @compileError(std.fmt.comptimePrint("Index field '{s}' is not a member of the data structure '{s}'.", .{ field_name, @typeName(T) }));
        }
    }
}
