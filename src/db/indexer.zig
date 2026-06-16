const std = @import("std");
const storage_engine = @import("./storage_engine.zig");

pub const IndexerError = error{
    CouldNotFindIndex,
};

/// Generic indexing type used for databases
pub fn Indexer(comptime IndexType: type, ReferenceType: type) type {
    return struct {
        const Self = @This();

        pub const Vtable = struct {
            index: *const fn (*anyopaque, IndexType, ReferenceType) anyerror!void,
            lookup: *const fn (*anyopaque, std.mem.Allocator, IndexType) anyerror![]const ReferenceType,
            delete: *const fn (*anyopaque, IndexType) anyerror!void,
        };

        ptr: *anyopaque,
        vtable: *const Vtable,

        // If the index already exists update the value instead or when looking up return the most recent change
        // You can also call the `edit` method from the storage engine also
        pub fn Index(i: *Self, index: IndexType, ref: ReferenceType) !void {
            return try i.vtable.index(i.ptr, index, ref);
        }

        pub fn LookUpData(i: *Self, allocator: std.mem.Allocator, index_value: IndexType) ![]const ReferenceType {
            return try i.vtable.lookup(i.ptr, allocator, index_value);
        }

        pub fn DeleteData(i: *Self, index_value: IndexType) !void {
            return try i.vtable.delete(i.ptr, index_value);
        }

    };
}

