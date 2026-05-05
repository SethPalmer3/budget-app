const std = @import("std");
const Allocator = std.mem.Allocator;
const Database = @import("./database.zig");
const Entry = @import("./BTreeEntry");

pub const Options = struct {
    /// Size of pages in bytes
    page_size: u64,

    data_path: []const u8,

    in_memory_alloc: Allocator,
};

pub const DefaultOptions: Options = .{
    .page_size = std.heap.pageSize(),

    .data_path = "./data",

    .in_memory_alloc = std.heap.DebugAllocator(.{}),
};

/// Creates a BTree type storage enginer manager
pub fn BTreeStorageEngine(comptime K: type, comptime T: type, comptime I: anytype, comptime O: Options) !type {
    // 1. Ensure the data structure type is actually a struct.
    if (@typeInfo(T) != .@"struct") {
        @compileError(std.fmt.comptimePrint("Expected a struct for the data structure, but got '{s}'", .{@typeName(T)}));
    }

    // 2. Ensure the indexes parameter is a tuple.
    const indexes_info = @typeInfo(@TypeOf(I));
    if (indexes_info != .@"struct" or !indexes_info.@"struct".is_tuple) {
        @compileError("The indexes parameter must be a tuple (e.g., .{\"field1\", \"field2\"}).");
    }

    // 3. Validate every entry in the tuple.
    inline for (I) |index| {
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
    return struct {
        pub const key_type = K;
        pub const record_type = T;
        pub const indexes = I;
        pub const Options = O;
        pub var active_page: []u8 = undefined;
        pub var number_of_entries: u64 = 0;

        const Self = @This();
        pub fn init(db: *Self) !void {
            // Initalize active page
            active_page = try Self.Options.in_memory_alloc.alloc(u8, Self.Options.page_size) catch {
                return Database.DBError.CannotInitalize;
            };
        }
        pub fn deinit(db: *Self) void {
            Self.Options.in_memory_alloc.free(active_page);
        }
        pub fn retrieveByKey(db: *Self, key: Self.key_type) Database.DBError!Self.record_type {}
    };
}

test "test init" {
    const K = u64;
    const T = struct { data: []const u8 };
    const ind = struct { "data" };
    const Test = BTreeStorageEngine(K, T, ind, DefaultOptions);
}
