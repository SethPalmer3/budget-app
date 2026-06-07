const std = @import("std");
const Indexer = @import("indexer.zig");
const StorageEngine = @import("storage_engine.zig");

pub const DBError = error{
    CannotInitalize,
    CannotStoreData,
    NoKeyFound,
};

pub fn Database(comptime D: type, comptime R: type, comptime I: type) type {
    return struct{
        pub const DataType = D;
        pub const ReferenceType = R;
        pub const IndexType = I;
        const StorageEngineType = StorageEngine.StorageEngine(D, R);
        const IndexerType = Indexer.Indexer(I, D, R);
        const DataRefType = IndexerType.DataRefType;
        const Self = @This();

        storage_engine: StorageEngineType,
        indexer: IndexerType,
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator, indexer: IndexerType, se: StorageEngineType) Self{
            return .{
                .alloc = alloc,
                .indexer = indexer,
                .storage_engine = se,
            };
        }

        pub fn StoreData(db: *Self, data: D) anyerror!void {
            try db.indexer.IndexData(data, &db.storage_engine);
        }

        pub fn GetEntriesByIndex(db: *Self, index: I) ![]const DataRefType {
            return try db.indexer.LookUpData(db.alloc, index, &db.storage_engine);
        }

        pub fn DeleteByIndex(db: *Self, index: I) !void {
            return try db.indexer.DeleteData(index, &db.storage_engine);
        }
    };
}
