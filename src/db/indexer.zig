const std = @import("std");
const storage_engine = @import("./storage_engine.zig");

pub const IndexerError = error{
    CouldNotFindIndex,
};

/// Generic indexing type used for databases
pub fn Indexer(comptime IndexType: type, DataType: type, DataReferenceType: type) type {
    return struct {
        pub const DataRefType = struct{
            data: DataType,
            ref: DataReferenceType,
        };
        const StorageEngine = storage_engine.StorageEngine(DataType, DataReferenceType);
        const Self = @This();

        pub const Vtable = struct {
            index: *const fn (*anyopaque, DataType, *StorageEngine) anyerror!void,
            lookup: *const fn (*anyopaque, std.mem.Allocator, IndexType, *StorageEngine) anyerror![]DataRefType,
            delete: *const fn (*anyopaque, IndexType, *StorageEngine) anyerror!void,
        };

        ptr: *anyopaque,
        vtable: *const Vtable,

        // If the index already exists update the value instead or when looking up return the most recent change
        // You can also call the `edit` method from the storage engine also
        pub fn IndexData(i: *Self, data: DataType, se: *StorageEngine) !void {
            return try i.vtable.index(i.ptr, data, se);
        }

        pub fn LookUpData(i: *Self, allocator: std.mem.Allocator, index_value: IndexType, se: *StorageEngine) ![]const DataRefType {
            return try i.vtable.lookup(i.ptr, allocator, index_value, se);
        }

        pub fn DeleteData(i: *Self, index_value: IndexType, se: *StorageEngine) !void {
            return try i.vtable.delete(i.ptr, index_value, se);
        }

    };
}
