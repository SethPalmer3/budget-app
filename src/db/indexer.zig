const std = @import("std");
const storage_engine = @import("./storage_engine.zig");

pub const IndexerError = error{
    CouldNotFindIndex,
};

/// Generic indexing type used for databases
pub fn Indexer(comptime IndexType: type, DataType: type, DataReferenceType: type, comptime StorageEngine: storage_engine.StorageEngine(DataType, DataReferenceType)) type {
    return struct {
        const Self = @This();

        pub const Vtable = struct {
            index: *const fn (*anyopaque, IndexType, DataType, *StorageEngine) IndexerError!void,
            lookup: *const fn (*anyopaque, IndexType, *StorageEngine) IndexerError!DataType,
            delete: *const fn (*anyopaque, IndexType, *StorageEngine) IndexerError!void,
        };

        ptr: ?*anyopaque,
        vtable: *const Vtable,

        // If the index already exists update the value instead or when looking up return the most recent change
        // You can also call the `edit` method from the storage engine also
        pub fn IndexData(i: *Self, index_value: IndexType, data: DataType, se: *StorageEngine) IndexerError!void {
            return try i.vtable.index(i.ptr, index_value, data, se);
        }

        pub fn LookUpData(i: *Self, index_value: IndexType, se: *StorageEngine) IndexerError!DataType {
            return try i.vtable.lookup(i.ptr, index_value, se);
        }

        pub fn DeleteData(i: *Self, index_value: IndexType, se: *StorageEngine) IndexerError!void {
            return try i.vtable.delete(i.ptr, index_value, se);
        }
    };
}
