const std = @import("std");

/// A generic database interface generator.
/// Validates that `T` is a struct, `indexes` is a tuple of strings,
/// and that every string corresponds to a valid field in `T`.
pub fn Database(comptime T: type, comptime indexes: anytype) type {
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

    // 4. Return the generated type storing the parameters.
    return struct {
        pub const RecordType = T;
        pub const index_tuple = indexes;

        pub const Vtable = struct {};

        ptr: ?*anyopaque,
        vtable: *const Vtable,

        // Example method demonstrating how to access the stored types and data
        pub fn init(impl: anytype) @This() {
            // TODO: change this function to update the ptr and vtable variables
            return .{};
        }

        pub fn printIndexes() void {
            std.debug.print("Indexing '{s}' by fields: ", .{@typeName(RecordType)});
            inline for (index_tuple) |field| {
                std.debug.print("'{s}' ", .{field});
            }
            std.debug.print("\n", .{});
        }
    };
}

// --- Example Usage ---

const User = struct {
    id: u32,
    username: []const u8,
    email: []const u8,
    is_active: bool,
};

test "data item wrong type check" {
    const simpleDataItem = struct {
        somestuff: u64,
        somestuff3: u64,
        somestuff4: u64,
        somestuff5: u64,
    };
    const db: Database(simpleDataItem, .{"somestuff"}) = .{};
}
